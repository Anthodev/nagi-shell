#include "protocol.h"
#include "volume.h"

#include <algorithm>
#include <array>
#include <cerrno>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <memory>
#include <optional>
#include <stdexcept>
#include <unordered_map>
#include <utility>
#include <vector>

#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QSocketNotifier>

#include <pipewire/pipewire.h>
#include <spa/param/props.h>
#include <spa/pod/builder.h>
#include <spa/pod/iter.h>
#include <spa/utils/result.h>
#include <unistd.h>

namespace {

using nagi::audio::Command;
using nagi::audio::Operation;
using nagi::audio::Role;

constexpr std::uint32_t InvalidNode = SPA_ID_INVALID;
constexpr int MaximumDiagnostics = 8;

struct Request {
    Operation operation = Operation::Shutdown;
    Role role = Role::Output;
    std::uint32_t nodeId = 0;
    std::uint32_t generation = 0;
    std::uint32_t requestId = 0;
    double volume = 0.0;
    bool muted = false;
    bool final = false;
};

struct KnownNode {
    std::uint32_t version = 0;
    nagi::audio::EasyEffectsInternalRole easyEffectsRole =
        nagi::audio::EasyEffectsInternalRole::None;
};

class PipeWireBridge;

struct NodeBinding {
    PipeWireBridge *owner = nullptr;
    std::uint32_t id = InvalidNode;
    pw_node *node = nullptr;
    spa_hook listener{};
    bool subscribed = false;
    bool hasVolumes = false;
    bool hasMute = false;
    std::vector<float> visualVolumes;
    bool muted = false;
};

struct RoleState {
    std::uint32_t nodeId = InvalidNode;
    std::uint32_t generation = 0;
    NodeBinding *binding = nullptr;
    bool volumeInFlight = false;
    bool muteInFlight = false;
    std::optional<Request> queuedVolume;
    std::optional<Request> queuedMute;
};

class PipeWireBridge final : public QObject {
public:
    explicit PipeWireBridge(QObject *parent = nullptr)
        : QObject(parent)
    {
        pw_init(nullptr, nullptr);
        threadLoop = pw_thread_loop_new("nagi-pipewire-audio", nullptr);
        if (threadLoop == nullptr) {
            throw std::runtime_error("could not create PipeWire thread loop");
        }

        context = pw_context_new(pw_thread_loop_get_loop(threadLoop), nullptr, 0);
        if (context == nullptr) {
            throw std::runtime_error("could not create PipeWire context");
        }
        core = pw_context_connect(context, nullptr, 0);
        if (core == nullptr) {
            throw std::runtime_error("could not connect to PipeWire");
        }

        static const pw_core_events coreEvents = [] {
            pw_core_events events{};
            events.version = PW_VERSION_CORE_EVENTS;
            events.done = &PipeWireBridge::onCoreDone;
            events.error = &PipeWireBridge::onCoreError;
            return events;
        }();
        pw_core_add_listener(core, &coreListener, &coreEvents, this);

        registry = pw_core_get_registry(core, PW_VERSION_REGISTRY, 0);
        if (registry == nullptr) {
            throw std::runtime_error("could not acquire PipeWire registry");
        }
        static const pw_registry_events registryEvents = {
            .version = PW_VERSION_REGISTRY_EVENTS,
            .global = &PipeWireBridge::onRegistryGlobal,
            .global_remove = &PipeWireBridge::onRegistryGlobalRemove,
        };
        pw_registry_add_listener(registry, &registryListener, &registryEvents, this);
        initialSyncSequence = pw_core_sync(core, PW_ID_CORE, 0);
        if (initialSyncSequence < 0) {
            throw std::runtime_error("could not synchronize PipeWire registry");
        }

        if (pw_thread_loop_start(threadLoop) < 0) {
            throw std::runtime_error("could not start PipeWire thread loop");
        }
        loopStarted = true;

        stdinNotifier = new QSocketNotifier(STDIN_FILENO, QSocketNotifier::Read, this);
        connect(stdinNotifier, &QSocketNotifier::activated, this, [this] { readCommands(); });
    }

    ~PipeWireBridge() override
    {
        if (threadLoop != nullptr && loopStarted) {
            pw_thread_loop_lock(threadLoop);
        }
        for (const auto &entry : bindings) {
            spa_hook_remove(&entry.second->listener);
        }
        bindings.clear();
        if (registry != nullptr) {
            spa_hook_remove(&registryListener);
            pw_proxy_destroy(reinterpret_cast<pw_proxy *>(registry));
            registry = nullptr;
        }
        if (core != nullptr) {
            spa_hook_remove(&coreListener);
            pw_core_disconnect(core);
            core = nullptr;
        }
        if (threadLoop != nullptr && loopStarted) {
            pw_thread_loop_unlock(threadLoop);
            pw_thread_loop_stop(threadLoop);
            loopStarted = false;
        }
        if (context != nullptr) {
            pw_context_destroy(context);
            context = nullptr;
        }
        if (threadLoop != nullptr) {
            pw_thread_loop_destroy(threadLoop);
            threadLoop = nullptr;
        }
        pw_deinit();
    }

private:
    static int roleIndex(Role role) { return role == Role::Output ? 0 : 1; }

    RoleState &roleState(Role role) { return roles[roleIndex(role)]; }

    const RoleState &roleState(Role role) const { return roles[roleIndex(role)]; }

    void publish(const QJsonObject &message)
    {
        const QByteArray line = QJsonDocument(message).toJson(QJsonDocument::Compact);
        std::fwrite(line.constData(), 1, static_cast<std::size_t>(line.size()), stdout);
        std::fputc('\n', stdout);
        std::fflush(stdout);
    }

    void post(const QJsonObject &message)
    {
        QMetaObject::invokeMethod(
            this,
            [this, message] { publish(message); },
            Qt::QueuedConnection);
    }

    void diagnose(const char *message)
    {
        if (diagnosticCount >= MaximumDiagnostics) {
            return;
        }
        ++diagnosticCount;
        std::fprintf(stderr, "nagi-shell PipeWire bridge: %.256s\n", message);
        std::fflush(stderr);
    }

    void postFailure(const Request &request, const QString &reason)
    {
        post(QJsonObject{
            {QStringLiteral("type"), QStringLiteral("failure")},
            {QStringLiteral("role"), nagi::audio::roleName(request.role)},
            {QStringLiteral("nodeId"), static_cast<qint64>(request.nodeId)},
            {QStringLiteral("generation"), static_cast<qint64>(request.generation)},
            {QStringLiteral("requestId"), static_cast<qint64>(request.requestId)},
            {QStringLiteral("kind"), nagi::audio::operationName(request.operation)},
            {QStringLiteral("reason"), reason.left(64)},
        });
    }

    void postUnavailable(Role role, std::uint32_t generation)
    {
        post(QJsonObject{
            {QStringLiteral("type"), QStringLiteral("unavailable")},
            {QStringLiteral("role"), nagi::audio::roleName(role)},
            {QStringLiteral("generation"), static_cast<qint64>(generation)},
        });
    }

    void postNodeMetadata(
        std::uint32_t nodeId,
        nagi::audio::EasyEffectsInternalRole role)
    {
        if (role == nagi::audio::EasyEffectsInternalRole::None) {
            postNodeRemoved(nodeId);
            return;
        }
        QString normalizedRole = QStringLiteral("none");
        if (role == nagi::audio::EasyEffectsInternalRole::Output) {
            normalizedRole = QStringLiteral("output");
        } else if (role == nagi::audio::EasyEffectsInternalRole::Input) {
            normalizedRole = QStringLiteral("input");
        }
        post(QJsonObject{
            {QStringLiteral("type"), QStringLiteral("node-metadata")},
            {QStringLiteral("nodeId"), static_cast<qint64>(nodeId)},
            {QStringLiteral("easyEffectsRole"), normalizedRole},
        });
    }

    void postNodeRemoved(std::uint32_t nodeId)
    {
        post(QJsonObject{
            {QStringLiteral("type"), QStringLiteral("node-removed")},
            {QStringLiteral("nodeId"), static_cast<qint64>(nodeId)},
        });
    }

    void postState(const RoleState &role, const NodeBinding &binding, const Request *request)
    {
        if (!binding.hasVolumes || !binding.hasMute || binding.visualVolumes.empty()) {
            return;
        }
        double total = 0.0;
        for (float volume : binding.visualVolumes) {
            total += volume;
        }
        const double average = total / static_cast<double>(binding.visualVolumes.size());
        post(QJsonObject{
            {QStringLiteral("type"), QStringLiteral("state")},
            {QStringLiteral("role"),
             nagi::audio::roleName(request == nullptr ? roleForState(role) : request->role)},
            {QStringLiteral("nodeId"), static_cast<qint64>(binding.id)},
            {QStringLiteral("generation"), static_cast<qint64>(role.generation)},
            {QStringLiteral("requestId"),
             static_cast<qint64>(request == nullptr ? 0 : request->requestId)},
            {QStringLiteral("kind"),
             request == nullptr ? QStringLiteral("external")
                                : nagi::audio::operationName(request->operation)},
            {QStringLiteral("volume"), average},
            {QStringLiteral("muted"), binding.muted},
        });
    }

    Role roleForState(const RoleState &state) const
    {
        return &state == &roles[0] ? Role::Output : Role::Input;
    }

    static void onCoreDone(void *data, std::uint32_t id, int sequence)
    {
        auto *bridge = static_cast<PipeWireBridge *>(data);
        if (id != PW_ID_CORE) {
            return;
        }
        if (sequence == bridge->initialSyncSequence) {
            bridge->helperReady = true;
            bridge->post(QJsonObject{{QStringLiteral("type"), QStringLiteral("ready")}});
            bridge->ensureTrackedBindings();
            return;
        }

        const auto iterator = bridge->syncRequests.find(sequence);
        if (iterator == bridge->syncRequests.end()) {
            return;
        }
        const Request request = iterator->second;
        bridge->syncRequests.erase(iterator);
        bridge->beginReadback(request);
    }

    static void onCoreError(
        void *data,
        std::uint32_t id,
        int,
        int result,
        const char *)
    {
        auto *bridge = static_cast<PipeWireBridge *>(data);
        if (id != PW_ID_CORE || result >= 0) {
            return;
        }
        bridge->post(QJsonObject{
            {QStringLiteral("type"), QStringLiteral("fatal")},
            {QStringLiteral("reason"), QStringLiteral("pipewire-core")},
        });
        QMetaObject::invokeMethod(
            QCoreApplication::instance(),
            [] { QCoreApplication::exit(2); },
            Qt::QueuedConnection);
    }

    static void onRegistryGlobal(
        void *data,
        std::uint32_t id,
        std::uint32_t,
        const char *type,
        std::uint32_t version,
        const spa_dict *properties)
    {
        auto *bridge = static_cast<PipeWireBridge *>(data);
        if (std::strcmp(type, PW_TYPE_INTERFACE_Node) != 0) {
            return;
        }
        const auto property = [properties](const char *name) {
            const char *value = properties == nullptr ? nullptr : spa_dict_lookup(properties, name);
            return value == nullptr ? QByteArray() : QByteArray(value);
        };
        const auto role = nagi::audio::classifyEasyEffectsNode(
            property(PW_KEY_NODE_NAME),
            property(PW_KEY_APP_ID),
            property(PW_KEY_NODE_VIRTUAL),
            property(PW_KEY_MEDIA_CLASS));
        bridge->knownNodes[id] = KnownNode{.version = version, .easyEffectsRole = role};
        bridge->postNodeMetadata(id, role);
        bridge->ensureTrackedBindings();
    }

    static void onRegistryGlobalRemove(void *data, std::uint32_t id)
    {
        auto *bridge = static_cast<PipeWireBridge *>(data);
        if (bridge->knownNodes.erase(id) > 0) {
            bridge->postNodeRemoved(id);
        }
        bridge->removeBinding(id);
    }

    static void onNodeInfo(void *data, const pw_node_info *)
    {
        auto *binding = static_cast<NodeBinding *>(data);
        if (binding->subscribed) {
            return;
        }
        binding->subscribed = true;
        std::uint32_t params[] = {SPA_PARAM_Props};
        pw_node_subscribe_params(binding->node, params, 1);
        pw_node_enum_params(binding->node, 0, SPA_PARAM_Props, 0, 1, nullptr);
    }

    static void onNodeParam(
        void *data,
        int sequence,
        std::uint32_t id,
        std::uint32_t,
        std::uint32_t,
        const spa_pod *parameter)
    {
        auto *binding = static_cast<NodeBinding *>(data);
        if (id != SPA_PARAM_Props || parameter == nullptr) {
            return;
        }
        if (!binding->owner->updateState(*binding, parameter)) {
            return;
        }

        auto readback = binding->owner->readbackRequests.find(sequence);
        if (readback == binding->owner->readbackRequests.end()) {
            auto candidate = binding->owner->readbackRequests.end();
            for (auto iterator = binding->owner->readbackRequests.begin();
                 iterator != binding->owner->readbackRequests.end();
                 ++iterator) {
                if (iterator->second.nodeId != binding->id) {
                    continue;
                }
                if (candidate != binding->owner->readbackRequests.end()) {
                    candidate = binding->owner->readbackRequests.end();
                    break;
                }
                candidate = iterator;
            }
            readback = candidate;
        }
        if (readback != binding->owner->readbackRequests.end()) {
            const Request request = readback->second;
            binding->owner->readbackRequests.erase(readback);
            binding->owner->completeRequest(request, *binding);
            return;
        }
        binding->owner->publishExternalState(*binding);
    }

    bool updateState(NodeBinding &binding, const spa_pod *parameter)
    {
        const spa_pod_prop *volumesProperty =
            spa_pod_find_prop(parameter, nullptr, SPA_PROP_channelVolumes);
        if (volumesProperty != nullptr && spa_pod_is_array(&volumesProperty->value)) {
            const auto *array = reinterpret_cast<const spa_pod_array *>(&volumesProperty->value);
            const std::uint32_t count = SPA_POD_ARRAY_N_VALUES(array);
            if (SPA_POD_ARRAY_VALUE_TYPE(array) == SPA_TYPE_Float
                && SPA_POD_ARRAY_VALUE_SIZE(array) == sizeof(float) && count > 0 && count <= 64) {
                const auto *values =
                    reinterpret_cast<const float *>(SPA_POD_ARRAY_VALUES(array));
                std::vector<float> volumes;
                volumes.reserve(count);
                for (std::uint32_t index = 0; index < count; ++index) {
                    const float cubic = values[index];
                    if (!std::isfinite(cubic) || cubic < 0.0F) {
                        volumes.clear();
                        break;
                    }
                    volumes.push_back(std::cbrt(cubic));
                }
                if (!volumes.empty()) {
                    binding.visualVolumes = std::move(volumes);
                    binding.hasVolumes = true;
                }
            }
        }

        const spa_pod_prop *muteProperty = spa_pod_find_prop(parameter, nullptr, SPA_PROP_mute);
        if (muteProperty != nullptr) {
            bool muted = false;
            if (spa_pod_get_bool(&muteProperty->value, &muted) == 0) {
                binding.muted = muted;
                binding.hasMute = true;
            }
        }
        return binding.hasVolumes && binding.hasMute;
    }

    void publishExternalState(const NodeBinding &binding)
    {
        for (Role role : {Role::Output, Role::Input}) {
            const RoleState &state = roleState(role);
            if (state.binding != &binding || state.volumeInFlight || state.muteInFlight) {
                continue;
            }
            postState(state, binding, nullptr);
        }
    }

    void ensureTrackedBindings()
    {
        if (!helperReady) {
            return;
        }
        for (Role role : {Role::Output, Role::Input}) {
            RoleState &state = roleState(role);
            if (state.nodeId == InvalidNode || state.binding != nullptr
                || !knownNodes.contains(state.nodeId)) {
                continue;
            }
            state.binding = ensureBinding(state.nodeId);
            if (state.binding != nullptr && state.binding->hasVolumes && state.binding->hasMute) {
                postState(state, *state.binding, nullptr);
            }
        }
    }

    NodeBinding *ensureBinding(std::uint32_t id)
    {
        const auto existing = bindings.find(id);
        if (existing != bindings.end()) {
            return existing->second.get();
        }
        const auto version = knownNodes.find(id);
        if (version == knownNodes.end()) {
            return nullptr;
        }

        auto binding = std::make_unique<NodeBinding>();
        binding->owner = this;
        binding->id = id;
        binding->node = static_cast<pw_node *>(pw_registry_bind(
            registry,
            id,
            PW_TYPE_INTERFACE_Node,
            std::min(version->second.version, static_cast<std::uint32_t>(PW_VERSION_NODE)),
            0));
        if (binding->node == nullptr) {
            return nullptr;
        }
        static const pw_node_events nodeEvents = [] {
            pw_node_events events{};
            events.version = PW_VERSION_NODE_EVENTS;
            events.info = &PipeWireBridge::onNodeInfo;
            events.param = &PipeWireBridge::onNodeParam;
            return events;
        }();
        pw_node_add_listener(binding->node, &binding->listener, &nodeEvents, binding.get());
        NodeBinding *result = binding.get();
        bindings.emplace(id, std::move(binding));
        return result;
    }

    void removeBinding(std::uint32_t id)
    {
        const auto bindingIterator = bindings.find(id);
        if (bindingIterator == bindings.end()) {
            return;
        }
        NodeBinding *binding = bindingIterator->second.get();
        for (Role role : {Role::Output, Role::Input}) {
            RoleState &state = roleState(role);
            if (state.binding != binding) {
                continue;
            }
            state.binding = nullptr;
            state.volumeInFlight = false;
            state.muteInFlight = false;
            state.queuedVolume.reset();
            state.queuedMute.reset();
            postUnavailable(role, state.generation);
        }
        eraseRequestsForNode(id);
        spa_hook_remove(&binding->listener);
        pw_proxy_destroy(reinterpret_cast<pw_proxy *>(binding->node));
        bindings.erase(bindingIterator);
    }

    void eraseRequestsForNode(std::uint32_t id)
    {
        std::erase_if(syncRequests, [id](const auto &entry) { return entry.second.nodeId == id; });
        std::erase_if(
            readbackRequests,
            [id](const auto &entry) { return entry.second.nodeId == id; });
    }

    bool bindingUsed(std::uint32_t id) const
    {
        return std::any_of(roles.begin(), roles.end(), [id](const RoleState &state) {
            return state.nodeId == id;
        });
    }

    void releaseBindingIfUnused(std::uint32_t id)
    {
        if (id != InvalidNode && !bindingUsed(id)) {
            removeBinding(id);
        }
    }

    void track(const Command &command)
    {
        RoleState &state = roleState(command.role);
        const std::uint32_t oldNode = state.nodeId;
        RoleState replacement;
        replacement.nodeId = command.nodeId;
        replacement.generation = command.generation;
        state = std::move(replacement);
        releaseBindingIfUnused(oldNode);
        ensureTrackedBindings();
        if (state.binding == nullptr && helperReady && !knownNodes.contains(command.nodeId)) {
            postUnavailable(command.role, command.generation);
        }
    }

    void untrack(const Command &command)
    {
        RoleState &state = roleState(command.role);
        if (state.generation != command.generation) {
            return;
        }
        const std::uint32_t oldNode = state.nodeId;
        state = RoleState{};
        releaseBindingIfUnused(oldNode);
    }

    Request makeRequest(const Command &command) const
    {
        return Request{
            .operation = command.operation,
            .role = command.role,
            .nodeId = command.nodeId,
            .generation = command.generation,
            .requestId = command.requestId,
            .volume = command.volume,
            .muted = command.muted,
            .final = command.final,
        };
    }

    void request(const Command &command)
    {
        RoleState &state = roleState(command.role);
        const Request request = makeRequest(command);
        if (state.nodeId != request.nodeId || state.generation != request.generation
            || state.binding == nullptr) {
            postFailure(request, QStringLiteral("stale"));
            return;
        }

        if (state.volumeInFlight || state.muteInFlight) {
            if (request.operation == Operation::SetVolume) {
                state.queuedVolume = request;
            } else {
                state.queuedMute = request;
            }
            return;
        }
        dispatch(request);
    }

    void dispatch(const Request &request)
    {
        RoleState &state = roleState(request.role);
        NodeBinding *binding = state.binding;
        if (binding == nullptr || binding->id != request.nodeId) {
            postFailure(request, QStringLiteral("stale"));
            return;
        }

        int result = 0;
        if (request.operation == Operation::SetVolume) {
            if (!binding->hasVolumes || binding->visualVolumes.empty()) {
                postFailure(request, QStringLiteral("not-ready"));
                return;
            }
            const auto cubicVolumes =
                nagi::audio::proportionalCubicVolumes(binding->visualVolumes, request.volume);
            if (!cubicVolumes) {
                postFailure(request, QStringLiteral("invalid-state"));
                return;
            }
            std::array<std::uint8_t, 1024> buffer{};
            spa_pod_builder builder{};
            spa_pod_builder_init(
                &builder,
                buffer.data(),
                static_cast<std::uint32_t>(buffer.size()));
            auto *parameter = static_cast<spa_pod *>(spa_pod_builder_add_object(
                &builder,
                SPA_TYPE_OBJECT_Props,
                SPA_PARAM_Props,
                SPA_PROP_channelVolumes,
                SPA_POD_Array(
                    sizeof(float),
                    SPA_TYPE_Float,
                    static_cast<std::uint32_t>(cubicVolumes->size()),
                    cubicVolumes->data())));
            result = pw_node_set_param(binding->node, SPA_PARAM_Props, 0, parameter);
            if (result >= 0) {
                state.volumeInFlight = true;
            }
        } else {
            std::array<std::uint8_t, 256> buffer{};
            spa_pod_builder builder{};
            spa_pod_builder_init(
                &builder,
                buffer.data(),
                static_cast<std::uint32_t>(buffer.size()));
            auto *parameter = static_cast<spa_pod *>(spa_pod_builder_add_object(
                &builder,
                SPA_TYPE_OBJECT_Props,
                SPA_PARAM_Props,
                SPA_PROP_mute,
                SPA_POD_Bool(request.muted)));
            result = pw_node_set_param(binding->node, SPA_PARAM_Props, 0, parameter);
            if (result >= 0) {
                state.muteInFlight = true;
            }
        }

        if (result < 0) {
            postFailure(request, QString::fromLatin1(spa_strerror(result)));
            return;
        }
        const int sequence = pw_core_sync(core, PW_ID_CORE, 0);
        if (sequence < 0) {
            clearInFlight(request);
            postFailure(request, QStringLiteral("sync-failed"));
            return;
        }
        syncRequests[sequence] = request;
    }

    void beginReadback(const Request &request)
    {
        const RoleState &state = roleState(request.role);
        if (state.nodeId != request.nodeId || state.generation != request.generation
            || state.binding == nullptr) {
            clearInFlight(request);
            return;
        }
        const int sequence = ++nextReadbackSequence;
        readbackRequests[sequence] = request;
        const int result = pw_node_enum_params(
            state.binding->node,
            sequence,
            SPA_PARAM_Props,
            0,
            1,
            nullptr);
        if (result < 0) {
            readbackRequests.erase(sequence);
            clearInFlight(request);
            postFailure(request, QStringLiteral("readback-failed"));
        }
    }

    void completeRequest(const Request &request, const NodeBinding &binding)
    {
        RoleState &state = roleState(request.role);
        if (state.nodeId != request.nodeId || state.generation != request.generation
            || state.binding != &binding) {
            return;
        }
        postState(state, binding, &request);
        clearInFlight(request);
        dispatchQueued(request.role);
    }

    void clearInFlight(const Request &request)
    {
        RoleState &state = roleState(request.role);
        if (state.nodeId != request.nodeId || state.generation != request.generation) {
            return;
        }
        if (request.operation == Operation::SetVolume) {
            state.volumeInFlight = false;
        } else if (request.operation == Operation::SetMute) {
            state.muteInFlight = false;
        }
    }

    void dispatchQueued(Role role)
    {
        RoleState &state = roleState(role);
        if (state.muteInFlight || state.volumeInFlight) {
            return;
        }
        if (state.queuedMute) {
            const Request request = *state.queuedMute;
            state.queuedMute.reset();
            dispatch(request);
        } else if (state.queuedVolume) {
            const Request request = *state.queuedVolume;
            state.queuedVolume.reset();
            dispatch(request);
        }
    }

    void handleCommand(const Command &command)
    {
        if (command.operation == Operation::Shutdown) {
            QCoreApplication::quit();
            return;
        }

        pw_thread_loop_lock(threadLoop);
        if (command.operation == Operation::Track) {
            track(command);
        } else if (command.operation == Operation::Untrack) {
            untrack(command);
        } else {
            request(command);
        }
        pw_thread_loop_unlock(threadLoop);
    }

    void readCommands()
    {
        std::array<char, 4096> bytes{};
        const ssize_t count = ::read(STDIN_FILENO, bytes.data(), bytes.size());
        if (count == 0) {
            QCoreApplication::quit();
            return;
        }
        if (count < 0) {
            if (errno != EAGAIN && errno != EINTR) {
                diagnose("stdin read failed");
                QCoreApplication::exit(2);
            }
            return;
        }

        commandBuffer.append(bytes.data(), count);
        if (commandBuffer.size() > nagi::audio::MaximumCommandBytes * 2) {
            diagnose("command buffer exceeded limit");
            commandBuffer.clear();
        }

        while (true) {
            const qsizetype newline = commandBuffer.indexOf('\n');
            if (newline < 0) {
                break;
            }
            QByteArray line = commandBuffer.left(newline);
            commandBuffer.remove(0, newline + 1);
            if (line.endsWith('\r')) {
                line.chop(1);
            }
            QString error;
            const auto command = nagi::audio::parseCommand(line, &error);
            if (!command) {
                diagnose(error.toUtf8().constData());
                continue;
            }
            handleCommand(*command);
        }
    }

    pw_thread_loop *threadLoop = nullptr;
    pw_context *context = nullptr;
    pw_core *core = nullptr;
    pw_registry *registry = nullptr;
    spa_hook coreListener{};
    spa_hook registryListener{};
    bool loopStarted = false;
    bool helperReady = false;
    int initialSyncSequence = -1;
    int nextReadbackSequence = 1000;
    int diagnosticCount = 0;
    QSocketNotifier *stdinNotifier = nullptr;
    QByteArray commandBuffer;
    std::array<RoleState, 2> roles{};
    std::unordered_map<std::uint32_t, KnownNode> knownNodes;
    std::unordered_map<std::uint32_t, std::unique_ptr<NodeBinding>> bindings;
    std::unordered_map<int, Request> syncRequests;
    std::unordered_map<int, Request> readbackRequests;
};

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    try {
        PipeWireBridge bridge;
        return application.exec();
    } catch (const std::exception &error) {
        std::fprintf(stderr, "nagi-shell PipeWire bridge: %.256s\n", error.what());
        return 2;
    }
}

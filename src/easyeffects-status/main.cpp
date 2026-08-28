#include "protocol.h"

#include <QCoreApplication>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QSocketNotifier>
#include <QSet>
#include <QStringList>

#include <algorithm>
#include <array>
#include <cerrno>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <thread>

namespace {

using easyeffects_status::PresetResult;
using easyeffects_status::PresetState;

constexpr qsizetype MaximumFrameBytes = 4096;
constexpr qsizetype MaximumResponseBytes = 101;
constexpr qsizetype MaximumPresetEntries = 128;
constexpr qsizetype MaximumDirectoryEntries = 512;
constexpr qsizetype MaximumPresetListBytes = 1500;
constexpr qint64 MaximumPresetFileBytes = 1024 * 1024;
constexpr auto OperationTimeout = std::chrono::milliseconds(250);

enum class SendState {
    Sent,
    Unavailable,
    Timeout,
};

bool waitFor(int fd, short events, std::chrono::steady_clock::time_point deadline)
{
    while (true) {
        const auto now = std::chrono::steady_clock::now();
        if (now >= deadline) {
            return false;
        }
        const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - now);
        pollfd descriptor{.fd = fd, .events = events, .revents = 0};
        const int result = ::poll(&descriptor, 1, static_cast<int>(remaining.count()));
        if (result > 0) {
            return (descriptor.revents & (events | POLLHUP)) != 0;
        }
        if (result < 0 && errno == EINTR) {
            continue;
        }
        return false;
    }
}

SendState openAndSend(const QByteArray &command, std::chrono::steady_clock::time_point deadline, int &fd)
{
    const char *runtimeDirectory = std::getenv("XDG_RUNTIME_DIR");
    if (runtimeDirectory == nullptr || runtimeDirectory[0] != '/') {
        return SendState::Unavailable;
    }

    const QByteArray socketPath = QByteArray(runtimeDirectory) + "/EasyEffectsServer";
    if (socketPath.size() >= static_cast<qsizetype>(sizeof(sockaddr_un::sun_path))) {
        return SendState::Unavailable;
    }

    fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    if (fd < 0) {
        return SendState::Unavailable;
    }
    const auto fail = [&fd](SendState state) {
        ::close(fd);
        fd = -1;
        return state;
    };

    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    std::memcpy(address.sun_path, socketPath.constData(), static_cast<std::size_t>(socketPath.size() + 1));
    if (::connect(fd, reinterpret_cast<const sockaddr *>(&address), sizeof(address)) < 0) {
        if (errno != EINPROGRESS) {
            return fail(SendState::Unavailable);
        }
        if (!waitFor(fd, POLLOUT, deadline)) {
            return fail(std::chrono::steady_clock::now() >= deadline ? SendState::Timeout : SendState::Unavailable);
        }
        int socketError = 0;
        socklen_t errorSize = sizeof(socketError);
        if (::getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &errorSize) < 0 || socketError != 0) {
            return fail(SendState::Unavailable);
        }
    }

    qsizetype sent = 0;
    while (sent < command.size()) {
        const ssize_t count = ::send(fd, command.constData() + sent,
                                     static_cast<std::size_t>(command.size() - sent), MSG_NOSIGNAL);
        if (count > 0) {
            sent += count;
            continue;
        }
        if (count < 0 && errno == EINTR) {
            continue;
        }
        if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            if (waitFor(fd, POLLOUT, deadline)) {
                continue;
            }
            return fail(std::chrono::steady_clock::now() >= deadline ? SendState::Timeout : SendState::Unavailable);
        }
        return fail(SendState::Unavailable);
    }
    return SendState::Sent;
}

PresetState presetStateFor(SendState state)
{
    return state == SendState::Timeout ? PresetState::Timeout : PresetState::Unavailable;
}

PresetResult queryPreset(const QByteArray &pipeline, std::chrono::steady_clock::time_point deadline)
{
    int fd = -1;
    const SendState sendState = openAndSend("get_last_loaded_preset:" + pipeline + '\n', deadline, fd);
    if (sendState != SendState::Sent) {
        return {.state = presetStateFor(sendState), .name = {}};
    }

    const auto closeSocket = [&fd]() {
        ::close(fd);
        fd = -1;
    };
    ::shutdown(fd, SHUT_WR);

    QByteArray response;
    std::array<char, MaximumResponseBytes + 1> buffer{};
    while (std::chrono::steady_clock::now() < deadline) {
        const ssize_t count = ::recv(fd, buffer.data(), buffer.size(), 0);
        if (count > 0) {
            response.append(buffer.data(), count);
            if (response.size() > MaximumResponseBytes) {
                closeSocket();
                return {.state = PresetState::Invalid, .name = {}};
            }
            const qsizetype newline = response.indexOf('\n');
            if (newline >= 0) {
                closeSocket();
                return easyeffects_status::parsePresetResponse(response);
            }
            continue;
        }
        if (count == 0) {
            closeSocket();
            return {.state = PresetState::Invalid, .name = {}};
        }
        if (errno == EINTR) {
            continue;
        }
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            if (waitFor(fd, POLLIN, deadline)) {
                continue;
            }
            closeSocket();
            return {.state = PresetState::Timeout, .name = {}};
        }
        closeSocket();
        return {.state = PresetState::Unavailable, .name = {}};
    }

    closeSocket();
    return {.state = PresetState::Timeout, .name = {}};
}

PresetResult queryPreset(const QByteArray &pipeline)
{
    return queryPreset(pipeline, std::chrono::steady_clock::now() + OperationTimeout);
}

struct LoadResult {
    QByteArray state;
    PresetResult observed;
};

LoadResult loadPreset(const QByteArray &pipeline, const QString &name)
{
    if (!easyeffects_status::isValidPresetName(name)) {
        return {.state = "invalid", .observed = {}};
    }

    const auto started = std::chrono::steady_clock::now();
    const auto deadline = started + std::chrono::milliseconds(450);
    int fd = -1;
    const SendState sendState =
        openAndSend("load_preset:" + pipeline + ':' + name.toUtf8() + '\n', deadline, fd);
    if (sendState != SendState::Sent) {
        return {.state = presetStateName(presetStateFor(sendState)), .observed = {}};
    }
    ::shutdown(fd, SHUT_WR);
    ::close(fd);

    PresetResult observed;
    constexpr std::array confirmationDelays{std::chrono::milliseconds(10), std::chrono::milliseconds(100),
                                            std::chrono::milliseconds(300)};
    for (const auto delay : confirmationDelays) {
        const auto scheduled = started + delay;
        if (std::chrono::steady_clock::now() < scheduled) {
            std::this_thread::sleep_until(scheduled);
        }
        observed = queryPreset(pipeline, deadline);
        if (observed.state == PresetState::LastLoaded && observed.name == name) {
            return {.state = "confirmed", .observed = observed};
        }
        if (observed.state != PresetState::LastLoaded && observed.state != PresetState::None) {
            return {.state = presetStateName(observed.state), .observed = observed};
        }
    }
    return {.state = "mismatch", .observed = observed};
}

struct PresetList {
    QByteArray state = "ready";
    QStringList names;
};

PresetList discoverPresets(const QByteArray &pipeline)
{
    const char *configuredDataHome = std::getenv("XDG_DATA_HOME");
    const char *home = std::getenv("HOME");
    QString dataHome;
    if (configuredDataHome != nullptr && configuredDataHome[0] == '/') {
        dataHome = QString::fromUtf8(configuredDataHome);
    } else if (home != nullptr && home[0] == '/') {
        dataHome = QString::fromUtf8(home) + QStringLiteral("/.local/share");
    } else {
        return {.state = "unavailable", .names = {}};
    }

    const QString directoryPath =
        dataHome + QStringLiteral("/easyeffects/") + QString::fromUtf8(pipeline);
    const QFileInfo directoryInfo(directoryPath);
    if (!directoryInfo.exists()) {
        return {};
    }
    if (!directoryInfo.isDir() || directoryInfo.isSymbolicLink() || !directoryInfo.isReadable()) {
        return {.state = "unavailable", .names = {}};
    }

    PresetList result;
    QSet<QString> seen;
    qsizetype inspected = 0;
    qsizetype encodedBytes = 0;
    QDirIterator entries(directoryPath, QDir::AllEntries | QDir::NoDotAndDotDot);
    while (entries.hasNext()) {
        entries.next();
        inspected += 1;
        if (inspected > MaximumDirectoryEntries) {
            result.state = "truncated";
            break;
        }
        const QFileInfo info = entries.fileInfo();
        if (!info.isFile() || info.isSymbolicLink() || info.suffix() != QLatin1String("json")
            || info.size() < 0 || info.size() > MaximumPresetFileBytes) {
            continue;
        }
        const QString name = info.completeBaseName();
        const qsizetype nameBytes = name.toUtf8().size();
        if (!easyeffects_status::isValidPresetName(name) || seen.contains(name)) {
            continue;
        }
        if (result.names.size() >= MaximumPresetEntries
            || encodedBytes + nameBytes > MaximumPresetListBytes) {
            result.state = "truncated";
            break;
        }
        seen.insert(name);
        result.names.append(name);
        encodedBytes += nameBytes;
    }
    std::sort(result.names.begin(), result.names.end(), [](const QString &left, const QString &right) {
        const int folded = QString::compare(left, right, Qt::CaseInsensitive);
        return folded == 0 ? left < right : folded < 0;
    });
    return result;
}

void publish(const QJsonObject &message)
{
    const QByteArray frame = QJsonDocument(message).toJson(QJsonDocument::Compact);
    if (frame.size() > MaximumFrameBytes) {
        return;
    }
    QFile output;
    if (!output.open(stdout, QIODevice::WriteOnly)) {
        return;
    }
    output.write(frame);
    output.write("\n");
    output.flush();
}

bool hasExactKeys(const QJsonObject &object, std::initializer_list<const char *> keys)
{
    if (object.size() != static_cast<qsizetype>(keys.size())) {
        return false;
    }
    for (const char *key : keys) {
        if (!object.contains(QLatin1String(key))) {
            return false;
        }
    }
    return true;
}

bool validGeneration(const QJsonValue &value)
{
    return value.isDouble() && value.toDouble() >= 1 && value.toDouble() <= 2147483647
        && value.toDouble() == static_cast<int>(value.toDouble());
}

class Helper final : public QObject
{
public:
    explicit Helper(QObject *parent = nullptr)
        : QObject(parent)
        , inputNotifier(STDIN_FILENO, QSocketNotifier::Read, this)
    {
        connect(&inputNotifier, &QSocketNotifier::activated, this, [this]() { readCommands(); });
        publish({{"type", "ready"}});
    }

private:
    void readCommands()
    {
        std::array<char, 1024> chunk{};
        while (true) {
            const ssize_t count = ::read(STDIN_FILENO, chunk.data(), chunk.size());
            if (count > 0) {
                inputBuffer.append(chunk.data(), count);
                if (inputBuffer.size() > MaximumFrameBytes && !inputBuffer.contains('\n')) {
                    QCoreApplication::exit(2);
                    return;
                }
                consumeFrames();
                continue;
            }
            if (count == 0) {
                QCoreApplication::quit();
                return;
            }
            if (errno == EINTR) {
                continue;
            }
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                return;
            }
            QCoreApplication::exit(2);
            return;
        }
    }

    void consumeFrames()
    {
        while (true) {
            const qsizetype newline = inputBuffer.indexOf('\n');
            if (newline < 0) {
                return;
            }
            const QByteArray frame = inputBuffer.first(newline);
            inputBuffer.remove(0, newline + 1);
            if (frame.isEmpty() || frame.size() > MaximumFrameBytes) {
                QCoreApplication::exit(2);
                return;
            }
            handleFrame(frame);
        }
    }

    void handleFrame(const QByteArray &frame)
    {
        QJsonParseError error{};
        const QJsonDocument document = QJsonDocument::fromJson(frame, &error);

        if (error.error != QJsonParseError::NoError || !document.isObject()) {
            QCoreApplication::exit(2);
            return;
        }
        const QJsonObject command = document.object();
        const QJsonValue operation = command.value("op");
        if (!operation.isString()) {
            QCoreApplication::exit(2);
            return;
        }

        if (operation.toString() == QLatin1String("shutdown") && hasExactKeys(command, {"op"})) {
            QCoreApplication::quit();
            return;
        }
        if (operation.toString() == QLatin1String("interest")
            && hasExactKeys(command, {"op", "generation", "active"})
            && validGeneration(command.value("generation")) && command.value("active").isBool()) {
            const int generation = command.value("generation").toInt();
            if (!command.value("active").toBool()) {
                if (generation == activeGeneration) {
                    activeGeneration = 0;
                }
                return;
            }
            activeGeneration = generation;
            snapshot(generation);
            return;
        }
        if (operation.toString() == QLatin1String("refresh")
            && hasExactKeys(command, {"op", "generation"})
            && validGeneration(command.value("generation"))
            && command.value("generation").toInt() == activeGeneration) {
            snapshot(activeGeneration);
            return;
        }
        if (operation.toString() == QLatin1String("load")
            && hasExactKeys(command, {"op", "generation", "pipeline", "name"})
            && validGeneration(command.value("generation"))
            && command.value("generation").toInt() == activeGeneration
            && command.value("pipeline").isString() && command.value("name").isString()) {
            const QByteArray pipeline = command.value("pipeline").toString().toUtf8();
            if (pipeline != "output" && pipeline != "input") {
                QCoreApplication::exit(2);
                return;
            }
            const QString requestedName = command.value("name").toString();
            const PresetList available = discoverPresets(pipeline);
            if (available.state == "unavailable" || !available.names.contains(requestedName)) {
                publish({{"type", "load"},
                         {"generation", activeGeneration},
                         {"pipeline", QString::fromUtf8(pipeline)},
                         {"state", available.state == "unavailable" ? "unavailable" : "invalid"}});
                return;
            }
            const LoadResult result = loadPreset(pipeline, requestedName);
            if (result.observed.state == PresetState::LastLoaded || result.observed.state == PresetState::None) {
                publishPipeline(activeGeneration, pipeline.constData(), result.observed);
            }
            publish({{"type", "load"},
                     {"generation", activeGeneration},
                     {"pipeline", QString::fromUtf8(pipeline)},
                     {"state", QString::fromUtf8(result.state)}});
            return;
        }
        QCoreApplication::exit(2);
    }

    void snapshot(int generation)
    {
        publishPipeline(generation, "output", queryPreset("output"));
        publishPipeline(generation, "input", queryPreset("input"));
        publishPresetList(generation, "output", discoverPresets("output"));
        publishPresetList(generation, "input", discoverPresets("input"));
    }

    static void publishPipeline(int generation, const char *pipeline, const PresetResult &result)
    {
        QJsonObject message{{"type", "pipeline"},
                            {"generation", generation},
                            {"pipeline", pipeline},
                            {"state", easyeffects_status::presetStateName(result.state)}};
        if (result.state == PresetState::LastLoaded) {
            message.insert("name", result.name);
        }
        publish(message);
    }

    static void publishPresetList(int generation, const char *pipeline, const PresetList &result)
    {
        publish({{"type", "presets"},
                 {"generation", generation},
                 {"pipeline", pipeline},
                 {"state", QString::fromUtf8(result.state)},
                 {"items", QJsonArray::fromStringList(result.names)}});
    }

    QSocketNotifier inputNotifier;
    QByteArray inputBuffer;
    int activeGeneration = 0;
};

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    const int flags = ::fcntl(STDIN_FILENO, F_GETFL, 0);
    if (flags < 0 || ::fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK) < 0) {
        return 2;
    }
    Helper helper;
    return application.exec();
}

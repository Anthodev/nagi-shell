#include <QCoreApplication>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QDBusServiceWatcher>
#include <QElapsedTimer>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QJsonValue>
#include <QSocketNotifier>
#include <QTimer>
#include <QVariantMap>

#include <algorithm>
#include <array>
#include <cerrno>
#include <cmath>
#include <cstdio>
#include <limits>
#include <optional>

#include <unistd.h>

namespace {

constexpr auto Service = "org.kde.ScreenBrightness";
constexpr auto RootPath = "/org/kde/ScreenBrightness";
constexpr auto RootInterface = "org.kde.ScreenBrightness";
constexpr auto DisplayInterface = "org.kde.ScreenBrightness.Display";
constexpr auto PropertiesInterface = "org.freedesktop.DBus.Properties";
constexpr int DbusTimeoutMs = 2000;
constexpr int RequestTimeoutMs = 2500;
constexpr int MaximumCommandBytes = 4096;
constexpr int MaximumDiagnostics = 8;
constexpr int MaximumDisplays = 32;
constexpr int MaximumDisplayNameLength = 128;
constexpr int MaximumLabelLength = 128;
constexpr quint32 SuppressIndicator = 0x1;

struct DisplayState {
    QString name;
    QString key;
    QString label;
    bool isInternal = false;
    int maximum = 0;
    int brightness = 0;
};

struct PendingRequest {
    int requestId = 0;
    int generation = 0;
    QString key;
    QString name;
    QString context;
    int requestedBrightness = 0;
    int maximum = 0;
    qint64 deadlineMs = 0;
};

struct ObservedChange {
    QString name;
    int brightness = 0;
    QString origin;
    int requestId = 0;
};

QString normalizeDbusFailure(const QDBusError &error)
{
    if (error.type() == QDBusError::NoReply || error.type() == QDBusError::Timeout) {
        return QStringLiteral("timeout");
    }
    if (error.type() == QDBusError::ServiceUnknown
        || error.type() == QDBusError::UnknownObject
        || error.type() == QDBusError::UnknownInterface
        || error.type() == QDBusError::UnknownMethod) {
        return QStringLiteral("unavailable");
    }
    return QStringLiteral("backend");
}

class BrightnessBridge final : public QObject {
    Q_OBJECT

public:
    explicit BrightnessBridge(QObject *parent = nullptr)
        : QObject(parent)
        , bus(QDBusConnection::sessionBus())
        , watcher(QString::fromLatin1(Service), bus,
                  QDBusServiceWatcher::WatchForOwnerChange, this)
    {
        monotonicClock.start();
        requestTimer.setSingleShot(true);
        connect(&requestTimer, &QTimer::timeout, this, &BrightnessBridge::expireRequests);
        connect(&watcher, &QDBusServiceWatcher::serviceOwnerChanged, this,
                &BrightnessBridge::onServiceOwnerChanged);

        stdinNotifier = new QSocketNotifier(STDIN_FILENO, QSocketNotifier::Read, this);
        connect(stdinNotifier, &QSocketNotifier::activated, this, &BrightnessBridge::readCommands);

        QTimer::singleShot(0, this, [this] {
            publishMessage(QJsonObject{{QStringLiteral("type"), QStringLiteral("ready")}});
            initialize();
        });
    }

    ~BrightnessBridge() override
    {
        detachOwner();
    }

private slots:
    void onRootSignal(const QDBusMessage &message)
    {
        const QString member = message.member();
        const QList<QVariant> arguments = message.arguments();
        if (member == QStringLiteral("BrightnessChanged")) {
            if (arguments.size() != 4) {
                diagnose(QStringLiteral("invalid brightness signal"));
                return;
            }
            const QString name = arguments.at(0).toString();
            const int brightness = arguments.at(1).toInt();
            if (!validDisplayName(name)) {
                diagnose(QStringLiteral("invalid brightness display"));
                return;
            }

            ObservedChange observed;
            observed.name = name;
            observed.brightness = brightness;
            const auto pending = pendingRequests.constFind(name);
            const QString sourceName = arguments.at(2).toString();
            const QString sourceContext = arguments.at(3).toString();
            if (pending != pendingRequests.cend() && sourceName == bus.baseService()
                && sourceContext == pending->context) {
                observed.origin = QStringLiteral("self");
                observed.requestId = pending->requestId;
            } else if (!sourceName.isEmpty() || !sourceContext.isEmpty()) {
                observed.origin = QStringLiteral("external");
            } else {
                observed.origin = QStringLiteral("unknown");
            }
            queueObservedChange(observed);
            scheduleSnapshot();
            return;
        }

        if (arguments.isEmpty() || !validDisplayName(arguments.constFirst().toString())) {
            diagnose(QStringLiteral("invalid display lifecycle signal"));
            return;
        }
        const QString name = arguments.constFirst().toString();
        if (member == QStringLiteral("BrightnessRangeChanged")) {
            clearPending(name, QStringLiteral("stale"));
        }
        scheduleSnapshot();
    }

    void onServiceOwnerChanged(const QString &, const QString &, const QString &newOwner)
    {
        if (newOwner == activeOwner) {
            return;
        }

        detachOwner();
        publishUnavailable();
        if (!newOwner.isEmpty()) {
            attachOwner(newOwner);
        }
    }

private:
    void initialize()
    {
        if (!bus.isConnected()) {
            diagnose(QStringLiteral("session bus is unavailable"));
            publishUnavailable();
            return;
        }
        const QString owner = currentServiceOwner();
        if (owner.isEmpty()) {
            publishUnavailable();
            return;
        }
        attachOwner(owner);
    }

    QString currentServiceOwner() const
    {
        QDBusConnectionInterface *connectionInterface = bus.interface();
        if (connectionInterface == nullptr) {
            return {};
        }
        const QDBusReply<QString> reply = connectionInterface->serviceOwner(
            QString::fromLatin1(Service));
        return reply.isValid() ? reply.value() : QString{};
    }

    void attachOwner(const QString &owner)
    {
        if (owner.isEmpty() || owner == activeOwner) {
            return;
        }
        if (!activeOwner.isEmpty()) {
            detachOwner();
        }

        if (ownerGeneration == std::numeric_limits<int>::max()) {
            diagnose(QStringLiteral("owner generation exhausted"));
            return;
        }
        ownerGeneration += 1;
        activeOwner = owner;

        bool subscribed = true;
        const auto subscribe = [this, &owner, &subscribed](const char *signal) {
            subscribed &= bus.connect(owner, QString::fromLatin1(RootPath),
                                      QString::fromLatin1(RootInterface),
                                      QString::fromLatin1(signal), this,
                                      SLOT(onRootSignal(QDBusMessage)));
        };
        subscribe("DisplayAdded");
        subscribe("DisplayRemoved");
        subscribe("BrightnessChanged");
        subscribe("BrightnessRangeChanged");
        if (!subscribed) {
            diagnose(QStringLiteral("one or more brightness subscriptions failed"));
        }
        scheduleSnapshot();
    }

    void detachOwner()
    {
        snapshotScheduled = false;
        observedChanges.clear();
        clearAllPending();
        displays.clear();
        displayFailures.clear();
        if (activeOwner.isEmpty()) {
            return;
        }

        const auto unsubscribe = [this](const char *signal) {
            bus.disconnect(activeOwner, QString::fromLatin1(RootPath),
                           QString::fromLatin1(RootInterface), QString::fromLatin1(signal), this,
                           SLOT(onRootSignal(QDBusMessage)));
        };
        unsubscribe("DisplayAdded");
        unsubscribe("DisplayRemoved");
        unsubscribe("BrightnessChanged");
        unsubscribe("BrightnessRangeChanged");
        activeOwner.clear();
    }

    void scheduleSnapshot()
    {
        if (snapshotScheduled || activeOwner.isEmpty()) {
            return;
        }
        snapshotScheduled = true;
        QTimer::singleShot(0, this, &BrightnessBridge::refreshSnapshot);
    }

    std::optional<QVariantMap> readProperties(const QString &owner, const QString &path,
                                              const char *interface)
    {
        QDBusMessage request = QDBusMessage::createMethodCall(
            owner, path, QString::fromLatin1(PropertiesInterface), QStringLiteral("GetAll"));
        request << QString::fromLatin1(interface);
        const QDBusMessage reply = bus.call(request, QDBus::Block, DbusTimeoutMs);
        if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().size() != 1) {
            return std::nullopt;
        }
        return qdbus_cast<QVariantMap>(reply.arguments().constFirst());
    }

    std::optional<DisplayState> readDisplay(const QString &owner, const QString &name)
    {
        if (!validDisplayName(name)) {
            diagnose(QStringLiteral("invalid display name"));
            return std::nullopt;
        }
        const QString path = QString::fromLatin1(RootPath) + QLatin1Char('/') + name;
        const auto properties = readProperties(owner, path, DisplayInterface);
        if (!properties) {
            diagnose(QStringLiteral("display property snapshot failed"));
            return std::nullopt;
        }

        const QVariant labelValue = properties->value(QStringLiteral("Label"));
        const QVariant internalValue = properties->value(QStringLiteral("IsInternal"));
        const QVariant maximumValue = properties->value(QStringLiteral("MaxBrightness"));
        const QVariant brightnessValue = properties->value(QStringLiteral("Brightness"));
        if (labelValue.metaType() != QMetaType::fromType<QString>()
            || internalValue.metaType() != QMetaType::fromType<bool>()
            || maximumValue.metaType() != QMetaType::fromType<int>()
            || brightnessValue.metaType() != QMetaType::fromType<int>()) {
            diagnose(QStringLiteral("invalid display property types"));
            return std::nullopt;
        }

        const int maximum = maximumValue.toInt();
        const int brightness = brightnessValue.toInt();
        if (maximum <= 0 || brightness < 0 || brightness > maximum) {
            diagnose(QStringLiteral("invalid display brightness range"));
            return std::nullopt;
        }

        DisplayState display;
        display.name = name;
        display.key = QString::number(ownerGeneration) + QLatin1Char(':') + name;
        display.label = labelValue.toString().left(MaximumLabelLength);
        display.isInternal = internalValue.toBool();
        display.maximum = maximum;
        display.brightness = brightness;
        return display;
    }

    void refreshSnapshot()
    {
        snapshotScheduled = false;
        const QString requestedOwner = activeOwner;
        const int requestedGeneration = ownerGeneration;
        if (requestedOwner.isEmpty()) {
            return;
        }

        const auto rootProperties = readProperties(requestedOwner, QString::fromLatin1(RootPath),
                                                   RootInterface);
        if (!rootProperties) {
            diagnose(QStringLiteral("brightness root snapshot failed"));
            return;
        }
        const QVariant namesValue = rootProperties->value(QStringLiteral("DisplaysDBusNames"));
        if (namesValue.metaType() != QMetaType::fromType<QStringList>()) {
            diagnose(QStringLiteral("invalid display list type"));
            return;
        }

        QStringList names = namesValue.toStringList();
        names.removeDuplicates();
        std::sort(names.begin(), names.end());
        if (names.size() > MaximumDisplays) {
            diagnose(QStringLiteral("display list exceeded limit"));
            names = names.mid(0, MaximumDisplays);
        }

        QHash<QString, DisplayState> refreshed;
        for (const QString &name : std::as_const(names)) {
            const auto display = readDisplay(requestedOwner, name);
            if (display) {
                refreshed.insert(name, *display);
            }
        }

        if (activeOwner != requestedOwner || ownerGeneration != requestedGeneration
            || currentServiceOwner() != requestedOwner) {
            return;
        }

        QVector<int> staleRequestIds;
        for (auto pending = pendingRequests.begin(); pending != pendingRequests.end();) {
            const auto display = refreshed.constFind(pending.key());
            if (display == refreshed.cend() || display->maximum != pending->maximum) {
                staleRequestIds.push_back(pending->requestId);
                pending = pendingRequests.erase(pending);
            } else {
                ++pending;
            }
        }
        armRequestTimer();
        displays = refreshed;

        QVector<ObservedChange> confirmedChanges;
        for (const ObservedChange &observed : std::as_const(observedChanges)) {
            const auto display = displays.constFind(observed.name);
            if (display == displays.cend() || display->brightness != observed.brightness) {
                continue;
            }
            ObservedChange confirmed = observed;
            if (observed.origin == QStringLiteral("self")) {
                const auto pending = pendingRequests.constFind(observed.name);
                if (pending == pendingRequests.cend()
                    || pending->requestId != observed.requestId) {
                    continue;
                }
                pendingRequests.remove(observed.name);
                displayFailures.remove(observed.name);
                armRequestTimer();
            } else {
                displayFailures.remove(observed.name);
            }
            confirmedChanges.push_back(confirmed);
        }
        observedChanges.clear();

        if (staleRequestIds.isEmpty() && confirmedChanges.isEmpty()) {
            publishState(std::nullopt, std::nullopt);
            return;
        }
        for (int requestId : std::as_const(staleRequestIds)) {
            publishRequestResult(requestId, QStringLiteral("stale"), std::nullopt);
        }
        for (const ObservedChange &change : std::as_const(confirmedChanges)) {
            std::optional<QJsonObject> request;
            if (change.origin == QStringLiteral("self")) {
                request = requestResult(change.requestId, QStringLiteral("confirmed"));
            }
            publishState(change, request);
        }
    }

    void requestBrightness(int requestId, const QString &key, double ratio)
    {
        const auto display = std::find_if(displays.cbegin(), displays.cend(),
                                          [&key](const DisplayState &candidate) {
                                              return candidate.key == key;
                                          });
        if (activeOwner.isEmpty() || display == displays.cend()) {
            publishRequestResult(requestId, QStringLiteral("stale"), std::nullopt);
            return;
        }
        for (const PendingRequest &pending : std::as_const(pendingRequests)) {
            if (pending.requestId == requestId) {
                publishRequestResult(requestId, QStringLiteral("busy"), std::nullopt);
                return;
            }
        }
        if (pendingRequests.contains(display.key())) {
            publishRequestResult(requestId, QStringLiteral("busy"), std::nullopt);
            return;
        }

        const int requestedBrightness = std::clamp(
            static_cast<int>(std::lround(ratio * static_cast<double>(display->maximum))), 0,
            display->maximum);
        if (requestedBrightness == display->brightness) {
            displayFailures.remove(display.key());
            publishRequestResult(requestId, QStringLiteral("noop"), std::nullopt);
            return;
        }

        PendingRequest pending;
        pending.requestId = requestId;
        pending.generation = ownerGeneration;
        pending.key = display->key;
        pending.name = display.key();
        pending.context = QStringLiteral("nagi-shell:") + QString::number(requestId);
        pending.requestedBrightness = requestedBrightness;
        pending.maximum = display->maximum;
        pending.deadlineMs = monotonicClock.elapsed() + RequestTimeoutMs;
        pendingRequests.insert(display.key(), pending);
        displayFailures.remove(display.key());
        armRequestTimer();
        publishRequestResult(requestId, QStringLiteral("pending"), std::nullopt);

        const QString owner = activeOwner;
        const int generation = ownerGeneration;
        const QString name = display.key();
        const QString path = QString::fromLatin1(RootPath) + QLatin1Char('/') + name;
        QDBusMessage request = QDBusMessage::createMethodCall(
            owner, path, QString::fromLatin1(DisplayInterface),
            QStringLiteral("SetBrightnessWithContext"));
        request << requestedBrightness << SuppressIndicator << pending.context;
        auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(request, DbusTimeoutMs), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this,
                [this, watcher, owner, generation, name, requestId] {
                    const QDBusPendingReply<> reply = *watcher;
                    watcher->deleteLater();
                    const auto pending = pendingRequests.constFind(name);
                    if (activeOwner != owner || ownerGeneration != generation
                        || pending == pendingRequests.cend()
                        || pending->requestId != requestId || !reply.isError()) {
                        return;
                    }
                    const QString outcome = normalizeDbusFailure(reply.error());
                    pendingRequests.remove(name);
                    displayFailures.insert(name, outcome);
                    armRequestTimer();
                    publishRequestResult(requestId, outcome, std::nullopt);
                });
    }

    void handleCommand(const QJsonObject &command)
    {
        const QString action = command.value(QStringLiteral("action")).toString();
        if (action == QStringLiteral("shutdown") && command.size() == 1) {
            QCoreApplication::quit();
            return;
        }

        const QJsonValue requestValue = command.value(QStringLiteral("requestId"));
        const QJsonValue ratioValue = command.value(QStringLiteral("ratio"));
        const QString key = command.value(QStringLiteral("displayKey")).toString();
        const bool validRequestId = requestValue.isDouble() && requestValue.toDouble() >= 1
            && requestValue.toDouble() <= std::numeric_limits<int>::max()
            && requestValue.toInt() == requestValue.toDouble();
        const bool validRatio = ratioValue.isDouble() && std::isfinite(ratioValue.toDouble())
            && ratioValue.toDouble() >= 0.0 && ratioValue.toDouble() <= 1.0;
        if (command.size() != 4 || action != QStringLiteral("setBrightness") || !validRequestId
            || key.isEmpty() || key.size() > MaximumDisplayNameLength + 16 || !validRatio) {
            diagnose(QStringLiteral("invalid command schema"));
            if (validRequestId) {
                publishRequestResult(requestValue.toInt(), QStringLiteral("invalid"), std::nullopt);
            }
            return;
        }
        requestBrightness(requestValue.toInt(), key, ratioValue.toDouble());
    }

    void readCommands()
    {
        std::array<char, MaximumCommandBytes> bytes{};
        const ssize_t count = ::read(STDIN_FILENO, bytes.data(), bytes.size());
        if (count == 0) {
            QCoreApplication::quit();
            return;
        }
        if (count < 0) {
            if (errno != EAGAIN && errno != EINTR) {
                diagnose(QStringLiteral("stdin read failed"));
                QCoreApplication::exit(2);
            }
            return;
        }

        commandBuffer.append(bytes.data(), count);
        if (commandBuffer.size() > MaximumCommandBytes * 2) {
            diagnose(QStringLiteral("command buffer exceeded limit"));
            commandBuffer.clear();
        }
        while (true) {
            const qsizetype newline = commandBuffer.indexOf('\n');
            if (newline < 0) {
                return;
            }
            QByteArray line = commandBuffer.left(newline);
            commandBuffer.remove(0, newline + 1);
            if (line.endsWith('\r')) {
                line.chop(1);
            }
            if (line.isEmpty() || line.size() > MaximumCommandBytes) {
                diagnose(QStringLiteral("invalid command length"));
                continue;
            }
            QJsonParseError error;
            const QJsonDocument document = QJsonDocument::fromJson(line, &error);
            if (error.error != QJsonParseError::NoError || !document.isObject()) {
                diagnose(QStringLiteral("malformed command"));
                continue;
            }
            handleCommand(document.object());
        }
    }

    bool validDisplayName(const QString &name) const
    {
        if (name.isEmpty() || name.size() > MaximumDisplayNameLength) {
            return false;
        }
        for (const QChar character : name) {
            const ushort value = character.unicode();
            if (!((value >= 'A' && value <= 'Z') || (value >= 'a' && value <= 'z')
                  || (value >= '0' && value <= '9') || value == '_')) {
                return false;
            }
        }
        return true;
    }

    void queueObservedChange(const ObservedChange &change)
    {
        for (ObservedChange &queued : observedChanges) {
            if (queued.name == change.name) {
                queued = change;
                return;
            }
        }
        if (observedChanges.size() >= MaximumDisplays) {
            observedChanges.removeFirst();
        }
        observedChanges.push_back(change);
    }

    void clearPending(const QString &name, const QString &outcome)
    {
        const auto pending = pendingRequests.find(name);
        if (pending == pendingRequests.end()) {
            return;
        }
        const int requestId = pending->requestId;
        pendingRequests.erase(pending);
        armRequestTimer();
        publishRequestResult(requestId, outcome, std::nullopt);
    }

    void clearAllPending()
    {
        pendingRequests.clear();
        requestTimer.stop();
    }

    void expireRequests()
    {
        const qint64 now = monotonicClock.elapsed();
        QVector<int> expired;
        for (auto pending = pendingRequests.begin(); pending != pendingRequests.end();) {
            if (pending->deadlineMs > now) {
                ++pending;
                continue;
            }
            expired.push_back(pending->requestId);
            displayFailures.insert(pending.key(), QStringLiteral("timeout"));
            pending = pendingRequests.erase(pending);
        }
        armRequestTimer();
        for (int requestId : std::as_const(expired)) {
            publishRequestResult(requestId, QStringLiteral("timeout"), std::nullopt);
        }
    }

    void armRequestTimer()
    {
        if (pendingRequests.isEmpty()) {
            requestTimer.stop();
            return;
        }
        qint64 nearest = std::numeric_limits<qint64>::max();
        for (const PendingRequest &pending : std::as_const(pendingRequests)) {
            nearest = std::min(nearest, pending.deadlineMs);
        }
        const qint64 remaining = std::max<qint64>(1, nearest - monotonicClock.elapsed());
        requestTimer.start(static_cast<int>(std::min<qint64>(remaining,
                                                             std::numeric_limits<int>::max())));
    }

    QJsonObject displayJson(const DisplayState &display) const
    {
        const auto pending = pendingRequests.constFind(display.name);
        return {
            {QStringLiteral("key"), display.key},
            {QStringLiteral("label"), display.label},
            {QStringLiteral("isInternal"), display.isInternal},
            {QStringLiteral("ratio"), static_cast<double>(display.brightness)
                 / static_cast<double>(display.maximum)},
            {QStringLiteral("pending"), pending != pendingRequests.cend()},
            {QStringLiteral("failure"), displayFailures.value(display.name,
                                                               QStringLiteral("none"))},
        };
    }

    QJsonObject changeJson(const ObservedChange &change) const
    {
        const DisplayState &display = displays.value(change.name);
        QJsonObject result{
            {QStringLiteral("key"), display.key},
            {QStringLiteral("ratio"), static_cast<double>(display.brightness)
                 / static_cast<double>(display.maximum)},
            {QStringLiteral("origin"), change.origin},
        };
        if (change.origin == QStringLiteral("self")) {
            result.insert(QStringLiteral("requestId"), change.requestId);
        } else {
            result.insert(QStringLiteral("requestId"), 0);
        }
        return result;
    }

    QJsonObject requestResult(int requestId, const QString &outcome) const
    {
        return {
            {QStringLiteral("requestId"), requestId},
            {QStringLiteral("outcome"), outcome},
        };
    }

    void publishRequestResult(int requestId, const QString &outcome,
                              const std::optional<ObservedChange> &change)
    {
        publishState(change, requestResult(requestId, outcome));
    }

    void publishUnavailable()
    {
        QJsonObject message{
            {QStringLiteral("type"), QStringLiteral("state")},
            {QStringLiteral("available"), false},
            {QStringLiteral("supported"), false},
            {QStringLiteral("generation"), 0},
            {QStringLiteral("displays"), QJsonArray{}},
            {QStringLiteral("change"), QJsonValue::Null},
            {QStringLiteral("request"), QJsonValue::Null},
        };
        publishMessage(message, true);
    }

    void publishState(const std::optional<ObservedChange> &change,
                      const std::optional<QJsonObject> &request)
    {
        QJsonArray displayArray;
        QStringList names = displays.keys();
        std::sort(names.begin(), names.end());
        for (const QString &name : std::as_const(names)) {
            displayArray.push_back(displayJson(displays.value(name)));
        }
        QJsonObject message{
            {QStringLiteral("type"), QStringLiteral("state")},
            {QStringLiteral("available"), !activeOwner.isEmpty()},
            {QStringLiteral("supported"), !displays.isEmpty()},
            {QStringLiteral("generation"), activeOwner.isEmpty() ? 0 : ownerGeneration},
            {QStringLiteral("displays"), displayArray},
            {QStringLiteral("change"), change ? QJsonValue(changeJson(*change)) : QJsonValue::Null},
            {QStringLiteral("request"), request ? QJsonValue(*request) : QJsonValue::Null},
        };
        publishMessage(message, change.has_value() || request.has_value());
    }

    void publishMessage(const QJsonObject &message, bool force = false)
    {
        const QByteArray bytes = QJsonDocument(message).toJson(QJsonDocument::Compact);
        if (!force && bytes == lastStateMessage) {
            return;
        }
        if (message.value(QStringLiteral("type")) == QStringLiteral("state")) {
            lastStateMessage = bytes;
        }
        std::fwrite(bytes.constData(), 1, static_cast<size_t>(bytes.size()), stdout);
        std::fputc('\n', stdout);
        std::fflush(stdout);
    }

    void diagnose(const QString &message)
    {
        if (diagnosticCount >= MaximumDiagnostics || message == lastDiagnostic) {
            return;
        }
        lastDiagnostic = message;
        diagnosticCount += 1;
        const QByteArray bounded = message.left(256).toUtf8();
        std::fprintf(stderr, "nagi-shell brightness helper: %s\n", bounded.constData());
        std::fflush(stderr);
    }

    QDBusConnection bus;
    QDBusServiceWatcher watcher;
    QSocketNotifier *stdinNotifier = nullptr;
    QTimer requestTimer;
    QElapsedTimer monotonicClock;
    QString activeOwner;
    QByteArray commandBuffer;
    QByteArray lastStateMessage;
    QString lastDiagnostic;
    QHash<QString, DisplayState> displays;
    QHash<QString, PendingRequest> pendingRequests;
    QHash<QString, QString> displayFailures;
    QVector<ObservedChange> observedChanges;
    int ownerGeneration = 0;
    int diagnosticCount = 0;
    bool snapshotScheduled = false;
};

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    application.setApplicationName(QStringLiteral("nagi-brightness"));
    BrightnessBridge bridge;
    return application.exec();
}

#include "main.moc"

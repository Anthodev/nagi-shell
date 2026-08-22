#include <QCoreApplication>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QDBusServiceWatcher>
#include <QDBusVariant>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QSocketNotifier>
#include <QTimer>
#include <QVariantMap>

#include <array>
#include <cerrno>
#include <cstdio>
#include <limits>
#include <optional>
#include <unistd.h>

using InterfaceProperties = QMap<QString, QVariantMap>;
using ManagedObjectMap = QMap<QDBusObjectPath, InterfaceProperties>;

Q_DECLARE_METATYPE(InterfaceProperties)
Q_DECLARE_METATYPE(ManagedObjectMap)

namespace {

constexpr auto NetworkService = "org.freedesktop.NetworkManager";
constexpr auto NetworkPath = "/org/freedesktop/NetworkManager";
constexpr auto NetworkInterface = "org.freedesktop.NetworkManager";
constexpr auto NetworkDeviceInterface = "org.freedesktop.NetworkManager.Device";
constexpr auto BluezService = "org.bluez";
constexpr auto BluezPath = "/";
constexpr auto BluezAdapterInterface = "org.bluez.Adapter1";
constexpr auto ObjectManagerInterface = "org.freedesktop.DBus.ObjectManager";
constexpr auto PropertiesInterface = "org.freedesktop.DBus.Properties";
constexpr int WifiDeviceType = 2;
constexpr int DbusTimeoutMs = 2000;
constexpr int RequestTimeoutMs = 3000;
constexpr int MaximumCommandBytes = 4096;
constexpr int MaximumDiagnostics = 8;

struct AdapterState {
    bool available = false;
    bool enabled = false;
    bool hardwareEnabled = false;
    bool pending = false;
    bool targetEnabled = false;
    int requestId = 0;
    QString failure = QStringLiteral("none");
};

QDBusConnection connectivityBus()
{
    return qEnvironmentVariable("NAGI_CONNECTIVITY_BUS") == QStringLiteral("session")
        ? QDBusConnection::sessionBus()
        : QDBusConnection::systemBus();
}

QVariant unwrapDbusVariant(const QVariant &value)
{
    return value.metaType() == QMetaType::fromType<QDBusVariant>()
        ? value.value<QDBusVariant>().variant()
        : value;
}

QString normalizeFailure(const QDBusError &error)
{
    const QString name = error.name().toLower();
    if (name.contains(QStringLiteral("accessdenied"))
        || name.contains(QStringLiteral("notauthorized"))
        || name.contains(QStringLiteral("permissiondenied"))
        || name.contains(QStringLiteral("authentication"))) {
        return QStringLiteral("denied");
    }
    if (error.type() == QDBusError::NoReply || error.type() == QDBusError::Timeout
        || name.contains(QStringLiteral("timeout"))) {
        return QStringLiteral("timeout");
    }
    return QStringLiteral("backend");
}

class ConnectivityBridge final : public QObject {
    Q_OBJECT

public:
    explicit ConnectivityBridge(QObject *parent = nullptr)
        : QObject(parent)
        , bus(connectivityBus())
        , networkWatcher(
              QString::fromLatin1(NetworkService),
              bus,
              QDBusServiceWatcher::WatchForOwnerChange,
              this)
        , bluezWatcher(
              QString::fromLatin1(BluezService),
              bus,
              QDBusServiceWatcher::WatchForOwnerChange,
              this)
    {
        wifiRequestTimer.setSingleShot(true);
        wifiRequestTimer.setInterval(RequestTimeoutMs);
        bluetoothRequestTimer.setSingleShot(true);
        bluetoothRequestTimer.setInterval(RequestTimeoutMs);

        connect(
            &networkWatcher,
            &QDBusServiceWatcher::serviceOwnerChanged,
            this,
            &ConnectivityBridge::onNetworkOwnerChanged);
        connect(
            &bluezWatcher,
            &QDBusServiceWatcher::serviceOwnerChanged,
            this,
            &ConnectivityBridge::onBluezOwnerChanged);
        connect(&wifiRequestTimer, &QTimer::timeout, this, [this] {
            failRequest(wifi, QStringLiteral("timeout"));
        });
        connect(&bluetoothRequestTimer, &QTimer::timeout, this, [this] {
            failRequest(bluetooth, QStringLiteral("timeout"));
        });

        stdinNotifier = new QSocketNotifier(STDIN_FILENO, QSocketNotifier::Read, this);
        connect(stdinNotifier, &QSocketNotifier::activated, this, [this] { readCommands(); });
        QTimer::singleShot(0, this, &ConnectivityBridge::initialize);
    }

    ~ConnectivityBridge() override
    {
        detachNetworkOwner();
        detachBluezOwner();
    }

private slots:
    void onNetworkSignal(const QDBusMessage &message)
    {
        if (message.interface() == QString::fromLatin1(PropertiesInterface)) {
            const QList<QVariant> arguments = message.arguments();
            if (arguments.isEmpty()
                || arguments.constFirst().toString() != QString::fromLatin1(NetworkInterface)) {
                return;
            }
        }
        scheduleNetworkRefresh();
    }

    void onBluezSignal(const QDBusMessage &message)
    {
        if (message.interface() == QString::fromLatin1(PropertiesInterface)) {
            const QList<QVariant> arguments = message.arguments();
            if (arguments.isEmpty()
                || arguments.constFirst().toString() != QString::fromLatin1(BluezAdapterInterface)) {
                return;
            }
        }
        scheduleBluezRefresh();
    }

private:
    void initialize()
    {
        publishMessage(QJsonObject{{QStringLiteral("type"), QStringLiteral("ready")}});
        if (!bus.isConnected()) {
            diagnose(QStringLiteral("system bus is unavailable"));
            publishState(true);
            return;
        }

        const QString networkOwner = currentServiceOwner(QString::fromLatin1(NetworkService));
        if (!networkOwner.isEmpty()) {
            attachNetworkOwner(networkOwner);
        }
        const QString bluezOwner = currentServiceOwner(QString::fromLatin1(BluezService));
        if (!bluezOwner.isEmpty()) {
            attachBluezOwner(bluezOwner);
        }
        publishState(true);
    }

    QString currentServiceOwner(const QString &service) const
    {
        QDBusConnectionInterface *connectionInterface = bus.interface();
        if (connectionInterface == nullptr) {
            return {};
        }
        const QDBusReply<QString> reply = connectionInterface->serviceOwner(service);
        return reply.isValid() ? reply.value() : QString{};
    }

    void onNetworkOwnerChanged(const QString &, const QString &, const QString &newOwner)
    {
        detachNetworkOwner();
        resetUnavailable(wifi);
        publishState();
        if (!newOwner.isEmpty()) {
            attachNetworkOwner(newOwner);
        }
    }

    void onBluezOwnerChanged(const QString &, const QString &, const QString &newOwner)
    {
        detachBluezOwner();
        bluetoothAdapters.clear();
        resetUnavailable(bluetooth);
        publishState();
        if (!newOwner.isEmpty()) {
            attachBluezOwner(newOwner);
        }
    }

    void attachNetworkOwner(const QString &owner)
    {
        if (owner == networkOwner) {
            return;
        }
        if (!networkOwner.isEmpty()) {
            detachNetworkOwner();
        }
        networkOwner = owner;
        bool subscribed = true;
        subscribed &= bus.connect(
            owner,
            QString::fromLatin1(NetworkPath),
            QString::fromLatin1(PropertiesInterface),
            QStringLiteral("PropertiesChanged"),
            this,
            SLOT(onNetworkSignal(QDBusMessage)));
        subscribed &= bus.connect(
            owner,
            QString::fromLatin1(NetworkPath),
            QString::fromLatin1(NetworkInterface),
            QStringLiteral("DeviceAdded"),
            this,
            SLOT(onNetworkSignal(QDBusMessage)));
        subscribed &= bus.connect(
            owner,
            QString::fromLatin1(NetworkPath),
            QString::fromLatin1(NetworkInterface),
            QStringLiteral("DeviceRemoved"),
            this,
            SLOT(onNetworkSignal(QDBusMessage)));
        if (!subscribed) {
            diagnose(QStringLiteral("NetworkManager signal subscription failed"));
        }
        scheduleNetworkRefresh();
    }

    void detachNetworkOwner()
    {
        networkRefreshScheduled = false;
        wifiRequestTimer.stop();
        if (networkOwner.isEmpty()) {
            return;
        }
        bus.disconnect(
            networkOwner,
            QString::fromLatin1(NetworkPath),
            QString::fromLatin1(PropertiesInterface),
            QStringLiteral("PropertiesChanged"),
            this,
            SLOT(onNetworkSignal(QDBusMessage)));
        bus.disconnect(
            networkOwner,
            QString::fromLatin1(NetworkPath),
            QString::fromLatin1(NetworkInterface),
            QStringLiteral("DeviceAdded"),
            this,
            SLOT(onNetworkSignal(QDBusMessage)));
        bus.disconnect(
            networkOwner,
            QString::fromLatin1(NetworkPath),
            QString::fromLatin1(NetworkInterface),
            QStringLiteral("DeviceRemoved"),
            this,
            SLOT(onNetworkSignal(QDBusMessage)));
        networkOwner.clear();
    }

    void attachBluezOwner(const QString &owner)
    {
        if (owner == bluezOwner) {
            return;
        }
        if (!bluezOwner.isEmpty()) {
            detachBluezOwner();
        }
        bluezOwner = owner;
        bool subscribed = true;
        subscribed &= bus.connect(
            owner,
            QString::fromLatin1(BluezPath),
            QString::fromLatin1(ObjectManagerInterface),
            QStringLiteral("InterfacesAdded"),
            this,
            SLOT(onBluezSignal(QDBusMessage)));
        subscribed &= bus.connect(
            owner,
            QString::fromLatin1(BluezPath),
            QString::fromLatin1(ObjectManagerInterface),
            QStringLiteral("InterfacesRemoved"),
            this,
            SLOT(onBluezSignal(QDBusMessage)));
        subscribed &= bus.connect(
            owner,
            QString(),
            QString::fromLatin1(PropertiesInterface),
            QStringLiteral("PropertiesChanged"),
            this,
            SLOT(onBluezSignal(QDBusMessage)));
        if (!subscribed) {
            diagnose(QStringLiteral("BlueZ signal subscription failed"));
        }
        scheduleBluezRefresh();
    }

    void detachBluezOwner()
    {
        bluezRefreshScheduled = false;
        bluetoothRequestTimer.stop();
        if (bluezOwner.isEmpty()) {
            return;
        }
        bus.disconnect(
            bluezOwner,
            QString::fromLatin1(BluezPath),
            QString::fromLatin1(ObjectManagerInterface),
            QStringLiteral("InterfacesAdded"),
            this,
            SLOT(onBluezSignal(QDBusMessage)));
        bus.disconnect(
            bluezOwner,
            QString::fromLatin1(BluezPath),
            QString::fromLatin1(ObjectManagerInterface),
            QStringLiteral("InterfacesRemoved"),
            this,
            SLOT(onBluezSignal(QDBusMessage)));
        bus.disconnect(
            bluezOwner,
            QString(),
            QString::fromLatin1(PropertiesInterface),
            QStringLiteral("PropertiesChanged"),
            this,
            SLOT(onBluezSignal(QDBusMessage)));
        bluezOwner.clear();
        bluetoothPendingCalls = 0;
        bluetoothCallFailure.clear();
    }

    void scheduleNetworkRefresh()
    {
        if (networkRefreshScheduled || networkOwner.isEmpty()) {
            return;
        }
        networkRefreshScheduled = true;
        QTimer::singleShot(0, this, &ConnectivityBridge::refreshNetwork);
    }

    void scheduleBluezRefresh()
    {
        if (bluezRefreshScheduled || bluezOwner.isEmpty()) {
            return;
        }
        bluezRefreshScheduled = true;
        QTimer::singleShot(0, this, &ConnectivityBridge::refreshBluez);
    }

    std::optional<QVariant> readProperty(
        const QString &owner,
        const QString &path,
        const QString &interface,
        const QString &property) const
    {
        QDBusMessage request = QDBusMessage::createMethodCall(
            owner,
            path,
            QString::fromLatin1(PropertiesInterface),
            QStringLiteral("Get"));
        request << interface << property;
        const QDBusMessage reply = bus.call(request, QDBus::Block, DbusTimeoutMs);
        if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().size() != 1) {
            return std::nullopt;
        }
        return unwrapDbusVariant(reply.arguments().constFirst());
    }

    void refreshNetwork()
    {
        networkRefreshScheduled = false;
        const QString requestedOwner = networkOwner;
        if (requestedOwner.isEmpty()) {
            return;
        }

        const auto wireless = readProperty(
            requestedOwner,
            QString::fromLatin1(NetworkPath),
            QString::fromLatin1(NetworkInterface),
            QStringLiteral("WirelessEnabled"));
        const auto hardware = readProperty(
            requestedOwner,
            QString::fromLatin1(NetworkPath),
            QString::fromLatin1(NetworkInterface),
            QStringLiteral("WirelessHardwareEnabled"));
        QDBusMessage devicesRequest = QDBusMessage::createMethodCall(
            requestedOwner,
            QString::fromLatin1(NetworkPath),
            QString::fromLatin1(NetworkInterface),
            QStringLiteral("GetDevices"));
        const QDBusReply<QList<QDBusObjectPath>> devicesReply(
            bus.call(devicesRequest, QDBus::Block, DbusTimeoutMs));
        if (!wireless || !hardware || !devicesReply.isValid()
            || wireless->metaType() != QMetaType::fromType<bool>()
            || hardware->metaType() != QMetaType::fromType<bool>()) {
            diagnose(QStringLiteral("NetworkManager snapshot failed"));
            resetUnavailable(wifi, QStringLiteral("backend"));
            publishState();
            return;
        }

        bool hasWifiDevice = false;
        for (const QDBusObjectPath &device : devicesReply.value()) {
            const auto type = readProperty(
                requestedOwner,
                device.path(),
                QString::fromLatin1(NetworkDeviceInterface),
                QStringLiteral("DeviceType"));
            if (type && type->toUInt() == WifiDeviceType) {
                hasWifiDevice = true;
                break;
            }
        }
        if (networkOwner != requestedOwner
            || currentServiceOwner(QString::fromLatin1(NetworkService)) != requestedOwner) {
            return;
        }

        wifi.available = hasWifiDevice;
        wifi.hardwareEnabled = hasWifiDevice && hardware->toBool();
        wifi.enabled = hasWifiDevice && wireless->toBool();
        if (wifi.pending) {
            if (!wifi.available) {
                failRequest(wifi, QStringLiteral("unavailable"));
                return;
            }
            if (wifi.enabled == wifi.targetEnabled) {
                wifi.pending = false;
                wifi.failure = QStringLiteral("none");
                wifiRequestTimer.stop();
            }
        }
        publishState();
    }

    void refreshBluez()
    {
        bluezRefreshScheduled = false;
        const QString requestedOwner = bluezOwner;
        if (requestedOwner.isEmpty()) {
            return;
        }

        QDBusMessage request = QDBusMessage::createMethodCall(
            requestedOwner,
            QString::fromLatin1(BluezPath),
            QString::fromLatin1(ObjectManagerInterface),
            QStringLiteral("GetManagedObjects"));
        const QDBusReply<ManagedObjectMap> reply(bus.call(request, QDBus::Block, DbusTimeoutMs));
        if (!reply.isValid()) {
            diagnose(QStringLiteral("BlueZ adapter snapshot failed"));
            bluetoothAdapters.clear();
            resetUnavailable(bluetooth, QStringLiteral("backend"));
            publishState();
            return;
        }
        if (bluezOwner != requestedOwner
            || currentServiceOwner(QString::fromLatin1(BluezService)) != requestedOwner) {
            return;
        }

        QStringList adapters;
        bool anyPowered = false;
        bool allPowered = true;
        for (auto object = reply.value().constBegin(); object != reply.value().constEnd(); ++object) {
            const auto adapter = object.value().constFind(QString::fromLatin1(BluezAdapterInterface));
            if (adapter == object.value().constEnd()) {
                continue;
            }
            const auto powered = adapter->constFind(QStringLiteral("Powered"));
            if (powered == adapter->constEnd() || powered->metaType() != QMetaType::fromType<bool>()) {
                continue;
            }
            adapters.append(object.key().path());
            anyPowered = anyPowered || powered->toBool();
            allPowered = allPowered && powered->toBool();
        }
        adapters.sort();
        bluetoothAdapters = adapters;
        bluetooth.available = !adapters.isEmpty();
        bluetooth.hardwareEnabled = bluetooth.available;
        bluetooth.enabled = bluetooth.available && anyPowered;
        if (bluetooth.pending) {
            if (!bluetooth.available) {
                failRequest(bluetooth, QStringLiteral("unavailable"));
                return;
            }
            const bool confirmed = bluetooth.targetEnabled ? allPowered : !anyPowered;
            if (confirmed) {
                bluetooth.pending = false;
                bluetooth.failure = QStringLiteral("none");
                bluetoothRequestTimer.stop();
            }
        }
        publishState();
    }

    void requestWifi(bool enabled, int requestId)
    {
        if (!wifi.available) {
            rejectRequest(wifi, requestId, QStringLiteral("unavailable"));
            return;
        }
        if (!wifi.hardwareEnabled) {
            rejectRequest(wifi, requestId, QStringLiteral("hardware"));
            return;
        }
        if (networkOwner.isEmpty()) {
            rejectRequest(wifi, requestId, QStringLiteral("unavailable"));
            return;
        }
        if (wifi.pending) {
            return;
        }
        if (wifi.enabled == enabled) {
            wifi.requestId = requestId;
            wifi.failure = QStringLiteral("none");
            publishState();
            return;
        }

        wifi.pending = true;
        wifi.targetEnabled = enabled;
        wifi.requestId = requestId;
        wifi.failure = QStringLiteral("none");
        wifiRequestTimer.start();
        publishState();

        const QString requestedOwner = networkOwner;
        QDBusMessage request = QDBusMessage::createMethodCall(
            requestedOwner,
            QString::fromLatin1(NetworkPath),
            QString::fromLatin1(PropertiesInterface),
            QStringLiteral("Set"));
        request << QString::fromLatin1(NetworkInterface) << QStringLiteral("WirelessEnabled")
                << QVariant::fromValue(QDBusVariant(enabled));
        auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(request, DbusTimeoutMs), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, requestedOwner, requestId] {
            const QDBusPendingReply<> reply = *watcher;
            watcher->deleteLater();
            if (!wifi.pending || wifi.requestId != requestId || networkOwner != requestedOwner) {
                return;
            }
            if (reply.isError()) {
                failRequest(wifi, normalizeFailure(reply.error()));
                return;
            }
            scheduleNetworkRefresh();
        });
    }

    void requestBluetooth(bool enabled, int requestId)
    {
        if (!bluetooth.available || bluezOwner.isEmpty()) {
            rejectRequest(bluetooth, requestId, QStringLiteral("unavailable"));
            return;
        }
        if (bluetooth.pending) {
            return;
        }
        if (bluetooth.enabled == enabled) {
            bluetooth.requestId = requestId;
            bluetooth.failure = QStringLiteral("none");
            publishState();
            return;
        }

        bluetooth.pending = true;
        bluetooth.targetEnabled = enabled;
        bluetooth.requestId = requestId;
        bluetooth.failure = QStringLiteral("none");
        bluetoothPendingCalls = 0;
        bluetoothCallFailure.clear();
        bluetoothRequestTimer.start();
        publishState();

        const QString requestedOwner = bluezOwner;
        for (const QString &path : std::as_const(bluetoothAdapters)) {
            QDBusMessage request = QDBusMessage::createMethodCall(
                requestedOwner,
                path,
                QString::fromLatin1(PropertiesInterface),
                QStringLiteral("Set"));
            request << QString::fromLatin1(BluezAdapterInterface) << QStringLiteral("Powered")
                    << QVariant::fromValue(QDBusVariant(enabled));
            bluetoothPendingCalls += 1;
            auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(request, DbusTimeoutMs), this);
            connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, requestedOwner, requestId] {
                const QDBusPendingReply<> reply = *watcher;
                watcher->deleteLater();
                if (!bluetooth.pending || bluetooth.requestId != requestId
                    || bluezOwner != requestedOwner) {
                    return;
                }
                if (reply.isError()) {
                    const QString failure = normalizeFailure(reply.error());
                    if (bluetoothCallFailure != QStringLiteral("denied")) {
                        bluetoothCallFailure = failure;
                    }
                }
                bluetoothPendingCalls -= 1;
                if (bluetoothPendingCalls != 0) {
                    return;
                }
                if (!bluetoothCallFailure.isEmpty()) {
                    failRequest(bluetooth, bluetoothCallFailure);
                } else {
                    scheduleBluezRefresh();
                }
            });
        }
        if (bluetoothPendingCalls == 0) {
            scheduleBluezRefresh();
        }
    }

    void rejectRequest(AdapterState &state, int requestId, const QString &failure)
    {
        state.pending = false;
        state.requestId = requestId;
        state.failure = failure;
        publishState();
    }

    void failRequest(AdapterState &state, const QString &failure)
    {
        state.pending = false;
        state.failure = failure;
        if (&state == &wifi) {
            wifiRequestTimer.stop();
        } else {
            bluetoothRequestTimer.stop();
            bluetoothPendingCalls = 0;
            bluetoothCallFailure.clear();
        }
        publishState();
    }

    void resetUnavailable(AdapterState &state, const QString &failure = QStringLiteral("none"))
    {
        state.available = false;
        state.enabled = false;
        state.hardwareEnabled = false;
        state.pending = false;
        state.targetEnabled = false;
        state.requestId = 0;
        state.failure = failure;
    }

    void handleCommand(const QJsonObject &command)
    {
        const QString operation = command.value(QStringLiteral("op")).toString();
        if (operation == QStringLiteral("shutdown")) {
            QCoreApplication::quit();
            return;
        }
        const QJsonValue enabledValue = command.value(QStringLiteral("enabled"));
        const QJsonValue requestValue = command.value(QStringLiteral("requestId"));
        const QString adapter = command.value(QStringLiteral("adapter")).toString();
        if (operation != QStringLiteral("set") || !enabledValue.isBool() || !requestValue.isDouble()
            || requestValue.toDouble() < 1
            || requestValue.toDouble() > std::numeric_limits<int>::max()
            || requestValue.toInt() != requestValue.toDouble()
            || (adapter != QStringLiteral("wifi") && adapter != QStringLiteral("bluetooth"))) {
            diagnose(QStringLiteral("invalid command schema"));
            return;
        }

        if (adapter == QStringLiteral("wifi")) {
            requestWifi(enabledValue.toBool(), requestValue.toInt());
        } else {
            requestBluetooth(enabledValue.toBool(), requestValue.toInt());
        }
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

    QJsonObject adapterJson(const AdapterState &state) const
    {
        return QJsonObject{
            {QStringLiteral("available"), state.available},
            {QStringLiteral("enabled"), state.enabled},
            {QStringLiteral("hardwareEnabled"), state.hardwareEnabled},
            {QStringLiteral("pending"), state.pending},
            {QStringLiteral("failure"), state.failure},
            {QStringLiteral("requestId"), state.requestId},
        };
    }

    void publishState(bool force = false)
    {
        const QJsonObject message{
            {QStringLiteral("type"), QStringLiteral("state")},
            {QStringLiteral("wifi"), adapterJson(wifi)},
            {QStringLiteral("bluetooth"), adapterJson(bluetooth)},
        };
        const QByteArray serialized = QJsonDocument(message).toJson(QJsonDocument::Compact);
        if (!force && serialized == lastState) {
            return;
        }
        lastState = serialized;
        publishBytes(serialized);
    }

    void publishMessage(const QJsonObject &message)
    {
        publishBytes(QJsonDocument(message).toJson(QJsonDocument::Compact));
    }

    void publishBytes(const QByteArray &message)
    {
        std::fwrite(message.constData(), 1, static_cast<size_t>(message.size()), stdout);
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
        std::fprintf(stderr, "nagi-shell connectivity helper: %s\n", bounded.constData());
        std::fflush(stderr);
    }

    QDBusConnection bus;
    QDBusServiceWatcher networkWatcher;
    QDBusServiceWatcher bluezWatcher;
    QString networkOwner;
    QString bluezOwner;
    QStringList bluetoothAdapters;
    AdapterState wifi;
    AdapterState bluetooth;
    QTimer wifiRequestTimer;
    QTimer bluetoothRequestTimer;
    QSocketNotifier *stdinNotifier = nullptr;
    QByteArray commandBuffer;
    QByteArray lastState;
    QString lastDiagnostic;
    QString bluetoothCallFailure;
    int bluetoothPendingCalls = 0;
    int diagnosticCount = 0;
    bool networkRefreshScheduled = false;
    bool bluezRefreshScheduled = false;
};

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    qDBusRegisterMetaType<InterfaceProperties>();
    qDBusRegisterMetaType<ManagedObjectMap>();
    ConnectivityBridge bridge;
    return application.exec();
}

#include "main.moc"

#include <QCoreApplication>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusContext>
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
#include <QJsonArray>
#include <QJsonObject>
#include <QHash>
#include <QMap>
#include <QSocketNotifier>
#include <QTimer>
#include <QVariantMap>
#include <QDateTime>
#include <QElapsedTimer>

#include <array>
#include <cerrno>
#include <cstring>
#include <cstdio>
#include <limits>
#include <optional>
#include <pwd.h>
#include <functional>
#include <unistd.h>

using InterfaceProperties = QMap<QString, QVariantMap>;
using ManagedObjectMap = QMap<QDBusObjectPath, InterfaceProperties>;
using ConnectionSettings = QMap<QString, QVariantMap>;

Q_DECLARE_METATYPE(InterfaceProperties)
Q_DECLARE_METATYPE(ManagedObjectMap)

namespace {

constexpr auto NetworkService = "org.freedesktop.NetworkManager";
constexpr auto NetworkPath = "/org/freedesktop/NetworkManager";
constexpr auto NetworkInterface = "org.freedesktop.NetworkManager";
constexpr auto NetworkDeviceInterface = "org.freedesktop.NetworkManager.Device";
constexpr auto NetworkWirelessInterface = "org.freedesktop.NetworkManager.Device.Wireless";
constexpr auto NetworkAccessPointInterface = "org.freedesktop.NetworkManager.AccessPoint";
constexpr auto NetworkSettingsPath = "/org/freedesktop/NetworkManager/Settings";
constexpr auto NetworkSettingsInterface = "org.freedesktop.NetworkManager.Settings";
constexpr auto NetworkConnectionInterface = "org.freedesktop.NetworkManager.Settings.Connection";
constexpr auto BluezService = "org.bluez";
constexpr auto BluezPath = "/";
constexpr auto BluezManagerPath = "/org/bluez";
constexpr auto BluezAgentPath = "/io/github/Anthodev/NagiShell/BluetoothAgent";
constexpr auto BluezAdapterInterface = "org.bluez.Adapter1";
constexpr auto BluezDeviceInterface = "org.bluez.Device1";
constexpr auto BluezAgentManagerInterface = "org.bluez.AgentManager1";
constexpr auto ObjectManagerInterface = "org.freedesktop.DBus.ObjectManager";
constexpr auto PropertiesInterface = "org.freedesktop.DBus.Properties";
constexpr int WifiDeviceType = 2;
constexpr int WifiDeviceActivated = 100;
constexpr int WifiDeviceFailed = 120;
constexpr quint32 WifiSecurityPsk = 0x100;
constexpr quint32 WifiSecuritySae = 0x400;
constexpr int DbusTimeoutMs = 2000;
constexpr int RadioTimeoutMs = 3000;
constexpr int WifiOperationTimeoutMs = 30000;
constexpr int MaximumCommandBytes = 4096;
constexpr int MaximumDiagnostics = 8;
constexpr int MaximumNetworks = 16;
constexpr int MaximumBluetoothDevices = 32;
constexpr int MaximumSsidBytes = 32;
constexpr int MaximumBluetoothNameCharacters = 64;
constexpr int DiscoveryDurationMs = 30000;
constexpr int DiscoveredDeviceRetentionMs = 60000;
constexpr qint64 ScanFreshnessMs = 30000;
constexpr qint64 ManualScanCooldownMs = 10000;
constexpr qsizetype MaximumUsernameBytes = 256;
constexpr size_t PasswordDatabaseBufferBytes = 16384;

struct AdapterState {
    bool available = false;
    bool enabled = false;
    bool hardwareEnabled = false;
    bool pending = false;
    bool targetEnabled = false;
    int requestId = 0;
    QString failure = QStringLiteral("none");
};

struct WifiNetwork {
    int token = 0;
    QByteArray ssid;
    QString label;
    QString security = QStringLiteral("unsupported");
    QString keyManagement;
    int strength = 0;
    bool connected = false;
    bool saved = false;
    bool forgettable = false;
    QString accessPointPath;
    QString profilePath;
};

struct WifiProfile {
    QByteArray ssid;
    QString security = QStringLiteral("unsupported");
    QString path;
    bool userOwned = false;
};

struct WifiOperation {
    QString kind = QStringLiteral("idle");
    QString failure = QStringLiteral("none");
    QString result = QStringLiteral("none");
    int generation = 0;
    int targetToken = 0;
    bool automaticScan = false;
};

struct BluetoothAdapter {
    QString path;
    bool powered = false;
    bool discovering = false;
};

struct BluetoothDevice {
    int token = 0;
    QString path;
    QString adapterPath;
    QString name;
    QString type = QStringLiteral("other");
    int signal = -1;
    bool paired = false;
    bool connected = false;
    bool trusted = false;
    qint64 lastSeenMs = 0;
};

struct BluetoothOperation {
    QString kind = QStringLiteral("idle");
    QString failure = QStringLiteral("none");
    QString result = QStringLiteral("none");
    QString prompt = QStringLiteral("none");
    QString displayValue;
    int displayEntered = 0;
    int generation = 0;
    int targetToken = 0;
};

QDBusConnection connectivityBus()
{
    return qEnvironmentVariable("NAGI_CONNECTIVITY_BUS") == QStringLiteral("session")
        ? QDBusConnection::sessionBus()
        : QDBusConnection::systemBus();
}

int bluetoothDiscoveryDurationMs()
{
    if (qEnvironmentVariable("NAGI_CONNECTIVITY_BUS") == QStringLiteral("session")) {
        bool valid = false;
        const int requested =
            qEnvironmentVariableIntValue("NAGI_BLUETOOTH_DISCOVERY_MS", &valid);
        if (valid) {
            return std::clamp(requested, 50, DiscoveryDurationMs);
        }
    }
    return DiscoveryDurationMs;
}

QString currentUserName()
{
    passwd entry{};
    passwd *result = nullptr;
    std::array<char, PasswordDatabaseBufferBytes> buffer{};
    if (::getpwuid_r(::getuid(), &entry, buffer.data(), buffer.size(), &result) != 0
        || result == nullptr || result->pw_name == nullptr) {
        return {};
    }
    const size_t length = ::strnlen(result->pw_name, MaximumUsernameBytes + 1);
    if (length == 0 || length > static_cast<size_t>(MaximumUsernameBytes)) {
        return {};
    }
    return QString::fromLocal8Bit(result->pw_name, static_cast<qsizetype>(length));
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
    if (name.contains(QStringLiteral("nosecrets"))
        || name.contains(QStringLiteral("secretsrequired"))
        || name.contains(QStringLiteral("invalidsecret"))) {
        return QStringLiteral("wrong-secret");
    }
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

class BluezAgent final : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.bluez.Agent1")

public:
    explicit BluezAgent(QDBusConnection connection, QObject *parent = nullptr)
        : QObject(parent)
        , bus(std::move(connection))
    {
    }

signals:
    void released();
    void cancelled();
    void promptRequested(
        const QString &kind,
        const QString &devicePath,
        const QString &value,
        uint entered,
        const QDBusMessage &message);
    void displayRequested(
        const QString &kind,
        const QString &devicePath,
        const QString &value,
        uint entered);

public slots:
    void Release()
    {
        emit released();
    }

    QString RequestPinCode(const QDBusObjectPath &device, const QDBusMessage &message)
    {
        message.setDelayedReply(true);
        emit promptRequested(
            QStringLiteral("enter-pin"),
            device.path(),
            QString(),
            0,
            message);
        return {};
    }

    void DisplayPinCode(const QDBusObjectPath &device, const QString &pin)
    {
        emit displayRequested(QStringLiteral("display-pin"), device.path(), pin.left(16), 0);
    }

    uint RequestPasskey(const QDBusObjectPath &device, const QDBusMessage &message)
    {
        message.setDelayedReply(true);
        emit promptRequested(
            QStringLiteral("enter-passkey"),
            device.path(),
            QString(),
            0,
            message);
        return 0;
    }

    void DisplayPasskey(const QDBusObjectPath &device, uint passkey, ushort entered)
    {
        emit displayRequested(
            QStringLiteral("display-passkey"),
            device.path(),
            QStringLiteral("%1").arg(passkey, 6, 10, QLatin1Char('0')),
            std::min<uint>(entered, 6));
    }

    void RequestConfirmation(
        const QDBusObjectPath &device,
        uint passkey,
        const QDBusMessage &message)
    {
        message.setDelayedReply(true);
        emit promptRequested(
            QStringLiteral("confirm-passkey"),
            device.path(),
            QStringLiteral("%1").arg(passkey, 6, 10, QLatin1Char('0')),
            0,
            message);
    }

    void RequestAuthorization(const QDBusObjectPath &device, const QDBusMessage &message)
    {
        message.setDelayedReply(true);
        emit promptRequested(
            QStringLiteral("authorize-pairing"),
            device.path(),
            QString(),
            0,
            message);
    }

    void AuthorizeService(
        const QDBusObjectPath &,
        const QString &,
        const QDBusMessage &message)
    {
        bus.send(message.createErrorReply(
            QStringLiteral("org.bluez.Error.Rejected"),
            QStringLiteral("service authorization is delegated to the default agent")));
    }

    void Cancel()
    {
        emit cancelled();
    }
private:
    QDBusConnection bus;
};

class ConnectivityBridge final : public QObject {
    Q_OBJECT

public:
    explicit ConnectivityBridge(QObject *parent = nullptr)
        : QObject(parent)
        , bus(connectivityBus())
        , bluezAgent(bus, this)
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
        wifiRequestTimer.setInterval(RadioTimeoutMs);
        wifiOperationTimer.setSingleShot(true);
        wifiOperationTimer.setInterval(WifiOperationTimeoutMs);
        bluetoothRequestTimer.setSingleShot(true);
        bluetoothRequestTimer.setInterval(RadioTimeoutMs);
        bluetoothDiscoveryTimer.setSingleShot(true);
        bluetoothDiscoveryTimer.setInterval(bluetoothDiscoveryDurationMs());
        bluetoothExpiryTimer.setSingleShot(true);

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
        connect(&wifiOperationTimer, &QTimer::timeout, this, [this] {
            finishWifiOperation(QStringLiteral("timeout"));
        });
        connect(&bluetoothRequestTimer, &QTimer::timeout, this, [this] {
            failRequest(bluetooth, QStringLiteral("timeout"));
        });
        connect(&bluetoothDiscoveryTimer, &QTimer::timeout, this, [this] {
            stopBluetoothDiscovery(allocateOperationGeneration(), QStringLiteral("expired"));
        });
        connect(&bluetoothExpiryTimer, &QTimer::timeout, this, [this] {
            expireBluetoothDevices();
        });
        connect(
            &bluezAgent,
            &BluezAgent::promptRequested,
            this,
            &ConnectivityBridge::handleAgentPrompt);
        connect(
            &bluezAgent,
            &BluezAgent::displayRequested,
            this,
            &ConnectivityBridge::handleAgentDisplay);
        connect(&bluezAgent, &BluezAgent::cancelled, this, [this] {
            finishBluetoothOperation(QStringLiteral("cancelled"), QStringLiteral("cancelled"));
        });
        connect(&bluezAgent, &BluezAgent::released, this, [this] {
            clearPairingReply(true);
            bluetoothAgentRegistered = false;
            finishBluetoothOperation(QStringLiteral("backend"));
        });

        stdinNotifier = new QSocketNotifier(STDIN_FILENO, QSocketNotifier::Read, this);
        connect(stdinNotifier, &QSocketNotifier::activated, this, [this] { readCommands(); });
        QTimer::singleShot(0, this, &ConnectivityBridge::initialize);
    }

    ~ConnectivityBridge() override
    {
        detachNetworkOwner();
        detachBluezOwner();
        bus.unregisterObject(QString::fromLatin1(BluezAgentPath));
    }

private slots:
    void onNetworkSignal(const QDBusMessage &message)
    {
        if (message.interface() == QString::fromLatin1(PropertiesInterface)) {
            const QList<QVariant> arguments = message.arguments();
            if (arguments.isEmpty()
                || !arguments.constFirst().toString().startsWith(
                    QString::fromLatin1(NetworkService))) {
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
                || (arguments.constFirst().toString()
                        != QString::fromLatin1(BluezAdapterInterface)
                    && arguments.constFirst().toString()
                        != QString::fromLatin1(BluezDeviceInterface))) {
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
        bluetoothClock.start();
        if (!bus.registerObject(
                QString::fromLatin1(BluezAgentPath),
                &bluezAgent,
                QDBusConnection::ExportAllSlots)) {
            diagnose(QStringLiteral("BlueZ scoped agent object registration failed"));
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
        clearWifiManagerState();
        resetUnavailable(wifi);
        wifiOperation.failure = newOwner.isEmpty() ? QStringLiteral("unavailable") :
                                                    QStringLiteral("none");
        publishState();
        if (!newOwner.isEmpty()) {
            attachNetworkOwner(newOwner);
        }
    }

    void onBluezOwnerChanged(const QString &, const QString &, const QString &newOwner)
    {
        detachBluezOwner();
        clearBluetoothManagerState(QStringLiteral("replaced"));
        resetUnavailable(bluetooth);
        bluetoothOperation.failure = newOwner.isEmpty() ? QStringLiteral("unavailable") :
                                                          QStringLiteral("none");
        publishState();
        if (!newOwner.isEmpty()) {
            attachBluezOwner(newOwner);
        }
    }

    bool setNetworkSignalConnections(const QString &owner, bool connectSignals)
    {
        const auto change = [this, &owner, connectSignals](
                                const QString &path,
                                const QString &interface,
                                const QString &member) {
            return connectSignals
                ? bus.connect(
                      owner,
                      path,
                      interface,
                      member,
                      this,
                      SLOT(onNetworkSignal(QDBusMessage)))
                : bus.disconnect(
                      owner,
                      path,
                      interface,
                      member,
                      this,
                      SLOT(onNetworkSignal(QDBusMessage)));
        };
        bool changed = true;
        changed &= change(
            QString(),
            QString::fromLatin1(PropertiesInterface),
            QStringLiteral("PropertiesChanged"));
        changed &= change(
            QString::fromLatin1(NetworkPath),
            QString::fromLatin1(NetworkInterface),
            QStringLiteral("DeviceAdded"));
        changed &= change(
            QString::fromLatin1(NetworkPath),
            QString::fromLatin1(NetworkInterface),
            QStringLiteral("DeviceRemoved"));
        changed &= change(
            QString(),
            QString::fromLatin1(NetworkWirelessInterface),
            QStringLiteral("AccessPointAdded"));
        changed &= change(
            QString(),
            QString::fromLatin1(NetworkWirelessInterface),
            QStringLiteral("AccessPointRemoved"));
        changed &= change(
            QString::fromLatin1(NetworkSettingsPath),
            QString::fromLatin1(NetworkSettingsInterface),
            QStringLiteral("NewConnection"));
        changed &= change(
            QString::fromLatin1(NetworkSettingsPath),
            QString::fromLatin1(NetworkSettingsInterface),
            QStringLiteral("ConnectionRemoved"));
        return changed;
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
        if (!setNetworkSignalConnections(owner, true)) {
            diagnose(QStringLiteral("NetworkManager signal subscription failed"));
        }
        scheduleNetworkRefresh();
    }

    void detachNetworkOwner()
    {
        networkRefreshScheduled = false;
        wifiRequestTimer.stop();
        wifiOperationTimer.stop();
        if (networkOwner.isEmpty()) {
            return;
        }
        setNetworkSignalConnections(networkOwner, false);
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
        QDBusMessage registerAgent = QDBusMessage::createMethodCall(
            owner,
            QString::fromLatin1(BluezManagerPath),
            QString::fromLatin1(BluezAgentManagerInterface),
            QStringLiteral("RegisterAgent"));
        registerAgent << QDBusObjectPath(QString::fromLatin1(BluezAgentPath))
                      << QStringLiteral("DisplayYesNo");
        const QDBusMessage registrationReply = bus.call(registerAgent, QDBus::Block, DbusTimeoutMs);
        bluetoothAgentRegistered = registrationReply.type() != QDBusMessage::ErrorMessage;
        if (!bluetoothAgentRegistered) {
            diagnose(QStringLiteral("BlueZ scoped agent registration failed"));
        }
        scheduleBluezRefresh();
    }

    void detachBluezOwner()
    {
        bluezRefreshScheduled = false;
        bluetoothRequestTimer.stop();
        bluetoothDiscoveryTimer.stop();
        bluetoothExpiryTimer.stop();
        if (bluezOwner.isEmpty()) {
            return;
        }
        if (bluetoothAgentRegistered) {
            QDBusMessage unregisterAgent = QDBusMessage::createMethodCall(
                bluezOwner,
                QString::fromLatin1(BluezManagerPath),
                QString::fromLatin1(BluezAgentManagerInterface),
                QStringLiteral("UnregisterAgent"));
            unregisterAgent << QDBusObjectPath(QString::fromLatin1(BluezAgentPath));
            bus.call(unregisterAgent, QDBus::Block, DbusTimeoutMs);
            bluetoothAgentRegistered = false;
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
        clearPairingReply(true);
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

    QList<QDBusObjectPath> callObjectPaths(
        const QString &owner,
        const QString &path,
        const QString &interface,
        const QString &method,
        bool *ok = nullptr) const
    {
        QDBusMessage request = QDBusMessage::createMethodCall(owner, path, interface, method);
        const QDBusReply<QList<QDBusObjectPath>> reply(
            bus.call(request, QDBus::Block, DbusTimeoutMs));
        if (ok != nullptr) {
            *ok = reply.isValid();
        }
        return reply.isValid() ? reply.value() : QList<QDBusObjectPath>{};
    }

    QString objectPath(const std::optional<QVariant> &value) const
    {
        if (!value) {
            return {};
        }
        const QVariant unwrapped = unwrapDbusVariant(*value);
        return unwrapped.canConvert<QDBusObjectPath>()
            ? unwrapped.value<QDBusObjectPath>().path()
            : QString{};
    }

    QString boundedSsidLabel(const QByteArray &ssid) const
    {
        QString label = QString::fromUtf8(ssid.constData(), ssid.size()).left(MaximumSsidBytes);
        for (QChar &character : label) {
            if (character.category() == QChar::Other_Control
                || character == QChar::LineSeparator
                || character == QChar::ParagraphSeparator) {
                character = QChar::ReplacementCharacter;
            }
        }
        return label.trimmed();
    }

    QString securityForFlags(quint32 flags, quint32 wpaFlags, quint32 rsnFlags) const
    {
        if (flags == 0 && wpaFlags == 0 && rsnFlags == 0) {
            return QStringLiteral("open");
        }
        if (((wpaFlags | rsnFlags) & (WifiSecurityPsk | WifiSecuritySae)) != 0) {
            return QStringLiteral("wpa-personal");
        }
        return QStringLiteral("unsupported");
    }

    QString securityForSettings(const ConnectionSettings &settings) const
    {
        const auto security = settings.constFind(
            QStringLiteral("802-11-wireless-security"));
        if (security == settings.constEnd()) {
            return QStringLiteral("open");
        }
        const QString keyManagement = security->value(QStringLiteral("key-mgmt")).toString();
        return keyManagement == QStringLiteral("wpa-psk")
                || keyManagement == QStringLiteral("sae")
            ? QStringLiteral("wpa-personal")
            : QStringLiteral("unsupported");
    }

    bool profileIsUserOwned(const QVariant &permissionsValue) const
    {
        const QString currentUser = currentUserName();
        if (currentUser.isEmpty() || currentUser.size() > 256) {
            return false;
        }
        QStringList permissions;
        if (permissionsValue.canConvert<QStringList>()) {
            permissions = permissionsValue.toStringList();
        } else {
            const QVariantList values = permissionsValue.toList();
            for (const QVariant &value : values) {
                permissions.append(value.toString());
            }
        }
        const QString expected = QStringLiteral("user:") + currentUser + QLatin1Char(':');
        return !permissions.isEmpty()
            && std::all_of(
                permissions.cbegin(),
                permissions.cend(),
                [&expected](const QString &permission) { return permission == expected; });
    }

    QList<WifiProfile> readProfiles(const QString &owner) const
    {
        bool listed = false;
        const QList<QDBusObjectPath> paths = callObjectPaths(
            owner,
            QString::fromLatin1(NetworkSettingsPath),
            QString::fromLatin1(NetworkSettingsInterface),
            QStringLiteral("ListConnections"),
            &listed);
        if (!listed) {
            return {};
        }

        QList<WifiProfile> profiles;
        profiles.reserve(std::min<qsizetype>(paths.size(), MaximumNetworks));
        for (const QDBusObjectPath &path : paths) {
            if (profiles.size() >= MaximumNetworks) {
                break;
            }
            QDBusMessage request = QDBusMessage::createMethodCall(
                owner,
                path.path(),
                QString::fromLatin1(NetworkConnectionInterface),
                QStringLiteral("GetSettings"));
            const QDBusReply<ConnectionSettings> reply(
                bus.call(request, QDBus::Block, DbusTimeoutMs));
            if (!reply.isValid()) {
                continue;
            }
            const ConnectionSettings settings = reply.value();
            const QVariantMap connection = settings.value(QStringLiteral("connection"));
            if (connection.value(QStringLiteral("type")).toString()
                != QStringLiteral("802-11-wireless")) {
                continue;
            }
            const QByteArray ssid = settings.value(QStringLiteral("802-11-wireless"))
                                        .value(QStringLiteral("ssid"))
                                        .toByteArray();
            if (ssid.isEmpty() || ssid.size() > MaximumSsidBytes) {
                continue;
            }
            profiles.append(WifiProfile{
                ssid,
                securityForSettings(settings),
                path.path(),
                profileIsUserOwned(connection.value(QStringLiteral("permissions"))),
            });
        }
        return profiles;
    }

    int tokenForNetwork(const QString &key)
    {
        const auto existing = networkTokens.constFind(key);
        if (existing != networkTokens.constEnd()) {
            return existing.value();
        }
        const int token = nextNetworkToken;
        nextNetworkToken = nextNetworkToken >= std::numeric_limits<int>::max()
            ? 1
            : nextNetworkToken + 1;
        networkTokens.insert(key, token);
        return token;
    }

    void rebuildNetworks(const QString &owner, const QString &devicePath)
    {
        bool listed = false;
        const QList<QDBusObjectPath> accessPoints = callObjectPaths(
            owner,
            devicePath,
            QString::fromLatin1(NetworkWirelessInterface),
            QStringLiteral("GetAllAccessPoints"),
            &listed);
        if (!listed) {
            wifiNetworks.clear();
            currentNetworkLabel.clear();
            return;
        }

        const QString activeAccessPoint = objectPath(readProperty(
            owner,
            devicePath,
            QString::fromLatin1(NetworkWirelessInterface),
            QStringLiteral("ActiveAccessPoint")));
        const QList<WifiProfile> profiles = readProfiles(owner);
        QHash<QString, WifiNetwork> grouped;
        for (const QDBusObjectPath &accessPoint : accessPoints) {
            if (grouped.size() >= MaximumNetworks * 2) {
                break;
            }
            const auto ssidValue = readProperty(
                owner,
                accessPoint.path(),
                QString::fromLatin1(NetworkAccessPointInterface),
                QStringLiteral("Ssid"));
            const auto strengthValue = readProperty(
                owner,
                accessPoint.path(),
                QString::fromLatin1(NetworkAccessPointInterface),
                QStringLiteral("Strength"));
            const auto flagsValue = readProperty(
                owner,
                accessPoint.path(),
                QString::fromLatin1(NetworkAccessPointInterface),
                QStringLiteral("Flags"));
            const auto wpaValue = readProperty(
                owner,
                accessPoint.path(),
                QString::fromLatin1(NetworkAccessPointInterface),
                QStringLiteral("WpaFlags"));
            const auto rsnValue = readProperty(
                owner,
                accessPoint.path(),
                QString::fromLatin1(NetworkAccessPointInterface),
                QStringLiteral("RsnFlags"));
            if (!ssidValue || !strengthValue || !flagsValue || !wpaValue || !rsnValue) {
                continue;
            }
            const QByteArray ssid = ssidValue->toByteArray();
            const QString label = boundedSsidLabel(ssid);
            if (ssid.isEmpty() || ssid.size() > MaximumSsidBytes || label.isEmpty()) {
                continue;
            }
            const QString security = securityForFlags(
                flagsValue->toUInt(),
                wpaValue->toUInt(),
                rsnValue->toUInt());
            const quint32 rsnFlags = rsnValue->toUInt();
            const QString keyManagement = security == QStringLiteral("wpa-personal")
                    && (rsnFlags & WifiSecuritySae) != 0
                    && (rsnFlags & WifiSecurityPsk) == 0
                ? QStringLiteral("sae")
                : QStringLiteral("wpa-psk");
            const QString key = QString::fromLatin1(ssid.toBase64()) + QLatin1Char('|') + security;
            const int strength = std::clamp(strengthValue->toInt(), 0, 100);
            const bool connected = accessPoint.path() == activeAccessPoint;
            auto current = grouped.find(key);
            if (current == grouped.end()) {
                WifiNetwork network;
                network.token = tokenForNetwork(key);
                network.ssid = ssid;
                network.label = label;
                network.security = security;
                network.keyManagement = keyManagement;
                network.strength = strength;
                network.connected = connected;
                network.accessPointPath = accessPoint.path();
                current = grouped.insert(key, network);
            } else {
                current->connected = current->connected || connected;
                if (strength > current->strength) {
                    current->strength = strength;
                    current->accessPointPath = accessPoint.path();
                    current->keyManagement = keyManagement;
                }
            }
        }

        for (auto current = grouped.begin(); current != grouped.end(); ++current) {
            for (const WifiProfile &profile : profiles) {
                if (profile.ssid != current->ssid || profile.security != current->security) {
                    continue;
                }
                current->saved = true;
                if (current->profilePath.isEmpty() || profile.userOwned) {
                    current->profilePath = profile.path;
                    current->forgettable = profile.userOwned;
                }
            }
        }

        wifiNetworks = grouped.values();
        std::sort(
            wifiNetworks.begin(),
            wifiNetworks.end(),
            [](const WifiNetwork &left, const WifiNetwork &right) {
                if (left.connected != right.connected) {
                    return left.connected;
                }
                if (left.strength != right.strength) {
                    return left.strength > right.strength;
                }
                return QString::localeAwareCompare(left.label, right.label) < 0;
            });
        if (wifiNetworks.size() > MaximumNetworks) {
            wifiNetworks.resize(MaximumNetworks);
        }
        currentNetworkLabel.clear();
        for (const WifiNetwork &network : std::as_const(wifiNetworks)) {
            if (network.connected) {
                currentNetworkLabel = network.label;
                break;
            }
        }
    }

    bool scanCacheStale() const
    {
        return wifiNetworks.isEmpty() || lastScanValue < 0 || !scanCacheAge.isValid()
            || scanCacheAge.elapsed() >= ScanFreshnessMs;
    }

    void clearWifiManagerState()
    {
        wifiOperationTimer.stop();
        wifiDevicePath.clear();
        wifiNetworks.clear();
        currentNetworkLabel.clear();
        networkTokens.clear();
        nextNetworkToken = 1;
        lastScanValue = -1;
        scanStartValue = -1;
        scanCacheAge.invalidate();
        manualScanAge.invalidate();
        wifiOperation = WifiOperation{};
    }

    void finishWifiOperation(
        const QString &failure = QStringLiteral("none"),
        const QString &result = QStringLiteral("none"))
    {
        wifiOperationTimer.stop();
        wifiOperation.kind = QStringLiteral("idle");
        wifiOperation.failure = failure;
        wifiOperation.result = result;
        wifiOperation.targetToken = 0;
        wifiOperation.automaticScan = false;
        publishState();
    }

    bool beginWifiOperation(const QString &kind, int generation)
    {
        if (generation < 1 || wifiOperation.kind != QStringLiteral("idle")) {
            return false;
        }
        wifiOperation.kind = kind;
        wifiOperation.failure = QStringLiteral("none");
        wifiOperation.result = QStringLiteral("none");
        wifiOperation.generation = generation;
        wifiOperation.targetToken = 0;
        wifiOperation.automaticScan = false;
        wifiOperationTimer.start();
        publishState();
        return true;
    }

    bool requestScan(int generation, bool automatic)
    {
        if (!wifiInterest || !wifi.available || !wifi.enabled || wifiDevicePath.isEmpty()
            || networkOwner.isEmpty()) {
            return false;
        }
        if (!automatic && manualScanAge.isValid()
            && manualScanAge.elapsed() < ManualScanCooldownMs) {
            wifiOperation.generation = generation;
            wifiOperation.failure = QStringLiteral("cooldown");
            wifiOperation.result = QStringLiteral("none");
            publishState();
            return false;
        }
        if (!beginWifiOperation(QStringLiteral("scanning"), generation)) {
            return false;
        }
        wifiOperation.automaticScan = automatic;
        scanStartValue = lastScanValue;
        if (!automatic) {
            manualScanAge.start();
        }

        const QString requestedOwner = networkOwner;
        const int requestedGeneration = generation;
        QDBusMessage request = QDBusMessage::createMethodCall(
            requestedOwner,
            wifiDevicePath,
            QString::fromLatin1(NetworkWirelessInterface),
            QStringLiteral("RequestScan"));
        request << QVariantMap{};
        auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(request, DbusTimeoutMs), this);
        connect(
            watcher,
            &QDBusPendingCallWatcher::finished,
            this,
            [this, watcher, requestedOwner, requestedGeneration] {
                const QDBusPendingReply<> reply = *watcher;
                watcher->deleteLater();
                if (networkOwner != requestedOwner
                    || wifiOperation.kind != QStringLiteral("scanning")
                    || wifiOperation.generation != requestedGeneration) {
                    return;
                }
                if (reply.isError()) {
                    finishWifiOperation(normalizeFailure(reply.error()));
                }
            });
        return true;
    }
    int allocateOperationGeneration()
    {
        const int generation = nextOperationGeneration;
        nextOperationGeneration = nextOperationGeneration >= std::numeric_limits<int>::max()
            ? 1
            : nextOperationGeneration + 1;
        return generation;
    }

    bool deviceFailureNeedsSecret(const QString &owner, const QString &devicePath) const
    {
        const auto value = readProperty(
            owner,
            devicePath,
            QString::fromLatin1(NetworkDeviceInterface),
            QStringLiteral("StateReason"));
        if (!value) {
            return false;
        }
        quint32 reason = 0;
        if (value->canConvert<QDBusArgument>()) {
            const QDBusArgument argument = value->value<QDBusArgument>();
            quint32 state = 0;
            argument.beginStructure();
            argument >> state >> reason;
            argument.endStructure();
        } else {
            const QVariantList values = value->toList();
            if (values.size() >= 2) {
                reason = values.at(1).toUInt();
            }
        }
        return reason == 7 || reason == 8 || reason == 9;
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
        const auto networking = readProperty(
            requestedOwner,
            QString::fromLatin1(NetworkPath),
            QString::fromLatin1(NetworkInterface),
            QStringLiteral("NetworkingEnabled"));
        bool devicesValid = false;
        const QList<QDBusObjectPath> devices = callObjectPaths(
            requestedOwner,
            QString::fromLatin1(NetworkPath),
            QString::fromLatin1(NetworkInterface),
            QStringLiteral("GetDevices"),
            &devicesValid);
        if (!wireless || !hardware || !networking || !devicesValid
            || wireless->metaType() != QMetaType::fromType<bool>()
            || hardware->metaType() != QMetaType::fromType<bool>()
            || networking->metaType() != QMetaType::fromType<bool>()) {
            diagnose(QStringLiteral("NetworkManager snapshot failed"));
            clearWifiManagerState();
            resetUnavailable(wifi, QStringLiteral("backend"));
            wifiOperation.failure = QStringLiteral("backend");
            publishState();
            return;
        }

        QString devicePath;
        for (const QDBusObjectPath &device : devices) {
            const auto type = readProperty(
                requestedOwner,
                device.path(),
                QString::fromLatin1(NetworkDeviceInterface),
                QStringLiteral("DeviceType"));
            if (type && type->toUInt() == WifiDeviceType) {
                devicePath = device.path();
                break;
            }
        }
        if (networkOwner != requestedOwner
            || currentServiceOwner(QString::fromLatin1(NetworkService)) != requestedOwner) {
            return;
        }

        wifiDevicePath = devicePath;
        wifiNetworkingEnabled = networking->toBool();
        wifi.available = !devicePath.isEmpty();
        wifi.hardwareEnabled = wifi.available && hardware->toBool();
        wifi.enabled = wifi.available && wireless->toBool() && wifiNetworkingEnabled;
        if (!wifi.available) {
            wifiNetworks.clear();
            currentNetworkLabel.clear();
            if (wifi.pending) {
                failRequest(wifi, QStringLiteral("unavailable"));
                return;
            }
            if (wifiOperation.kind != QStringLiteral("idle")) {
                finishWifiOperation(QStringLiteral("unavailable"));
                return;
            }
            publishState();
            return;
        }

        if (wifi.pending && wifi.enabled == wifi.targetEnabled) {
            wifi.pending = false;
            wifi.failure = QStringLiteral("none");
            wifiRequestTimer.stop();
            if (wifiOperation.kind == QStringLiteral("radio")) {
                finishWifiOperation(QStringLiteral("none"), QStringLiteral("radio-updated"));
            }
        }

        if (!wifi.enabled) {
            wifiNetworks.clear();
            currentNetworkLabel.clear();
            lastScanValue = -1;
            scanCacheAge.invalidate();
            if (wifiOperation.kind == QStringLiteral("scanning")) {
                finishWifiOperation(QStringLiteral("none"), QStringLiteral("cancelled"));
                return;
            }
            publishState();
            return;
        }

        const auto scanValue = readProperty(
            requestedOwner,
            devicePath,
            QString::fromLatin1(NetworkWirelessInterface),
            QStringLiteral("LastScan"));
        const auto deviceStateValue = readProperty(
            requestedOwner,
            devicePath,
            QString::fromLatin1(NetworkDeviceInterface),
            QStringLiteral("State"));
        if (scanValue) {
            const qint64 observedScan = scanValue->toLongLong();
            if (observedScan != lastScanValue) {
                lastScanValue = observedScan;
                if (observedScan >= 0) {
                    scanCacheAge.start();
                }
            }
        }
        rebuildNetworks(requestedOwner, devicePath);

        const uint deviceState = deviceStateValue ? deviceStateValue->toUInt() : 0U;
        if (wifiOperation.kind == QStringLiteral("scanning") && lastScanValue >= 0
            && lastScanValue != scanStartValue) {
            finishWifiOperation(QStringLiteral("none"), QStringLiteral("scan-complete"));
            return;
        }
        if (wifiOperation.kind == QStringLiteral("connecting")) {
            bool targetConnected = false;
            for (const WifiNetwork &network : std::as_const(wifiNetworks)) {
                targetConnected = targetConnected
                    || (network.token == wifiOperation.targetToken && network.connected);
            }
            if (deviceState == WifiDeviceActivated && targetConnected) {
                finishWifiOperation(QStringLiteral("none"), QStringLiteral("connected"));
                return;
            }
            if (deviceState == WifiDeviceFailed) {
                finishWifiOperation(
                    deviceFailureNeedsSecret(requestedOwner, devicePath)
                        ? QStringLiteral("wrong-secret")
                        : QStringLiteral("backend"));
                return;
            }
        }
        if (wifiOperation.kind == QStringLiteral("disconnecting")
            && currentNetworkLabel.isEmpty()) {
            finishWifiOperation(QStringLiteral("none"), QStringLiteral("disconnected"));
            return;
        }

        publishState();
        if (wifiInterest && wifiOperation.kind == QStringLiteral("idle") && scanCacheStale()) {
            requestScan(allocateOperationGeneration(), true);
        }
    }

    QString boundedBluetoothName(const QVariantMap &properties) const
    {
        QString name = unwrapDbusVariant(properties.value(QStringLiteral("Alias"))).toString();
        if (name.isEmpty()) {
            name = unwrapDbusVariant(properties.value(QStringLiteral("Name"))).toString();
        }
        name = name.simplified().left(MaximumBluetoothNameCharacters);
        return name.isEmpty() ? QStringLiteral("Bluetooth device") : name;
    }

    QString bluetoothType(const QVariantMap &properties) const
    {
        const QString icon =
            unwrapDbusVariant(properties.value(QStringLiteral("Icon"))).toString().toLower();
        if (icon.contains(QStringLiteral("audio")) || icon.contains(QStringLiteral("headset"))
            || icon.contains(QStringLiteral("headphones"))) {
            return QStringLiteral("audio");
        }
        if (icon.contains(QStringLiteral("input")) || icon.contains(QStringLiteral("keyboard"))
            || icon.contains(QStringLiteral("mouse"))) {
            return QStringLiteral("input");
        }
        if (icon.contains(QStringLiteral("phone"))) {
            return QStringLiteral("phone");
        }
        if (icon.contains(QStringLiteral("computer"))) {
            return QStringLiteral("computer");
        }
        return QStringLiteral("other");
    }

    int normalizedBluetoothSignal(const QVariantMap &properties) const
    {
        const QVariant value = unwrapDbusVariant(properties.value(QStringLiteral("RSSI")));
        if (!value.isValid() || !value.canConvert<int>()) {
            return -1;
        }
        return std::clamp((value.toInt() + 100) * 100 / 80, 0, 100);
    }

    int tokenForBluetoothDevice(const QString &path)
    {
        const auto existing = bluetoothDeviceTokens.constFind(path);
        if (existing != bluetoothDeviceTokens.constEnd()) {
            return existing.value();
        }
        const int token = nextBluetoothDeviceToken;
        nextBluetoothDeviceToken =
            nextBluetoothDeviceToken >= std::numeric_limits<int>::max()
            ? 1
            : nextBluetoothDeviceToken + 1;
        bluetoothDeviceTokens.insert(path, token);
        return token;
    }

    const BluetoothDevice *bluetoothDeviceForToken(int token) const
    {
        const auto device = std::find_if(
            bluetoothDevices.cbegin(),
            bluetoothDevices.cend(),
            [token](const BluetoothDevice &candidate) { return candidate.token == token; });
        return device == bluetoothDevices.cend() ? nullptr : &*device;
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
            diagnose(QStringLiteral("BlueZ state snapshot failed"));
            clearBluetoothManagerState(QStringLiteral("backend"));
            resetUnavailable(bluetooth, QStringLiteral("backend"));
            publishState();
            return;
        }
        if (bluezOwner != requestedOwner
            || currentServiceOwner(QString::fromLatin1(BluezService)) != requestedOwner) {
            return;
        }

        QList<BluetoothAdapter> adapters;
        QList<BluetoothDevice> devices;
        bool anyPowered = false;
        bool allPowered = true;
        const qint64 now = bluetoothClock.isValid() ? bluetoothClock.elapsed() : 0;
        const auto deviceBefore = [this](
                                      const BluetoothDevice &left,
                                      const BluetoothDevice &right) {
            const bool leftTarget = left.token == bluetoothOperation.targetToken;
            const bool rightTarget = right.token == bluetoothOperation.targetToken;
            if (leftTarget != rightTarget) {
                return leftTarget;
            }
            if (left.connected != right.connected) {
                return left.connected;
            }
            if (left.paired != right.paired) {
                return left.paired;
            }
            const int nameOrder =
                QString::compare(left.name, right.name, Qt::CaseInsensitive);
            return nameOrder == 0 ? left.token < right.token : nameOrder < 0;
        };
        for (auto object = reply.value().constBegin(); object != reply.value().constEnd(); ++object) {
            const auto adapter = object.value().constFind(QString::fromLatin1(BluezAdapterInterface));
            if (adapter != object.value().constEnd()) {
                const QVariant poweredValue =
                    unwrapDbusVariant(adapter->value(QStringLiteral("Powered")));
                if (poweredValue.metaType() == QMetaType::fromType<bool>()) {
                    const bool powered = poweredValue.toBool();
                    adapters.append(BluetoothAdapter{
                        object.key().path(),
                        powered,
                        unwrapDbusVariant(adapter->value(QStringLiteral("Discovering"))).toBool(),
                    });
                    anyPowered = anyPowered || powered;
                    allPowered = allPowered && powered;
                }
            }

            const auto device = object.value().constFind(QString::fromLatin1(BluezDeviceInterface));
            if (device == object.value().constEnd()) {
                continue;
            }
            const QString path = object.key().path();
            const auto previous = std::find_if(
                bluetoothDevices.cbegin(),
                bluetoothDevices.cend(),
                [&path](const BluetoothDevice &candidate) { return candidate.path == path; });
            const bool paired =
                unwrapDbusVariant(device->value(QStringLiteral("Paired"))).toBool();
            const bool connected =
                unwrapDbusVariant(device->value(QStringLiteral("Connected"))).toBool();
            const qint64 lastSeen =
                bluetoothDiscoveryActive ? now :
                previous != bluetoothDevices.cend() ? previous->lastSeenMs : 0;
            if (!paired && !connected && !bluetoothDiscoveryActive
                && (lastSeen == 0 || now - lastSeen >= DiscoveredDeviceRetentionMs)) {
                continue;
            }
            devices.append(BluetoothDevice{
                tokenForBluetoothDevice(path),
                path,
                unwrapDbusVariant(device->value(QStringLiteral("Adapter"))).value<QDBusObjectPath>().path(),
                boundedBluetoothName(*device),
                bluetoothType(*device),
                normalizedBluetoothSignal(*device),
                paired,
                connected,
                unwrapDbusVariant(device->value(QStringLiteral("Trusted"))).toBool(),
                lastSeen,
            });
            if (devices.size() > MaximumBluetoothDevices) {
                std::sort(devices.begin(), devices.end(), deviceBefore);
                devices.resize(MaximumBluetoothDevices);
                QHash<QString, int> boundedTokens;
                boundedTokens.reserve(devices.size());
                for (const BluetoothDevice &retained : std::as_const(devices)) {
                    boundedTokens.insert(retained.path, retained.token);
                }
                bluetoothDeviceTokens = boundedTokens;
            }
        }
        std::sort(
            adapters.begin(),
            adapters.end(),
            [](const BluetoothAdapter &left, const BluetoothAdapter &right) {
                return left.path < right.path;
            });
        std::sort(devices.begin(), devices.end(), deviceBefore);
        QHash<QString, int> retainedTokens;
        retainedTokens.reserve(devices.size());
        for (const BluetoothDevice &device : std::as_const(devices)) {
            retainedTokens.insert(device.path, device.token);
        }
        bluetoothDeviceTokens = retainedTokens;

        bluetoothAdapters = adapters;
        bluetoothDevices = devices;
        selectedBluetoothAdapter.clear();
        const auto poweredAdapter = std::find_if(
            adapters.cbegin(),
            adapters.cend(),
            [](const BluetoothAdapter &candidate) { return candidate.powered; });
        if (poweredAdapter != adapters.cend()) {
            selectedBluetoothAdapter = poweredAdapter->path;
        } else if (!adapters.isEmpty()) {
            selectedBluetoothAdapter = adapters.constFirst().path;
        }
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

        const BluetoothDevice *target =
            bluetoothDeviceForToken(bluetoothOperation.targetToken);
        if (bluetoothOperation.kind == QStringLiteral("connecting") && target != nullptr
            && target->connected) {
            finishBluetoothOperation(QStringLiteral("none"), QStringLiteral("connected"));
            return;
        }
        if (bluetoothOperation.kind == QStringLiteral("disconnecting")
            && (target == nullptr || !target->connected)) {
            finishBluetoothOperation(QStringLiteral("none"), QStringLiteral("disconnected"));
            return;
        }
        if (bluetoothOperation.kind == QStringLiteral("unpairing") && target == nullptr) {
            finishBluetoothOperation(QStringLiteral("none"), QStringLiteral("unpaired"));
            return;
        }
        publishState();
    }

    void requestWifi(bool enabled, int requestId)
    {
        if (!wifi.available || networkOwner.isEmpty()) {
            rejectRequest(wifi, requestId, QStringLiteral("unavailable"));
            return;
        }
        if (!wifi.hardwareEnabled) {
            rejectRequest(wifi, requestId, QStringLiteral("hardware"));
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
        if (wifiOperation.kind == QStringLiteral("scanning")) {
            wifiOperationTimer.stop();
            wifiOperation.kind = QStringLiteral("idle");
            wifiOperation.failure = QStringLiteral("none");
            wifiOperation.result = QStringLiteral("replaced");
        } else if (wifiOperation.kind != QStringLiteral("idle")) {
            return;
        }
        if (!beginWifiOperation(QStringLiteral("radio"), requestId)) {
            return;
        }

        wifi.pending = true;
        wifi.targetEnabled = enabled;
        wifi.requestId = requestId;
        wifi.failure = QStringLiteral("none");
        wifiRequestTimer.start();
        if (!enabled) {
            wifiNetworks.clear();
            currentNetworkLabel.clear();
            scanCacheAge.invalidate();
        }
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
        connect(
            watcher,
            &QDBusPendingCallWatcher::finished,
            this,
            [this, watcher, requestedOwner, requestId] {
                const QDBusPendingReply<> reply = *watcher;
                watcher->deleteLater();
                if (!wifi.pending || wifi.requestId != requestId
                    || networkOwner != requestedOwner) {
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
        if (!enabled) {
            if (bluetoothOperation.kind == QStringLiteral("pairing")) {
                cancelBluetoothPairing(requestId);
            }
            if (bluetoothDiscoveryActive) {
                stopBluetoothDiscovery(requestId, QStringLiteral("cancelled"));
            }
        }
        if (bluetoothOperation.kind != QStringLiteral("idle")) {
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
        for (const BluetoothAdapter &adapter : std::as_const(bluetoothAdapters)) {
            QDBusMessage request = QDBusMessage::createMethodCall(
                requestedOwner,
                adapter.path,
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

    QString normalizeBluetoothFailure(const QDBusError &error) const
    {
        const QString name = error.name().toLower();
        if (name.contains(QStringLiteral("canceled"))
            || name.contains(QStringLiteral("cancelled"))) {
            return QStringLiteral("cancelled");
        }
        if (name.contains(QStringLiteral("rejected"))
            || name.contains(QStringLiteral("failed"))) {
            return QStringLiteral("rejected");
        }
        if (name.contains(QStringLiteral("timeout")) || error.type() == QDBusError::Timeout
            || error.type() == QDBusError::NoReply) {
            return QStringLiteral("timeout");
        }
        if (name.contains(QStringLiteral("notready"))) {
            return QStringLiteral("unavailable");
        }
        if (name.contains(QStringLiteral("inprogress"))) {
            return QStringLiteral("busy");
        }
        return normalizeFailure(error);
    }

    void clearPairingReply(bool reject)
    {
        if (pendingAgentReply.type() == QDBusMessage::MethodCallMessage) {
            if (reject) {
                bus.send(pendingAgentReply.createErrorReply(
                    QStringLiteral("org.bluez.Error.Rejected"),
                    QStringLiteral("pairing request is no longer active")));
            }
            pendingAgentReply = {};
        }
        bluetoothOperation.prompt = QStringLiteral("none");
        bluetoothOperation.displayValue.clear();
        bluetoothOperation.displayEntered = 0;
    }

    void finishBluetoothOperation(
        const QString &failure,
        const QString &result = QStringLiteral("none"))
    {
        clearPairingReply(failure != QStringLiteral("none"));
        bluetoothOperation.kind = QStringLiteral("idle");
        bluetoothOperation.failure = failure;
        bluetoothOperation.result = result;
        bluetoothOperation.targetToken = 0;
        publishState();
    }

    bool beginBluetoothOperation(const QString &kind, int generation, int targetToken = 0)
    {
        if (bluetoothOperation.kind != QStringLiteral("idle")) {
            return false;
        }
        bluetoothOperation.kind = kind;
        bluetoothOperation.failure = QStringLiteral("none");
        bluetoothOperation.result = QStringLiteral("none");
        bluetoothOperation.prompt = QStringLiteral("none");
        bluetoothOperation.displayValue.clear();
        bluetoothOperation.displayEntered = 0;
        bluetoothOperation.generation = generation;
        bluetoothOperation.targetToken = targetToken;
        publishState();
        return true;
    }

    void handleAgentPrompt(
        const QString &kind,
        const QString &devicePath,
        const QString &value,
        uint entered,
        const QDBusMessage &message)
    {
        const BluetoothDevice *target =
            bluetoothDeviceForToken(bluetoothOperation.targetToken);
        if (bluetoothOperation.kind != QStringLiteral("pairing") || target == nullptr
            || target->path != devicePath
            || pendingAgentReply.type() == QDBusMessage::MethodCallMessage) {
            bus.send(message.createErrorReply(
                QStringLiteral("org.bluez.Error.Rejected"),
                QStringLiteral("pairing was not initiated by Nagi")));
            return;
        }
        pendingAgentReply = message;
        bluetoothOperation.prompt = kind;
        bluetoothOperation.displayValue = value.left(16);
        bluetoothOperation.displayEntered = std::min<uint>(entered, 16);
        publishState();
    }

    void handleAgentDisplay(
        const QString &kind,
        const QString &devicePath,
        const QString &value,
        uint entered)
    {
        const BluetoothDevice *target =
            bluetoothDeviceForToken(bluetoothOperation.targetToken);
        if (bluetoothOperation.kind != QStringLiteral("pairing") || target == nullptr
            || target->path != devicePath) {
            return;
        }
        bluetoothOperation.prompt = kind;
        bluetoothOperation.displayValue = value.left(16);
        bluetoothOperation.displayEntered = std::min<uint>(entered, 16);
        publishState();
    }

    void respondToBluetoothPrompt(
        int generation,
        bool accepted,
        const QString &response)
    {
        if (bluetoothOperation.kind != QStringLiteral("pairing")
            || bluetoothOperation.generation != generation
            || pendingAgentReply.type() != QDBusMessage::MethodCallMessage) {
            return;
        }
        const QString prompt = bluetoothOperation.prompt;
        QDBusMessage reply;
        if (!accepted) {
            reply = pendingAgentReply.createErrorReply(
                QStringLiteral("org.bluez.Error.Rejected"),
                QStringLiteral("pairing rejected"));
        } else if (prompt == QStringLiteral("enter-pin")) {
            if (response.isEmpty() || response.size() > 16) {
                return;
            }
            reply = pendingAgentReply.createReply(QVariantList{response});
        } else if (prompt == QStringLiteral("enter-passkey")) {
            bool valid = false;
            const uint passkey = response.toUInt(&valid);
            if (!valid || response.size() > 6 || passkey > 999999U) {
                return;
            }
            reply = pendingAgentReply.createReply(QVariantList{passkey});
        } else if (prompt == QStringLiteral("confirm-passkey")
                   || prompt == QStringLiteral("authorize-pairing")) {
            reply = pendingAgentReply.createReply();
        } else {
            return;
        }
        bus.send(reply);
        pendingAgentReply = {};
        bluetoothOperation.prompt = QStringLiteral("none");
        bluetoothOperation.displayValue.clear();
        bluetoothOperation.displayEntered = 0;
        publishState();
    }

    void expireBluetoothDevices()
    {
        const qint64 now = bluetoothClock.isValid() ? bluetoothClock.elapsed() : 0;
        bluetoothDevices.erase(
            std::remove_if(
                bluetoothDevices.begin(),
                bluetoothDevices.end(),
                [now](const BluetoothDevice &device) {
                    return !device.paired && !device.connected
                        && (device.lastSeenMs == 0
                            || now - device.lastSeenMs >= DiscoveredDeviceRetentionMs);
                }),
            bluetoothDevices.end());
        QHash<QString, int> retainedTokens;
        retainedTokens.reserve(bluetoothDevices.size());
        for (const BluetoothDevice &device : std::as_const(bluetoothDevices)) {
            retainedTokens.insert(device.path, device.token);
        }
        bluetoothDeviceTokens = retainedTokens;
        publishState();
    }

    void clearBluetoothManagerState(const QString &failure)
    {
        bluetoothDiscoveryTimer.stop();
        bluetoothExpiryTimer.stop();
        bluetoothDiscoveryActive = false;
        bluetoothDiscoveryAdapters.clear();
        bluetoothDevices.clear();
        bluetoothAdapters.clear();
        bluetoothDeviceTokens.clear();
        nextBluetoothDeviceToken = 1;
        selectedBluetoothAdapter.clear();
        clearPairingReply(true);
        bluetoothOperation = BluetoothOperation{};
        bluetoothOperation.failure = failure;
    }

    bool startBluetoothDiscovery(int generation)
    {
        if (!bluetoothInterest || !bluetooth.available || !bluetooth.enabled
            || bluezOwner.isEmpty() || bluetoothOperation.kind != QStringLiteral("idle")) {
            return false;
        }
        QStringList startedAdapters;
        const QString requestedOwner = bluezOwner;
        for (const BluetoothAdapter &adapter : std::as_const(bluetoothAdapters)) {
            if (!adapter.powered) {
                continue;
            }
            QVariantMap filter;
            filter.insert(
                QStringLiteral("Transport"),
                QVariant::fromValue(QDBusVariant(QStringLiteral("auto"))));
            QDBusMessage setFilter = QDBusMessage::createMethodCall(
                requestedOwner,
                adapter.path,
                QString::fromLatin1(BluezAdapterInterface),
                QStringLiteral("SetDiscoveryFilter"));
            setFilter << filter;
            const QDBusMessage filterReply = bus.call(setFilter, QDBus::Block, DbusTimeoutMs);
            if (filterReply.type() == QDBusMessage::ErrorMessage) {
                break;
            }
            QDBusMessage start = QDBusMessage::createMethodCall(
                requestedOwner,
                adapter.path,
                QString::fromLatin1(BluezAdapterInterface),
                QStringLiteral("StartDiscovery"));
            const QDBusMessage startReply = bus.call(start, QDBus::Block, DbusTimeoutMs);
            if (startReply.type() == QDBusMessage::ErrorMessage
                && !startReply.errorName().contains(QStringLiteral("InProgress"))) {
                break;
            }
            startedAdapters.append(adapter.path);
        }
        const int poweredCount = static_cast<int>(std::count_if(
            bluetoothAdapters.cbegin(),
            bluetoothAdapters.cend(),
            [](const BluetoothAdapter &adapter) { return adapter.powered; }));
        if (startedAdapters.size() != poweredCount || startedAdapters.isEmpty()) {
            bluetoothDiscoveryAdapters = startedAdapters;
            bluetoothDiscoveryActive = true;
            stopBluetoothDiscovery(generation, QStringLiteral("backend"));
            return false;
        }
        bluetoothDiscoveryAdapters = startedAdapters;
        bluetoothDiscoveryActive = true;
        bluetoothDiscoveryTimer.start();
        bluetoothOperation.kind = QStringLiteral("discovering");
        bluetoothOperation.failure = QStringLiteral("none");
        bluetoothOperation.result = QStringLiteral("none");
        bluetoothOperation.generation = generation;
        bluetoothOperation.targetToken = 0;
        publishState();
        scheduleBluezRefresh();
        return true;
    }

    void stopBluetoothDiscovery(int generation, const QString &result)
    {
        if (!bluetoothDiscoveryActive) {
            return;
        }
        bluetoothDiscoveryTimer.stop();
        const QString requestedOwner = bluezOwner;
        for (const QString &path : std::as_const(bluetoothDiscoveryAdapters)) {
            if (requestedOwner.isEmpty()) {
                break;
            }
            QDBusMessage stop = QDBusMessage::createMethodCall(
                requestedOwner,
                path,
                QString::fromLatin1(BluezAdapterInterface),
                QStringLiteral("StopDiscovery"));
            bus.call(stop, QDBus::Block, DbusTimeoutMs);
        }
        bluetoothDiscoveryActive = false;
        bluetoothDiscoveryAdapters.clear();
        bluetoothExpiryTimer.start(DiscoveredDeviceRetentionMs);
        bluetoothOperation.kind = QStringLiteral("idle");
        bluetoothOperation.generation = generation;
        bluetoothOperation.failure =
            result == QStringLiteral("backend") ? QStringLiteral("backend") :
                                                  QStringLiteral("none");
        bluetoothOperation.result = result;
        publishState();
        scheduleBluezRefresh();
    }

    void setBluetoothInterest(bool interested, int generation)
    {
        bluetoothInterest = interested;
        if (!interested) {
            if (bluetoothOperation.kind == QStringLiteral("pairing")) {
                cancelBluetoothPairing(generation);
            }
            if (bluetoothDiscoveryActive) {
                stopBluetoothDiscovery(generation, QStringLiteral("cancelled"));
            } else {
                publishState();
            }
        } else {
            publishState();
        }
    }

    void cancelBluetoothPairing(int generation)
    {
        if (bluetoothOperation.kind != QStringLiteral("pairing")) {
            return;
        }
        const BluetoothDevice *target =
            bluetoothDeviceForToken(bluetoothOperation.targetToken);
        if (target != nullptr && !bluezOwner.isEmpty()) {
            QDBusMessage cancel = QDBusMessage::createMethodCall(
                bluezOwner,
                target->path,
                QString::fromLatin1(BluezDeviceInterface),
                QStringLiteral("CancelPairing"));
            bus.call(cancel, QDBus::NoBlock);
        }
        bluetoothOperation.generation = generation;
        finishBluetoothOperation(QStringLiteral("cancelled"), QStringLiteral("cancelled"));
    }

    void connectAfterPairing(
        const QString &owner,
        const QString &path,
        int generation,
        int token)
    {
        if (bluezOwner != owner || bluetoothOperation.kind != QStringLiteral("pairing")
            || bluetoothOperation.generation != generation) {
            return;
        }
        QDBusMessage trust = QDBusMessage::createMethodCall(
            owner,
            path,
            QString::fromLatin1(PropertiesInterface),
            QStringLiteral("Set"));
        trust << QString::fromLatin1(BluezDeviceInterface) << QStringLiteral("Trusted")
              << QVariant::fromValue(QDBusVariant(true));
        const QDBusMessage trustReply = bus.call(trust, QDBus::Block, DbusTimeoutMs);
        if (trustReply.type() == QDBusMessage::ErrorMessage) {
            finishBluetoothOperation(QStringLiteral("trust-failed"), QStringLiteral("paired"));
            scheduleBluezRefresh();
            return;
        }
        QDBusMessage connectRequest = QDBusMessage::createMethodCall(
            owner,
            path,
            QString::fromLatin1(BluezDeviceInterface),
            QStringLiteral("Connect"));
        auto *watcher =
            new QDBusPendingCallWatcher(bus.asyncCall(connectRequest, WifiOperationTimeoutMs), this);
        connect(
            watcher,
            &QDBusPendingCallWatcher::finished,
            this,
            [this, watcher, owner, generation, token] {
                const QDBusPendingReply<> reply = *watcher;
                watcher->deleteLater();
                if (bluezOwner != owner || bluetoothOperation.kind != QStringLiteral("pairing")
                    || bluetoothOperation.generation != generation
                    || bluetoothOperation.targetToken != token) {
                    return;
                }
                if (reply.isError()
                    && !reply.error().name().contains(QStringLiteral("AlreadyConnected"))) {
                    finishBluetoothOperation(
                        QStringLiteral("connection-failed"),
                        QStringLiteral("paired"));
                } else {
                    finishBluetoothOperation(
                        QStringLiteral("none"),
                        QStringLiteral("paired-connected"));
                }
                scheduleBluezRefresh();
            });
    }

    bool requestBluetoothPair(int token, int generation)
    {
        if (!bluetoothInterest || !bluetoothAgentRegistered || !bluetooth.enabled
            || bluezOwner.isEmpty()) {
            return false;
        }
        if (bluetoothDiscoveryActive) {
            stopBluetoothDiscovery(generation, QStringLiteral("replaced"));
        }
        const BluetoothDevice *device = bluetoothDeviceForToken(token);
        if (device == nullptr || device->paired || bluetoothOperation.kind != QStringLiteral("idle")
            || !beginBluetoothOperation(QStringLiteral("pairing"), generation, token)) {
            return false;
        }
        const QString owner = bluezOwner;
        const QString path = device->path;
        QDBusMessage pair = QDBusMessage::createMethodCall(
            owner,
            path,
            QString::fromLatin1(BluezDeviceInterface),
            QStringLiteral("Pair"));
        auto *watcher = new QDBusPendingCallWatcher(
            bus.asyncCall(pair, std::numeric_limits<int>::max()),
            this);
        connect(
            watcher,
            &QDBusPendingCallWatcher::finished,
            this,
            [this, watcher, owner, path, generation, token] {
                const QDBusPendingReply<> reply = *watcher;
                watcher->deleteLater();
                if (bluezOwner != owner || bluetoothOperation.kind != QStringLiteral("pairing")
                    || bluetoothOperation.generation != generation
                    || bluetoothOperation.targetToken != token) {
                    return;
                }
                clearPairingReply(false);
                if (reply.isError()) {
                    finishBluetoothOperation(normalizeBluetoothFailure(reply.error()));
                    scheduleBluezRefresh();
                    return;
                }
                connectAfterPairing(owner, path, generation, token);
            });
        return true;
    }

    bool requestBluetoothDeviceAction(
        const QString &kind,
        int token,
        int generation)
    {
        if (!bluetoothInterest || !bluetooth.enabled || bluezOwner.isEmpty()) {
            return false;
        }
        if (bluetoothDiscoveryActive) {
            stopBluetoothDiscovery(generation, QStringLiteral("replaced"));
        }
        const BluetoothDevice *device = bluetoothDeviceForToken(token);
        if (device == nullptr || bluetoothOperation.kind != QStringLiteral("idle")) {
            return false;
        }
        QString member;
        QString operation;
        QString targetPath = device->path;
        if (kind == QStringLiteral("connect") && device->paired && !device->connected) {
            member = QStringLiteral("Connect");
            operation = QStringLiteral("connecting");
        } else if (kind == QStringLiteral("disconnect") && device->connected) {
            member = QStringLiteral("Disconnect");
            operation = QStringLiteral("disconnecting");
        } else if (kind == QStringLiteral("unpair") && device->paired
                   && std::any_of(
                       bluetoothAdapters.cbegin(),
                       bluetoothAdapters.cend(),
                       [&device](const BluetoothAdapter &adapter) {
                           return adapter.path == device->adapterPath;
                       })) {
            member = QStringLiteral("RemoveDevice");
            operation = QStringLiteral("unpairing");
            targetPath = device->adapterPath;
        } else {
            return false;
        }
        if (!beginBluetoothOperation(operation, generation, token)) {
            return false;
        }
        const QString owner = bluezOwner;
        QDBusMessage request = QDBusMessage::createMethodCall(
            owner,
            targetPath,
            kind == QStringLiteral("unpair") ? QString::fromLatin1(BluezAdapterInterface) :
                                               QString::fromLatin1(BluezDeviceInterface),
            member);
        if (kind == QStringLiteral("unpair")) {
            request << QDBusObjectPath(device->path);
        }
        auto *watcher =
            new QDBusPendingCallWatcher(bus.asyncCall(request, WifiOperationTimeoutMs), this);
        connect(
            watcher,
            &QDBusPendingCallWatcher::finished,
            this,
            [this, watcher, owner, generation, operation] {
                const QDBusPendingReply<> reply = *watcher;
                watcher->deleteLater();
                if (bluezOwner != owner || bluetoothOperation.kind != operation
                    || bluetoothOperation.generation != generation) {
                    return;
                }
                if (reply.isError()) {
                    finishBluetoothOperation(normalizeBluetoothFailure(reply.error()));
                } else {
                    scheduleBluezRefresh();
                }
            });
        return true;
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
            if (wifiOperation.kind == QStringLiteral("radio")) {
                finishWifiOperation(failure);
                return;
            }
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

    WifiNetwork *networkForToken(int token)
    {
        for (WifiNetwork &network : wifiNetworks) {
            if (network.token == token) {
                return &network;
            }
        }
        return nullptr;
    }

    bool validPersonalSecret(const QString &secret) const
    {
        const QByteArray bytes = secret.toUtf8();
        if (bytes.size() >= 8 && bytes.size() <= 63) {
            return true;
        }
        if (bytes.size() != 64) {
            return false;
        }
        return std::all_of(bytes.cbegin(), bytes.cend(), [](char character) {
            return (character >= '0' && character <= '9')
                || (character >= 'a' && character <= 'f')
                || (character >= 'A' && character <= 'F');
        });
    }

    ConnectionSettings connectionSettings(
        const QByteArray &ssid,
        const QString &label,
        const QString &security,
        const QString &keyManagement,
        QString secret,
        bool hidden,
        bool remember) const
    {
        QVariantMap connection{
            {QStringLiteral("id"), label.left(MaximumSsidBytes)},
            {QStringLiteral("type"), QStringLiteral("802-11-wireless")},
            {QStringLiteral("autoconnect"), remember},
        };
        const QString currentUser = currentUserName();
        if (!currentUser.isEmpty() && currentUser.size() <= 256) {
            connection.insert(
                QStringLiteral("permissions"),
                QStringList{QStringLiteral("user:") + currentUser + QLatin1Char(':')});
        }
        ConnectionSettings settings{
            {QStringLiteral("connection"), connection},
            {QStringLiteral("802-11-wireless"),
             QVariantMap{
                 {QStringLiteral("ssid"), ssid},
                 {QStringLiteral("hidden"), hidden},
                 {QStringLiteral("mode"), QStringLiteral("infrastructure")},
             }},
        };
        if (security == QStringLiteral("wpa-personal")) {
            settings.insert(
                QStringLiteral("802-11-wireless-security"),
                QVariantMap{
                    {QStringLiteral("key-mgmt"), keyManagement},
                    {QStringLiteral("psk"), secret},
                    {QStringLiteral("psk-flags"), remember ? 1U : 2U},
                });
        }
        secret.fill(QChar());
        return settings;
    }

    bool prepareConnectionOperation(int generation)
    {
        if (!wifiInterest || !wifi.available || !wifi.enabled || wifiDevicePath.isEmpty()
            || networkOwner.isEmpty() || wifi.pending) {
            return false;
        }
        if (wifiOperation.kind == QStringLiteral("scanning")) {
            wifiOperationTimer.stop();
            wifiOperation.kind = QStringLiteral("idle");
            wifiOperation.failure = QStringLiteral("none");
            wifiOperation.result = QStringLiteral("replaced");
        }
        return beginWifiOperation(QStringLiteral("connecting"), generation);
    }

    void dispatchConnection(
        int token,
        const QByteArray &ssid,
        const QString &label,
        const QString &security,
        const QString &keyManagement,
        const QString &profilePath,
        const QString &accessPointPath,
        QString secret,
        bool hidden,
        bool remember,
        int generation)
    {
        if (!prepareConnectionOperation(generation)) {
            secret.fill(QChar());
            return;
        }
        wifiOperation.targetToken = token;
        const QString requestedOwner = networkOwner;
        QDBusMessage request;
        if (!profilePath.isEmpty()) {
            request = QDBusMessage::createMethodCall(
                requestedOwner,
                QString::fromLatin1(NetworkPath),
                QString::fromLatin1(NetworkInterface),
                QStringLiteral("ActivateConnection"));
            request << QVariant::fromValue(QDBusObjectPath(profilePath))
                    << QVariant::fromValue(QDBusObjectPath(wifiDevicePath))
                    << QVariant::fromValue(QDBusObjectPath(
                           accessPointPath.isEmpty() ? QStringLiteral("/") : accessPointPath));
        } else {
            const ConnectionSettings settings = connectionSettings(
                ssid,
                label,
                security,
                keyManagement,
                secret,
                hidden,
                remember);
            QVariantMap options{
                {QStringLiteral("persist"),
                 remember ? QStringLiteral("disk") : QStringLiteral("memory")},
                {QStringLiteral("bind-activation"), QStringLiteral("dbus-client")},
            };
            request = QDBusMessage::createMethodCall(
                requestedOwner,
                QString::fromLatin1(NetworkPath),
                QString::fromLatin1(NetworkInterface),
                QStringLiteral("AddAndActivateConnection2"));
            request << QVariant::fromValue(settings)
                    << QVariant::fromValue(QDBusObjectPath(wifiDevicePath))
                    << QVariant::fromValue(QDBusObjectPath(
                           hidden ? QStringLiteral("/") : accessPointPath))
                    << options;
        }
        secret.fill(QChar());

        auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(request, DbusTimeoutMs), this);
        connect(
            watcher,
            &QDBusPendingCallWatcher::finished,
            this,
            [this, watcher, requestedOwner, generation] {
                const QDBusPendingReply<> reply = *watcher;
                watcher->deleteLater();
                if (networkOwner != requestedOwner
                    || wifiOperation.kind != QStringLiteral("connecting")
                    || wifiOperation.generation != generation) {
                    return;
                }
                if (reply.isError()) {
                    finishWifiOperation(normalizeFailure(reply.error()));
                    return;
                }
                scheduleNetworkRefresh();
            });
    }

    void requestVisibleConnection(
        int token,
        QString secret,
        bool remember,
        int generation)
    {
        WifiNetwork *network = networkForToken(token);
        if (network == nullptr || (!network->saved
                                   && network->security == QStringLiteral("unsupported"))
            || (!network->saved && network->security == QStringLiteral("wpa-personal")
                && !validPersonalSecret(secret))
            || (!network->saved && network->security == QStringLiteral("open")
                && !secret.isEmpty())) {
            secret.fill(QChar());
            wifiOperation.generation = generation;
            wifiOperation.failure = QStringLiteral("invalid");
            wifiOperation.result = QStringLiteral("none");
            publishState();
            return;
        }
        dispatchConnection(
            network->token,
            network->ssid,
            network->label,
            network->security,
            network->keyManagement,
            network->profilePath,
            network->accessPointPath,
            secret,
            false,
            remember,
            generation);
    }

    void requestHiddenConnection(
        QByteArray ssid,
        const QString &label,
        const QString &security,
        QString secret,
        bool remember,
        int generation)
    {
        if (ssid.isEmpty() || ssid.size() > MaximumSsidBytes || label.isEmpty()
            || (security != QStringLiteral("open")
                && security != QStringLiteral("wpa-personal"))
            || (security == QStringLiteral("wpa-personal") && !validPersonalSecret(secret))
            || (security == QStringLiteral("open") && !secret.isEmpty())) {
            ssid.fill('\0');
            secret.fill(QChar());
            wifiOperation.generation = generation;
            wifiOperation.failure = QStringLiteral("invalid");
            wifiOperation.result = QStringLiteral("none");
            publishState();
            return;
        }
        const QString key = QString::fromLatin1(ssid.toBase64()) + QLatin1Char('|') + security;
        const int token = tokenForNetwork(key);
        dispatchConnection(
            token,
            ssid,
            label,
            security,
            QStringLiteral("wpa-psk"),
            QString(),
            QStringLiteral("/"),
            secret,
            true,
            remember,
            generation);
        ssid.fill('\0');
    }

    void requestDisconnect(int generation)
    {
        if (!wifi.available || !wifi.enabled || wifiDevicePath.isEmpty()
            || currentNetworkLabel.isEmpty() || wifiOperation.kind != QStringLiteral("idle")
            || wifi.pending || !beginWifiOperation(QStringLiteral("disconnecting"), generation)) {
            return;
        }
        const QString requestedOwner = networkOwner;
        QDBusMessage request = QDBusMessage::createMethodCall(
            requestedOwner,
            wifiDevicePath,
            QString::fromLatin1(NetworkDeviceInterface),
            QStringLiteral("Disconnect"));
        auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(request, DbusTimeoutMs), this);
        connect(
            watcher,
            &QDBusPendingCallWatcher::finished,
            this,
            [this, watcher, requestedOwner, generation] {
                const QDBusPendingReply<> reply = *watcher;
                watcher->deleteLater();
                if (networkOwner != requestedOwner
                    || wifiOperation.kind != QStringLiteral("disconnecting")
                    || wifiOperation.generation != generation) {
                    return;
                }
                if (reply.isError()) {
                    finishWifiOperation(normalizeFailure(reply.error()));
                } else {
                    scheduleNetworkRefresh();
                }
            });
    }

    void requestForget(int token, int generation)
    {
        WifiNetwork *network = networkForToken(token);
        if (network == nullptr || !network->forgettable || network->profilePath.isEmpty()
            || wifiOperation.kind != QStringLiteral("idle") || wifi.pending
            || !beginWifiOperation(QStringLiteral("forgetting"), generation)) {
            return;
        }
        wifiOperation.targetToken = token;
        const QString profilePath = network->profilePath;
        const QString requestedOwner = networkOwner;
        QDBusMessage request = QDBusMessage::createMethodCall(
            requestedOwner,
            profilePath,
            QString::fromLatin1(NetworkConnectionInterface),
            QStringLiteral("Delete"));
        auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(request, DbusTimeoutMs), this);
        connect(
            watcher,
            &QDBusPendingCallWatcher::finished,
            this,
            [this, watcher, requestedOwner, generation, token] {
                const QDBusPendingReply<> reply = *watcher;
                watcher->deleteLater();
                if (networkOwner != requestedOwner
                    || wifiOperation.kind != QStringLiteral("forgetting")
                    || wifiOperation.generation != generation) {
                    return;
                }
                if (reply.isError()) {
                    finishWifiOperation(normalizeFailure(reply.error()));
                    return;
                }
                if (WifiNetwork *network = networkForToken(token); network != nullptr) {
                    network->saved = false;
                    network->forgettable = false;
                    network->profilePath.clear();
                }
                finishWifiOperation(QStringLiteral("none"), QStringLiteral("forgotten"));
                scheduleNetworkRefresh();
            });
    }

    void setWifiInterest(bool interested, int generation)
    {
        wifiInterest = interested;
        if (!interested) {
            if (wifiOperation.kind == QStringLiteral("scanning")) {
                wifiOperation.generation = generation;
                finishWifiOperation(QStringLiteral("none"), QStringLiteral("cancelled"));
            } else {
                publishState();
            }
            return;
        }
        scheduleNetworkRefresh();
    }
    bool validPositiveInteger(const QJsonValue &value) const
    {
        return value.isDouble() && value.toDouble() >= 1
            && value.toDouble() <= std::numeric_limits<int>::max()
            && value.toInt() == value.toDouble();
    }

    void handleCommand(const QJsonObject &command)
    {
        const QString operation = command.value(QStringLiteral("op")).toString();
        if (operation == QStringLiteral("shutdown")) {
            QCoreApplication::quit();
            return;
        }
        const QJsonValue requestValue = command.value(QStringLiteral("requestId"));
        if (!validPositiveInteger(requestValue)) {
            diagnose(QStringLiteral("invalid command schema"));
            return;
        }
        const int requestId = requestValue.toInt();

        if (operation == QStringLiteral("set")) {
            const QJsonValue enabledValue = command.value(QStringLiteral("enabled"));
            const QString adapter = command.value(QStringLiteral("adapter")).toString();
            if (!enabledValue.isBool()
                || (adapter != QStringLiteral("wifi")
                    && adapter != QStringLiteral("bluetooth"))) {
                diagnose(QStringLiteral("invalid command schema"));
                return;
            }
            if (adapter == QStringLiteral("wifi")) {
                requestWifi(enabledValue.toBool(), requestId);
            } else {
                requestBluetooth(enabledValue.toBool(), requestId);
            }
            return;
        }
        if (operation == QStringLiteral("wifi-interest")) {
            const QJsonValue interested = command.value(QStringLiteral("interested"));
            if (!interested.isBool()) {
                diagnose(QStringLiteral("invalid command schema"));
                return;
            }
            setWifiInterest(interested.toBool(), requestId);
            return;
        }
        if (operation == QStringLiteral("bluetooth-interest")) {
            const QJsonValue interested = command.value(QStringLiteral("interested"));
            if (!interested.isBool()) {
                diagnose(QStringLiteral("invalid command schema"));
                return;
            }
            setBluetoothInterest(interested.toBool(), requestId);
            return;
        }
        if (operation == QStringLiteral("bluetooth-scan")) {
            startBluetoothDiscovery(requestId);
            return;
        }
        if (operation == QStringLiteral("bluetooth-stop-scan")) {
            stopBluetoothDiscovery(requestId, QStringLiteral("stopped"));
            return;
        }
        if (operation == QStringLiteral("bluetooth-cancel")) {
            cancelBluetoothPairing(requestId);
            return;
        }
        if (operation == QStringLiteral("bluetooth-agent-response")) {
            const QJsonValue generation = command.value(QStringLiteral("generation"));
            const QJsonValue accepted = command.value(QStringLiteral("accepted"));
            const QJsonValue response = command.value(QStringLiteral("response"));
            if (!validPositiveInteger(generation) || !accepted.isBool() || !response.isString()
                || response.toString().size() > 16) {
                diagnose(QStringLiteral("invalid command schema"));
                return;
            }
            QString privateResponse = response.toString();
            respondToBluetoothPrompt(
                generation.toInt(),
                accepted.toBool(),
                privateResponse);
            privateResponse.fill(QChar());
            return;
        }
        if (operation == QStringLiteral("bluetooth-pair")
            || operation == QStringLiteral("bluetooth-connect")
            || operation == QStringLiteral("bluetooth-disconnect")
            || operation == QStringLiteral("bluetooth-unpair")) {
            const QJsonValue token = command.value(QStringLiteral("token"));
            if (!validPositiveInteger(token)) {
                diagnose(QStringLiteral("invalid command schema"));
                return;
            }
            if (operation == QStringLiteral("bluetooth-pair")) {
                requestBluetoothPair(token.toInt(), requestId);
            } else {
                requestBluetoothDeviceAction(
                    operation.mid(QStringLiteral("bluetooth-").size()),
                    token.toInt(),
                    requestId);
            }
            return;
        }
        if (operation == QStringLiteral("scan")) {
            requestScan(requestId, false);
            return;
        }
        if (operation == QStringLiteral("disconnect")) {
            requestDisconnect(requestId);
            return;
        }
        if (operation == QStringLiteral("forget")) {
            const QJsonValue token = command.value(QStringLiteral("token"));
            if (!validPositiveInteger(token)) {
                diagnose(QStringLiteral("invalid command schema"));
                return;
            }
            requestForget(token.toInt(), requestId);
            return;
        }
        if (operation == QStringLiteral("connect")) {
            const QJsonValue token = command.value(QStringLiteral("token"));
            const QJsonValue secretValue = command.value(QStringLiteral("secret"));
            const QJsonValue rememberValue = command.value(QStringLiteral("remember"));
            if (!validPositiveInteger(token) || !secretValue.isString()
                || secretValue.toString().toUtf8().size() > 64 || !rememberValue.isBool()) {
                diagnose(QStringLiteral("invalid command schema"));
                return;
            }
            QString secret = secretValue.toString();
            requestVisibleConnection(
                token.toInt(),
                secret,
                rememberValue.toBool(),
                requestId);
            secret.fill(QChar());
            return;
        }
        if (operation == QStringLiteral("hidden-connect")) {
            const QJsonValue ssidValue = command.value(QStringLiteral("ssid"));
            const QJsonValue securityValue = command.value(QStringLiteral("security"));
            const QJsonValue secretValue = command.value(QStringLiteral("secret"));
            const QJsonValue rememberValue = command.value(QStringLiteral("remember"));
            if (!ssidValue.isString() || !securityValue.isString() || !secretValue.isString()
                || !rememberValue.isBool() || ssidValue.toString().toUtf8().size() < 1
                || ssidValue.toString().toUtf8().size() > MaximumSsidBytes
                || secretValue.toString().toUtf8().size() > 64) {
                diagnose(QStringLiteral("invalid command schema"));
                return;
            }
            QByteArray ssid = ssidValue.toString().toUtf8();
            QString secret = secretValue.toString();
            requestHiddenConnection(
                ssid,
                boundedSsidLabel(ssid),
                securityValue.toString(),
                secret,
                rememberValue.toBool(),
                requestId);
            ssid.fill('\0');
            secret.fill(QChar());
            return;
        }
        diagnose(QStringLiteral("invalid command schema"));
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

    QJsonObject wifiJson() const
    {
        QJsonObject state = adapterJson(wifi);
        QJsonArray networks;
        for (const WifiNetwork &network : wifiNetworks) {
            networks.append(QJsonObject{
                {QStringLiteral("token"), network.token},
                {QStringLiteral("ssid"), network.label},
                {QStringLiteral("security"), network.security},
                {QStringLiteral("strength"), network.strength},
                {QStringLiteral("connected"), network.connected},
                {QStringLiteral("saved"), network.saved},
                {QStringLiteral("forgettable"), network.forgettable},
                {QStringLiteral("connectable"),
                 network.saved || network.security == QStringLiteral("open")
                     || network.security == QStringLiteral("wpa-personal")},
                {QStringLiteral("forgetReason"),
                 network.saved && !network.forgettable ? QStringLiteral("admin-owned") :
                                                         QStringLiteral("none")},
            });
        }
        state.insert(QStringLiteral("networkingEnabled"), wifiNetworkingEnabled);
        state.insert(
            QStringLiteral("scanning"),
            wifiInterest && wifiOperation.kind == QStringLiteral("scanning"));
        state.insert(QStringLiteral("currentNetwork"), currentNetworkLabel);
        state.insert(QStringLiteral("networks"), networks);
        state.insert(QStringLiteral("operation"), wifiOperation.kind);
        state.insert(QStringLiteral("operationGeneration"), wifiOperation.generation);
        state.insert(QStringLiteral("operationFailure"), wifiOperation.failure);
        state.insert(QStringLiteral("operationResult"), wifiOperation.result);
        return state;
    }

    QJsonObject bluetoothJson() const
    {
        QJsonObject state = adapterJson(bluetooth);
        QJsonArray devices;
        const bool actionsAvailable =
            bluetoothOperation.kind == QStringLiteral("idle")
            || bluetoothOperation.kind == QStringLiteral("discovering");
        for (const BluetoothDevice &device : bluetoothDevices) {
            devices.append(QJsonObject{
                {QStringLiteral("token"), device.token},
                {QStringLiteral("name"), device.name},
                {QStringLiteral("type"), device.type},
                {QStringLiteral("signal"), device.signal},
                {QStringLiteral("paired"), device.paired},
                {QStringLiteral("connected"), device.connected},
                {QStringLiteral("trusted"), device.trusted},
                {QStringLiteral("pairable"),
                 !device.paired && actionsAvailable && bluetoothAgentRegistered},
                {QStringLiteral("connectable"),
                 device.paired && !device.connected && actionsAvailable},
                {QStringLiteral("disconnectable"), device.connected && actionsAvailable},
                {QStringLiteral("unpairable"), device.paired && actionsAvailable},
            });
        }
        int selectedController = 0;
        for (qsizetype index = 0; index < bluetoothAdapters.size(); ++index) {
            if (bluetoothAdapters.at(index).path == selectedBluetoothAdapter) {
                selectedController = static_cast<int>(index + 1);
                break;
            }
        }
        state.insert(QStringLiteral("controllerCount"), bluetoothAdapters.size());
        state.insert(QStringLiteral("selectedController"), selectedController);
        state.insert(QStringLiteral("discovering"), bluetoothDiscoveryActive);
        state.insert(
            QStringLiteral("discoveryDeadlineMs"),
            bluetoothDiscoveryActive ? std::max(0, bluetoothDiscoveryTimer.remainingTime()) : 0);
        state.insert(QStringLiteral("devices"), devices);
        state.insert(QStringLiteral("operation"), bluetoothOperation.kind);
        state.insert(QStringLiteral("operationGeneration"), bluetoothOperation.generation);
        state.insert(QStringLiteral("operationFailure"), bluetoothOperation.failure);
        state.insert(QStringLiteral("operationResult"), bluetoothOperation.result);
        state.insert(QStringLiteral("pairingPrompt"), bluetoothOperation.prompt);
        state.insert(QStringLiteral("pairingValue"), bluetoothOperation.displayValue);
        state.insert(QStringLiteral("pairingEntered"), bluetoothOperation.displayEntered);
        state.insert(QStringLiteral("pairingToken"), bluetoothOperation.targetToken);
        return state;
    }

    void publishState(bool force = false)
    {
        const QJsonObject message{
            {QStringLiteral("type"), QStringLiteral("state")},
            {QStringLiteral("wifi"), wifiJson()},
            {QStringLiteral("bluetooth"), bluetoothJson()},
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
    BluezAgent bluezAgent;
    QDBusServiceWatcher networkWatcher;
    QDBusServiceWatcher bluezWatcher;
    QString networkOwner;
    QString bluezOwner;
    QList<BluetoothAdapter> bluetoothAdapters;
    QList<BluetoothDevice> bluetoothDevices;
    QHash<QString, int> bluetoothDeviceTokens;
    QStringList bluetoothDiscoveryAdapters;
    QString selectedBluetoothAdapter;
    QString wifiDevicePath;
    QString currentNetworkLabel;
    QList<WifiNetwork> wifiNetworks;
    QHash<QString, int> networkTokens;
    AdapterState wifi;
    AdapterState bluetooth;
    QTimer wifiRequestTimer;
    QTimer bluetoothRequestTimer;
    QTimer wifiOperationTimer;
    QTimer bluetoothDiscoveryTimer;
    QTimer bluetoothExpiryTimer;
    QSocketNotifier *stdinNotifier = nullptr;
    QByteArray commandBuffer;
    QByteArray lastState;
    QString lastDiagnostic;
    QString bluetoothCallFailure;
    QDBusMessage pendingAgentReply;
    int bluetoothPendingCalls = 0;
    WifiOperation wifiOperation;
    BluetoothOperation bluetoothOperation;
    QElapsedTimer scanCacheAge;
    QElapsedTimer manualScanAge;
    QElapsedTimer bluetoothClock;
    qint64 lastScanValue = -1;
    qint64 scanStartValue = -1;
    int nextNetworkToken = 1;
    int nextBluetoothDeviceToken = 1;
    int nextOperationGeneration = 1;
    bool wifiInterest = false;
    bool bluetoothInterest = false;
    bool bluetoothDiscoveryActive = false;
    bool bluetoothAgentRegistered = false;
    bool wifiNetworkingEnabled = false;
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

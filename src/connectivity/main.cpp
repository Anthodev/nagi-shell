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
#include <QJsonArray>
#include <QJsonObject>
#include <QHash>
#include <QMap>
#include <QSocketNotifier>
#include <QTimer>
#include <QVariantMap>
#include <QElapsedTimer>

#include <array>
#include <cerrno>
#include <cstring>
#include <cstdio>
#include <limits>
#include <optional>
#include <pwd.h>
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
constexpr auto BluezAdapterInterface = "org.bluez.Adapter1";
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
constexpr int MaximumSsidBytes = 32;
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

QDBusConnection connectivityBus()
{
    return qEnvironmentVariable("NAGI_CONNECTIVITY_BUS") == QStringLiteral("session")
        ? QDBusConnection::sessionBus()
        : QDBusConnection::systemBus();
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
        wifiRequestTimer.setInterval(RadioTimeoutMs);
        wifiOperationTimer.setSingleShot(true);
        wifiOperationTimer.setInterval(WifiOperationTimeoutMs);
        bluetoothRequestTimer.setSingleShot(true);
        bluetoothRequestTimer.setInterval(RadioTimeoutMs);

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
        bluetoothAdapters.clear();
        resetUnavailable(bluetooth);
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

    void publishState(bool force = false)
    {
        const QJsonObject message{
            {QStringLiteral("type"), QStringLiteral("state")},
            {QStringLiteral("wifi"), wifiJson()},
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
    QString wifiDevicePath;
    QString currentNetworkLabel;
    QList<WifiNetwork> wifiNetworks;
    QHash<QString, int> networkTokens;
    AdapterState wifi;
    AdapterState bluetooth;
    QTimer wifiRequestTimer;
    QTimer bluetoothRequestTimer;
    QTimer wifiOperationTimer;
    QSocketNotifier *stdinNotifier = nullptr;
    QByteArray commandBuffer;
    QByteArray lastState;
    QString lastDiagnostic;
    QString bluetoothCallFailure;
    int bluetoothPendingCalls = 0;
    WifiOperation wifiOperation;
    QElapsedTimer scanCacheAge;
    QElapsedTimer manualScanAge;
    qint64 lastScanValue = -1;
    qint64 scanStartValue = -1;
    int nextNetworkToken = 1;
    int nextOperationGeneration = 1;
    bool wifiInterest = false;
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

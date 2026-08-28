#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusVariant>
#include <QDBusVirtualObject>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QMap>
#include <QProcess>
#include <QTimer>
#include <QVariantMap>

#include <array>
#include <cstdio>
#include <cstring>
#include <utility>
#include <pwd.h>
#include <unistd.h>

using InterfaceProperties = QMap<QString, QVariantMap>;
using ManagedObjectMap = QMap<QDBusObjectPath, InterfaceProperties>;

Q_DECLARE_METATYPE(InterfaceProperties)
Q_DECLARE_METATYPE(ManagedObjectMap)

namespace {

constexpr auto NetworkService = "org.freedesktop.NetworkManager";
constexpr auto NetworkPath = "/org/freedesktop/NetworkManager";
constexpr auto NetworkInterface = "org.freedesktop.NetworkManager";
constexpr auto NetworkDevicePath = "/org/freedesktop/NetworkManager/Devices/1";
constexpr auto NetworkDeviceInterface = "org.freedesktop.NetworkManager.Device";
constexpr auto NetworkWirelessInterface = "org.freedesktop.NetworkManager.Device.Wireless";
constexpr auto NetworkAccessPointInterface = "org.freedesktop.NetworkManager.AccessPoint";
constexpr auto NetworkSettingsPath = "/org/freedesktop/NetworkManager/Settings";
constexpr auto NetworkSettingsInterface = "org.freedesktop.NetworkManager.Settings";
constexpr auto NetworkConnectionInterface = "org.freedesktop.NetworkManager.Settings.Connection";
constexpr auto MeshAccessPointPath = "/org/freedesktop/NetworkManager/AccessPoint/1";
constexpr auto MeshWeakAccessPointPath = "/org/freedesktop/NetworkManager/AccessPoint/2";
constexpr auto SecureAccessPointPath = "/org/freedesktop/NetworkManager/AccessPoint/6";
constexpr auto CafeAccessPointPath = "/org/freedesktop/NetworkManager/AccessPoint/3";
constexpr auto AdminAccessPointPath = "/org/freedesktop/NetworkManager/AccessPoint/4";
constexpr auto HiddenAccessPointPath = "/org/freedesktop/NetworkManager/AccessPoint/5";
constexpr auto UserProfilePath = "/org/freedesktop/NetworkManager/Settings/User";
constexpr auto AdminProfilePath = "/org/freedesktop/NetworkManager/Settings/Admin";
constexpr auto BluezService = "org.bluez";
constexpr auto BluezAdapterPath = "/org/bluez/hci0";
constexpr auto BluezAdapterInterface = "org.bluez.Adapter1";
constexpr auto ObjectManagerInterface = "org.freedesktop.DBus.ObjectManager";
constexpr auto PropertiesInterface = "org.freedesktop.DBus.Properties";

QString currentUserName()
{
    constexpr qsizetype maximumUsernameBytes = 256;
    std::array<char, 16384> buffer{};
    passwd entry{};
    passwd *result = nullptr;
    if (::getpwuid_r(::getuid(), &entry, buffer.data(), buffer.size(), &result) != 0
        || result == nullptr || result->pw_name == nullptr) {
        return {};
    }
    const size_t length = ::strnlen(result->pw_name, maximumUsernameBytes + 1);
    return length > 0 && length <= static_cast<size_t>(maximumUsernameBytes)
        ? QString::fromLocal8Bit(result->pw_name, static_cast<qsizetype>(length))
        : QString{};
}

class FakeConnectivityServices final : public QDBusVirtualObject {
public:
    explicit FakeConnectivityServices(QDBusConnection bus, QObject *parent = nullptr)
        : QDBusVirtualObject(parent)
        , bus(std::move(bus))
    {
    }

    QString introspect(const QString &) const override
    {
        return {};
    }

    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override
    {
        if (message.interface() == QString::fromLatin1(PropertiesInterface)) {
            if (message.member() == QStringLiteral("Get")) {
                return handleGet(message, connection);
            }
            if (message.member() == QStringLiteral("Set")) {
                return handleSet(message, connection);
            }
        }
        if (message.path() == QString::fromLatin1(NetworkPath)
            && message.interface() == QString::fromLatin1(NetworkInterface)
            && message.member() == QStringLiteral("GetDevices")) {
            connection.send(message.createReply(QVariantList{QVariant::fromValue(
                QList<QDBusObjectPath>{QDBusObjectPath(QString::fromLatin1(NetworkDevicePath))})}));
            return true;
        }
        if (message.path() == QString::fromLatin1(NetworkDevicePath)
            && message.interface() == QString::fromLatin1(NetworkWirelessInterface)
            && message.member() == QStringLiteral("GetAllAccessPoints")) {
            QList<QDBusObjectPath> paths{
                QDBusObjectPath(QString::fromLatin1(MeshAccessPointPath)),
                QDBusObjectPath(QString::fromLatin1(MeshWeakAccessPointPath)),
                QDBusObjectPath(QString::fromLatin1(CafeAccessPointPath)),
                QDBusObjectPath(QString::fromLatin1(AdminAccessPointPath)),
                QDBusObjectPath(QString::fromLatin1(SecureAccessPointPath)),
            };
            if (hiddenVisible) {
                paths.append(QDBusObjectPath(QString::fromLatin1(HiddenAccessPointPath)));
            }
            connection.send(
                message.createReply(QVariantList{QVariant::fromValue(paths)}));
            return true;
        }
        if (message.path() == QString::fromLatin1(NetworkDevicePath)
            && message.interface() == QString::fromLatin1(NetworkWirelessInterface)
            && message.member() == QStringLiteral("RequestScan")) {
            connection.send(message.createReply());
            QTimer::singleShot(20, this, [this] {
                lastScan = 424242;
                sendPropertyChanged(
                    QString::fromLatin1(NetworkDevicePath),
                    QString::fromLatin1(NetworkWirelessInterface),
                    QStringLiteral("LastScan"),
                    lastScan);
            });
            return true;
        }
        if (message.path() == QString::fromLatin1(NetworkSettingsPath)
            && message.interface() == QString::fromLatin1(NetworkSettingsInterface)
            && message.member() == QStringLiteral("ListConnections")) {
            QList<QDBusObjectPath> paths{
                QDBusObjectPath(QString::fromLatin1(AdminProfilePath)),
            };
            if (!userProfileDeleted) {
                paths.prepend(QDBusObjectPath(QString::fromLatin1(UserProfilePath)));
            }
            connection.send(
                message.createReply(QVariantList{QVariant::fromValue(paths)}));
            return true;
        }
        if (message.interface() == QString::fromLatin1(NetworkConnectionInterface)
            && message.member() == QStringLiteral("GetSettings")) {
            return handleGetSettings(message, connection);
        }
        if (message.interface() == QString::fromLatin1(NetworkConnectionInterface)
            && message.member() == QStringLiteral("Delete")) {
            return handleDelete(message, connection);
        }
        if (message.path() == QString::fromLatin1(NetworkPath)
            && message.interface() == QString::fromLatin1(NetworkInterface)
            && (message.member() == QStringLiteral("ActivateConnection")
                || message.member() == QStringLiteral("AddAndActivateConnection2"))) {
            return handleActivate(message, connection);
        }
        if (message.path() == QString::fromLatin1(NetworkDevicePath)
            && message.interface() == QString::fromLatin1(NetworkDeviceInterface)
            && message.member() == QStringLiteral("Disconnect")) {
            connection.send(message.createReply());
            QTimer::singleShot(0, this, [this] { setActiveAccessPoint(QString(), 30U); });
            return true;
        }
        if (message.path() == QStringLiteral("/")
            && message.interface() == QString::fromLatin1(ObjectManagerInterface)
            && message.member() == QStringLiteral("GetManagedObjects")) {
            InterfaceProperties interfaces;
            interfaces.insert(
                QString::fromLatin1(BluezAdapterInterface),
                QVariantMap{{QStringLiteral("Powered"), bluetoothPowered}});
            ManagedObjectMap objects;
            objects.insert(QDBusObjectPath(QString::fromLatin1(BluezAdapterPath)), interfaces);
            connection.send(message.createReply(
                QVariantList{QVariant::fromValue(objects)}));
            return true;
        }
        return false;
    }

    void setWifiExternally(bool enabled)
    {
        wifiEnabled = enabled;
        sendPropertyChanged(
            QString::fromLatin1(NetworkPath),
            QString::fromLatin1(NetworkInterface),
            QStringLiteral("WirelessEnabled"),
            enabled);
    }

    void setBluetoothExternally(bool enabled)
    {
        bluetoothPowered = enabled;
        sendPropertyChanged(
            QString::fromLatin1(BluezAdapterPath),
            QString::fromLatin1(BluezAdapterInterface),
            QStringLiteral("Powered"),
            enabled);
    }

    bool denyBluetooth = false;
    int activationCallCount() const { return activationCalls; }
    bool hiddenShapeWasValid() const { return hiddenShapeValid; }

private:
    InterfaceProperties profileSettings(bool userOwned) const
    {
        const QString user = currentUserName();
        QVariantMap connection{
            {QStringLiteral("id"), userOwned ? QStringLiteral("Mesh profile") :
                                              QStringLiteral("Admin profile")},
            {QStringLiteral("type"), QStringLiteral("802-11-wireless")},
            {QStringLiteral("permissions"),
             userOwned && !user.isEmpty()
                 ? QStringList{QStringLiteral("user:") + user + QLatin1Char(':')}
                 : QStringList{}},
        };
        return InterfaceProperties{
            {QStringLiteral("connection"), connection},
            {QStringLiteral("802-11-wireless"),
             QVariantMap{{QStringLiteral("ssid"),
                          userOwned ? QByteArray("Mesh") : QByteArray("Admin")}}},
            {QStringLiteral("802-11-wireless-security"),
             QVariantMap{{QStringLiteral("key-mgmt"), QStringLiteral("wpa-psk")}}},
        };
    }

    bool handleGetSettings(
        const QDBusMessage &message,
        const QDBusConnection &connection)
    {
        const bool userOwned = message.path() == QString::fromLatin1(UserProfilePath);
        if ((!userOwned && message.path() != QString::fromLatin1(AdminProfilePath))
            || (userOwned && userProfileDeleted)) {
            connection.send(message.createErrorReply(
                QDBusError::UnknownObject,
                QStringLiteral("missing profile")));
            return true;
        }
        connection.send(message.createReply(
            QVariantList{QVariant::fromValue(profileSettings(userOwned))}));
        return true;
    }

    bool handleDelete(const QDBusMessage &message, const QDBusConnection &connection)
    {
        if (message.path() != QString::fromLatin1(UserProfilePath)
            || userProfileDeleted) {
            connection.send(message.createErrorReply(
                QStringLiteral("org.freedesktop.NetworkManager.Settings.PermissionDenied"),
                QStringLiteral("profile is not user-owned")));
            return true;
        }
        userProfileDeleted = true;
        connection.send(message.createReply());
        return true;
    }

    void setActiveAccessPoint(const QString &path, uint state)
    {
        activeAccessPoint = path;
        deviceState = state;
        sendPropertyChanged(
            QString::fromLatin1(NetworkDevicePath),
            QString::fromLatin1(NetworkWirelessInterface),
            QStringLiteral("ActiveAccessPoint"),
            QVariant::fromValue(QDBusObjectPath(
                path.isEmpty() ? QStringLiteral("/") : path)));
        sendPropertyChanged(
            QString::fromLatin1(NetworkDevicePath),
            QString::fromLatin1(NetworkDeviceInterface),
            QStringLiteral("State"),
            state);
    }

    bool handleActivate(const QDBusMessage &message, const QDBusConnection &connection)
    {
        ++activationCalls;
        QString targetAccessPoint;
        if (message.member() == QStringLiteral("ActivateConnection")) {
            const QList<QVariant> arguments = message.arguments();
            if (arguments.size() != 3) {
                return false;
            }
            const QString profile = arguments.at(0).value<QDBusObjectPath>().path();
            targetAccessPoint = profile == QString::fromLatin1(UserProfilePath)
                ? QString::fromLatin1(MeshAccessPointPath)
                : QString::fromLatin1(AdminAccessPointPath);
            connection.send(message.createReply(QVariantList{QVariant::fromValue(
                QDBusObjectPath(QStringLiteral("/org/freedesktop/NetworkManager/ActiveConnection/1")))}));
        } else {
            const QList<QVariant> arguments = message.arguments();
            if (arguments.size() != 4) {
                return false;
            }
            const QVariant settingsValue = arguments.at(0);
            const InterfaceProperties settings = settingsValue.canConvert<QDBusArgument>()
                ? qdbus_cast<InterfaceProperties>(settingsValue.value<QDBusArgument>())
                : settingsValue.value<InterfaceProperties>();
            const QVariantMap wireless = settings.value(QStringLiteral("802-11-wireless"));
            const QVariantMap security = settings.value(
                QStringLiteral("802-11-wireless-security"));
            const QByteArray ssid = wireless.value(QStringLiteral("ssid")).toByteArray();
            const QString secret = security.value(QStringLiteral("psk")).toString();
            if (secret == QStringLiteral("wrong-password")) {
                connection.send(message.createErrorReply(
                    QStringLiteral("org.freedesktop.NetworkManager.AgentManager.NoSecrets"),
                    QStringLiteral("secret rejected")));
                return true;
            }
            if (ssid == QByteArray("Secure")
                && security.value(QStringLiteral("key-mgmt")).toString()
                    != QStringLiteral("sae")) {
                connection.send(message.createErrorReply(
                    QDBusError::InvalidArgs,
                    QStringLiteral("SAE key management required")));
                return true;
            }
            if (ssid == QByteArray("Hidden Fixture")) {
                hiddenVisible = true;
                targetAccessPoint = QString::fromLatin1(HiddenAccessPointPath);
                hiddenShapeValid = wireless.value(QStringLiteral("hidden")).toBool()
                    && wireless.value(QStringLiteral("mode")).toString()
                        == QStringLiteral("infrastructure")
                    && security.value(QStringLiteral("key-mgmt")).toString()
                        == QStringLiteral("wpa-psk")
                    && security.value(QStringLiteral("psk-flags")).toUInt() == 1U;
            } else {
                targetAccessPoint = arguments.at(2).value<QDBusObjectPath>().path();
            }
            connection.send(message.createReply(QVariantList{
                QVariant::fromValue(QDBusObjectPath(QString::fromLatin1(UserProfilePath))),
                QVariant::fromValue(QDBusObjectPath(
                    QStringLiteral("/org/freedesktop/NetworkManager/ActiveConnection/1"))),
                QVariantMap{},
            }));
        }
        QTimer::singleShot(
            20,
            this,
            [this, targetAccessPoint] { setActiveAccessPoint(targetAccessPoint, 100U); });
        return true;
    }

    bool handleGet(const QDBusMessage &message, const QDBusConnection &connection)
    {
        const QList<QVariant> arguments = message.arguments();
        if (arguments.size() != 2) {
            return false;
        }
        const QString interface = arguments.at(0).toString();
        const QString property = arguments.at(1).toString();
        QVariant value;
        if (message.path() == QString::fromLatin1(NetworkPath)
            && interface == QString::fromLatin1(NetworkInterface)) {
            if (property == QStringLiteral("WirelessEnabled")) {
                value = wifiEnabled;
            } else if (property == QStringLiteral("WirelessHardwareEnabled")
                       || property == QStringLiteral("NetworkingEnabled")) {
                value = true;
            }
        } else if (message.path() == QString::fromLatin1(NetworkDevicePath)
                   && interface == QString::fromLatin1(NetworkDeviceInterface)) {
            if (property == QStringLiteral("DeviceType")) {
                value = 2U;
            } else if (property == QStringLiteral("State")) {
                value = deviceState;
            }
        } else if (message.path() == QString::fromLatin1(NetworkDevicePath)
                   && interface == QString::fromLatin1(NetworkWirelessInterface)) {
            if (property == QStringLiteral("LastScan")) {
                value = lastScan;
            } else if (property == QStringLiteral("ActiveAccessPoint")) {
                value = QDBusObjectPath(
                    activeAccessPoint.isEmpty() ? QStringLiteral("/") : activeAccessPoint);
            }
        } else if (interface == QString::fromLatin1(NetworkAccessPointInterface)) {
            QByteArray ssid;
            int strength = 0;
            quint32 flags = 0;
            quint32 rsnFlags = 0;
            if (message.path() == QString::fromLatin1(MeshAccessPointPath)) {
                ssid = "Mesh";
                strength = 83;
                flags = 1;
                rsnFlags = 0x100;
            } else if (message.path() == QString::fromLatin1(MeshWeakAccessPointPath)) {
                ssid = "Mesh";
                strength = 42;
                flags = 1;
                rsnFlags = 0x100;
            } else if (message.path() == QString::fromLatin1(CafeAccessPointPath)) {
                ssid = "Cafe";
                strength = 61;
            } else if (message.path() == QString::fromLatin1(AdminAccessPointPath)) {
                ssid = "Admin";
                strength = 55;
                flags = 1;
                rsnFlags = 0x100;
            } else if (message.path() == QString::fromLatin1(SecureAccessPointPath)) {
                ssid = "Secure";
                strength = 72;
                flags = 1;
                rsnFlags = 0x400;
            } else if (message.path() == QString::fromLatin1(HiddenAccessPointPath)
                       && hiddenVisible) {
                ssid = "Hidden Fixture";
                strength = 70;
                flags = 1;
                rsnFlags = 0x100;
            }
            if (property == QStringLiteral("Ssid")) {
                value = ssid;
            } else if (property == QStringLiteral("Strength")) {
                value = strength;
            } else if (property == QStringLiteral("Flags")) {
                value = flags;
            } else if (property == QStringLiteral("WpaFlags")) {
                value = 0U;
            } else if (property == QStringLiteral("RsnFlags")) {
                value = rsnFlags;
            }
        } else if (message.path() == QString::fromLatin1(BluezAdapterPath)
                   && interface == QString::fromLatin1(BluezAdapterInterface)
                   && property == QStringLiteral("Powered")) {
            value = bluetoothPowered;
        }
        if (!value.isValid()) {
            connection.send(message.createErrorReply(
                QDBusError::UnknownProperty,
                QStringLiteral("unknown property")));
            return true;
        }
        connection.send(message.createReply(
            QVariantList{QVariant::fromValue(QDBusVariant(value))}));
        return true;
    }

    bool handleSet(const QDBusMessage &message, const QDBusConnection &connection)
    {
        const QList<QVariant> arguments = message.arguments();
        if (arguments.size() != 3) {
            return false;
        }
        const QString interface = arguments.at(0).toString();
        const QString property = arguments.at(1).toString();
        const QVariant value = arguments.at(2).value<QDBusVariant>().variant();
        if (message.path() == QString::fromLatin1(NetworkPath)
            && interface == QString::fromLatin1(NetworkInterface)
            && property == QStringLiteral("WirelessEnabled") && value.canConvert<bool>()) {
            wifiEnabled = value.toBool();
            connection.send(message.createReply());
            QTimer::singleShot(0, this, [this] { setWifiExternally(wifiEnabled); });
            return true;
        }
        if (message.path() == QString::fromLatin1(BluezAdapterPath)
            && interface == QString::fromLatin1(BluezAdapterInterface)
            && property == QStringLiteral("Powered") && value.canConvert<bool>()) {
            if (denyBluetooth) {
                connection.send(message.createErrorReply(
                    QStringLiteral("org.bluez.Error.NotAuthorized"),
                    QStringLiteral("test denial")));
                return true;
            }
            bluetoothPowered = value.toBool();
            connection.send(message.createReply());
            QTimer::singleShot(0, this, [this] { setBluetoothExternally(bluetoothPowered); });
            return true;
        }
        connection.send(message.createErrorReply(
            QDBusError::InvalidArgs,
            QStringLiteral("invalid property write")));
        return true;
    }

    void sendPropertyChanged(
        const QString &path,
        const QString &interface,
        const QString &property,
        const QVariant &value)
    {
        QDBusMessage signal = QDBusMessage::createSignal(
            path,
            QString::fromLatin1(PropertiesInterface),
            QStringLiteral("PropertiesChanged"));
        signal << interface << QVariantMap{{property, value}} << QStringList{};
        bus.send(signal);
    }

    QDBusConnection bus;
    bool wifiEnabled = true;
    QString activeAccessPoint;
    qint64 lastScan = -1;
    uint deviceState = 30;
    bool hiddenVisible = false;
    bool hiddenShapeValid = false;
    bool userProfileDeleted = false;
    bool bluetoothPowered = false;
    int activationCalls = 0;
};

class ConnectivityDbusTest final : public QObject {
    Q_OBJECT

public:
    ConnectivityDbusTest(QString helperPath, QObject *parent = nullptr)
        : QObject(parent)
        , helperPath(std::move(helperPath))
        , bus(QDBusConnection::sessionBus())
        , services(bus, this)
    {
    }

    void start()
    {
        if (!bus.isConnected()
            || !bus.registerVirtualObject(
                QStringLiteral("/"),
                &services,
                QDBusConnection::SubPath)
            || !bus.registerService(QString::fromLatin1(NetworkService))
            || !bus.registerService(QString::fromLatin1(BluezService))) {
            fail("could not register fake connectivity services");
            return;
        }

        connect(&helper, &QProcess::readyReadStandardOutput, this, &ConnectivityDbusTest::readOutput);
        connect(&helper, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) {
            fail("connectivity helper process failed");
        });
        connect(&helper, &QProcess::finished, this, [this](int exitCode, QProcess::ExitStatus status) {
            const QByteArray diagnostics = helper.readAllStandardError();
            if (stage != Stage::Cleanup || exitCode != 0 || status != QProcess::NormalExit
                || ownerReplacementCount != 5 || bridgeProcessId <= 0
                || transcript.contains("wrong-password")
                || transcript.contains("correct-password")
                || transcript.contains("queued-password")
                || transcript.contains("hidden-password")
                || diagnostics.contains("wrong-password")
                || diagnostics.contains("correct-password")
                || diagnostics.contains("queued-password")
                || diagnostics.contains("hidden-password")) {
                fail("connectivity helper did not finish with clean bounded state");
                return;
            }
            timeout.stop();
            qInfo("connectivity D-Bus tests passed");
            QCoreApplication::exit(0);
        });
        timeout.setSingleShot(true);
        timeout.setInterval(20000);
        connect(&timeout, &QTimer::timeout, this, [this] { fail("connectivity D-Bus test timed out"); });
        timeout.start();

        QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
        environment.insert(QStringLiteral("NAGI_CONNECTIVITY_BUS"), QStringLiteral("session"));
        helper.setProcessEnvironment(environment);
        helper.start(helperPath);
    }

private:
    enum class Stage {
        Initial,
        WifiPending,
        WifiConfirmed,
        WifiExternal,
        BluetoothDenied,
        BluetoothConfirmed,
        ScanPending,
        OpenConnecting,
        OpenDisconnecting,
        WrongSecret,
        ProtectedConnecting,
        ProtectedDisconnecting,
        Forgetting,
        HiddenConnecting,
        Unavailable,
        Replaced,
        Cleanup,
    };

    static bool adapterValue(const QJsonObject &state, const char *adapter, const char *property)
    {
        return state.value(QString::fromLatin1(adapter))
            .toObject()
            .value(QString::fromLatin1(property))
            .toBool();
    }

    static QString adapterFailure(const QJsonObject &state, const char *adapter)
    {
        return state.value(QString::fromLatin1(adapter))
            .toObject()
            .value(QStringLiteral("failure"))
            .toString();
    }

    static QString wifiOperation(const QJsonObject &state)
    {
        return state.value(QStringLiteral("wifi"))
            .toObject()
            .value(QStringLiteral("operation"))
            .toString();
    }

    static QString wifiOperationFailure(const QJsonObject &state)
    {
        return state.value(QStringLiteral("wifi"))
            .toObject()
            .value(QStringLiteral("operationFailure"))
            .toString();
    }

    static QString wifiOperationResult(const QJsonObject &state)
    {
        return state.value(QStringLiteral("wifi"))
            .toObject()
            .value(QStringLiteral("operationResult"))
            .toString();
    }

    static QJsonObject networkByName(const QJsonObject &state, const QString &name)
    {
        const QJsonArray networks = state.value(QStringLiteral("wifi"))
                                        .toObject()
                                        .value(QStringLiteral("networks"))
                                        .toArray();
        for (const QJsonValue &value : networks) {
            const QJsonObject network = value.toObject();
            if (network.value(QStringLiteral("ssid")).toString() == name) {
                return network;
            }
        }
        return {};
    }

    void readOutput()
    {
        const QByteArray chunk = helper.readAllStandardOutput();
        transcript.append(chunk);
        output.append(chunk);
        while (true) {
            const qsizetype newline = output.indexOf('\n');
            if (newline < 0) {
                return;
            }
            const QByteArray line = output.left(newline);
            output.remove(0, newline + 1);
            const QJsonObject message = QJsonDocument::fromJson(line).object();
            if (message.value(QStringLiteral("type")) == QStringLiteral("state")) {
                processState(message);
            }
        }
    }

    void processState(const QJsonObject &state)
    {
        const bool wifiAvailable = adapterValue(state, "wifi", "available");
        const bool wifiEnabled = adapterValue(state, "wifi", "enabled");
        const bool wifiPending = adapterValue(state, "wifi", "pending");
        const bool bluetoothAvailable = adapterValue(state, "bluetooth", "available");
        const bool bluetoothEnabled = adapterValue(state, "bluetooth", "enabled");
        const bool bluetoothPending = adapterValue(state, "bluetooth", "pending");

        if (bridgeProcessId == 0) {
            bridgeProcessId = helper.processId();
        }

        if (stage == Stage::Initial && wifiAvailable && wifiEnabled && bluetoothAvailable
            && !bluetoothEnabled) {
            stage = Stage::WifiPending;
            sendSet("wifi", false, 1);
            return;
        }
        if (stage == Stage::WifiPending && wifiPending && wifiEnabled) {
            sawWifiPending = true;
            return;
        }
        if (stage == Stage::WifiPending && sawWifiPending && wifiAvailable && !wifiPending
            && !wifiEnabled) {
            stage = Stage::WifiConfirmed;
            services.setWifiExternally(true);
            return;
        }
        if (stage == Stage::WifiConfirmed && wifiEnabled && !wifiPending) {
            stage = Stage::WifiExternal;
            services.denyBluetooth = true;
            sendSet("bluetooth", true, 2);
            return;
        }
        if (stage == Stage::WifiExternal && bluetoothPending && !bluetoothEnabled) {
            sawBluetoothPending = true;
            return;
        }
        if (stage == Stage::WifiExternal && sawBluetoothPending && !bluetoothPending
            && !bluetoothEnabled && adapterFailure(state, "bluetooth") == QStringLiteral("denied")) {
            stage = Stage::BluetoothDenied;
            services.denyBluetooth = false;
            sendSet("bluetooth", true, 3);
            return;
        }
        if (stage == Stage::BluetoothDenied && bluetoothPending && !bluetoothEnabled) {
            return;
        }
        if (stage == Stage::BluetoothDenied && bluetoothEnabled && !bluetoothPending
            && adapterFailure(state, "bluetooth") == QStringLiteral("none")) {
            stage = Stage::ScanPending;
            sendCommand(QJsonObject{
                {QStringLiteral("op"), QStringLiteral("wifi-interest")},
                {QStringLiteral("interested"), true},
                {QStringLiteral("requestId"), 4},
            });
            return;
        }
        if (stage == Stage::ScanPending && wifiOperation(state) == QStringLiteral("scanning")) {
            const QJsonObject mesh = networkByName(state, QStringLiteral("Mesh"));
            const QJsonObject cafe = networkByName(state, QStringLiteral("Cafe"));
            const QJsonObject admin = networkByName(state, QStringLiteral("Admin"));
            const QJsonObject secure = networkByName(state, QStringLiteral("Secure"));
            if (mesh.isEmpty() || cafe.isEmpty() || admin.isEmpty() || secure.isEmpty()
                || mesh.value(QStringLiteral("strength")).toInt() != 83
                || mesh.value(QStringLiteral("security")).toString()
                    != QStringLiteral("wpa-personal")
                || cafe.value(QStringLiteral("security")).toString() != QStringLiteral("open")
                || admin.value(QStringLiteral("forgetReason")).toString()
                    != QStringLiteral("admin-owned")) {
                fail("logical Wi-Fi networks were not safely grouped and normalized");
                return;
            }
            meshToken = mesh.value(QStringLiteral("token")).toInt();
            cafeToken = cafe.value(QStringLiteral("token")).toInt();
            secureToken = secure.value(QStringLiteral("token")).toInt();
            sawScanPending = true;
            return;
        }
        if (stage == Stage::ScanPending && sawScanPending
            && wifiOperationResult(state) == QStringLiteral("scan-complete")) {
            stage = Stage::OpenConnecting;
            sendWifiConnect(cafeToken, QString(), false, 5);
            return;
        }
        if (stage == Stage::OpenConnecting
            && wifiOperationResult(state) == QStringLiteral("connected")) {
            stage = Stage::OpenDisconnecting;
            sendCommand(QJsonObject{
                {QStringLiteral("op"), QStringLiteral("disconnect")},
                {QStringLiteral("requestId"), 6},
            });
            return;
        }
        if (stage == Stage::OpenDisconnecting
            && wifiOperationResult(state) == QStringLiteral("disconnected")) {
            stage = Stage::WrongSecret;
            sendWifiConnect(secureToken, QStringLiteral("wrong-password"), false, 7);
            return;
        }
        if (stage == Stage::WrongSecret
            && wifiOperationFailure(state) == QStringLiteral("wrong-secret")) {
            if (QJsonDocument(state).toJson(QJsonDocument::Compact).contains("wrong-password")) {
                fail("failed PSK remained in normalized state");
                return;
            }
            protectedActivationBaseline = services.activationCallCount();
            stage = Stage::ProtectedConnecting;
            sendWifiConnect(secureToken, QStringLiteral("correct-password"), true, 8);
            return;
        }
        if (stage == Stage::ProtectedConnecting && !protectedFloodSent
            && wifiOperation(state) == QStringLiteral("connecting")) {
            const QJsonObject secure = networkByName(state, QStringLiteral("Secure"));
            if (secure.value(QStringLiteral("connected")).toBool()
                || !state.value(QStringLiteral("wifi"))
                        .toObject()
                        .value(QStringLiteral("currentNetwork"))
                        .toString()
                        .isEmpty()) {
                fail("mutable connection changed backend-owned state before confirmation");
                return;
            }
            protectedFloodSent = true;
            for (int request = 0; request < 32; ++request) {
                sendWifiConnect(
                    secureToken,
                    QStringLiteral("queued-password"),
                    false,
                    1000 + request);
            }
            sendCommand(QJsonObject{
                {QStringLiteral("op"), QStringLiteral("wifi-interest")},
                {QStringLiteral("interested"), false},
                {QStringLiteral("requestId"), 1100},
            });
            return;
        }
        if (stage == Stage::ProtectedConnecting
            && wifiOperationResult(state) == QStringLiteral("connected")) {
            if (!protectedFloodSent
                || services.activationCallCount() != protectedActivationBaseline + 1
                || QJsonDocument(state).toJson(QJsonDocument::Compact)
                       .contains("correct-password")) {
                fail("connection flood queued work or retained submitted PSK");
                return;
            }
            stage = Stage::ProtectedDisconnecting;
            sendCommand(QJsonObject{
                {QStringLiteral("op"), QStringLiteral("wifi-interest")},
                {QStringLiteral("interested"), true},
                {QStringLiteral("requestId"), 1101},
            });
            sendCommand(QJsonObject{
                {QStringLiteral("op"), QStringLiteral("disconnect")},
                {QStringLiteral("requestId"), 1102},
            });
            return;
        }
        if (stage == Stage::ProtectedDisconnecting
            && wifiOperationResult(state) == QStringLiteral("disconnected")) {
            stage = Stage::Forgetting;
            sendCommand(QJsonObject{
                {QStringLiteral("op"), QStringLiteral("forget")},
                {QStringLiteral("token"), meshToken},
                {QStringLiteral("requestId"), 10},
            });
            return;
        }
        if (stage == Stage::Forgetting
            && wifiOperationResult(state) == QStringLiteral("forgotten")
            && !networkByName(state, QStringLiteral("Mesh"))
                    .value(QStringLiteral("saved"))
                    .toBool()) {
            stage = Stage::HiddenConnecting;
            sendCommand(QJsonObject{
                {QStringLiteral("op"), QStringLiteral("hidden-connect")},
                {QStringLiteral("ssid"), QStringLiteral("Hidden Fixture")},
                {QStringLiteral("security"), QStringLiteral("wpa-personal")},
                {QStringLiteral("secret"), QStringLiteral("hidden-password")},
                {QStringLiteral("remember"), true},
                {QStringLiteral("requestId"), 11},
            });
            return;
        }
        if (stage == Stage::HiddenConnecting
            && wifiOperationResult(state) == QStringLiteral("connected")
            && services.hiddenShapeWasValid()) {
            if (QJsonDocument(state).toJson(QJsonDocument::Compact).contains("hidden-password")) {
                fail("hidden-network PSK remained in normalized state");
                return;
            }
            preSoakWifiEnabled = wifiEnabled;
            preSoakBluetoothEnabled = bluetoothEnabled;
            sendCommand(QJsonObject{
                {QStringLiteral("op"), QStringLiteral("wifi-interest")},
                {QStringLiteral("interested"), false},
                {QStringLiteral("requestId"), 12},
            });
            if (helper.processId() != bridgeProcessId
                || !bus.unregisterService(QString::fromLatin1(NetworkService))
                || !bus.unregisterService(QString::fromLatin1(BluezService))) {
                fail("could not release fake connectivity owners");
                return;
            }
            stage = Stage::Unavailable;
            return;
        }
        if (stage == Stage::Unavailable && !wifiAvailable && !bluetoothAvailable) {
            const QJsonObject wifiState = state.value(QStringLiteral("wifi")).toObject();
            const QJsonObject bluetoothState =
                state.value(QStringLiteral("bluetooth")).toObject();
            if (wifiPending || bluetoothPending
                || wifiState.value(QStringLiteral("operation")).toString()
                    != QStringLiteral("idle")
                || bluetoothState.value(QStringLiteral("operation")).toString()
                    != QStringLiteral("idle")
                || !wifiState.value(QStringLiteral("networks")).toArray().isEmpty()
                || !bluetoothState.value(QStringLiteral("devices")).toArray().isEmpty()
                || !bluetoothState.value(QStringLiteral("pairingValue")).toString().isEmpty()) {
                fail("owner loss retained operation, model, or secret state");
                return;
            }
            const bool finalReplacement = ownerReplacementCount == 4;
            expectedWifiEnabled =
                finalReplacement ? preSoakWifiEnabled : ownerReplacementCount % 2 != 0;
            expectedBluetoothEnabled =
                finalReplacement ? preSoakBluetoothEnabled : ownerReplacementCount % 2 == 0;
            services.setWifiExternally(expectedWifiEnabled);
            services.setBluetoothExternally(expectedBluetoothEnabled);
            stage = Stage::Replaced;
            QTimer::singleShot(0, this, [this] {
                if (!bus.registerService(QString::fromLatin1(NetworkService))
                    || !bus.registerService(QString::fromLatin1(BluezService))) {
                    fail("could not restore fake connectivity owners");
                }
            });
            return;
        }
        if (stage == Stage::Replaced && wifiAvailable && bluetoothAvailable
            && wifiEnabled == expectedWifiEnabled
            && bluetoothEnabled == expectedBluetoothEnabled
            && wifiOperation(state) == QStringLiteral("idle")
            && state.value(QStringLiteral("bluetooth"))
                       .toObject()
                       .value(QStringLiteral("operation"))
                       .toString()
                == QStringLiteral("idle")) {
            if (helper.processId() != bridgeProcessId || wifiPending || bluetoothPending) {
                fail("owner replacement duplicated the helper or retained pending work");
                return;
            }
            ++ownerReplacementCount;
            if (ownerReplacementCount == 5) {
                stage = Stage::Cleanup;
                helper.closeWriteChannel();
                return;
            }
            stage = Stage::Unavailable;
            QTimer::singleShot(0, this, [this] {
                if (!bus.unregisterService(QString::fromLatin1(NetworkService))
                    || !bus.unregisterService(QString::fromLatin1(BluezService))) {
                    fail("could not repeat fake connectivity owner loss");
                }
            });
        }
    }

    void sendCommand(const QJsonObject &command)
    {
        helper.write(QJsonDocument(command).toJson(QJsonDocument::Compact) + '\n');
    }

    void sendWifiConnect(int token, const QString &secret, bool remember, int requestId)
    {
        sendCommand(QJsonObject{
            {QStringLiteral("op"), QStringLiteral("connect")},
            {QStringLiteral("token"), token},
            {QStringLiteral("secret"), secret},
            {QStringLiteral("remember"), remember},
            {QStringLiteral("requestId"), requestId},
        });
    }

    void sendSet(const char *adapter, bool enabled, int requestId)
    {
        const QJsonObject command{
            {QStringLiteral("op"), QStringLiteral("set")},
            {QStringLiteral("adapter"), QString::fromLatin1(adapter)},
            {QStringLiteral("enabled"), enabled},
            {QStringLiteral("requestId"), requestId},
        };
        sendCommand(command);
    }

    void fail(const char *message)
    {
        std::fprintf(stderr, "FAIL: %s (stage=%d)\n", message, static_cast<int>(stage));
        if (helper.state() != QProcess::NotRunning) {
            helper.kill();
            helper.waitForFinished(1000);
        }
        const QByteArray diagnostics = helper.readAllStandardError();
        if (!diagnostics.isEmpty()) {
            qCritical("helper stderr: %s", diagnostics.constData());
        }
        QCoreApplication::exit(1);
    }

    QString helperPath;
    QDBusConnection bus;
    FakeConnectivityServices services;
    QProcess helper;
    QTimer timeout;
    QByteArray output;
    QByteArray transcript;
    Stage stage = Stage::Initial;
    bool sawWifiPending = false;
    bool sawBluetoothPending = false;
    int meshToken = 0;
    int cafeToken = 0;
    int secureToken = 0;
    bool sawScanPending = false;
    bool protectedFloodSent = false;
    int protectedActivationBaseline = 0;
    int ownerReplacementCount = 0;
    qint64 bridgeProcessId = 0;
    bool preSoakWifiEnabled = false;
    bool preSoakBluetoothEnabled = false;
    bool expectedWifiEnabled = false;
    bool expectedBluetoothEnabled = false;
};

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    if (application.arguments().size() != 2) {
        qCritical("usage: connectivity-dbus-test HELPER");
        return 2;
    }
    qDBusRegisterMetaType<InterfaceProperties>();
    qDBusRegisterMetaType<ManagedObjectMap>();
    ConnectivityDbusTest test(application.arguments().at(1));
    QTimer::singleShot(0, &test, &ConnectivityDbusTest::start);
    return application.exec();
}

#include "connectivity_dbus_test.moc"

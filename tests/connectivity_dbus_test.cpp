#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusVariant>
#include <QDBusVirtualObject>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QProcess>
#include <QTimer>
#include <QVariantMap>

#include <utility>

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
constexpr auto BluezService = "org.bluez";
constexpr auto BluezAdapterPath = "/org/bluez/hci0";
constexpr auto BluezAdapterInterface = "org.bluez.Adapter1";
constexpr auto ObjectManagerInterface = "org.freedesktop.DBus.ObjectManager";
constexpr auto PropertiesInterface = "org.freedesktop.DBus.Properties";

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

private:
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
            } else if (property == QStringLiteral("WirelessHardwareEnabled")) {
                value = true;
            }
        } else if (message.path() == QString::fromLatin1(NetworkDevicePath)
                   && interface == QString::fromLatin1(NetworkDeviceInterface)
                   && property == QStringLiteral("DeviceType")) {
            value = 2U;
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
        bool value)
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
    bool bluetoothPowered = false;
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
            if (stage != Stage::Cleanup || exitCode != 0 || status != QProcess::NormalExit) {
                fail("connectivity helper exited unexpectedly");
                return;
            }
            timeout.stop();
            qInfo("connectivity D-Bus tests passed");
            QCoreApplication::exit(0);
        });
        timeout.setSingleShot(true);
        timeout.setInterval(10000);
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

    void readOutput()
    {
        output.append(helper.readAllStandardOutput());
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
            stage = Stage::BluetoothConfirmed;
            bus.unregisterService(QString::fromLatin1(NetworkService));
            bus.unregisterService(QString::fromLatin1(BluezService));
            return;
        }
        if (stage == Stage::BluetoothConfirmed && !wifiAvailable && !bluetoothAvailable) {
            stage = Stage::Unavailable;
            services.setWifiExternally(false);
            services.setBluetoothExternally(false);
            QTimer::singleShot(0, this, [this] {
                if (!bus.registerService(QString::fromLatin1(NetworkService))
                    || !bus.registerService(QString::fromLatin1(BluezService))) {
                    fail("could not restore fake connectivity owners");
                }
            });
            return;
        }
        if (stage == Stage::Unavailable && wifiAvailable && !wifiEnabled && bluetoothAvailable
            && !bluetoothEnabled) {
            stage = Stage::Replaced;
            QTimer::singleShot(0, this, [this] {
                stage = Stage::Cleanup;
                helper.closeWriteChannel();
            });
        }
    }

    void sendSet(const char *adapter, bool enabled, int requestId)
    {
        const QJsonObject command{
            {QStringLiteral("op"), QStringLiteral("set")},
            {QStringLiteral("adapter"), QString::fromLatin1(adapter)},
            {QStringLiteral("enabled"), enabled},
            {QStringLiteral("requestId"), requestId},
        };
        helper.write(QJsonDocument(command).toJson(QJsonDocument::Compact) + '\n');
    }

    void fail(const char *message)
    {
        qCritical("FAIL: %s", message);
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
    Stage stage = Stage::Initial;
    bool sawWifiPending = false;
    bool sawBluetoothPending = false;
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

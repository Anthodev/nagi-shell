#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusArgument>
#include <QDBusError>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusReply>
#include <QDBusVariant>
#include <QDBusVirtualObject>
#include <QElapsedTimer>
#include <QProcess>
#include <QTimer>
#include <QThread>
#include <QVariantMap>

#include <functional>
#include <cstdio>

using ProfileList = QList<QVariantMap>;
Q_DECLARE_METATYPE(ProfileList)

namespace {
constexpr auto GameService = "com.feralinteractive.GameMode";
constexpr auto GamePath = "/com/feralinteractive/GameMode";
constexpr auto GameInterface = "com.feralinteractive.GameMode";
constexpr auto ModernService = "org.freedesktop.UPower.PowerProfiles";
constexpr auto ModernPath = "/org/freedesktop/UPower/PowerProfiles";
constexpr auto ModernInterface = "org.freedesktop.UPower.PowerProfiles";
constexpr auto LegacyService = "net.hadess.PowerProfiles";
constexpr auto LegacyPath = "/net/hadess/PowerProfiles";
constexpr auto LegacyInterface = "net.hadess.PowerProfiles";
constexpr auto PropertiesInterface = "org.freedesktop.DBus.Properties";
constexpr auto ControlService = "org.nagishell.Test.GamingPowerControl";
constexpr auto ControlPath = "/org/nagishell/Test/GamingPowerControl";
constexpr auto ControlInterface = "org.nagishell.Test.GamingPowerControl";

class GamingPowerMock final : public QDBusVirtualObject {
public:
    explicit GamingPowerMock(QDBusConnection connection)
        : bus(std::move(connection))
    {
        profiles = {
            QVariantMap{{QStringLiteral("Profile"), QStringLiteral("power-saver")}},
            QVariantMap{{QStringLiteral("Profile"), QStringLiteral("balanced")}},
            QVariantMap{{QStringLiteral("Profile"), QStringLiteral("performance")}},
        };
    }

    QString introspect(const QString &path) const override
    {
        if (path == QString::fromLatin1(GamePath)) {
            return QStringLiteral(R"XML(<node>
  <interface name="com.feralinteractive.GameMode">
    <property name="ClientCount" type="i" access="read"/>
    <signal name="GameRegistered"><arg type="i"/><arg type="o"/></signal>
    <signal name="GameUnregistered"><arg type="i"/><arg type="o"/></signal>
  </interface>
</node>)XML");
        }
        if (path == QString::fromLatin1(ModernPath) || path == QString::fromLatin1(LegacyPath)) {
            const QString interface = path == QString::fromLatin1(ModernPath)
                ? QString::fromLatin1(ModernInterface)
                : QString::fromLatin1(LegacyInterface);
            return QStringLiteral(R"XML(<node>
  <interface name="%1">
    <property name="ActiveProfile" type="s" access="readwrite"/>
    <property name="Profiles" type="aa{sv}" access="read"/>
    <property name="PerformanceDegraded" type="s" access="read"/>
  </interface>
</node>)XML").arg(interface);
        }
        return QStringLiteral("<node/>");
    }

    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override
    {
        if (message.path() == QString::fromLatin1(ControlPath)
            && message.interface() == QString::fromLatin1(ControlInterface)) {
            const auto arguments = message.arguments();
            if (message.member() == QStringLiteral("RegisterGameFixture") && arguments.size() == 1) {
                registerGame(arguments.at(0).toInt());
                connection.send(message.createReply());
                return true;
            }
            if (message.member() == QStringLiteral("UnregisterGameFixture") && arguments.size() == 1) {
                unregisterGame(arguments.at(0).toInt());
                connection.send(message.createReply());
                return true;
            }
            if (message.member() == QStringLiteral("SwitchProfileFixture") && arguments.size() == 1) {
                switchProfile(arguments.at(0).toString());
                connection.send(message.createReply());
                return true;
            }
            if (message.member() == QStringLiteral("MutationCalls")) {
                connection.send(message.createReply(QVariantList{mutationCalls}));
                return true;
            }
            if (message.member() == QStringLiteral("Quit")) {
                connection.send(message.createReply());
                QTimer::singleShot(0, QCoreApplication::instance(), &QCoreApplication::quit);
                return true;
            }
        }
        if (message.interface() == QString::fromLatin1(PropertiesInterface)) {
            if (message.member() == QStringLiteral("Get")) {
                return handleGet(message, connection);
            }
            if (message.member() == QStringLiteral("GetAll")) {
                return handleGetAll(message, connection);
            }
            if (message.member() == QStringLiteral("Set")) {
                ++mutationCalls;
                connection.send(message.createErrorReply(
                    QDBusError::AccessDenied,
                    QStringLiteral("fixture is observation-only")));
                return true;
            }
        }
        if (message.member() == QStringLiteral("RegisterGame")
            || message.member() == QStringLiteral("UnregisterGame")
            || message.member() == QStringLiteral("HoldProfile")
            || message.member() == QStringLiteral("ReleaseProfile")) {
            ++mutationCalls;
            connection.send(message.createErrorReply(
                QDBusError::AccessDenied,
                QStringLiteral("fixture is observation-only")));
            return true;
        }
        return false;
    }

    void registerGame(qint32 pid)
    {
        clientCount = 1;
        QDBusMessage signal = QDBusMessage::createSignal(
            QString::fromLatin1(GamePath),
            QString::fromLatin1(GameInterface),
            QStringLiteral("GameRegistered"));
        signal << pid << QVariant::fromValue(QDBusObjectPath(
            QStringLiteral("/com/feralinteractive/GameMode/Games/%1").arg(pid)));
        bus.send(signal);
        sendPropertiesChanged(
            QString::fromLatin1(GamePath),
            QString::fromLatin1(GameInterface),
            QVariantMap{{QStringLiteral("ClientCount"), clientCount}});
    }

    void unregisterGame(qint32 pid)
    {
        clientCount = 0;
        QDBusMessage signal = QDBusMessage::createSignal(
            QString::fromLatin1(GamePath),
            QString::fromLatin1(GameInterface),
            QStringLiteral("GameUnregistered"));
        signal << pid << QVariant::fromValue(QDBusObjectPath(
            QStringLiteral("/com/feralinteractive/GameMode/Games/%1").arg(pid)));
        bus.send(signal);
        sendPropertiesChanged(
            QString::fromLatin1(GamePath),
            QString::fromLatin1(GameInterface),
            QVariantMap{{QStringLiteral("ClientCount"), clientCount}});
    }

    void switchProfile(const QString &profile)
    {
        activeProfile = profile;
        sendPropertiesChanged(
            QString::fromLatin1(ModernPath),
            QString::fromLatin1(ModernInterface),
            QVariantMap{{QStringLiteral("ActiveProfile"), activeProfile}});
        sendPropertiesChanged(
            QString::fromLatin1(LegacyPath),
            QString::fromLatin1(LegacyInterface),
            QVariantMap{{QStringLiteral("ActiveProfile"), activeProfile}});
    }

    int mutationCalls = 0;

private:
    QVariant property(const QString &interface, const QString &name) const
    {
        if (interface == QString::fromLatin1(GameInterface) && name == QStringLiteral("ClientCount")) {
            return clientCount;
        }
        if ((interface == QString::fromLatin1(ModernInterface)
             || interface == QString::fromLatin1(LegacyInterface))) {
            if (name == QStringLiteral("ActiveProfile")) {
                return activeProfile;
            }
            if (name == QStringLiteral("Profiles")) {
                return QVariant::fromValue(profiles);
            }
            if (name == QStringLiteral("PerformanceDegraded")) {
                return performanceDegraded;
            }
        }
        return {};
    }

    bool handleGet(const QDBusMessage &message, const QDBusConnection &connection)
    {
        const auto arguments = message.arguments();
        if (arguments.size() != 2) {
            return false;
        }
        const QVariant value = property(arguments.at(0).toString(), arguments.at(1).toString());
        if (!value.isValid()) {
            connection.send(message.createErrorReply(QDBusError::UnknownProperty, QStringLiteral("unknown property")));
            return true;
        }
        connection.send(message.createReply(QVariantList{QVariant::fromValue(QDBusVariant(value))}));
        return true;
    }

    bool handleGetAll(const QDBusMessage &message, const QDBusConnection &connection)
    {
        const auto arguments = message.arguments();
        if (arguments.size() != 1) {
            return false;
        }
        const QString interface = arguments.at(0).toString();
        QVariantMap values;
        if (interface == QString::fromLatin1(GameInterface)) {
            values.insert(QStringLiteral("ClientCount"), clientCount);
        } else if (interface == QString::fromLatin1(ModernInterface)
                   || interface == QString::fromLatin1(LegacyInterface)) {
            values.insert(QStringLiteral("ActiveProfile"), activeProfile);
            values.insert(QStringLiteral("Profiles"), QVariant::fromValue(profiles));
            values.insert(QStringLiteral("PerformanceDegraded"), performanceDegraded);
        } else {
            connection.send(message.createErrorReply(QDBusError::UnknownInterface, QStringLiteral("unknown interface")));
            return true;
        }
        connection.send(message.createReply(QVariantList{values}));
        return true;
    }

    void sendPropertiesChanged(const QString &path, const QString &interface, const QVariantMap &changed)
    {
        QDBusMessage signal = QDBusMessage::createSignal(
            path,
            QString::fromLatin1(PropertiesInterface),
            QStringLiteral("PropertiesChanged"));
        signal << interface << changed << QStringList{};
        bus.send(signal);
    }

    QDBusConnection bus;
    qint32 clientCount = 0;
    QString activeProfile = QStringLiteral("balanced");
    QString performanceDegraded;
    ProfileList profiles;
};

class Probe final : public QObject {
    Q_OBJECT

public:
    explicit Probe(QCoreApplication &application)
        : QObject(&application)
        , bus(QDBusConnection::sessionBus())
    {
    }

    int run()
    {
        if (!bus.isConnected()) {
            return fail("private session bus unavailable");
        }
        if (!verifyAbsence()) {
            return 1;
        }
        server.setProcessChannelMode(QProcess::ForwardedChannels);
        server.start(QCoreApplication::applicationFilePath(), {QStringLiteral("--mock")});
        if (!server.waitForStarted(2000)
            || !waitFor([this] { return mockNamesOwned(); })) {
            server.kill();
            server.waitForFinished();
            return fail("could not start private mock services");
        }
        if (!connectSignals()) {
            stopServer();
            return 1;
        }
        bool passed = verifyGameMode() && verifyPowerProfiles();
        const QDBusReply<qint32> mutationCount(controlCall(QStringLiteral("MutationCalls")));
        if (!mutationCount.isValid() || mutationCount.value() != 0) {
            fail("observer attempted a mutating D-Bus call");
            passed = false;
        }
        stopServer();
        return passed ? 0 : 1;
    }

private slots:
    void gameRegistered(qint32 pid, const QDBusObjectPath &path)
    {
        registeredPid = pid;
        registeredPath = path.path();
    }

    void gameUnregistered(qint32 pid, const QDBusObjectPath &path)
    {
        unregisteredPid = pid;
        unregisteredPath = path.path();
    }

    void propertiesChanged(const QString &interface, const QVariantMap &changed, const QStringList &)
    {
        if ((interface == QString::fromLatin1(ModernInterface)
             || interface == QString::fromLatin1(LegacyInterface))
            && changed.contains(QStringLiteral("ActiveProfile"))) {
            const QVariant value = changed.value(QStringLiteral("ActiveProfile"));
            if (value.metaType().id() == QMetaType::QString) {
                eventProfiles.insert(interface, value.toString());
            }
        }
    }

private:
    bool verifyAbsence()
    {
        QDBusInterface broker(
            QStringLiteral("org.freedesktop.DBus"),
            QStringLiteral("/org/freedesktop/DBus"),
            QStringLiteral("org.freedesktop.DBus"),
            bus);
        const QDBusReply<QStringList> names = broker.call(QStringLiteral("ListNames"));
        if (!names.isValid() || names.value().contains(QString::fromLatin1(GameService))) {
            fail("GameMode absence was not detected through ListNames");
            return false;
        }
        const QDBusMessage reply = broker.call(QStringLiteral("GetConnectionUnixProcessID"), QString::fromLatin1(GameService));
        if (reply.type() != QDBusMessage::ErrorMessage
            || reply.errorName() != QStringLiteral("org.freedesktop.DBus.Error.NameHasNoOwner")) {
            fail("GameMode missing-owner lookup did not fail gracefully");
            return false;
        }
        std::puts("PASS 3: unowned GameMode detected without activating or calling it");
        return true;
    }

    bool connectSignals()
    {
        const bool gameSignals = bus.connect(
            QString::fromLatin1(GameService), QString::fromLatin1(GamePath),
            QString::fromLatin1(GameInterface), QStringLiteral("GameRegistered"),
            this, SLOT(gameRegistered(qint32,QDBusObjectPath)))
            && bus.connect(
                QString::fromLatin1(GameService), QString::fromLatin1(GamePath),
                QString::fromLatin1(GameInterface), QStringLiteral("GameUnregistered"),
                this, SLOT(gameUnregistered(qint32,QDBusObjectPath)));
        const bool profileSignals = bus.connect(
            QString::fromLatin1(ModernService), QString::fromLatin1(ModernPath),
            QString::fromLatin1(PropertiesInterface), QStringLiteral("PropertiesChanged"),
            this, SLOT(propertiesChanged(QString,QVariantMap,QStringList)))
            && bus.connect(
                QString::fromLatin1(LegacyService), QString::fromLatin1(LegacyPath),
                QString::fromLatin1(PropertiesInterface), QStringLiteral("PropertiesChanged"),
                this, SLOT(propertiesChanged(QString,QVariantMap,QStringList)));
        if (!gameSignals || !profileSignals) {
            fail("could not subscribe before snapshots");
            return false;
        }
        return true;
    }

    bool mockNamesOwned()
    {
        QDBusInterface broker(
            QStringLiteral("org.freedesktop.DBus"),
            QStringLiteral("/org/freedesktop/DBus"),
            QStringLiteral("org.freedesktop.DBus"),
            bus);
        const QDBusReply<QStringList> names = broker.call(QStringLiteral("ListNames"));
        return names.isValid()
            && names.value().contains(QString::fromLatin1(GameService))
            && names.value().contains(QString::fromLatin1(ModernService))
            && names.value().contains(QString::fromLatin1(LegacyService))
            && names.value().contains(QString::fromLatin1(ControlService));
    }

    QDBusMessage controlCall(const QString &member, const QVariant &argument = {})
    {
        QDBusMessage call = QDBusMessage::createMethodCall(
            QString::fromLatin1(ControlService),
            QString::fromLatin1(ControlPath),
            QString::fromLatin1(ControlInterface),
            member);
        if (argument.isValid()) {
            call << argument;
        }
        return bus.call(call, QDBus::Block, 2000);
    }

    bool fixtureCall(const QString &member, const QVariant &argument)
    {
        const QDBusMessage reply = controlCall(member, argument);
        if (reply.type() == QDBusMessage::ReplyMessage) {
            return true;
        }
        fail(QStringLiteral("fixture control %1 failed: %2").arg(member, reply.errorMessage()));
        return false;
    }

    void stopServer()
    {
        controlCall(QStringLiteral("Quit"));
        if (!server.waitForFinished(2000)) {
            server.kill();
            server.waitForFinished();
        }
    }

    QVariant readProperty(const QString &service, const QString &path, const QString &interface, const QString &name)
    {
        QDBusInterface properties(service, path, QString::fromLatin1(PropertiesInterface), bus);
        const QDBusReply<QDBusVariant> reply = properties.call(
            QDBus::BlockWithGui,
            QStringLiteral("Get"),
            interface,
            name);
        if (!reply.isValid()) {
            fail(QStringLiteral("property read failed: %1.%2: %3")
                     .arg(interface, name, reply.error().message()));
            return {};
        }
        return reply.value().variant();
    }

    bool verifyGameMode()
    {
        const QVariant initial = readProperty(
            QString::fromLatin1(GameService), QString::fromLatin1(GamePath),
            QString::fromLatin1(GameInterface), QStringLiteral("ClientCount"));
        if (initial.metaType().id() != QMetaType::Int || initial.toInt() != 0) {
            fail("ClientCount was not D-Bus INT32 zero");
            return false;
        }
        std::puts("PASS 1: ClientCount property has signature i and returns the aggregate count");

        if (!fixtureCall(QStringLiteral("RegisterGameFixture"), 4242)) {
            return false;
        }
        if (!waitFor([this] { return registeredPid == 4242; })
            || registeredPath != QStringLiteral("/com/feralinteractive/GameMode/Games/4242")) {
            fail("GameRegistered(i,o) was not delivered after event-first subscription");
            return false;
        }
        const QVariant active = readProperty(
            QString::fromLatin1(GameService), QString::fromLatin1(GamePath),
            QString::fromLatin1(GameInterface), QStringLiteral("ClientCount"));
        if (!fixtureCall(QStringLiteral("UnregisterGameFixture"), 4242)) {
            return false;
        }
        if (active.metaType().id() != QMetaType::Int || active.toInt() != 1
            || !waitFor([this] { return unregisteredPid == 4242; })
            || unregisteredPath != QStringLiteral("/com/feralinteractive/GameMode/Games/4242")) {
            fail("GameRegistered/GameUnregistered payload or count transition was wrong");
            return false;
        }
        std::puts("PASS 2: GameRegistered and GameUnregistered signals delivered event-first as (i,o)");
        return true;
    }

    bool verifyPowerProfiles()
    {
        const QVariant initial = readProperty(
            QString::fromLatin1(ModernService), QString::fromLatin1(ModernPath),
            QString::fromLatin1(ModernInterface), QStringLiteral("ActiveProfile"));
        if (initial.metaType().id() != QMetaType::QString || initial.toString() != QStringLiteral("balanced")) {
            fail("modern ActiveProfile snapshot has the wrong type or value");
            return false;
        }
        if (!fixtureCall(QStringLiteral("SwitchProfileFixture"), QStringLiteral("performance"))) {
            return false;
        }
        if (!waitFor([this] {
                return eventProfiles.value(QString::fromLatin1(ModernInterface)) == QStringLiteral("performance")
                    && eventProfiles.value(QString::fromLatin1(LegacyInterface)) == QStringLiteral("performance");
            })) {
            fail("ActiveProfile PropertiesChanged was not delivered on both event-first subscriptions");
            return false;
        }
        std::puts("PASS 4: ActiveProfile read and PropertiesChanged switch event are event-first");

        const QVariant profileValue = readProperty(
            QString::fromLatin1(ModernService), QString::fromLatin1(ModernPath),
            QString::fromLatin1(ModernInterface), QStringLiteral("Profiles"));
        const QVariant degraded = readProperty(
            QString::fromLatin1(ModernService), QString::fromLatin1(ModernPath),
            QString::fromLatin1(ModernInterface), QStringLiteral("PerformanceDegraded"));
        const ProfileList advertised = qdbus_cast<ProfileList>(profileValue);
        bool shapeOkay = advertised.size() == 3;
        for (const QVariantMap &profile : advertised) {
            shapeOkay = shapeOkay
                && profile.value(QStringLiteral("Profile")).metaType().id() == QMetaType::QString;
        }
        if (!shapeOkay || degraded.metaType().id() != QMetaType::QString || !degraded.toString().isEmpty()) {
            fail("Profiles aa{sv} or PerformanceDegraded s shape was wrong");
            return false;
        }
        std::puts("PASS 5: Profiles is aa{sv} and PerformanceDegraded is s");

        const QVariant legacy = readProperty(
            QString::fromLatin1(LegacyService), QString::fromLatin1(LegacyPath),
            QString::fromLatin1(LegacyInterface), QStringLiteral("ActiveProfile"));
        const QVariant modern = readProperty(
            QString::fromLatin1(ModernService), QString::fromLatin1(ModernPath),
            QString::fromLatin1(ModernInterface), QStringLiteral("ActiveProfile"));
        if (legacy.toString() != QStringLiteral("performance")
            || modern.toString() != QStringLiteral("performance")) {
            fail("modern and legacy name/path/interface triples do not agree");
            return false;
        }
        std::puts("PASS 6: modern and legacy PowerProfiles name/path/interface triples both answer");
        return true;
    }

    bool waitFor(const std::function<bool()> &predicate)
    {
        QElapsedTimer timer;
        timer.start();
        while (!predicate() && timer.elapsed() < 2000) {
            QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
            QThread::msleep(5);
        }
        return predicate();
    }

    int fail(const QString &message)
    {
        std::fprintf(stderr, "gaming-power-contract: %s\n", qPrintable(message));
        return 1;
    }

    int fail(const char *message)
    {
        return fail(QString::fromUtf8(message));
    }

    QDBusConnection bus;
    QProcess server;
    qint32 registeredPid = -1;
    qint32 unregisteredPid = -1;
    QString registeredPath;
    QString unregisteredPath;
    QMap<QString, QString> eventProfiles;
};
} // namespace

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    qDBusRegisterMetaType<ProfileList>();
    if (app.arguments().contains(QStringLiteral("--mock"))) {
        QDBusConnection bus = QDBusConnection::sessionBus();
        GamingPowerMock mock(bus);
        if (!bus.isConnected()
            || !bus.registerVirtualObject(QStringLiteral("/"), &mock, QDBusConnection::SubPath)
            || !bus.registerService(QString::fromLatin1(GameService))
            || !bus.registerService(QString::fromLatin1(ModernService))
            || !bus.registerService(QString::fromLatin1(LegacyService))
            || !bus.registerService(QString::fromLatin1(ControlService))) {
            std::fputs("gaming-power-contract: mock registration failed\n", stderr);
            return 1;
        }
        return app.exec();
    }
    Probe probe(app);
    return probe.run();
}

#include "gaming_power_probe.moc"

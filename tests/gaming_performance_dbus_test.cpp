#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusVariant>
#include <QDBusVirtualObject>
#include <QElapsedTimer>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QProcessEnvironment>
#include <QThread>
#include <QVariantMap>

#include <cstdio>
#include <functional>
#include <stdexcept>

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

void require(bool condition, const char *message)
{
    if (!condition) {
        throw std::runtime_error(message);
    }
}

class GamingServices final : public QDBusVirtualObject {
public:
    explicit GamingServices(QDBusConnection connection)
        : bus(std::move(connection))
    {
    }

    QString introspect(const QString &) const override
    {
        return QStringLiteral("<node/>");
    }

    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override
    {
        if (message.interface() == QString::fromLatin1(PropertiesInterface)
            && message.member() == QStringLiteral("Get")) {
            const auto arguments = message.arguments();
            if (arguments.size() != 2) {
                return false;
            }
            const QVariant value = property(arguments.at(0).toString(), arguments.at(1).toString());
            if (!value.isValid()) {
                connection.send(message.createErrorReply(QDBusError::UnknownProperty,
                                                         QStringLiteral("unknown property")));
            } else {
                connection.send(message.createReply(
                    QVariantList{QVariant::fromValue(QDBusVariant(value))}));
            }
            return true;
        }

        mutationCalls += 1;
        connection.send(message.createErrorReply(QDBusError::AccessDenied,
                                                 QStringLiteral("fixture is read-only")));
        return true;
    }

    void registerGame(qint32 pid)
    {
        gameClientCount += 1;
        sendGameSignal(QStringLiteral("GameRegistered"), pid);
    }

    void unregisterGame(qint32 pid)
    {
        gameClientCount = qMax(0, gameClientCount - 1);
        sendGameSignal(QStringLiteral("GameUnregistered"), pid);
    }

    void switchProfile(const QString &profile)
    {
        activeProfile = profile;
        sendProfileSignal(QString::fromLatin1(ModernPath),
                          QString::fromLatin1(ModernInterface));
        sendProfileSignal(QString::fromLatin1(LegacyPath),
                          QString::fromLatin1(LegacyInterface));
    }

    int gameClientCount = 0;
    int mutationCalls = 0;
    QString activeProfile = QStringLiteral("balanced");

private:
    QVariant property(const QString &interface, const QString &name) const
    {
        if (interface == QString::fromLatin1(GameInterface)
            && name == QStringLiteral("ClientCount")) {
            return gameClientCount;
        }
        if ((interface == QString::fromLatin1(ModernInterface)
             || interface == QString::fromLatin1(LegacyInterface))
            && name == QStringLiteral("ActiveProfile")) {
            return activeProfile;
        }
        return {};
    }

    void sendGameSignal(const QString &member, qint32 pid)
    {
        QDBusMessage signal = QDBusMessage::createSignal(
            QString::fromLatin1(GamePath), QString::fromLatin1(GameInterface), member);
        signal << pid << QVariant::fromValue(QDBusObjectPath(
            QStringLiteral("/com/feralinteractive/GameMode/Games/%1").arg(pid)));
        bus.send(signal);
    }

    void sendProfileSignal(const QString &path, const QString &interface)
    {
        QDBusMessage signal = QDBusMessage::createSignal(
            path, QString::fromLatin1(PropertiesInterface), QStringLiteral("PropertiesChanged"));
        signal << interface << QVariantMap{{QStringLiteral("ActiveProfile"), activeProfile}}
               << QStringList{};
        bus.send(signal);
    }

    QDBusConnection bus;
};

class Fixture final : public QObject {
    Q_OBJECT

public:
    Fixture(QString helperPath, QObject *parent = nullptr)
        : QObject(parent)
        , bus(QDBusConnection::sessionBus())
        , services(bus)
        , helperPath(std::move(helperPath))
    {
        connect(&helper, &QProcess::readyReadStandardOutput, this, &Fixture::readOutput);
    }

    int run()
    {
        try {
            setupServices();
            startHelper();
            verifyInitialState();
            verifyIndependentAndOverlappingSources();
            verifyAliasAndOwnerLoss();
            verifyPrivacyAndPassivity();
            stopHelper();
            std::puts("gaming-performance-dbus: all lifecycle checks passed");
            return 0;
        } catch (const std::exception &error) {
            std::fprintf(stderr, "gaming-performance-dbus: %s\n", error.what());
            stopHelper();
            return 1;
        }
    }

private:
    void setupServices()
    {
        require(bus.isConnected(), "private session bus is unavailable");
        require(bus.registerVirtualObject(QStringLiteral("/"), &services,
                                          QDBusConnection::SubPath),
                "could not register fixture object");
        require(bus.registerService(QString::fromLatin1(GameService)),
                "could not own GameMode fixture name");
        require(bus.registerService(QString::fromLatin1(ModernService)),
                "could not own modern Power Profiles fixture name");
        require(bus.registerService(QString::fromLatin1(LegacyService)),
                "could not own legacy Power Profiles fixture name");
    }

    void startHelper()
    {
        QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
        const QString address = environment.value(QStringLiteral("DBUS_SESSION_BUS_ADDRESS"));
        require(!address.isEmpty(), "private bus address is unavailable");
        environment.insert(QStringLiteral("DBUS_SYSTEM_BUS_ADDRESS"), address);
        helper.setProcessEnvironment(environment);
        helper.setProgram(helperPath);
        helper.start();
        require(helper.waitForStarted(2000), "observer helper did not start");
        require(waitFor([this] { return ready && !states.isEmpty(); }),
                "observer helper did not publish initial state");
    }

    void verifyInitialState()
    {
        const QJsonObject state = states.constLast();
        require(state.value(QStringLiteral("available")).toBool()
                    && state.value(QStringLiteral("gameModeAvailable")).toBool()
                    && state.value(QStringLiteral("powerProfilesAvailable")).toBool()
                    && state.value(QStringLiteral("sourceCount")).toInt() == 0,
                "initial aggregate state is wrong");
        std::puts("PASS 1 initial passive aggregate snapshot");
    }

    void verifyIndependentAndOverlappingSources()
    {
        services.registerGame(4242);
        require(waitForState(QStringLiteral("registered"), 1),
                "first GameMode registration was not observed");
        services.registerGame(5252);
        require(waitForState(QStringLiteral("registered"), 2),
                "second GameMode registration was not observed individually");
        services.switchProfile(QStringLiteral("performance"));
        require(waitForState(QStringLiteral("profile"), 3),
                "performance profile was not counted once alongside clients");

        const int beforeDuplicate = states.size();
        services.switchProfile(QStringLiteral("performance"));
        spin(80);
        require(states.size() == beforeDuplicate,
                "duplicate performance profile produced a second source event");

        services.unregisterGame(4242);
        require(waitForState(QStringLiteral("unregistered"), 2),
                "intermediate client removal did not preserve profile source");
        services.switchProfile(QStringLiteral("balanced"));
        require(waitForState(QStringLiteral("profile"), 1),
                "profile removal did not preserve remaining client");
        services.unregisterGame(5252);
        require(waitForState(QStringLiteral("unregistered"), 0),
                "final client removal did not clear aggregate state");
        std::puts("PASS 2 independent, overlapping, and duplicate sources normalize exactly");
    }

    void verifyAliasAndOwnerLoss()
    {
        services.switchProfile(QStringLiteral("performance"));
        require(waitForState(QStringLiteral("profile"), 1),
                "profile activation before owner-loss test failed");

        const int beforeAliasLoss = states.size();
        require(bus.unregisterService(QString::fromLatin1(ModernService)),
                "could not remove modern alias");
        require(waitFor([this, beforeAliasLoss] {
                    return states.size() > beforeAliasLoss
                        && states.constLast().value(QStringLiteral("sourceCount")).toInt() == 1
                        && states.constLast()
                               .value(QStringLiteral("powerProfilesAvailable"))
                               .toBool();
                }),
                "legacy alias did not retain the one effective profile source");
        for (int index = beforeAliasLoss; index < states.size(); ++index) {
            require(states.at(index).value(QStringLiteral("event")).toString()
                        != QStringLiteral("sourceUnavailable"),
                    "alias fallback was misreported as backend loss");
        }

        require(bus.unregisterService(QString::fromLatin1(LegacyService)),
                "could not remove final Power Profiles owner");
        require(waitForState(QStringLiteral("sourceUnavailable"), 0),
                "active profile owner loss was reported as normal inactivity");

        require(bus.registerService(QString::fromLatin1(ModernService)),
                "could not restore Power Profiles owner");
        require(waitFor([this] {
                    const QJsonObject state = states.constLast();
                    return state.value(QStringLiteral("powerProfilesAvailable")).toBool()
                        && state.value(QStringLiteral("sourceCount")).toInt() == 1;
                }),
                "restored profile owner did not republish its active snapshot");

        services.registerGame(6262);
        require(waitForState(QStringLiteral("registered"), 2),
                "GameMode source before owner-loss test failed");
        require(bus.unregisterService(QString::fromLatin1(GameService)),
                "could not remove GameMode owner");
        require(waitForState(QStringLiteral("sourceUnavailable"), 1),
                "active GameMode owner loss did not retain the profile source");
        std::puts("PASS 3 alias selection, appearance, and active owner loss are truthful");
    }

    void verifyPrivacyAndPassivity()
    {
        require(services.mutationCalls == 0, "observer attempted a mutating D-Bus call");
        for (const QByteArray &line : std::as_const(rawLines)) {
            require(!line.contains("4242") && !line.contains("5252") && !line.contains("6262")
                        && !line.contains("/Games/") && !line.contains("feralinteractive")
                        && !line.contains("PowerProfiles"),
                    "helper output leaked backend or client identity");
        }
        require(helper.state() == QProcess::Running,
                "helper exited during passive lifecycle observation");
        std::puts("PASS 4 helper output is bounded, identity-free, and observation-only");
    }

    bool waitForState(const QString &event, int sourceCount)
    {
        const int start = states.size();
        return waitFor([this, start, event, sourceCount] {
            for (int index = start; index < states.size(); ++index) {
                const QJsonObject state = states.at(index);
                if (state.value(QStringLiteral("event")).toString() == event
                    && state.value(QStringLiteral("sourceCount")).toInt() == sourceCount) {
                    return true;
                }
            }
            return false;
        });
    }

    static void spin(int milliseconds)
    {
        QElapsedTimer timer;
        timer.start();
        while (timer.elapsed() < milliseconds) {
            QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
            QThread::msleep(1);
        }
    }

    static bool waitFor(const std::function<bool()> &predicate, int timeoutMs = 2000)
    {
        QElapsedTimer timer;
        timer.start();
        while (timer.elapsed() < timeoutMs) {
            QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
            if (predicate()) {
                return true;
            }
            QThread::msleep(1);
        }
        return predicate();
    }

    void readOutput()
    {
        outputBuffer += helper.readAllStandardOutput();
        while (true) {
            const qsizetype newline = outputBuffer.indexOf('\n');
            if (newline < 0) {
                return;
            }
            const QByteArray line = outputBuffer.left(newline);
            outputBuffer.remove(0, newline + 1);
            if (line.isEmpty()) {
                continue;
            }
            rawLines.push_back(line);
            const QJsonDocument document = QJsonDocument::fromJson(line);
            if (!document.isObject()) {
                continue;
            }
            const QJsonObject object = document.object();
            if (object.value(QStringLiteral("type")) == QStringLiteral("ready")) {
                ready = true;
            } else if (object.value(QStringLiteral("type")) == QStringLiteral("state")) {
                states.push_back(object);
            }
        }
    }

    void stopHelper()
    {
        if (helper.state() == QProcess::NotRunning) {
            return;
        }
        helper.terminate();
        if (!helper.waitForFinished(1000)) {
            helper.kill();
            helper.waitForFinished(1000);
        }
    }

    QDBusConnection bus;
    GamingServices services;
    QString helperPath;
    QProcess helper;
    QByteArray outputBuffer;
    QList<QByteArray> rawLines;
    QList<QJsonObject> states;
    bool ready = false;
};
} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    try {
        require(application.arguments().size() == 2, "helper path argument is required");
        Fixture fixture(application.arguments().at(1));
        return fixture.run();
    } catch (const std::exception &error) {
        std::fprintf(stderr, "gaming-performance-dbus: %s\n", error.what());
        return 1;
    }
}

#include "gaming_performance_dbus_test.moc"

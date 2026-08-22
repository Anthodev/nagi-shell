#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusVirtualObject>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QProcess>
#include <QTimer>

#include <cstdlib>
#include <cstdio>
#include <utility>

namespace {

constexpr auto ScreenSaverService = "org.freedesktop.ScreenSaver";
constexpr auto PowerService = "org.kde.Solid.PowerManagement";
constexpr auto LogoutService = "org.kde.LogoutPrompt";

class FakeSessionServices final : public QDBusVirtualObject {
public:
    enum class Mode {
        Success,
        Denied,
        Backend,
        Timeout,
    };

    explicit FakeSessionServices(QObject *parent = nullptr)
        : QDBusVirtualObject(parent)
    {
    }

    QString introspect(const QString &) const override
    {
        return {};
    }

    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override
    {
        const QString member = message.member();
        if (member != QStringLiteral("Lock") && member != QStringLiteral("suspendToRam")
            && member != QStringLiteral("promptLogout")
            && member != QStringLiteral("promptReboot")
            && member != QStringLiteral("promptShutDown")) {
            return false;
        }

        calls[member] += 1;
        if (mode == Mode::Denied) {
            connection.send(message.createErrorReply(
                QStringLiteral("org.freedesktop.DBus.Error.AccessDenied"),
                QStringLiteral("test denial payload must remain private")));
            return true;
        }
        if (mode == Mode::Backend) {
            connection.send(message.createErrorReply(
                QStringLiteral("org.kde.Session.Error.Failed"),
                QStringLiteral("test backend payload must remain private")));
            return true;
        }
        if (mode == Mode::Timeout) {
            connection.send(message.createErrorReply(
                QStringLiteral("org.freedesktop.DBus.Error.NoReply"),
                QStringLiteral("test timeout payload must remain private")));
            return true;
        }

        connection.send(message.createReply());
        return true;
    }

    int callCount(const QString &member) const
    {
        return calls.value(member);
    }


    Mode mode = Mode::Success;

private:
    QMap<QString, int> calls;
};

class SessionDbusTest final : public QObject {
    Q_OBJECT

public:
    SessionDbusTest(QString helperPath, QObject *parent = nullptr)
        : QObject(parent)
        , helperPath(std::move(helperPath))
        , bus(QDBusConnection::sessionBus())
        , services(this)
    {
    }

    void start()
    {
        if (!bus.isConnected()
            || !bus.registerVirtualObject(QStringLiteral("/"), &services, QDBusConnection::SubPath)
            || !bus.registerService(QString::fromLatin1(ScreenSaverService))
            || !bus.registerService(QString::fromLatin1(PowerService))
            || !bus.registerService(QString::fromLatin1(LogoutService))) {
            fail("could not register fake session services");
            return;
        }

        connect(&helper, &QProcess::readyReadStandardOutput, this, &SessionDbusTest::readOutput);
        connect(&helper, &QProcess::readyReadStandardError, this, [this] {
            helperDiagnostics.append(helper.readAllStandardError());
        });
        connect(&helper, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) {
            fail("session helper process failed");
        });
        connect(&helper, &QProcess::finished, this, [this](int exitCode, QProcess::ExitStatus status) {
            if (stage != Stage::Cleanup || exitCode != 0 || status != QProcess::NormalExit) {
                fail("session helper exited unexpectedly");
                return;
            }
            timeout.stop();
            qInfo("session D-Bus tests passed");
            QCoreApplication::exit(0);
        });

        timeout.setSingleShot(true);
        timeout.setInterval(10000);
        connect(&timeout, &QTimer::timeout, this, [this] { fail("session D-Bus test timed out"); });
        timeout.start();
        helper.start(helperPath);
    }

private:
    enum class Stage {
        Initial,
        Lock,
        Suspend,
        Logout,
        Reboot,
        PowerOff,
        Denied,
        Backend,
        Timeout,
        Busy,
        HeldAccepted,
        Unavailable,
        Cleanup,
    };

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
            processMessage(message);
        }
    }

    void processMessage(const QJsonObject &message)
    {
        if (stage == Stage::Initial) {
            require(message.value(QStringLiteral("type")) == QStringLiteral("ready"),
                    "helper publishes readiness first");
            stage = Stage::Lock;
            sendAction(1, "lock");
            return;
        }
        require(message.value(QStringLiteral("type")) == QStringLiteral("result"),
                "helper publishes only bounded result messages after readiness");

        const int requestId = message.value(QStringLiteral("requestId")).toInt();
        const QString action = message.value(QStringLiteral("action")).toString();
        const QString outcome = message.value(QStringLiteral("outcome")).toString();
        if (stage == Stage::Lock) {
            expect(requestId, action, outcome, 1, "lock", "accepted");
            require(services.callCount(QStringLiteral("Lock")) == 1,
                    "lock invokes the screen saver exactly once");
            stage = Stage::Suspend;
            sendAction(2, "suspend");
        } else if (stage == Stage::Suspend) {
            expect(requestId, action, outcome, 2, "suspend", "accepted");
            require(services.callCount(QStringLiteral("suspendToRam")) == 1,
                    "suspend invokes PowerDevil exactly once");
            stage = Stage::Logout;
            sendAction(3, "logout");
        } else if (stage == Stage::Logout) {
            expect(requestId, action, outcome, 3, "logout", "accepted");
            stage = Stage::Reboot;
            sendAction(4, "reboot");
        } else if (stage == Stage::Reboot) {
            expect(requestId, action, outcome, 4, "reboot", "accepted");
            stage = Stage::PowerOff;
            sendAction(5, "powerOff");
        } else if (stage == Stage::PowerOff) {
            expect(requestId, action, outcome, 5, "powerOff", "accepted");
            require(services.callCount(QStringLiteral("promptLogout")) == 1
                        && services.callCount(QStringLiteral("promptReboot")) == 1
                        && services.callCount(QStringLiteral("promptShutDown")) == 1,
                    "destructive actions use their matching KDE confirmation prompts");
            services.mode = FakeSessionServices::Mode::Denied;
            stage = Stage::Denied;
            sendAction(6, "lock");
        } else if (stage == Stage::Denied) {
            expect(requestId, action, outcome, 6, "lock", "denied");
            require(!QString::fromUtf8(output).contains(QStringLiteral("test denial")),
                    "D-Bus denial payload is not exposed");
            services.mode = FakeSessionServices::Mode::Backend;
            stage = Stage::Backend;
            sendAction(7, "suspend");
        } else if (stage == Stage::Backend) {
            expect(requestId, action, outcome, 7, "suspend", "backend");
            services.mode = FakeSessionServices::Mode::Timeout;
            stage = Stage::Timeout;
            sendAction(8, "suspend");
        } else if (stage == Stage::Timeout) {
            expect(requestId, action, outcome, 8, "suspend", "timeout");
            services.mode = FakeSessionServices::Mode::Success;
            stage = Stage::Busy;
            sendAction(9, "logout");
            sendAction(10, "reboot");
        } else if (stage == Stage::Busy) {
            expect(requestId, action, outcome, 10, "reboot", "busy");
            require(services.callCount(QStringLiteral("promptReboot")) == 1,
                    "a repeated activation never reaches D-Bus while another action is pending");
            stage = Stage::HeldAccepted;
        } else if (stage == Stage::HeldAccepted) {
            expect(requestId, action, outcome, 9, "logout", "accepted");
            services.mode = FakeSessionServices::Mode::Success;
            require(bus.unregisterService(QString::fromLatin1(ScreenSaverService)),
                    "screen saver fixture unregisters");
            stage = Stage::Unavailable;
            sendAction(11, "lock");
        } else if (stage == Stage::Unavailable) {
            expect(requestId, action, outcome, 11, "lock", "unavailable");
            require(!QString::fromUtf8(helperDiagnostics).contains(QStringLiteral("payload")),
                    "helper diagnostics reveal no backend payload");
            stage = Stage::Cleanup;
            sendShutdown();
        }
    }

    void expect(int actualRequestId,
                const QString &actualAction,
                const QString &actualOutcome,
                int requestId,
                const char *action,
                const char *outcome)
    {
        if (actualRequestId != requestId || actualAction != QString::fromLatin1(action)
                || actualOutcome != QString::fromLatin1(outcome)) {
            const QByteArray actualActionBytes = actualAction.toUtf8();
            const QByteArray actualOutcomeBytes = actualOutcome.toUtf8();
            std::fprintf(stderr,
                         "expected result %d/%s/%s, received %d/%s/%s\n",
                         requestId,
                         action,
                         outcome,
                         actualRequestId,
                         actualActionBytes.constData(),
                         actualOutcomeBytes.constData());
            fail("result preserves request identity and normalized outcome");
        }
    }

    void sendAction(int requestId, const char *action)
    {
        const QJsonObject command{
            {QStringLiteral("op"), QStringLiteral("action")},
            {QStringLiteral("requestId"), requestId},
            {QStringLiteral("action"), QString::fromLatin1(action)},
        };
        helper.write(QJsonDocument(command).toJson(QJsonDocument::Compact) + '\n');
    }

    void sendShutdown()
    {
        helper.write("{\"op\":\"shutdown\"}\n");
        helper.closeWriteChannel();
    }

    void require(bool condition, const char *message)
    {
        if (!condition) {
            fail(message);
        }
    }

    [[noreturn]] void fail(const char *message)
    {
        std::fprintf(stderr, "session D-Bus test failed: %s\n", message);
        std::fflush(stderr);
        if (helper.state() != QProcess::NotRunning) {
            helper.kill();
            helper.waitForFinished();
        }
        std::exit(1);
    }

    QString helperPath;
    QDBusConnection bus;
    FakeSessionServices services;
    QProcess helper;
    QTimer timeout;
    QByteArray output;
    QByteArray helperDiagnostics;
    Stage stage = Stage::Initial;
};

} // namespace
int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    if (argc != 2) {
        qCritical("usage: session-dbus-test <helper>");
        return 2;
    }

    SessionDbusTest test(QString::fromLocal8Bit(argv[1]));
    QTimer::singleShot(0, &test, [&test] { test.start(); });
    return application.exec();
}

#include "session_dbus_test.moc"

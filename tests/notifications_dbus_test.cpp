#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QProcess>
#include <QProcessEnvironment>
#include <QTimer>

#include <cstdio>
#include <cstdlib>

namespace {

constexpr auto Service = "org.freedesktop.Notifications";
constexpr auto Path = "/org/freedesktop/Notifications";
constexpr auto Interface = "org.freedesktop.Notifications";

class NotificationDbusTest final : public QObject {
    Q_OBJECT

public:
    NotificationDbusTest(QString quickshell, QString testDirectory, QObject *parent = nullptr)
        : QObject(parent)
        , quickshell(std::move(quickshell))
        , testDirectory(std::move(testDirectory))
    {
        process.setProcessChannelMode(QProcess::MergedChannels);
        connect(&process, &QProcess::readyReadStandardOutput, this,
                &NotificationDbusTest::readOutput);
        connect(&process, &QProcess::finished, this, &NotificationDbusTest::processFinished);
        timeout.setSingleShot(true);
        timeout.setInterval(20'000);
        connect(&timeout, &QTimer::timeout, this, [this] { fail("integration-timeout"); });
    }

    void start()
    {
        timeout.start();
        phase = Phase::Ready;
        startQuickshell(QStringLiteral("normal"));
    }

private:
    enum class Phase {
        Ready,
        Received,
        Replaced,
        Transient,
        Readmitted,
        Closed,
        Unknown,
        UnknownClosed,
        ExpiryAdmitted,
        Expired,
        Dismissed,
        ReloadReady,
        Reloaded,
        StopForRestart,
        Restarted,
        StopForOwnership,
        OwnershipFailed,
        OwnershipRecovered,
        StopComplete,
    };

    [[noreturn]] void fail(const char *category)
    {
        std::fprintf(stderr, "notification D-Bus test failed: %s (phase=%d)\n", category,
                     static_cast<int>(phase));
        if (process.state() != QProcess::NotRunning) {
            process.kill();
        }
        std::exit(1);
    }

    void startQuickshell(const QString &mode)
    {
        QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
        environment.insert(QStringLiteral("NAGI_NOTIFICATION_TEST_MODE"), mode);
        environment.insert(QStringLiteral("NAGI_SKIP_DEFAULT_CONFIG_CREATION"),
                           QStringLiteral("1"));
        const QString xdgRoot = testDirectory + QStringLiteral("/xdg");
        QDir().mkpath(xdgRoot + QStringLiteral("/home"));
        environment.insert(QStringLiteral("HOME"), xdgRoot + QStringLiteral("/home"));
        environment.insert(QStringLiteral("XDG_CONFIG_HOME"), xdgRoot + QStringLiteral("/config"));
        environment.insert(QStringLiteral("XDG_STATE_HOME"), xdgRoot + QStringLiteral("/state"));
        environment.insert(QStringLiteral("XDG_CACHE_HOME"), xdgRoot + QStringLiteral("/cache"));
        environment.insert(QStringLiteral("XDG_DATA_HOME"), xdgRoot + QStringLiteral("/data"));
        process.setProcessEnvironment(environment);
        process.setWorkingDirectory(testDirectory);
        process.start(quickshell,
                      {QStringLiteral("-p"), testDirectory, QStringLiteral("--no-duplicate")});
        if (!process.waitForStarted(3000)) {
            fail("quickshell-start");
        }
    }

    uint notify(uint replacesId, const QString &summary, const QVariantMap &hints,
                int expireTimeout)
    {
        QDBusInterface notifications(QString::fromLatin1(Service), QString::fromLatin1(Path),
                                     QString::fromLatin1(Interface),
                                     QDBusConnection::sessionBus());
        const QDBusReply<uint> reply = notifications.call(
            QStringLiteral("Notify"), QStringLiteral("App\u0001Name"), replacesId,
            QStringLiteral("example-app"), summary,
            QStringLiteral("<b>Bold</b> <a href=\"file:///secret\">link</a>"
                           "<img src=\"https://invalid\" alt=\"ALT\"/>"),
            QStringList {}, hints, expireTimeout);
        if (!reply.isValid() || reply.value() == 0) {
            fail("notify-call");
        }
        return reply.value();
    }

    void close(uint id)
    {
        QDBusInterface notifications(QString::fromLatin1(Service), QString::fromLatin1(Path),
                                     QString::fromLatin1(Interface),
                                     QDBusConnection::sessionBus());
        const QDBusMessage reply = notifications.call(QStringLiteral("CloseNotification"), id);
        if (reply.type() == QDBusMessage::ErrorMessage) {
            fail("close-call");
        }
    }

    void verifyCapabilities()
    {
        QDBusInterface notifications(QString::fromLatin1(Service), QString::fromLatin1(Path),
                                     QString::fromLatin1(Interface),
                                     QDBusConnection::sessionBus());
        const QDBusReply<QStringList> reply = notifications.call(
            QStringLiteral("GetCapabilities"));
        if (!reply.isValid() || reply.value() != QStringList {QStringLiteral("body")}) {
            fail("capabilities");
        }
    }

    void verifyNoPersistentFiles()
    {
        const QString root = testDirectory + QStringLiteral("/xdg");
        const QStringList directories {
            root + QStringLiteral("/config"),
            root + QStringLiteral("/state"),
            root + QStringLiteral("/cache"),
            root + QStringLiteral("/data"),
        };
        for (const QString &directory : directories) {
            QDirIterator entries(directory,
                                 QDir::Files | QDir::Hidden | QDir::NoDotAndDotDot,
                                 QDirIterator::Subdirectories);
            if (entries.hasNext()) {
                fail("persistent-file-created");
            }
        }
    }

    QVariantMap hints(bool transient = false) const
    {
        QVariantMap values {
            {QStringLiteral("urgency"), QVariant::fromValue(uchar(1))},
            {QStringLiteral("desktop-entry"), QStringLiteral("org.example.App")},
        };
        if (transient) {
            values.insert(QStringLiteral("transient"), true);
        }
        return values;
    }

    void readOutput()
    {
        outputBuffer.append(process.readAllStandardOutput());
        qsizetype newline = -1;
        while ((newline = outputBuffer.indexOf('\n')) >= 0) {
            const QByteArray line = outputBuffer.first(newline);
            outputBuffer.remove(0, newline + 1);
            handleLine(line);
        }
    }

    void handleLine(const QByteArray &line)
    {
        if (line.contains("notification-")) {
            std::fprintf(stderr, "%s\n", line.constData());
        }
        if (phase == Phase::Ready && line.contains("notification-harness-ready")) {
            verifyCapabilities();
            currentId = notify(0, QStringLiteral("Initial"), hints(), 0);
            phase = Phase::Received;
        } else if (phase == Phase::Received
                   && line.contains("notification-harness-received")) {
            const uint replacement = notify(currentId, QStringLiteral("Replacement"), hints(), 0);
            if (replacement != currentId) {
                fail("known-replacement-id");
            }
            phase = Phase::Replaced;
        } else if (phase == Phase::Replaced
                   && line.contains("notification-harness-replaced")) {
            notify(currentId, QStringLiteral("Transient"), hints(true), 0);
            phase = Phase::Transient;
        } else if (phase == Phase::Transient
                   && line.contains("notification-harness-transient")) {
            notify(currentId, QStringLiteral("Readmitted"), hints(), 0);
            phase = Phase::Readmitted;
        } else if (phase == Phase::Readmitted
                   && line.contains("notification-harness-readmitted")) {
            close(currentId);
            phase = Phase::Closed;
        } else if (phase == Phase::Closed && line.contains("notification-harness-closed")) {
            unknownId = notify(999'999, QStringLiteral("Unknown"), hints(), 0);
            if (unknownId == 999'999) {
                fail("unknown-replacement-was-aliased");
            }
            phase = Phase::Unknown;
        } else if (phase == Phase::Unknown && line.contains("notification-harness-unknown")) {
            close(unknownId);
            phase = Phase::UnknownClosed;
        } else if (phase == Phase::UnknownClosed
                   && line.contains("notification-harness-unknown-closed")) {
            notify(0, QStringLiteral("Expiry"), hints(), 30);
            phase = Phase::ExpiryAdmitted;
        } else if (phase == Phase::ExpiryAdmitted
                   && line.contains("notification-harness-expiry-admitted")) {
            phase = Phase::Expired;
        } else if (phase == Phase::Expired && line.contains("notification-harness-expired")) {
            notify(0, QStringLiteral("Dismiss"), hints(), 0);
            phase = Phase::Dismissed;
        } else if (phase == Phase::Dismissed
                   && line.contains("notification-harness-dismissed")) {
            currentId = notify(0, QStringLiteral("Reload"), hints(), 0);
            phase = Phase::ReloadReady;
        } else if (phase == Phase::ReloadReady
                   && line.contains("notification-harness-reload-ready")) {
            QFile shell(testDirectory + QStringLiteral("/shell.qml"));
            if (!shell.open(QIODevice::Append)
                || shell.write("\n// notification reload trigger\n") < 0) {
                fail("reload-trigger");
            }
            shell.close();
            phase = Phase::Reloaded;
        } else if (phase == Phase::Reloaded
                   && line.contains("notification-harness-reloaded")) {
            phase = Phase::StopForRestart;
            process.terminate();
        } else if (phase == Phase::Restarted
                   && line.contains("notification-harness-restarted")) {
            phase = Phase::StopForOwnership;
            process.terminate();
        } else if (phase == Phase::OwnershipFailed
                   && line.contains("notification-harness-ownership-failed")) {
            if (!QDBusConnection::sessionBus().unregisterService(QString::fromLatin1(Service))) {
                fail("ownership-release");
            }
            phase = Phase::OwnershipRecovered;
        } else if (phase == Phase::OwnershipRecovered
                   && line.contains("notification-harness-ownership-recovered")) {
            phase = Phase::StopComplete;
            process.terminate();
        } else if (line.contains("notification-harness-failure:")) {
            fail("qml-assertion");
        }
    }

    void processFinished(int exitCode, QProcess::ExitStatus status)
    {
        outputBuffer.clear();
        if (phase == Phase::StopForRestart) {
            phase = Phase::Restarted;
            startQuickshell(QStringLiteral("restart"));
            return;
        }
        if (phase == Phase::StopForOwnership) {
            if (!QDBusConnection::sessionBus().registerService(QString::fromLatin1(Service))) {
                fail("ownership-fixture");
            }
            phase = Phase::OwnershipFailed;
            startQuickshell(QStringLiteral("ownership"));
            return;
        }
        if (phase == Phase::StopComplete) {
            timeout.stop();
            verifyNoPersistentFiles();
            qInfo("notification D-Bus integration tests passed");
            QCoreApplication::exit(0);
            return;
        }
        if (status != QProcess::NormalExit || exitCode != 0) {
            fail("quickshell-crash");
        }
        fail("unexpected-quickshell-exit");
    }

    QString quickshell;
    QString testDirectory;
    QProcess process;
    QTimer timeout;
    QByteArray outputBuffer;
    Phase phase = Phase::Ready;
    uint currentId = 0;
    uint unknownId = 0;
};

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    if (application.arguments().size() != 3) {
        std::fprintf(stderr, "usage: notification-dbus-test <qs> <test-directory>\n");
        return 2;
    }
    NotificationDbusTest test(application.arguments().at(1), application.arguments().at(2));
    QTimer::singleShot(0, &test, [&test] { test.start(); });
    return application.exec();
}

#include "notifications_dbus_test.moc"

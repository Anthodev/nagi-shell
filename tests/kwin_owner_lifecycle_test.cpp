#include <QCoreApplication>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMetaType>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QTimer>

struct FakeDesktop {
    quint32 position;
    QString id;
    QString name;
};

Q_DECLARE_METATYPE(FakeDesktop)

QDBusArgument &operator<<(QDBusArgument &argument, const FakeDesktop &desktop)
{
    argument.beginStructure();
    argument << desktop.position << desktop.id << desktop.name;
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, FakeDesktop &desktop)
{
    argument.beginStructure();
    argument >> desktop.position >> desktop.id >> desktop.name;
    argument.endStructure();
    return argument;
}

class FakeVirtualDesktopManager final : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.KWin.VirtualDesktopManager")
    Q_PROPERTY(QList<FakeDesktop> desktops READ desktops)
    Q_PROPERTY(QString current READ current)

public:
    QList<FakeDesktop> desktops() const
    {
        return {{0, desktopId, QStringLiteral("Test Desktop")}};
    }

    QString current() const
    {
        return desktopId;
    }

    void replaceDesktop()
    {
        desktopId = QStringLiteral("new-owner-desktop");
    }

private:
    QString desktopId = QStringLiteral("old-owner-desktop");
};

class OwnerLifecycleTest final : public QObject {
    Q_OBJECT

public:
    OwnerLifecycleTest(QString helperPath, QObject *parent = nullptr)
        : QObject(parent)
        , helperPath(std::move(helperPath))
        , bus(QDBusConnection::sessionBus())
    {
    }

    void start()
    {
        if (!bus.isConnected()
            || !bus.registerObject(
                QStringLiteral("/VirtualDesktopManager"),
                &manager,
                QDBusConnection::ExportAllProperties)
            || !bus.registerService(QStringLiteral("org.kde.KWin"))) {
            fail("could not register fake KWin service");
            return;
        }

        connect(&helper, &QProcess::readyReadStandardOutput, this, &OwnerLifecycleTest::readSnapshots);
        connect(
            &helper,
            &QProcess::errorOccurred,
            this,
            [this](QProcess::ProcessError) { fail("helper process failed"); });
        timeout.setSingleShot(true);
        timeout.setInterval(5000);
        connect(&timeout, &QTimer::timeout, this, [this] { fail("owner lifecycle timed out"); });
        timeout.start();
        helper.start(helperPath);
    }

private:
    enum class Stage {
        OldOwner,
        Unavailable,
        NewOwner,
    };

    void readSnapshots()
    {
        bufferedOutput.append(helper.readAllStandardOutput());
        while (true) {
            const qsizetype newline = bufferedOutput.indexOf('\n');
            if (newline < 0) {
                return;
            }

            const QByteArray line = bufferedOutput.left(newline);
            bufferedOutput.remove(0, newline + 1);
            processSnapshot(QJsonDocument::fromJson(line).object());
        }
    }

    void processSnapshot(const QJsonObject &snapshot)
    {
        const bool available = snapshot.value(QStringLiteral("available")).toBool();
        const QString currentId = snapshot.value(QStringLiteral("currentId")).toString();
        if (stage == Stage::OldOwner && available
            && currentId == QStringLiteral("old-owner-desktop")) {
            stage = Stage::Unavailable;
            bus.unregisterService(QStringLiteral("org.kde.KWin"));
            return;
        }

        if (stage == Stage::Unavailable && !available) {
            stage = Stage::NewOwner;
            manager.replaceDesktop();
            QTimer::singleShot(0, this, [this] {
                if (!bus.registerService(QStringLiteral("org.kde.KWin"))) {
                    fail("could not replace fake KWin owner");
                }
            });
            return;
        }

        if (stage == Stage::NewOwner && available
            && currentId == QStringLiteral("new-owner-desktop")) {
            timeout.stop();
            helper.terminate();
            helper.waitForFinished(1000);
            qInfo("owner lifecycle tests passed");
            QCoreApplication::exit(0);
        }
    }

    void fail(const char *message)
    {
        qCritical("FAIL: %s", message);
        timeout.stop();
        if (helper.state() != QProcess::NotRunning) {
            helper.kill();
            helper.waitForFinished(1000);
        }
        QCoreApplication::exit(1);
    }

    QString helperPath;
    QDBusConnection bus;
    FakeVirtualDesktopManager manager;
    QProcess helper;
    QTimer timeout;
    QByteArray bufferedOutput;
    Stage stage = Stage::OldOwner;
};

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    if (application.arguments().size() != 2) {
        qCritical("usage: kwin-owner-lifecycle-test HELPER");
        return 2;
    }

    qDBusRegisterMetaType<FakeDesktop>();
    qDBusRegisterMetaType<QList<FakeDesktop>>();
    OwnerLifecycleTest test(application.arguments().at(1));
    QTimer::singleShot(0, &test, &OwnerLifecycleTest::start);
    return application.exec();
}

#include "kwin_owner_lifecycle_test.moc"

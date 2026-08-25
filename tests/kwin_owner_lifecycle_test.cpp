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
        if (replacementOwner) {
            return {{0, QStringLiteral("new-owner-desktop"), QStringLiteral("New Desktop")}};
        }
        return {
            {0, QStringLiteral("desktop-one"), QStringLiteral("Desktop 1")},
            {1, QStringLiteral("desktop-two"), QStringLiteral("Desktop 2")},
        };
    }

    QString current() const
    {
        return currentId;
    }

    void setCurrent(const QString &id)
    {
        currentId = id;
        emit currentChanged(id);
    }

    void replaceDesktop()
    {
        replacementOwner = true;
        currentId = QStringLiteral("new-owner-desktop");
    }

signals:
    void currentChanged(const QString &id);

private:
    QString currentId = QStringLiteral("desktop-one");
    bool replacementOwner = false;
};

class FakeKWinRoot final : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.KWin")

public:
    void setActiveOutputName(const QString &name)
    {
        outputName = name;
    }

public slots:
    QString activeOutputName() const
    {
        return outputName;
    }

private:
    QString outputName = QStringLiteral("output-one");
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
                QDBusConnection::ExportAllProperties | QDBusConnection::ExportAllSignals)
            || !bus.registerObject(
                QStringLiteral("/KWin"),
                &root,
                QDBusConnection::ExportAllSlots)
            || !bus.registerService(QStringLiteral("org.kde.KWin"))) {
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
        Initial,
        OutputChange,
        DesktopChange,
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
        const bool showTransient = snapshot.value(QStringLiteral("showTransient")).toBool();
        if (stage == Stage::Initial && available && currentId == QStringLiteral("desktop-one")) {
            if (showTransient) {
                fail("initial snapshot requested transient feedback");
                return;
            }
            stage = Stage::OutputChange;
            root.setActiveOutputName(QStringLiteral("output-two"));
            manager.setCurrent(QStringLiteral("desktop-two"));
            return;
        }

        if (stage == Stage::OutputChange && available
            && currentId == QStringLiteral("desktop-two")) {
            if (showTransient) {
                fail("active-output change requested workspace feedback");
                return;
            }
            stage = Stage::DesktopChange;
            manager.setCurrent(QStringLiteral("desktop-one"));
            return;
        }

        if (stage == Stage::DesktopChange && available
            && currentId == QStringLiteral("desktop-one")) {
            if (!showTransient) {
                fail("same-output desktop switch suppressed workspace feedback");
                return;
            }
            stage = Stage::Unavailable;
            bus.unregisterService(QStringLiteral("org.kde.KWin"));
            return;
        }

        if (stage == Stage::Unavailable && !available) {
            if (showTransient) {
                fail("unavailable snapshot requested transient feedback");
                return;
            }
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
            if (showTransient) {
                fail("replacement owner replayed workspace feedback");
                return;
            }
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
    FakeKWinRoot root;
    QProcess helper;
    QTimer timeout;
    QByteArray bufferedOutput;
    Stage stage = Stage::Initial;
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

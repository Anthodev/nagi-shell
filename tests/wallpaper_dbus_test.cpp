#include "analyzer.h"

#include <QGuiApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusVirtualObject>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QTemporaryDir>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <utility>
#include <condition_variable>
#include <mutex>

namespace {

constexpr auto PlasmaService = "org.kde.plasmashell";
constexpr auto PlasmaPath = "/PlasmaShell";
constexpr auto PlasmaInterface = "org.kde.PlasmaShell";
constexpr auto ActivityService = "org.kde.ActivityManager";
constexpr auto ActivityPath = "/ActivityManager/Activities";
constexpr auto ActivityInterface = "org.kde.ActivityManager.Activities";

class FakeServices final : public QDBusVirtualObject {
public:
    explicit FakeServices(QObject *parent = nullptr)
        : QDBusVirtualObject(parent)
    {
    }
    QString introspect(const QString &) const override
    {
        return {};
    }

    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override
    {
        if (message.path() != QString::fromLatin1(PlasmaPath)
            || message.interface() != QString::fromLatin1(PlasmaInterface)
            || message.member() != QStringLiteral("wallpaper")) {
            return false;
        }
        wallpaperCalls += 1;
        connection.send(message.createReply(QVariant::fromValue(wallpaper)));
        return true;
    }

    QVariantMap wallpaper;
    int wallpaperCalls = 0;
};

class WallpaperDbusTest final : public QObject {
    Q_OBJECT

public:
    WallpaperDbusTest(QString helperPath, QString fixtureDirectory, QObject *parent = nullptr)
        : QObject(parent)
        , helperPath(std::move(helperPath))
        , fixtures(std::move(fixtureDirectory))
        , bus(QDBusConnection::sessionBus())
        , services(this)
    {
    }

    void start()
    {
        if (!temporary.isValid() || !bus.isConnected()
            || !bus.registerVirtualObject(QStringLiteral("/"), &services, QDBusConnection::SubPath)
            || !bus.registerService(QString::fromLatin1(ActivityService))
            || !bus.registerService(QString::fromLatin1(PlasmaService))) {
            fail("could not register mock services");
        }

        const QString source = fixtures + QStringLiteral("/colorful.png");
        unreadablePath = temporary.filePath(QStringLiteral("unreadable.png"));
        raceSourcePath = temporary.filePath(QStringLiteral("race-source.png"));
        if (!QFile::copy(source, unreadablePath)
            || !QFile::setPermissions(unreadablePath, QFileDevice::Permissions{})
            || !QFile::copy(source, raceSourcePath)) {
            fail("could not prepare wallpaper fixtures");
        }
        // Root in the Fedora CI container can still read a mode-000 file.
        restrictedFixtureReadable = QFileInfo(unreadablePath).isReadable();
        setWallpaper(QStringLiteral("org.kde.image"), QUrl::fromLocalFile(raceSourcePath).toString());

        timeout.setSingleShot(true);
        timeout.setInterval(15000);
        connect(&timeout, &QTimer::timeout, this, [this] { fail("wallpaper D-Bus test timed out"); });
        timeout.start();
        startInvalidationRace();
    }

private:
    enum class Stage {
        Initial,
        IgnoreNonPrimary,
        UnsupportedPlugin,
        Activity,
        Missing,
        Unreadable,
        OwnerLoss,
        Reappearance,
        Cleanup,
    };

    void startInvalidationRace()
    {
        nagi::wallpaper::testing::setObserverHooks(
            [](const QString &, const std::function<bool()> &) {
                return nagi::wallpaper::FingerprintResult{
                    {true, {}, QStringLiteral("Verified")},
                    QByteArrayLiteral("blocked-source"),
                };
            },
            [this](
                const QString &,
                const QByteArray &digest,
                const std::function<bool()> &) {
                extractionCount += 1;
                if (firstExtraction.exchange(false)) {
                    QMetaObject::invokeMethod(
                        this,
                        [this] {
                            require(QFile::remove(raceSourcePath),
                                    "source deletion succeeds while palette extraction is blocked");
                        },
                        Qt::QueuedConnection);
                    std::unique_lock lock(raceMutex);
                    raceBarrier.wait(lock, [this] { return releaseOldAnalysis; });
                }
                return nagi::wallpaper::SourceResult{
                    {true, QStringLiteral("#D94A38"), QStringLiteral("Ready")},
                    digest,
                };
            },
            [this](const QString &status, quint64 generation) {
                if (generation == 1) {
                    require(status == QStringLiteral("Missing"),
                            "terminal source failure publishes while the old analysis is blocked");
                    raceSnapshots += 1;
                    {
                        std::lock_guard lock(raceMutex);
                        releaseOldAnalysis = true;
                    }
                    raceBarrier.notify_one();
                    return;
                }
                require(generation == 2 && status == QStringLiteral("Ready"),
                        "the retained directory watch detects source recreation");
                raceSnapshots += 1;
                QTimer::singleShot(0, this, [this] {
                    require(raceSnapshots == 2,
                            "the released old analysis cannot overwrite terminal failure with Ready");
                    require(extractionCount == 2,
                            "only the original and recreated sources perform palette extraction");
                    delete raceObserver;
                    raceObserver = nullptr;
                    nagi::wallpaper::testing::resetObserverHooks();
                    setWallpaper(
                        QStringLiteral("org.kde.image"),
                        QUrl::fromLocalFile(fixtures + QStringLiteral("/colorful.png")).toString());
                    services.wallpaperCalls = 0;
                    startHelperProcess();
                });
            },
            [this] {
                if (recreationScheduled) {
                    return;
                }
                recreationScheduled = true;
                QTimer::singleShot(0, this, [this] {
                    require(raceSnapshots == 1 && extractionCount == 1,
                            "old analysis completion leaves the terminal failure unchanged");
                    require(
                        QFile::copy(
                            fixtures + QStringLiteral("/colorful.png"),
                            raceSourcePath),
                        "blocked source is recreated at the watched path");
                });
            });
        raceObserver = nagi::wallpaper::testing::createObserver();
    }

    void startHelperProcess()
    {
        connect(&helper, &QProcess::readyReadStandardOutput, this, &WallpaperDbusTest::readOutput);
        connect(&helper, &QProcess::readyReadStandardError, this, [this] {
            diagnostics.append(helper.readAllStandardError());
        });
        connect(&helper, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) {
            if (stage != Stage::Cleanup) {
                fail("wallpaper helper process failed");
            }
        });
        connect(&helper, &QProcess::finished, this, [this](int, QProcess::ExitStatus) {
            if (stage != Stage::Cleanup) {
                fail("wallpaper helper exited unexpectedly");
            }
            timeout.stop();
            std::puts("wallpaper D-Bus tests passed");
            QCoreApplication::exit(0);
        });

        QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
        environment.insert(QStringLiteral("QT_QPA_PLATFORM"), QStringLiteral("offscreen"));
        helper.setProcessEnvironment(environment);
        helper.start(helperPath);
    }

    void setWallpaper(const QString &plugin, const QString &image)
    {
        services.wallpaper = {
            {QStringLiteral("wallpaperPlugin"), plugin},
            {QStringLiteral("Image"), image},
        };
    }

    void emitWallpaperChanged(uint screen)
    {
        QDBusMessage signal = QDBusMessage::createSignal(
            QString::fromLatin1(PlasmaPath),
            QString::fromLatin1(PlasmaInterface),
            QStringLiteral("wallpaperChanged"));
        signal << screen;
        require(bus.send(signal), "wallpaper signal sends");
    }

    void emitActivityChanged()
    {
        QDBusMessage signal = QDBusMessage::createSignal(
            QString::fromLatin1(ActivityPath),
            QString::fromLatin1(ActivityInterface),
            QStringLiteral("CurrentActivityChanged"));
        signal << QStringLiteral("activity-test");
        require(bus.send(signal), "activity signal sends");
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
            process(QJsonDocument::fromJson(line).object());
        }
    }

    void process(const QJsonObject &snapshot)
    {
        require(!snapshot.isEmpty(), "helper emits JSON objects only");
        require(snapshot.value(QStringLiteral("generation")).toInteger() == expectedGeneration,
                "generation advances exactly once per effective change");
        if (stage == Stage::Initial) {
            expect(snapshot, true, "Ready", "#D94A38");
            require(services.wallpaperCalls == 1, "startup queries wallpaper once");
            stage = Stage::IgnoreNonPrimary;
            emitWallpaperChanged(1);
            QTimer::singleShot(150, this, [this] {
                require(stage == Stage::IgnoreNonPrimary, "non-primary wallpaper signal is ignored");
                setWallpaper(QStringLiteral("org.kde.color"), {});
                stage = Stage::UnsupportedPlugin;
                expectedGeneration += 1;
                emitWallpaperChanged(0);
            });
        } else if (stage == Stage::UnsupportedPlugin) {
            expect(snapshot, false, "UnsupportedPlugin", "");
            setWallpaper(QStringLiteral("org.kde.image"), QStringLiteral("https://example.invalid/a.png"));
            stage = Stage::Activity;
            expectedGeneration += 1;
            emitActivityChanged();
        } else if (stage == Stage::Activity) {
            expect(snapshot, false, "UnsupportedSource", "");
            setWallpaper(
                QStringLiteral("org.kde.image"),
                QUrl::fromLocalFile(temporary.filePath(QStringLiteral("missing.png"))).toString());
            stage = Stage::Missing;
            expectedGeneration += 1;
            emitWallpaperChanged(0);
        } else if (stage == Stage::Missing) {
            expect(snapshot, false, "Missing", "");
            setWallpaper(QStringLiteral("org.kde.image"), QUrl::fromLocalFile(unreadablePath).toString());
            stage = Stage::Unreadable;
            expectedGeneration += 1;
            emitWallpaperChanged(0);
        } else if (stage == Stage::Unreadable) {
            if (restrictedFixtureReadable) {
                expect(snapshot, true, "Ready", "#D94A38");
            } else {
                expect(snapshot, false, "Unreadable", "");
            }
            stage = Stage::OwnerLoss;
            expectedGeneration += 1;
            require(bus.unregisterService(QString::fromLatin1(PlasmaService)),
                    "mock Plasma owner unregisters");
        } else if (stage == Stage::OwnerLoss) {
            expect(snapshot, false, "Unavailable", "");
            setWallpaper(
                QStringLiteral("org.kde.image"),
                QUrl::fromLocalFile(fixtures + QStringLiteral("/oversized.png")).toString());
            stage = Stage::Reappearance;
            expectedGeneration += 1;
            require(bus.registerService(QString::fromLatin1(PlasmaService)),
                    "mock Plasma owner reappears");
        } else if (stage == Stage::Reappearance) {
            expect(snapshot, true, "Ready", "#1E6FD9");
            require(services.wallpaperCalls == 6,
                    "only startup and applicable invalidations query wallpaper");
            require(!QString::fromUtf8(diagnostics).contains(fixtures)
                        && !QString::fromUtf8(diagnostics).contains(QStringLiteral("activity-test")),
                    "helper diagnostics contain no paths or identifiers");
            stage = Stage::Cleanup;
            helper.terminate();
        } else {
            fail("unexpected helper snapshot");
        }
    }

    void expect(
        const QJsonObject &snapshot,
        bool available,
        const char *status,
        const char *accent)
    {
        require(snapshot.value(QStringLiteral("available")).toBool() == available,
                "availability matches state");
        require(snapshot.value(QStringLiteral("status")).toString() == QString::fromLatin1(status),
                "status is normalized");
        require(snapshot.value(QStringLiteral("accent")).toString() == QString::fromLatin1(accent),
                "accent matches state");
        const QString path = snapshot.value(QStringLiteral("imagePath")).toString();
        require(available ? !path.isEmpty() : path.isEmpty(),
                "image path is exposed only for Ready snapshots");
    }

    void require(bool condition, const char *message)
    {
        if (!condition) {
            fail(message);
        }
    }

    [[noreturn]] void fail(const char *message)
    {
        std::fprintf(stderr, "wallpaper D-Bus test failed: %s\n", message);
        const QByteArray processError = helper.errorString().toUtf8();
        const QByteArray helperError = diagnostics.left(1024);
        std::fprintf(stderr, "process: %s\nhelper: %s\n", processError.constData(), helperError.constData());
        if (helper.state() != QProcess::NotRunning) {
            helper.kill();
            helper.waitForFinished();
        }
        std::exit(1);
    }

    QString helperPath;
    QString fixtures;
    QString unreadablePath;
    QString raceSourcePath;
    QDBusConnection bus;
    FakeServices services;
    QTemporaryDir temporary;
    QProcess helper;
    QTimer timeout;
    QByteArray output;
    QByteArray diagnostics;
    QObject *raceObserver = nullptr;
    std::mutex raceMutex;
    std::condition_variable raceBarrier;
    int raceSnapshots = 0;
    int extractionCount = 0;
    std::atomic_bool firstExtraction = true;
    bool recreationScheduled = false;
    bool releaseOldAnalysis = false;
    bool restrictedFixtureReadable = false;
    qint64 expectedGeneration = 1;
    Stage stage = Stage::Initial;
};

} // namespace

int main(int argc, char **argv)
{
    qputenv("QT_QPA_PLATFORM", QByteArrayLiteral("offscreen"));
    QGuiApplication application(argc, argv);
    if (argc != 3) {
        std::fprintf(stderr, "usage: wallpaper-dbus-test <helper> <fixture-directory>\n");
        return 2;
    }
    WallpaperDbusTest test(QString::fromLocal8Bit(argv[1]), QString::fromLocal8Bit(argv[2]));
    QTimer::singleShot(0, &test, [&test] { test.start(); });
    return application.exec();
}

#include "wallpaper_dbus_test.moc"

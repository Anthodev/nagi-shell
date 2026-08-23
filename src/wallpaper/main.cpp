#include "analyzer.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QDBusServiceWatcher>
#include <QDir>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QFutureWatcher>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QScreen>
#include <QTimer>
#include <QUrl>
#include <QtConcurrentRun>

#include <atomic>
#include <cstdio>
#include <memory>

#ifdef NAGI_WALLPAPER_TESTING
namespace nagi::wallpaper::testing {

FingerprintFunction fingerprintHook;
AnalyzeFunction analyzeHook;
SnapshotFunction snapshotHook;
WorkFinishedFunction workFinishedHook;

void setObserverHooks(
    FingerprintFunction fingerprint,
    AnalyzeFunction analyze,
    SnapshotFunction snapshot,
    WorkFinishedFunction workFinished)
{
    fingerprintHook = std::move(fingerprint);
    analyzeHook = std::move(analyze);
    snapshotHook = std::move(snapshot);
    workFinishedHook = std::move(workFinished);
}

void resetObserverHooks()
{
    fingerprintHook = {};
    analyzeHook = {};
    snapshotHook = {};
    workFinishedHook = {};
}

} // namespace nagi::wallpaper::testing
#endif

namespace {

constexpr auto PlasmaService = "org.kde.plasmashell";
constexpr auto PlasmaPath = "/PlasmaShell";
constexpr auto PlasmaInterface = "org.kde.PlasmaShell";
constexpr auto ActivityService = "org.kde.ActivityManager";
constexpr auto ActivityPath = "/ActivityManager/Activities";
constexpr auto ActivityInterface = "org.kde.ActivityManager.Activities";
constexpr int PrimaryScreen = 0;
constexpr int MaximumDiagnostics = 8;

nagi::wallpaper::FingerprintResult fingerprint(
    const QString &path,
    const std::function<bool()> &cancelled)
{
#ifdef NAGI_WALLPAPER_TESTING
    if (nagi::wallpaper::testing::fingerprintHook) {
        return nagi::wallpaper::testing::fingerprintHook(path, cancelled);
    }
#endif
    return nagi::wallpaper::fingerprintSource(path, cancelled);
}

nagi::wallpaper::SourceResult analyze(
    const QString &path,
    const QByteArray &digest,
    const std::function<bool()> &cancelled)
{
#ifdef NAGI_WALLPAPER_TESTING
    if (nagi::wallpaper::testing::analyzeHook) {
        return nagi::wallpaper::testing::analyzeHook(path, digest, cancelled);
    }
#endif
    return nagi::wallpaper::analyzeVerifiedSource(path, digest, cancelled);
}

QString statusName(const nagi::wallpaper::AnalysisResult &result)
{
    if (result.accepted) {
        return QStringLiteral("Ready");
    }
    if (result.status == QStringLiteral("Missing")) {
        return QStringLiteral("Missing");
    }
    if (result.status == QStringLiteral("Unreadable")) {
        return QStringLiteral("Unreadable");
    }
    return QStringLiteral("UnsupportedSource");
}

class WallpaperObserver final : public QObject {
    Q_OBJECT

public:
    explicit WallpaperObserver(bool once, QObject *parent = nullptr)
        : QObject(parent)
        , bus(QDBusConnection::sessionBus())
        , serviceWatcher(
              QString::fromLatin1(PlasmaService),
              bus,
              QDBusServiceWatcher::WatchForOwnerChange,
              this)
        , once(once)
    {
        connect(
            &serviceWatcher,
            &QDBusServiceWatcher::serviceOwnerChanged,
            this,
            &WallpaperObserver::onServiceOwnerChanged);
        connect(&fileWatcher, &QFileSystemWatcher::fileChanged, this, &WallpaperObserver::onImageChanged);
        connect(
            &fileWatcher,
            &QFileSystemWatcher::directoryChanged,
            this,
            &WallpaperObserver::onDirectoryChanged);
        connect(
            qGuiApp,
            &QGuiApplication::primaryScreenChanged,
            this,
            [this](QScreen *) { scheduleRefresh(); });
        connect(qGuiApp, &QGuiApplication::screenAdded, this, [this](QScreen *) { scheduleRefresh(); });
        connect(qGuiApp, &QGuiApplication::screenRemoved, this, [this](QScreen *) { scheduleRefresh(); });

        bus.connect(
            QString::fromLatin1(ActivityService),
            QString::fromLatin1(ActivityPath),
            QString::fromLatin1(ActivityInterface),
            QStringLiteral("CurrentActivityChanged"),
            this,
            SLOT(onActivityChanged(QString)));
        QTimer::singleShot(0, this, &WallpaperObserver::initialize);
    }

    ~WallpaperObserver() override
    {
        cancelAnalysis();
        detachPlasmaOwner();
    }

private slots:
    void onWallpaperChanged(uint screen)
    {
        if (screen == PrimaryScreen) {
            scheduleRefresh();
        }
    }

    void onActivityChanged(const QString &)
    {
        scheduleRefresh();
    }

    void onImageChanged(const QString &)
    {
        if (currentPath.isEmpty()) {
            return;
        }
        restoreImageWatch();
        inspectCurrentPath(true);
    }

    void onDirectoryChanged(const QString &)
    {
        if (currentPath.isEmpty()) {
            return;
        }
        const QFileInfo info(currentPath);
        const bool wasWatched = fileWatcher.files().contains(currentPath);
        restoreImageWatch();
        if (!info.exists()) {
            failCurrentSource(QStringLiteral("Missing"));
        } else if (!wasWatched || info.size() != currentSize || info.lastModified() != currentMtime) {
            inspectCurrentPath(true);
        }
    }

private:
    void initialize()
    {
        if (!bus.isConnected()) {
            cancelAnalysis();
            publish(QStringLiteral("Unavailable"), {}, {}, {});
            return;
        }
        const QString owner = currentServiceOwner();
        if (owner.isEmpty()) {
            cancelAnalysis();
            publish(QStringLiteral("Unavailable"), {}, {}, {});
            return;
        }
        attachPlasmaOwner(owner);
    }

    QString currentServiceOwner() const
    {
        QDBusConnectionInterface *interface = bus.interface();
        if (interface == nullptr) {
            return {};
        }
        const QDBusReply<QString> reply = interface->serviceOwner(QString::fromLatin1(PlasmaService));
        return reply.isValid() ? reply.value() : QString{};
    }

    void onServiceOwnerChanged(const QString &, const QString &, const QString &newOwner)
    {
        if (newOwner == plasmaOwner) {
            return;
        }
        detachPlasmaOwner();
        publish(QStringLiteral("Unavailable"), {}, {}, {});
        if (!newOwner.isEmpty()) {
            attachPlasmaOwner(newOwner);
        }
    }

    void attachPlasmaOwner(const QString &owner)
    {
        plasmaOwner = owner;
        if (!bus.connect(
                owner,
                QString::fromLatin1(PlasmaPath),
                QString::fromLatin1(PlasmaInterface),
                QStringLiteral("wallpaperChanged"),
                this,
                SLOT(onWallpaperChanged(uint)))) {
            diagnose("wallpaper signal subscription failed");
        }
        scheduleRefresh();
    }

    void detachPlasmaOwner()
    {
        refreshScheduled = false;
        refreshPending = false;
        if (inFlight != nullptr) {
            inFlight->disconnect(this);
            inFlight->deleteLater();
            inFlight = nullptr;
        }
        if (!plasmaOwner.isEmpty()) {
            bus.disconnect(
                plasmaOwner,
                QString::fromLatin1(PlasmaPath),
                QString::fromLatin1(PlasmaInterface),
                QStringLiteral("wallpaperChanged"),
                this,
                SLOT(onWallpaperChanged(uint)));
            plasmaOwner.clear();
        }
        cancelAnalysis();
        clearImageWatch();
        currentPath.clear();
    }

    void scheduleRefresh()
    {
        if (plasmaOwner.isEmpty()) {
            return;
        }
        if (inFlight != nullptr) {
            refreshPending = true;
            return;
        }
        if (refreshScheduled) {
            return;
        }
        refreshScheduled = true;
        QTimer::singleShot(0, this, &WallpaperObserver::refresh);
    }

    void refresh()
    {
        refreshScheduled = false;
        if (plasmaOwner.isEmpty() || inFlight != nullptr) {
            return;
        }

        QDBusMessage request = QDBusMessage::createMethodCall(
            QString::fromLatin1(PlasmaService),
            QString::fromLatin1(PlasmaPath),
            QString::fromLatin1(PlasmaInterface),
            QStringLiteral("wallpaper"));
        request << static_cast<uint>(PrimaryScreen);
        inFlight = new QDBusPendingCallWatcher(bus.asyncCall(request), this);
        connect(inFlight, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
            const QDBusPendingReply<QVariantMap> reply = *call;
            call->deleteLater();
            inFlight = nullptr;
            if (reply.isError()) {
                cancelAnalysis();
                publish(QStringLiteral("Unavailable"), {}, {}, {});
            } else {
                acceptWallpaperMap(reply.value());
            }
            if (refreshPending) {
                refreshPending = false;
                scheduleRefresh();
            }
        });
    }

    void acceptWallpaperMap(const QVariantMap &values)
    {
        if (values.value(QStringLiteral("wallpaperPlugin")).toString()
            != QStringLiteral("org.kde.image")) {
            rejectCurrent(QStringLiteral("UnsupportedPlugin"));
            return;
        }

        const QString image = values.value(QStringLiteral("Image")).toString();
        const QUrl url(image, QUrl::StrictMode);
        if (!url.isValid() || !url.isLocalFile() || !url.fragment().isEmpty()) {
            rejectCurrent(QStringLiteral("UnsupportedSource"));
            return;
        }
        const QString path = QDir::cleanPath(QFileInfo(url.toLocalFile()).absoluteFilePath());
        if (path.isEmpty() || !QFileInfo(path).isAbsolute()) {
            rejectCurrent(QStringLiteral("UnsupportedSource"));
            return;
        }

        if (path != currentPath) {
            cancelAnalysis();
            clearImageWatch();
            currentPath = path;
            currentSize = -1;
            currentMtime = {};
            restoreImageWatch();
        }
        inspectCurrentPath(false);
    }

    void rejectCurrent(const QString &status)
    {
        cancelAnalysis();
        clearImageWatch();
        currentPath.clear();
        currentSize = -1;
        currentMtime = {};
        publish(status, {}, {}, {});
    }

    void inspectCurrentPath(bool forceDigest)
    {
        const QFileInfo info(currentPath);
        if (!info.exists() || !info.isFile()) {
            failCurrentSource(QStringLiteral("Missing"));
            return;
        }
        if (!info.isReadable()) {
            failCurrentSource(QStringLiteral("Unreadable"));
            return;
        }
        if (info.size() <= 0 || info.size() > nagi::wallpaper::MaximumImageBytes) {
            failCurrentSource(QStringLiteral("UnsupportedSource"));
            return;
        }
        if (!forceDigest && publishedStatus == QStringLiteral("Ready") && currentPath == publishedPath
            && info.size() == currentSize && info.lastModified() == currentMtime) {
            return;
        }

        currentSize = info.size();
        currentMtime = info.lastModified();
        startFingerprint(currentPath);
    }

    void failCurrentSource(const QString &status)
    {
        cancelAnalysis();
        restoreImageWatch();
        publish(status, {}, {}, {});
    }

    void startFingerprint(const QString &path)
    {
        cancelAnalysis();
        const quint64 token = ++analysisToken;
        auto cancelled = std::make_shared<std::atomic_bool>(false);
        analysisCancellation = cancelled;
        auto *watcher = new QFutureWatcher<nagi::wallpaper::FingerprintResult>(this);
        fingerprintWatcher = watcher;
        connect(
            watcher,
            &QFutureWatcher<nagi::wallpaper::FingerprintResult>::finished,
            this,
            [this, watcher, token, path] {
                const bool hasResult = watcher->future().resultCount() > 0;
                watcher->deleteLater();
                if (fingerprintWatcher == watcher) {
                    fingerprintWatcher = nullptr;
                }
                if (token != analysisToken || path != currentPath || !hasResult) {
                    return;
                }
                const nagi::wallpaper::FingerprintResult result = watcher->result();
                if (result.validation.status == QStringLiteral("Cancelled")) {
                    return;
                }
                if (!result.validation.accepted) {
                    failCurrentSource(statusName(result.validation));
                    return;
                }
                if (publishedStatus == QStringLiteral("Ready") && publishedPath == path
                    && publishedDigest == result.digest) {
                    analysisCancellation.reset();
                    return;
                }
                startPaletteAnalysis(path, result.digest);
            });
        watcher->setFuture(QtConcurrent::run([path, cancelled] {
            return fingerprint(path, [cancelled] { return cancelled->load(); });
        }));
    }

    void startPaletteAnalysis(const QString &path, const QByteArray &digest)
    {
        cancelAnalysis();
        const quint64 token = ++analysisToken;
        auto cancelled = std::make_shared<std::atomic_bool>(false);
        analysisCancellation = cancelled;
        auto *watcher = new QFutureWatcher<nagi::wallpaper::SourceResult>(this);
        analysisWatcher = watcher;
        connect(watcher, &QFutureWatcher<nagi::wallpaper::SourceResult>::finished, this, [this, watcher, token, path] {
            const bool hasResult = watcher->future().resultCount() > 0;
            watcher->deleteLater();
            if (analysisWatcher == watcher) {
                analysisWatcher = nullptr;
            }
#ifdef NAGI_WALLPAPER_TESTING
            if (nagi::wallpaper::testing::workFinishedHook) {
                nagi::wallpaper::testing::workFinishedHook();
            }
#endif
            if (token != analysisToken || path != currentPath || !hasResult) {
                return;
            }
            const nagi::wallpaper::SourceResult result = watcher->result();
            if (result.analysis.status == QStringLiteral("Cancelled")) {
                return;
            }
            if (result.analysis.status == QStringLiteral("Changed")) {
                inspectCurrentPath(true);
                return;
            }
            if (!result.analysis.accepted) {
                failCurrentSource(statusName(result.analysis));
                return;
            }
            publish(QStringLiteral("Ready"), path, result.analysis.accent, result.digest);
        });
        watcher->setFuture(QtConcurrent::run([path, digest, cancelled] {
            return analyze(path, digest, [cancelled] { return cancelled->load(); });
        }));
    }

    void cancelAnalysis()
    {
        ++analysisToken;
        if (analysisCancellation) {
            analysisCancellation->store(true);
            analysisCancellation.reset();
        }
        if (fingerprintWatcher != nullptr) {
            fingerprintWatcher->cancel();
            fingerprintWatcher = nullptr;
        }
        if (analysisWatcher != nullptr) {
            analysisWatcher->cancel();
            analysisWatcher = nullptr;
        }
    }

    void restoreImageWatch()
    {
        if (currentPath.isEmpty()) {
            return;
        }
        const QFileInfo info(currentPath);
        const QString directory = info.absolutePath();
        if (!directory.isEmpty() && !fileWatcher.directories().contains(directory)) {
            fileWatcher.addPath(directory);
        }
        if (info.exists() && !fileWatcher.files().contains(currentPath)) {
            fileWatcher.addPath(currentPath);
        }
    }

    void clearImageWatch()
    {
        const QStringList files = fileWatcher.files();
        if (!files.isEmpty()) {
            fileWatcher.removePaths(files);
        }
        const QStringList directories = fileWatcher.directories();
        if (!directories.isEmpty()) {
            fileWatcher.removePaths(directories);
        }
    }

    void publish(
        const QString &status,
        const QString &path,
        const QString &accent,
        const QByteArray &digest)
    {
        if (hasPublished && status == publishedStatus && path == publishedPath
            && digest == publishedDigest && accent == publishedAccent) {
            return;
        }
        hasPublished = true;
        publishedStatus = status;
        publishedPath = path;
        publishedDigest = digest;
        publishedAccent = accent;
        generation += 1;
#ifdef NAGI_WALLPAPER_TESTING
        if (nagi::wallpaper::testing::snapshotHook) {
            nagi::wallpaper::testing::snapshotHook(status, generation);
            return;
        }
#endif

        const QJsonObject snapshot{
            {QStringLiteral("generation"), static_cast<qint64>(generation)},
            {QStringLiteral("available"), status == QStringLiteral("Ready")},
            {QStringLiteral("status"), status},
            {QStringLiteral("imagePath"), status == QStringLiteral("Ready") ? path : QString{}},
            {QStringLiteral("accent"), status == QStringLiteral("Ready") ? accent : QString{}},
        };
        const QByteArray json = QJsonDocument(snapshot).toJson(QJsonDocument::Compact);
        std::fwrite(json.constData(), 1, static_cast<size_t>(json.size()), stdout);
        std::fputc('\n', stdout);
        std::fflush(stdout);
        if (once) {
            QCoreApplication::quit();
        }
    }

    void diagnose(const char *message)
    {
        if (diagnosticCount >= MaximumDiagnostics) {
            return;
        }
        diagnosticCount += 1;
        std::fprintf(stderr, "nagi-shell wallpaper helper: %s\n", message);
        std::fflush(stderr);
    }

    QDBusConnection bus;
    QDBusServiceWatcher serviceWatcher;
    QFileSystemWatcher fileWatcher;
    QString plasmaOwner;
    QDBusPendingCallWatcher *inFlight = nullptr;
    QFutureWatcher<nagi::wallpaper::FingerprintResult> *fingerprintWatcher = nullptr;
    QFutureWatcher<nagi::wallpaper::SourceResult> *analysisWatcher = nullptr;
    std::shared_ptr<std::atomic_bool> analysisCancellation;
    QString currentPath;
    qint64 currentSize = -1;
    QDateTime currentMtime;
    QString publishedStatus;
    QString publishedPath;
    QString publishedAccent;
    QByteArray publishedDigest;
    quint64 generation = 0;
    quint64 analysisToken = 0;
    bool refreshScheduled = false;
    bool refreshPending = false;
    bool hasPublished = false;
    bool once = false;
    int diagnosticCount = 0;
};

[[maybe_unused]] int analyzeCommand(const QString &path)
{
    const nagi::wallpaper::SourceResult result = nagi::wallpaper::analyzeSource(path);
    const QJsonObject output{
        {QStringLiteral("accepted"), result.analysis.accepted},
        {QStringLiteral("status"), result.analysis.status},
        {QStringLiteral("accent"), result.analysis.accent},
    };
    const QByteArray json = QJsonDocument(output).toJson(QJsonDocument::Compact);
    std::fwrite(json.constData(), 1, static_cast<size_t>(json.size()), stdout);
    std::fputc('\n', stdout);
    return 0;
}

} // namespace

#ifdef NAGI_WALLPAPER_TESTING
namespace nagi::wallpaper::testing {

QObject *createObserver()
{
    return new WallpaperObserver(false);
}

} // namespace nagi::wallpaper::testing
#endif

#ifndef NAGI_WALLPAPER_NO_MAIN
int main(int argc, char **argv)
{
    QGuiApplication application(argc, argv);
    const QStringList arguments = application.arguments();
    if (arguments.size() == 3 && arguments.at(1) == QStringLiteral("--analyze")) {
        return analyzeCommand(arguments.at(2));
    }
    if (arguments.size() > 2 || (arguments.size() == 2 && arguments.at(1) != QStringLiteral("--once"))) {
        std::fprintf(stderr, "usage: nagi-wallpaper [--once | --analyze FILE]\n");
        return 2;
    }
    WallpaperObserver observer(arguments.size() == 2);
    return application.exec();
}
#endif

#include "main.moc"

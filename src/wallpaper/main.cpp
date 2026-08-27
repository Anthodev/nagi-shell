#include "analyzer.h"
#include "library.h"

#include <QCoreApplication>
#include <QCryptographicHash>
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
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QScreen>
#include <QSocketNotifier>
#include <QTimer>
#include <QUrl>
#include <QtConcurrentRun>

#include <array>
#include <atomic>
#include <cstdio>
#include <functional>
#include <memory>
#include <optional>
#include <cerrno>
#include <fcntl.h>
#include <unistd.h>

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
constexpr int MaximumDiagnostics = 8;
constexpr int MaximumProtocolLineBytes = 1024 * 1024;
constexpr int MaximumThumbnailQueue = 32;
constexpr int DecodeTimeoutMilliseconds = 2500;
constexpr auto StaticPlugin = "org.kde.image";

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

QString candidateId(const QString &path, const QByteArray &digest)
{
    QByteArray material = path.toUtf8();
    material.append('\0');
    material.append(digest);
    return QStringLiteral("c")
        + QString::fromLatin1(
            QCryptographicHash::hash(material, QCryptographicHash::Sha256).toHex().left(24));
}

QString jsQuoted(const QString &value)
{
    QByteArray encoded = QJsonDocument(QJsonArray{value}).toJson(QJsonDocument::Compact);
    return QString::fromUtf8(encoded.mid(1, encoded.size() - 2));
}

struct ScreenState {
    QString status;
    QString plugin;
    QString path;
};

struct Candidate {
    QString id;
    QString path;
    QString name;
    QByteArray digest;
    QString accent;
    QString thumbnail;
    int width = 0;
    int height = 0;
    qint64 byteSize = 0;
    bool outsideLibrary = false;
};

struct DecodeRequest {
    QString kind;
    QString identity;
    QString path;
    QString name;
    qint64 byteSize = 0;
    bool outsideLibrary = false;
};

class WallpaperService final : public QObject {
    Q_OBJECT

public:
    explicit WallpaperService(bool once, QObject *parent = nullptr, bool commandsEnabled = true)
        : QObject(parent)
        , bus(QDBusConnection::sessionBus())
        , serviceWatcher(
              QString::fromLatin1(PlasmaService),
              bus,
              QDBusServiceWatcher::WatchForOwnerChange,
              this)
        , cache()
        , once(once)
    {
        connect(
            &serviceWatcher,
            &QDBusServiceWatcher::serviceOwnerChanged,
            this,
            &WallpaperService::onServiceOwnerChanged);
        connect(&currentWatcher, &QFileSystemWatcher::fileChanged, this,
                &WallpaperService::onCurrentImageChanged);
        connect(&currentWatcher, &QFileSystemWatcher::directoryChanged, this,
                &WallpaperService::onCurrentDirectoryChanged);
        connect(&libraryWatcher, &QFileSystemWatcher::directoryChanged, this,
                &WallpaperService::scheduleLibraryRefresh);
        connect(&scanner, &nagi::wallpaper::LibraryScanner::progressChanged, this,
                &WallpaperService::publishLibraryProgress);
        connect(&scanner, &nagi::wallpaper::LibraryScanner::finished, this,
                &WallpaperService::acceptLibraryScan);
        connect(&decodeTimeout, &QTimer::timeout, this, &WallpaperService::decodeTimedOut);
        decodeTimeout.setSingleShot(true);
        connect(qGuiApp, &QGuiApplication::primaryScreenChanged, this,
                [this](QScreen *) { scheduleRefresh(); });
        connect(qGuiApp, &QGuiApplication::screenAdded, this,
                [this](QScreen *) { scheduleRefresh(); });
        connect(qGuiApp, &QGuiApplication::screenRemoved, this,
                [this](QScreen *) { scheduleRefresh(); });
        bus.connect(
            QString::fromLatin1(ActivityService),
            QString::fromLatin1(ActivityPath),
            QString::fromLatin1(ActivityInterface),
            QStringLiteral("CurrentActivityChanged"),
            this,
            SLOT(onActivityChanged(QString)));
        if (!once && commandsEnabled) {
            inputFd = fileno(stdin);
            const int flags = inputFd >= 0 ? fcntl(inputFd, F_GETFL, 0) : -1;
            if (flags >= 0 && fcntl(inputFd, F_SETFL, flags | O_NONBLOCK) == 0) {
                inputNotifier = std::make_unique<QSocketNotifier>(
                    inputFd, QSocketNotifier::Read, this);
                connect(inputNotifier.get(), &QSocketNotifier::activated, this,
                        &WallpaperService::readCommands);
            } else {
                diagnose("command input unavailable");
            }
        }
        QTimer::singleShot(0, this, &WallpaperService::initialize);
    }

    ~WallpaperService() override
    {
        cancelCurrentAnalysis();
        cancelDecode();
        scanner.cancel();
        detachPlasmaOwner();
    }

private slots:
    void onWallpaperChanged(uint)
    {
        scheduleRefresh();
    }

    void onActivityChanged(const QString &)
    {
        scheduleRefresh();
    }

    void onCurrentImageChanged(const QString &)
    {
        restoreCurrentWatches();
        if (!commonPath.isEmpty()) {
            inspectCommonPath(true);
        } else {
            scheduleRefresh();
        }
    }

    void onCurrentDirectoryChanged(const QString &)
    {
        restoreCurrentWatches();
        if (commonPath.isEmpty()) {
            scheduleRefresh();
            return;
        }
        const QFileInfo info(commonPath);
        if (!info.exists()) {
            failCommonSource(QStringLiteral("Missing"));
        } else if (info.size() != currentSize || info.lastModified() != currentMtime) {
            inspectCommonPath(true);
        }
    }

private:
    void initialize()
    {
        if (!bus.isConnected()) {
            publishUnavailable();
            return;
        }
        const QString owner = currentServiceOwner();
        if (owner.isEmpty()) {
            publishUnavailable();
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
        publishUnavailable();
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
        if (applyWatcher != nullptr) {
            applyWatcher->disconnect(this);
            applyWatcher->deleteLater();
            applyWatcher = nullptr;
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
        cancelCurrentAnalysis();
        clearCurrentWatches();
        commonPath.clear();
        screenStates.clear();
    }

    int activeScreenCount() const
    {
        return std::max(1, static_cast<int>(qGuiApp->screens().size()));
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
        QTimer::singleShot(0, this, &WallpaperService::refresh);
    }

    void refresh()
    {
        refreshScheduled = false;
        if (plasmaOwner.isEmpty() || inFlight != nullptr) {
            return;
        }
        pendingWallpaperMaps.clear();
        pendingScreenCount = activeScreenCount();
        requestWallpaper(0);
    }

    void requestWallpaper(int screen)
    {
        QDBusMessage request = QDBusMessage::createMethodCall(
            QString::fromLatin1(PlasmaService),
            QString::fromLatin1(PlasmaPath),
            QString::fromLatin1(PlasmaInterface),
            QStringLiteral("wallpaper"));
        request << static_cast<uint>(screen);
        inFlight = new QDBusPendingCallWatcher(bus.asyncCall(request), this);
        connect(inFlight, &QDBusPendingCallWatcher::finished, this,
                [this, screen](QDBusPendingCallWatcher *call) {
                    const QDBusPendingReply<QVariantMap> reply = *call;
                    call->deleteLater();
                    inFlight = nullptr;
                    pendingWallpaperMaps.append(reply.isError() ? QVariantMap{} : reply.value());
                    if (screen + 1 < pendingScreenCount) {
                        requestWallpaper(screen + 1);
                        return;
                    }
                    acceptWallpaperMaps();
                    if (refreshPending) {
                        refreshPending = false;
                        scheduleRefresh();
                    }
                });
    }

    ScreenState normalizeScreen(const QVariantMap &values) const
    {
        ScreenState state;
        if (values.isEmpty()) {
            state.status = QStringLiteral("Unavailable");
            return state;
        }
        state.plugin = values.value(QStringLiteral("wallpaperPlugin")).toString().left(128);
        if (state.plugin != QString::fromLatin1(StaticPlugin)) {
            state.status = QStringLiteral("UnsupportedPlugin");
            return state;
        }
        const QUrl url(values.value(QStringLiteral("Image")).toString(), QUrl::StrictMode);
        if (!url.isValid() || !url.isLocalFile() || !url.fragment().isEmpty()) {
            state.status = QStringLiteral("UnsupportedSource");
            return state;
        }
        const QFileInfo info(QDir::cleanPath(url.toLocalFile()));
        state.path = info.absoluteFilePath();
        if (!info.isAbsolute() || state.path.isEmpty()) {
            state.status = QStringLiteral("UnsupportedSource");
        } else if (!info.exists() || !info.isFile()) {
            state.status = QStringLiteral("Missing");
        } else if (!info.isReadable()) {
            state.status = QStringLiteral("Unreadable");
        } else if (info.size() <= 0 || info.size() > nagi::wallpaper::MaximumImageBytes) {
            state.status = QStringLiteral("UnsupportedSource");
        } else {
            state.status = QStringLiteral("Ready");
        }
        return state;
    }

    void acceptWallpaperMaps()
    {
        QVector<ScreenState> normalized;
        normalized.reserve(pendingWallpaperMaps.size());
        for (const QVariantMap &map : std::as_const(pendingWallpaperMaps)) {
            normalized.append(normalizeScreen(map));
        }
        screenStates = normalized;
        clearCurrentWatches();
        commonPath.clear();
        currentSize = -1;
        currentMtime = {};

        bool allReady = !screenStates.isEmpty();
        QString firstPath;
        bool samePath = true;
        bool sameState = true;
        const QString firstStatus = screenStates.isEmpty() ? QStringLiteral("Unavailable")
                                                            : screenStates.first().status;
        for (const ScreenState &state : std::as_const(screenStates)) {
            allReady = allReady && state.status == QStringLiteral("Ready");
            sameState = sameState && state.status == firstStatus;
            if (state.status == QStringLiteral("Ready")) {
                if (firstPath.isEmpty()) {
                    firstPath = state.path;
                } else if (state.path != firstPath) {
                    samePath = false;
                }
            } else {
                samePath = false;
            }
        }
        restoreCurrentWatches();
        if (allReady && samePath && !firstPath.isEmpty()) {
            commonPath = firstPath;
            inspectCommonPath(false);
            return;
        }
        cancelCurrentAnalysis();
        const QString status = sameState ? firstStatus : QStringLiteral("Multiple");
        publishCurrent(status, {}, {}, {});
    }

    void inspectCommonPath(bool forceDigest)
    {
        const QFileInfo info(commonPath);
        if (!info.exists() || !info.isFile()) {
            failCommonSource(QStringLiteral("Missing"));
            return;
        }
        if (!info.isReadable()) {
            failCommonSource(QStringLiteral("Unreadable"));
            return;
        }
        if (info.size() <= 0 || info.size() > nagi::wallpaper::MaximumImageBytes) {
            failCommonSource(QStringLiteral("UnsupportedSource"));
            return;
        }
        if (!forceDigest && publishedStatus == QStringLiteral("Ready")
            && commonPath == publishedPath && info.size() == currentSize
            && info.lastModified() == currentMtime) {
            return;
        }
        currentSize = info.size();
        currentMtime = info.lastModified();
        startFingerprint(commonPath);
    }

    void failCommonSource(const QString &status)
    {
        cancelCurrentAnalysis();
        restoreCurrentWatches();
        for (ScreenState &screen : screenStates) {
            if (screen.path == commonPath) {
                screen.status = status;
            }
        }
        publishCurrent(status, {}, {}, {});
        if (status == QStringLiteral("Missing")) {
            const QString path = commonPath;
            QTimer::singleShot(200, this, [this, path] {
                if (path == commonPath && QFileInfo(path).exists()) {
                    inspectCommonPath(true);
                }
            });
        }
    }

    void startFingerprint(const QString &path)
    {
        cancelCurrentAnalysis();
        const quint64 token = ++analysisToken;
        auto cancelled = std::make_shared<std::atomic_bool>(false);
        analysisCancellation = cancelled;
        auto *watcher = new QFutureWatcher<nagi::wallpaper::FingerprintResult>(this);
        fingerprintWatcher = watcher;
        connect(watcher, &QFutureWatcher<nagi::wallpaper::FingerprintResult>::finished, this,
                [this, watcher, token, path] {
                    const bool hasResult = watcher->future().resultCount() > 0;
                    watcher->deleteLater();
                    if (fingerprintWatcher == watcher) {
                        fingerprintWatcher = nullptr;
                    }
                    if (token != analysisToken || path != commonPath || !hasResult) {
                        return;
                    }
                    const auto result = watcher->result();
                    if (result.validation.status == QStringLiteral("Cancelled")) {
                        return;
                    }
                    if (!result.validation.accepted) {
                        failCommonSource(statusName(result.validation));
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
        cancelCurrentAnalysis();
        const quint64 token = ++analysisToken;
        auto cancelled = std::make_shared<std::atomic_bool>(false);
        analysisCancellation = cancelled;
        auto *watcher = new QFutureWatcher<nagi::wallpaper::SourceResult>(this);
        analysisWatcher = watcher;
        connect(watcher, &QFutureWatcher<nagi::wallpaper::SourceResult>::finished, this,
                [this, watcher, token, path] {
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
                    if (token != analysisToken || path != commonPath || !hasResult) {
                        return;
                    }
                    const auto result = watcher->result();
                    if (result.analysis.status == QStringLiteral("Cancelled")) {
                        return;
                    }
                    if (result.analysis.status == QStringLiteral("Changed")) {
                        inspectCommonPath(true);
                        return;
                    }
                    if (!result.analysis.accepted) {
                        failCommonSource(statusName(result.analysis));
                        return;
                    }
                    publishCurrent(
                        QStringLiteral("Ready"), path, result.analysis.accent, result.digest);
                });
        watcher->setFuture(QtConcurrent::run([path, digest, cancelled] {
            return analyze(path, digest, [cancelled] { return cancelled->load(); });
        }));
    }

    void cancelCurrentAnalysis()
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

    void restoreCurrentWatches()
    {
        QSet<QString> directories;
        QSet<QString> files;
        for (const ScreenState &state : std::as_const(screenStates)) {
            if (state.path.isEmpty()) {
                continue;
            }
            const QFileInfo info(state.path);
            directories.insert(info.absolutePath());
            if (info.exists()) {
                files.insert(state.path);
            }
        }
        for (const QString &directory : std::as_const(directories)) {
            if (!directory.isEmpty() && !currentWatcher.directories().contains(directory)) {
                currentWatcher.addPath(directory);
            }
        }
        for (const QString &file : std::as_const(files)) {
            if (!currentWatcher.files().contains(file)) {
                currentWatcher.addPath(file);
            }
        }
    }

    void clearCurrentWatches()
    {
        if (!currentWatcher.files().isEmpty()) {
            currentWatcher.removePaths(currentWatcher.files());
        }
        if (!currentWatcher.directories().isEmpty()) {
            currentWatcher.removePaths(currentWatcher.directories());
        }
    }

    QJsonArray publicScreens() const
    {
        QJsonArray screens;
        int index = 0;
        for (const ScreenState &state : screenStates) {
            screens.append(QJsonObject{
                {QStringLiteral("label"), QStringLiteral("Display %1").arg(index + 1)},
                {QStringLiteral("status"), state.status},
                {QStringLiteral("supported"), state.status == QStringLiteral("Ready")},
            });
            index += 1;
        }
        return screens;
    }

    void publishUnavailable()
    {
        screenStates = QVector<ScreenState>(activeScreenCount());
        for (ScreenState &state : screenStates) {
            state.status = QStringLiteral("Unavailable");
        }
        publishCurrent(QStringLiteral("Unavailable"), {}, {}, {});
    }

    void publishCurrent(
        const QString &status,
        const QString &path,
        const QString &accent,
        const QByteArray &digest)
    {
        const QJsonArray screens = publicScreens();
        const QByteArray publicKey = QJsonDocument(screens).toJson(QJsonDocument::Compact);
        if (hasPublished && status == publishedStatus && path == publishedPath
            && digest == publishedDigest && accent == publishedAccent
            && publicKey == publishedScreens) {
            return;
        }
        hasPublished = true;
        publishedStatus = status;
        publishedPath = path;
        publishedDigest = digest;
        publishedAccent = accent;
        publishedScreens = publicKey;
        currentGeneration += 1;
#ifdef NAGI_WALLPAPER_TESTING
        if (nagi::wallpaper::testing::snapshotHook) {
            nagi::wallpaper::testing::snapshotHook(status, currentGeneration);
            return;
        }
#endif
        bool unsupported = false;
        for (const ScreenState &screen : std::as_const(screenStates)) {
            unsupported = unsupported || screen.status == QStringLiteral("UnsupportedPlugin");
        }
        emitJson(QJsonObject{
            {QStringLiteral("type"), QStringLiteral("current")},
            {QStringLiteral("generation"), static_cast<qint64>(currentGeneration)},
            {QStringLiteral("available"), status == QStringLiteral("Ready")},
            {QStringLiteral("status"), status},
            {QStringLiteral("multiple"), status == QStringLiteral("Multiple")},
            {QStringLiteral("unsupported"), unsupported},
            {QStringLiteral("accent"), status == QStringLiteral("Ready") ? accent : QString{}},
            {QStringLiteral("screens"), screens},
        });
        if (once) {
            QCoreApplication::quit();
        }
    }

    void readCommands()
    {
        std::array<char, 64 * 1024> bytes{};
        while (true) {
            const ssize_t count = ::read(inputFd, bytes.data(), bytes.size());
            if (count > 0) {
                commandBuffer.append(bytes.data(), count);
                continue;
            }
            if (count == 0 && inputNotifier) {
                inputNotifier->setEnabled(false);
            } else if (count < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
                diagnose("command input failed");
            }
            break;
        }
        if (commandBuffer.size() > MaximumProtocolLineBytes * 2) {
            commandBuffer.clear();
            diagnose("oversized command rejected");
            return;
        }
        while (true) {
            const qsizetype newline = commandBuffer.indexOf('\n');
            if (newline < 0) {
                return;
            }
            const QByteArray line = commandBuffer.left(newline).trimmed();
            commandBuffer.remove(0, newline + 1);
            if (line.isEmpty()) {
                continue;
            }
            if (line.size() > MaximumProtocolLineBytes) {
                diagnose("oversized command rejected");
                continue;
            }
            const QJsonDocument document = QJsonDocument::fromJson(line);
            if (!document.isObject()) {
                diagnose("invalid command rejected");
                continue;
            }
            handleCommand(document.object());
        }
    }

    void handleCommand(const QJsonObject &command)
    {
        const QString operation = command.value(QStringLiteral("op")).toString();
        if (operation == QStringLiteral("interest")) {
            setLibraryInterest(command);
        } else if (operation == QStringLiteral("thumbnail")) {
            queueThumbnail(command.value(QStringLiteral("id")).toString());
        } else if (operation == QStringLiteral("preview")) {
            previewIdentity(command.value(QStringLiteral("id")).toString());
        } else if (operation == QStringLiteral("preview-path")) {
            previewPath(command.value(QStringLiteral("path")).toString());
        } else if (operation == QStringLiteral("apply")) {
            applyCandidate(command.value(QStringLiteral("id")).toString());
        } else if (operation == QStringLiteral("cancel-preview")) {
            cancelDecode();
        } else if (operation == QStringLiteral("shutdown")) {
            QCoreApplication::quit();
        } else {
            diagnose("unknown command rejected");
        }
    }

    void setLibraryInterest(const QJsonObject &command)
    {
        const bool active = command.value(QStringLiteral("active")).toBool(false);
        if (!active) {
            libraryActive = false;
            scanner.cancel();
            clearLibraryWatches();
            cancelDecode();
            libraryImages.clear();
            thumbnailQueue.clear();
            publishLibraryState(QStringLiteral("idle"), false, false);
            return;
        }
        const QJsonArray rootValues = command.value(QStringLiteral("roots")).toArray();
        if (rootValues.size() > nagi::wallpaper::MaximumLibraryRoots) {
            publishLibraryState(QStringLiteral("invalid-roots"), false, false);
            return;
        }
        QStringList roots;
        for (const QJsonValue &value : rootValues) {
            if (!value.isString() || value.toString().toUtf8().size() > nagi::wallpaper::MaximumRootBytes) {
                publishLibraryState(QStringLiteral("invalid-roots"), false, false);
                return;
            }
            roots.append(value.toString());
        }
        libraryActive = true;
        approvedRoots = roots;
        publishLibraryState(QStringLiteral("indexing"), true, false);
        scanner.start(approvedRoots);
    }

    void scheduleLibraryRefresh()
    {
        if (!libraryActive || libraryRefreshScheduled) {
            return;
        }
        libraryRefreshScheduled = true;
        QTimer::singleShot(120, this, [this] {
            libraryRefreshScheduled = false;
            if (libraryActive) {
                scanner.start(approvedRoots);
            }
        });
    }

    void publishLibraryProgress()
    {
        if (libraryActive) {
            publishLibraryState(QStringLiteral("indexing"), true, false);
        }
    }

    void acceptLibraryScan()
    {
        if (!libraryActive) {
            return;
        }
        const auto &result = scanner.result();
        libraryImages.clear();
        for (const auto &image : result.images) {
            libraryImages.insert(image.id, image);
        }
        clearLibraryWatches();
        for (const QString &directory : result.watchedDirectories) {
            if (libraryWatcher.directories().size() >= nagi::wallpaper::MaximumWatchedDirectories) {
                break;
            }
            libraryWatcher.addPath(directory);
        }
        publishLibrary(result);
    }

    void clearLibraryWatches()
    {
        if (!libraryWatcher.directories().isEmpty()) {
            libraryWatcher.removePaths(libraryWatcher.directories());
        }
    }

    void publishLibraryState(const QString &status, bool scanning, bool truncated)
    {
        libraryGeneration += 1;
        emitJson(QJsonObject{
            {QStringLiteral("type"), QStringLiteral("library")},
            {QStringLiteral("generation"), static_cast<qint64>(libraryGeneration)},
            {QStringLiteral("status"), status},
            {QStringLiteral("scanning"), scanning},
            {QStringLiteral("truncated"), truncated},
            {QStringLiteral("visited"), 0},
            {QStringLiteral("elapsedMs"), 0},
            {QStringLiteral("directories"), QJsonArray{}},
            {QStringLiteral("images"), QJsonArray{}},
        });
    }

    void publishLibrary(const nagi::wallpaper::LibraryScanResult &result)
    {
        QJsonArray directories;
        for (const auto &directory : result.directories) {
            directories.append(QJsonObject{
                {QStringLiteral("id"), directory.id},
                {QStringLiteral("parentId"), directory.parentId},
                {QStringLiteral("name"), directory.name},
                {QStringLiteral("breadcrumb"), directory.breadcrumb},
                {QStringLiteral("rootId"), directory.rootId},
            });
        }
        QJsonArray images;
        for (const auto &image : result.images) {
            images.append(QJsonObject{
                {QStringLiteral("id"), image.id},
                {QStringLiteral("directoryId"), image.directoryId},
                {QStringLiteral("name"), image.name},
                {QStringLiteral("byteSize"), image.byteSize},
                {QStringLiteral("modifiedMs"), image.modifiedMilliseconds},
                {QStringLiteral("width"), image.width},
                {QStringLiteral("height"), image.height},
            });
        }
        libraryGeneration += 1;
        emitJson(QJsonObject{
            {QStringLiteral("type"), QStringLiteral("library")},
            {QStringLiteral("generation"), static_cast<qint64>(libraryGeneration)},
            {QStringLiteral("status"), result.status},
            {QStringLiteral("scanning"), false},
            {QStringLiteral("truncated"), result.truncated},
            {QStringLiteral("visited"), result.visitedEntries},
            {QStringLiteral("elapsedMs"), result.elapsedMilliseconds},
            {QStringLiteral("directories"), directories},
            {QStringLiteral("images"), images},
        });
    }

    void queueThumbnail(const QString &identity)
    {
        if (!libraryActive || identity.isEmpty() || !libraryImages.contains(identity)
            || thumbnailQueue.size() >= MaximumThumbnailQueue) {
            return;
        }
        for (const DecodeRequest &queued : std::as_const(thumbnailQueue)) {
            if (queued.kind == QStringLiteral("thumbnail") && queued.identity == identity) {
                return;
            }
        }
        const auto image = libraryImages.value(identity);
        thumbnailQueue.append(
            {QStringLiteral("thumbnail"), identity, image.path, image.name, image.byteSize, false});
        startNextDecode();
    }

    void previewIdentity(const QString &identity)
    {
        if (!libraryActive || !libraryImages.contains(identity)) {
            publishPreviewFailure(QStringLiteral("invalid"));
            return;
        }
        const auto image = libraryImages.value(identity);
        enqueuePreview({QStringLiteral("preview"), identity, image.path, image.name,
                        image.byteSize, false});
    }

    void previewPath(const QString &path)
    {
        if (!libraryActive || path.isEmpty() || path.size() > 4096) {
            publishPreviewFailure(QStringLiteral("invalid"));
            return;
        }
        const QFileInfo info(path);
        const QString absolute = QDir::cleanPath(info.absoluteFilePath());
        const QString canonical = info.canonicalFilePath();
        if (!info.isAbsolute() || info.isSymLink() || !info.exists() || !info.isFile()
            || canonical.isEmpty() || canonical != absolute) {
            publishPreviewFailure(QStringLiteral("invalid"));
            return;
        }
        enqueuePreview({QStringLiteral("preview"), {}, canonical, info.fileName().left(255),
                        info.size(), true});
    }

    void enqueuePreview(DecodeRequest request)
    {
        cancelDecode();
        thumbnailQueue.prepend(std::move(request));
        publishPreviewPending();
        startNextDecode();
    }

    void startNextDecode()
    {
        if (decodeWatcher != nullptr || thumbnailQueue.isEmpty()) {
            return;
        }
        activeDecode = thumbnailQueue.takeFirst();
        const quint64 token = ++decodeToken;
        auto cancelled = std::make_shared<std::atomic_bool>(false);
        decodeCancellation = cancelled;
        auto *watcher = new QFutureWatcher<nagi::wallpaper::ThumbnailResult>(this);
        decodeWatcher = watcher;
        connect(watcher, &QFutureWatcher<nagi::wallpaper::ThumbnailResult>::finished, this,
                [this, watcher, token] {
                    decodeTimeout.stop();
                    const bool hasResult = watcher->future().resultCount() > 0;
                    watcher->deleteLater();
                    if (decodeWatcher == watcher) {
                        decodeWatcher = nullptr;
                    }
                    if (token != decodeToken || !hasResult) {
                        startNextDecode();
                        return;
                    }
                    const auto result = watcher->result();
                    if (activeDecode.kind == QStringLiteral("thumbnail")) {
                        publishThumbnail(activeDecode.identity, result);
                    } else {
                        publishPreview(activeDecode, result);
                    }
                    decodeCancellation.reset();
                    startNextDecode();
                });
        const QString path = activeDecode.path;
        const bool includePalette = activeDecode.kind == QStringLiteral("preview");
        watcher->setFuture(QtConcurrent::run([this, path, cancelled, includePalette] {
            return cache.load(
                path, [cancelled] { return cancelled->load(); }, includePalette);
        }));
        decodeTimeout.start(DecodeTimeoutMilliseconds);
    }

    void decodeTimedOut()
    {
        if (decodeCancellation) {
            decodeCancellation->store(true);
        }
        if (activeDecode.kind == QStringLiteral("preview")) {
            publishPreviewFailure(QStringLiteral("timeout"));
        } else if (!activeDecode.identity.isEmpty()) {
            emitJson(QJsonObject{
                {QStringLiteral("type"), QStringLiteral("thumbnail")},
                {QStringLiteral("id"), activeDecode.identity},
                {QStringLiteral("status"), QStringLiteral("timeout")},
                {QStringLiteral("data"), QString{}},
            });
        }
    }

    void cancelDecode()
    {
        ++decodeToken;
        decodeTimeout.stop();
        thumbnailQueue.clear();
        if (decodeCancellation) {
            decodeCancellation->store(true);
            decodeCancellation.reset();
        }
        if (decodeWatcher != nullptr) {
            decodeWatcher->cancel();
            decodeWatcher = nullptr;
        }
        activeDecode = {};
    }

    void publishThumbnail(
        const QString &identity,
        const nagi::wallpaper::ThumbnailResult &result)
    {
        emitJson(QJsonObject{
            {QStringLiteral("type"), QStringLiteral("thumbnail")},
            {QStringLiteral("id"), identity},
            {QStringLiteral("status"), result.accepted ? QStringLiteral("ready")
                                                        : QStringLiteral("failed")},
            {QStringLiteral("data"), result.accepted ? result.dataUrl : QString{}},
        });
    }

    void publishPreviewPending()
    {
        previewGeneration += 1;
        emitJson(QJsonObject{
            {QStringLiteral("type"), QStringLiteral("preview")},
            {QStringLiteral("generation"), static_cast<qint64>(previewGeneration)},
            {QStringLiteral("status"), QStringLiteral("loading")},
        });
    }

    void publishPreviewFailure(const QString &status)
    {
        activeCandidate.reset();
        previewGeneration += 1;
        emitJson(QJsonObject{
            {QStringLiteral("type"), QStringLiteral("preview")},
            {QStringLiteral("generation"), static_cast<qint64>(previewGeneration)},
            {QStringLiteral("status"), status},
        });
    }

    void publishPreview(
        const DecodeRequest &request,
        const nagi::wallpaper::ThumbnailResult &result)
    {
        if (!result.accepted) {
            publishPreviewFailure(QStringLiteral("failed"));
            return;
        }
        Candidate candidate;
        candidate.id = candidateId(request.path, result.digest);
        candidate.path = request.path;
        candidate.name = request.name;
        candidate.digest = result.digest;
        candidate.accent = result.accent;
        candidate.thumbnail = result.dataUrl;
        candidate.width = result.width;
        candidate.height = result.height;
        candidate.byteSize = request.byteSize;
        candidate.outsideLibrary = request.outsideLibrary;
        activeCandidate = candidate;
        previewGeneration += 1;
        emitJson(QJsonObject{
            {QStringLiteral("type"), QStringLiteral("preview")},
            {QStringLiteral("generation"), static_cast<qint64>(previewGeneration)},
            {QStringLiteral("status"), QStringLiteral("ready")},
            {QStringLiteral("id"), candidate.id},
            {QStringLiteral("name"), candidate.name},
            {QStringLiteral("thumbnail"), candidate.thumbnail},
            {QStringLiteral("accent"), candidate.accent},
            {QStringLiteral("width"), candidate.width},
            {QStringLiteral("height"), candidate.height},
            {QStringLiteral("byteSize"), candidate.byteSize},
            {QStringLiteral("outsideLibrary"), candidate.outsideLibrary},
        });
    }

    void applyCandidate(const QString &identity)
    {
        if (applyWatcher != nullptr || !activeCandidate.has_value()
            || identity != activeCandidate->id || plasmaOwner.isEmpty()) {
            publishApplyResult(false, false, QStringLiteral("invalid"), {});
            return;
        }
        const auto verified = fingerprint(activeCandidate->path, {});
        if (!verified.validation.accepted || verified.digest != activeCandidate->digest) {
            publishApplyResult(false, false, QStringLiteral("changed"), {});
            return;
        }
        applyingCandidate = *activeCandidate;
        applyGeneration += 1;
        emitJson(QJsonObject{
            {QStringLiteral("type"), QStringLiteral("apply")},
            {QStringLiteral("generation"), static_cast<qint64>(applyGeneration)},
            {QStringLiteral("status"), QStringLiteral("pending")},
        });
        const QString imageUrl = QUrl::fromLocalFile(applyingCandidate.path)
                                     .toString(QUrl::FullyEncoded);
        const QString script = QStringLiteral(
                                   "const plugin = 'org.kde.image';\n"
                                   "const image = %1;\n"
                                   "const available = knownWallpaperPlugins();\n"
                                   "if (!Object.prototype.hasOwnProperty.call(available, plugin)) "
                                   "{ throw new Error(plugin); }\n"
                                   "for (const desktop of desktopsForActivity(currentActivity())) {\n"
                                   "desktop.wallpaperPlugin = plugin;\n"
                                   "desktop.currentConfigGroup = ['Wallpaper', plugin, 'General'];\n"
                                   "desktop.writeConfig('Image', image);\n"
                                   "desktop.reloadConfig();\n"
                                   "print('requested screen=' + desktop.screen);\n"
                                   "}\n")
                                   .arg(jsQuoted(imageUrl));
        callEvaluate(script, [this](bool, const QString &) { readBackApply(); });
    }

    void readBackApply()
    {
        const QString script = QStringLiteral(
            "for (const desktop of desktopsForActivity(currentActivity())) {\n"
            "desktop.currentConfigGroup = ['Wallpaper', 'org.kde.image', 'General'];\n"
            "print(desktop.screen, desktop.wallpaperPlugin, desktop.readConfig('Image', ''));\n"
            "}\n");
        callEvaluate(script, [this](bool valid, const QString &output) {
            QJsonArray results;
            bool any = false;
            bool all = valid;
            QSet<int> seen;
            const QString expectedPath = QFileInfo(applyingCandidate.path).absoluteFilePath();
            const QRegularExpression plainPattern(
                QStringLiteral("^(\\d+)\\s+(\\S+)\\s+(.*)$"));
            const QRegularExpression labelledPattern(
                QStringLiteral("^screen=(\\d+)\\s+plugin=(\\S+)\\s+image=(.*)$"));
            for (const QString &line : output.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                auto match = plainPattern.match(line.trimmed());
                if (!match.hasMatch()) {
                    match = labelledPattern.match(line.trimmed());
                }
                if (!match.hasMatch()) {
                    continue;
                }
                const int screen = match.captured(1).toInt();
                const QString plugin = match.captured(2);
                const QUrl url(match.captured(3), QUrl::StrictMode);
                const QString path = url.isLocalFile() ? QFileInfo(url.toLocalFile()).absoluteFilePath()
                                                       : QString{};
                const bool success = plugin == QString::fromLatin1(StaticPlugin)
                    && path == expectedPath;
                seen.insert(screen);
                any = any || success;
                all = all && success;
                results.append(QJsonObject{
                    {QStringLiteral("label"), QStringLiteral("Display %1").arg(screen + 1)},
                    {QStringLiteral("status"), success ? QStringLiteral("success")
                                                       : QStringLiteral("failed")},
                });
            }
            all = all && seen.size() == activeScreenCount();
            publishApplyResult(all, any && !all, all ? QStringLiteral("success")
                                                     : any ? QStringLiteral("partial")
                                                           : QStringLiteral("failed"),
                               results);
            scheduleRefresh();
        });
    }

    void callEvaluate(
        const QString &script,
        std::function<void(bool, const QString &)> completion)
    {
        QDBusMessage request = QDBusMessage::createMethodCall(
            QString::fromLatin1(PlasmaService),
            QString::fromLatin1(PlasmaPath),
            QString::fromLatin1(PlasmaInterface),
            QStringLiteral("evaluateScript"));
        request << script;
        applyWatcher = new QDBusPendingCallWatcher(bus.asyncCall(request), this);
        connect(applyWatcher, &QDBusPendingCallWatcher::finished, this,
                [this, completion = std::move(completion)](QDBusPendingCallWatcher *watcher) {
                    const QDBusPendingReply<QString> reply = *watcher;
                    watcher->deleteLater();
                    applyWatcher = nullptr;
                    completion(!reply.isError(), reply.isError() ? QString{} : reply.value());
                });
    }

    void publishApplyResult(
        bool success,
        bool partial,
        const QString &status,
        const QJsonArray &results)
    {
        applyGeneration += 1;
        emitJson(QJsonObject{
            {QStringLiteral("type"), QStringLiteral("apply")},
            {QStringLiteral("generation"), static_cast<qint64>(applyGeneration)},
            {QStringLiteral("status"), status},
            {QStringLiteral("success"), success},
            {QStringLiteral("partial"), partial},
            {QStringLiteral("rollbackAttempted"), false},
            {QStringLiteral("results"), results},
        });
    }

    void emitJson(const QJsonObject &object)
    {
        const QByteArray json = QJsonDocument(object).toJson(QJsonDocument::Compact);
        if (json.size() > MaximumProtocolLineBytes) {
            diagnose("oversized response suppressed");
            return;
        }
        std::fwrite(json.constData(), 1, static_cast<size_t>(json.size()), stdout);
        std::fputc('\n', stdout);
        std::fflush(stdout);
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
    QFileSystemWatcher currentWatcher;
    QFileSystemWatcher libraryWatcher;
    nagi::wallpaper::LibraryScanner scanner;
    nagi::wallpaper::ThumbnailCache cache;
    QByteArray commandBuffer;
    std::unique_ptr<QSocketNotifier> inputNotifier;
    int inputFd = -1;
    QString plasmaOwner;
    QDBusPendingCallWatcher *inFlight = nullptr;
    QDBusPendingCallWatcher *applyWatcher = nullptr;
    QFutureWatcher<nagi::wallpaper::FingerprintResult> *fingerprintWatcher = nullptr;
    QFutureWatcher<nagi::wallpaper::SourceResult> *analysisWatcher = nullptr;
    QFutureWatcher<nagi::wallpaper::ThumbnailResult> *decodeWatcher = nullptr;
    std::shared_ptr<std::atomic_bool> analysisCancellation;
    std::shared_ptr<std::atomic_bool> decodeCancellation;
    QTimer decodeTimeout;
    QVector<QVariantMap> pendingWallpaperMaps;
    QVector<ScreenState> screenStates;
    QHash<QString, nagi::wallpaper::LibraryImage> libraryImages;
    QList<DecodeRequest> thumbnailQueue;
    std::optional<Candidate> activeCandidate;
    Candidate applyingCandidate;
    DecodeRequest activeDecode;
    QStringList approvedRoots;
    QString commonPath;
    qint64 currentSize = -1;
    QDateTime currentMtime;
    QString publishedStatus;
    QString publishedPath;
    QString publishedAccent;
    QByteArray publishedDigest;
    QByteArray publishedScreens;
    quint64 currentGeneration = 0;
    quint64 libraryGeneration = 0;
    quint64 previewGeneration = 0;
    quint64 applyGeneration = 0;
    quint64 analysisToken = 0;
    quint64 decodeToken = 0;
    int pendingScreenCount = 0;
    bool refreshScheduled = false;
    bool refreshPending = false;
    bool hasPublished = false;
    bool once = false;
    bool libraryActive = false;
    bool libraryRefreshScheduled = false;
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
    return new WallpaperService(false, nullptr, false);
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
    WallpaperService service(arguments.size() == 2);
    return application.exec();
}
#endif

#include "main.moc"

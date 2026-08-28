#include "library.h"

#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QTemporaryDir>
#include <QTimer>
#include <algorithm>

#include <cstdio>
#include <cstdlib>

namespace {
constexpr int SoakCycleCount = 50;
constexpr qint64 EventLoopServiceBudgetMilliseconds = 100;
constexpr qint64 PageCloseBudgetMilliseconds = 250;

struct ScanObservation {
    int progressCount = 0;
    int eventLoopServiceCount = 0;
    qint64 maximumServiceGapMilliseconds = 0;
};


void require(bool condition, const char *message)
{
    if (!condition) {
        std::fprintf(stderr, "wallpaper library test failed: %s\n", message);
        std::exit(1);
    }
}

void copyFile(const QString &source, const QString &destination)
{
    QFile::remove(destination);
    require(QFile::copy(source, destination), "fixture copy succeeds");
}
void createSizedFile(const QString &path, qint64 size)
{
    QFile::remove(path);
    QFile file(path);
    require(file.open(QIODevice::WriteOnly) && file.resize(size), "sized fixture is created");
}

qint64 fileBytes(const QFileInfoList &entries)
{
    qint64 bytes = 0;
    for (const QFileInfo &entry : entries) {
        bytes += entry.size();
    }
    return bytes;
}


nagi::wallpaper::LibraryScanResult scan(
    nagi::wallpaper::LibraryScanner &scanner,
    const QStringList &roots,
    ScanObservation *observation = nullptr)
{
    QEventLoop loop;
    QTimer timeout;
    timeout.setSingleShot(true);
    timeout.setInterval(10000);
    QObject::connect(&timeout, &QTimer::timeout, &loop, [&] {
        std::fprintf(stderr, "wallpaper library test timed out\n");
        std::exit(1);
    });

    QTimer eventLoopService;
    QElapsedTimer serviceElapsed;
    qint64 lastServiceMilliseconds = 0;
    QMetaObject::Connection progress;
    if (observation != nullptr) {
        eventLoopService.setInterval(0);
        QObject::connect(&eventLoopService, &QTimer::timeout, &loop, [&] {
            const qint64 now = serviceElapsed.elapsed();
            observation->maximumServiceGapMilliseconds = std::max(
                observation->maximumServiceGapMilliseconds, now - lastServiceMilliseconds);
            lastServiceMilliseconds = now;
            observation->eventLoopServiceCount += 1;
        });
        progress = QObject::connect(
            &scanner,
            &nagi::wallpaper::LibraryScanner::progressChanged,
            &loop,
            [observation] { observation->progressCount += 1; });
        serviceElapsed.start();
        eventLoopService.start();
    }

    const QMetaObject::Connection done = QObject::connect(
        &scanner, &nagi::wallpaper::LibraryScanner::finished, &loop, &QEventLoop::quit);
    timeout.start();
    scanner.start(roots);
    loop.exec();
    timeout.stop();
    QObject::disconnect(done);
    if (observation != nullptr) {
        eventLoopService.stop();
        observation->maximumServiceGapMilliseconds = std::max(
            observation->maximumServiceGapMilliseconds,
            serviceElapsed.elapsed() - lastServiceMilliseconds);
    }
    if (progress) {
        QObject::disconnect(progress);
    }
    return scanner.result();
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    if (argc != 2) {
        std::fprintf(stderr, "usage: wallpaper-library-test <fixture-directory>\n");
        return 2;
    }
    const QString fixtures = QString::fromLocal8Bit(argv[1]);
    QTemporaryDir temporary;
    require(temporary.isValid(), "temporary root is available");
    require(nagi::wallpaper::MaximumLibraryRoots == 8
                && nagi::wallpaper::MaximumTraversalEntries == 4096
                && nagi::wallpaper::MaximumLibraryImages == 512
                && nagi::wallpaper::MaximumLibraryDirectories == 512
                && nagi::wallpaper::MaximumWatchedDirectories == 512
                && nagi::wallpaper::MaximumImageBytes == 32LL * 1024 * 1024,
            "root, traversal, model, watcher, and source-byte caps remain exact");


    const QString root = temporary.filePath(QStringLiteral("Wallpapers"));
    const QString nested = root + QStringLiteral("/Landscapes/Deep");
    const QString many = root + QStringLiteral("/Many");
    require(QDir().mkpath(nested) && QDir().mkpath(many), "bounded directory tree is created");
    copyFile(fixtures + QStringLiteral("/colorful.png"), root + QStringLiteral("/root.png"));
    copyFile(fixtures + QStringLiteral("/oversized.png"), nested + QStringLiteral("/nested.png"));
    copyFile(fixtures + QStringLiteral("/malformed.png"), root + QStringLiteral("/corrupt.png"));
    require(QFile::link(root, nested + QStringLiteral("/cycle")), "directory cycle symlink is created");
    require(QFile::link(root + QStringLiteral("/root.png"), root + QStringLiteral("/linked.png")),
            "file symlink is created");
    for (int index = 0; index < nagi::wallpaper::MaximumLibraryImages + 12; ++index) {
        copyFile(
            fixtures + QStringLiteral("/colorful.png"),
            many + QStringLiteral("/image-%1.png").arg(index, 3, 10, QLatin1Char('0')));
    }

    nagi::wallpaper::LibraryScanner scanner;
    ScanObservation scanObservation;
    const auto result = scan(scanner, {root}, &scanObservation);
    require(result.status == QStringLiteral("truncated") && result.truncated,
            "image-count bound is explicit and observable");
    require(result.images.size() == nagi::wallpaper::MaximumLibraryImages,
            "library image projection stops at the fixed bound");
    require(result.visitedEntries <= nagi::wallpaper::MaximumTraversalEntries,
            "visited entry count stays within the traversal budget");
    require(result.directories.size() <= nagi::wallpaper::MaximumLibraryDirectories
                && result.watchedDirectories.size() <= nagi::wallpaper::MaximumWatchedDirectories,
            "directory and watcher models remain bounded");
    require(scanObservation.progressCount > 1,
            "large traversal yields across multiple event-loop slices");
    require(scanObservation.eventLoopServiceCount > 0
                && scanObservation.maximumServiceGapMilliseconds
                    <= EventLoopServiceBudgetMilliseconds,
            "indexing services unrelated event-loop work within 100 ms");
    bool sawSymlink = false;
    bool sawCorrupt = false;
    for (const auto &image : result.images) {
        sawSymlink = sawSymlink || image.name == QStringLiteral("linked.png");
        sawCorrupt = sawCorrupt || image.name == QStringLiteral("corrupt.png");
        require(image.path.startsWith(root), "indexed source remains inside an approved root");
    }
    require(!sawSymlink && !sawCorrupt,
            "symlinked and corrupt inputs never enter the static-image model");
    for (const auto &directory : result.directories) {
        require(directory.name != QStringLiteral("cycle"), "directory symlink cycles are not followed");
    }
    const QString rootsCapParent = temporary.filePath(QStringLiteral("RootsCap"));
    QStringList rootsOverCap;
    for (int index = 0; index < nagi::wallpaper::MaximumLibraryRoots + 1; ++index) {
        const QString cappedRoot =
            rootsCapParent + QStringLiteral("/root-%1").arg(index, 2, 10, QLatin1Char('0'));
        require(QDir().mkpath(cappedRoot), "root-cap fixture is created");
        rootsOverCap.append(cappedRoot);
    }
    const auto rootsCapResult = scan(scanner, rootsOverCap);
    require(rootsCapResult.status == QStringLiteral("ready")
                && rootsCapResult.directories.size() == nagi::wallpaper::MaximumLibraryRoots
                && rootsCapResult.watchedDirectories.size()
                    == nagi::wallpaper::MaximumLibraryRoots,
            "only the first eight approved roots become models and watches");

    const QString directoryCapRoot = temporary.filePath(QStringLiteral("DirectoryCap"));
    require(QDir().mkpath(directoryCapRoot), "directory-cap root is created");
    for (int index = 0; index < nagi::wallpaper::MaximumLibraryDirectories + 8; ++index) {
        require(
            QDir().mkpath(
                directoryCapRoot
                + QStringLiteral("/directory-%1").arg(index, 3, 10, QLatin1Char('0'))),
            "directory-cap fixture is created");
    }
    const auto directoryCapResult = scan(scanner, {directoryCapRoot});
    require(directoryCapResult.status == QStringLiteral("truncated")
                && directoryCapResult.truncated
                && directoryCapResult.directories.size()
                    == nagi::wallpaper::MaximumLibraryDirectories
                && directoryCapResult.watchedDirectories.size()
                    == nagi::wallpaper::MaximumWatchedDirectories,
            "directory and watch projections stop exactly at their 512-entry caps");

    const QString traversalCapRoot = temporary.filePath(QStringLiteral("TraversalCap"));
    require(QDir().mkpath(traversalCapRoot), "traversal-cap root is created");
    for (int index = 0; index < nagi::wallpaper::MaximumTraversalEntries + 1; ++index) {
        createSizedFile(
            traversalCapRoot
                + QStringLiteral("/entry-%1.txt").arg(index, 4, 10, QLatin1Char('0')),
            1);
    }
    const auto traversalCapResult = scan(scanner, {traversalCapRoot});
    require(traversalCapResult.status == QStringLiteral("truncated")
                && traversalCapResult.truncated
                && traversalCapResult.visitedEntries
                    == nagi::wallpaper::MaximumTraversalEntries,
            "traversal stops exactly at 4096 visited entries");


    QTemporaryDir cacheRoot;
    require(cacheRoot.isValid(), "temporary cache is available");
    const QString versionedCache = cacheRoot.filePath(QStringLiteral("wallpaper-v1"));
    nagi::wallpaper::ThumbnailCache cache(versionedCache);
    require(QDir(versionedCache).entryList(QDir::Files).isEmpty(),
            "indexing performs no eager thumbnail or full-resolution decode");
    const QString source = root + QStringLiteral("/root.png");
    const auto first = cache.load(source);
    require(first.accepted && first.status == QStringLiteral("Ready")
                && first.dataUrl.startsWith(QStringLiteral("data:image/png;base64,"))
                && first.digest.size() == 32 && first.accent == QStringLiteral("#D94A38"),
            "thumbnail and palette decode stays bounded behind one helper API");
    const QFileInfoList firstEntries = QDir(versionedCache).entryInfoList(
        {QStringLiteral("*.png")}, QDir::Files);
    require(firstEntries.size() == 1 && firstEntries.first().size() < nagi::wallpaper::MaximumImageBytes,
            "one atomic versioned disk entry is written lazily");
    require((firstEntries.first().permissions()
             & (QFileDevice::ReadGroup | QFileDevice::WriteGroup | QFileDevice::ReadOther
                | QFileDevice::WriteOther)) == QFileDevice::Permissions{},
            "thumbnail cache entries remain private");
    const auto second = cache.load(source);
    require(second.accepted && second.digest == first.digest && second.dataUrl == first.dataUrl,
            "unchanged sources reuse the memory or disk cache deterministically");

    copyFile(fixtures + QStringLiteral("/oversized.png"), source);
    const auto changed = cache.load(source);
    require(changed.accepted && changed.digest != first.digest
                && QDir(versionedCache).entryList({QStringLiteral("*.png")}, QDir::Files).size() == 2,
            "changed bytes invalidate the prior cache identity without stale reuse");
    const auto corrupt = cache.load(root + QStringLiteral("/corrupt.png"));
    require(!corrupt.accepted, "malformed image input is rejected without escaping the helper");
    const auto cancelled = cache.load(source, [] { return true; });
    require(!cancelled.accepted && cancelled.status == QStringLiteral("Cancelled"),
            "decode cancellation is observable before image work");
    const QString churnRoot = temporary.filePath(QStringLiteral("Churn"));
    require(QDir().mkpath(churnRoot), "file-churn root is created");
    const QString churnImage = churnRoot + QStringLiteral("/candidate.png");
    const QString churnCorrupt = churnRoot + QStringLiteral("/corrupt.png");
    const QString churnOversized = churnRoot + QStringLiteral("/over-limit.png");
    const auto churnBefore = scan(scanner, {churnRoot});
    require(churnBefore.status == QStringLiteral("ready") && churnBefore.images.isEmpty()
                && churnBefore.directories.size() == 1
                && churnBefore.watchedDirectories.size() == 1
                && churnBefore.visitedEntries == 0,
            "file churn starts from one empty watched root");
    for (int cycle = 0; cycle < SoakCycleCount; ++cycle) {
        const QString validFixture = fixtures
            + (cycle % 2 == 0 ? QStringLiteral("/colorful.png")
                              : QStringLiteral("/oversized.png"));
        copyFile(validFixture, churnImage);
        copyFile(fixtures + QStringLiteral("/malformed.png"), churnCorrupt);
        createSizedFile(churnOversized, nagi::wallpaper::MaximumImageBytes + 1);

        const auto churnPresent = scan(scanner, {churnRoot});
        require(churnPresent.status == QStringLiteral("ready") && !churnPresent.truncated
                    && churnPresent.images.size() == 1
                    && churnPresent.images.first().name == QStringLiteral("candidate.png")
                    && churnPresent.directories.size() == 1
                    && churnPresent.watchedDirectories.size() == 1
                    && churnPresent.visitedEntries == 3,
                "each churn cycle projects only its one valid bounded image");
        const auto valid = cache.load(churnImage);
        const auto malformed = cache.load(churnCorrupt);
        const auto overLimit = cache.load(churnOversized);
        require(valid.accepted && valid.status == QStringLiteral("Ready")
                    && !malformed.accepted && malformed.status == QStringLiteral("Malformed")
                    && !overLimit.accepted && overLimit.status == QStringLiteral("Oversized"),
                "each churn cycle accepts scaled images and rejects corrupt or over-limit bytes");

        require(QFile::remove(churnImage) && QFile::remove(churnCorrupt)
                    && QFile::remove(churnOversized),
                "file-churn fixtures are removed");
        const auto churnAfter = scan(scanner, {churnRoot});
        require(churnAfter.status == QStringLiteral("ready") && churnAfter.images.isEmpty()
                    && churnAfter.directories.size() == 1
                    && churnAfter.watchedDirectories.size() == 1
                    && churnAfter.visitedEntries == 0,
                "each churn cycle returns to the exact pre-cycle library and watch counts");
        require(QDir(versionedCache).entryList({QStringLiteral("*.png")}, QDir::Files).size() == 2,
                "repeated source identities do not grow the private disk cache");
    }


    nagi::wallpaper::LibraryScanner cancelledScanner;
    QEventLoop cancellationLoop;
    QTimer cancellationTimeout;
    QElapsedTimer cancellationElapsed;
    cancellationTimeout.setSingleShot(true);
    cancellationTimeout.setInterval(10000);
    QObject::connect(&cancellationTimeout, &QTimer::timeout, &cancellationLoop, [&] {
        require(false, "page-close cancellation timed out");
    });
    bool cancellationRequested = false;
    int cancellationFinishedCount = 0;
    qint64 cancellationMilliseconds = -1;
    QObject::connect(
        &cancelledScanner,
        &nagi::wallpaper::LibraryScanner::progressChanged,
        &cancellationLoop,
        [&] {
            if (!cancellationRequested && cancelledScanner.running()) {
                cancellationRequested = true;
                cancellationElapsed.start();
                cancelledScanner.cancel();
            }
        });
    QObject::connect(
        &cancelledScanner,
        &nagi::wallpaper::LibraryScanner::finished,
        &cancellationLoop,
        [&] {
            cancellationFinishedCount += 1;
            if (cancellationRequested) {
                cancellationMilliseconds = cancellationElapsed.elapsed();
            }
            cancellationLoop.quit();
        });
    cancellationTimeout.start();
    cancelledScanner.start({root});
    cancellationLoop.exec();
    cancellationTimeout.stop();
    require(cancellationRequested && cancellationFinishedCount == 1
                && !cancelledScanner.running() && cancelledScanner.result().cancelled
                && cancelledScanner.result().status == QStringLiteral("cancelled")
                && cancelledScanner.result().visitedEntries
                    == nagi::wallpaper::MaximumEntriesPerSlice
                && cancellationMilliseconds >= 0
                && cancellationMilliseconds <= PageCloseBudgetMilliseconds,
            "page close cancels active indexing within 250 ms with one terminal result");

    const QString linkedRoot = temporary.filePath(QStringLiteral("linked-root"));
    require(QFile::link(root, linkedRoot), "root symlink fixture is created");
    const auto linkedRootResult = scan(scanner, {linkedRoot});
    require(linkedRootResult.images.isEmpty() && linkedRootResult.directories.isEmpty(),
            "approved root symlinks fail closed");

    require(nagi::wallpaper::MaximumMemoryCacheBytes == 8 * 1024 * 1024
                && nagi::wallpaper::MaximumDiskCacheBytes == 64LL * 1024 * 1024
                && nagi::wallpaper::MaximumDiskCacheEntries == 512
                && nagi::wallpaper::ThumbnailCacheVersion == 1,
            "cache memory, disk, entry, and version budgets remain measured and explicit");
    const QString entryBoundCachePath =
        cacheRoot.filePath(QStringLiteral("wallpaper-entry-bound"));
    require(QDir().mkpath(entryBoundCachePath), "entry-bound cache root is created");
    for (int index = 0; index < nagi::wallpaper::MaximumDiskCacheEntries + 1; ++index) {
        createSizedFile(
            entryBoundCachePath
                + QLatin1Char('/')
                + QStringLiteral("%1.png").arg(index, 64, 16, QLatin1Char('0')),
            1);
    }
    const QFileInfoList entriesBefore = QDir(entryBoundCachePath).entryInfoList(
        {QStringLiteral("*.png")}, QDir::Files);
    require(entriesBefore.size() == nagi::wallpaper::MaximumDiskCacheEntries + 1
                && fileBytes(entriesBefore) == nagi::wallpaper::MaximumDiskCacheEntries + 1,
            "entry-bound cache starts one file over its fixed cap");
    nagi::wallpaper::ThumbnailCache entryBoundCache(entryBoundCachePath);
    entryBoundCache.cleanup();
    const QFileInfoList entriesAfter = QDir(entryBoundCachePath).entryInfoList(
        {QStringLiteral("*.png")}, QDir::Files);
    require(entriesAfter.size() == nagi::wallpaper::MaximumDiskCacheEntries
                && fileBytes(entriesAfter) == nagi::wallpaper::MaximumDiskCacheEntries,
            "private disk LRU returns exactly to its 512-entry cap");

    constexpr qint64 CacheMiB = 1024 * 1024;
    const QString byteBoundCachePath = cacheRoot.filePath(QStringLiteral("wallpaper-byte-bound"));
    require(QDir().mkpath(byteBoundCachePath), "byte-bound cache root is created");
    const int byteBoundEntryCount =
        static_cast<int>(nagi::wallpaper::MaximumDiskCacheBytes / CacheMiB) + 1;
    for (int index = 0; index < byteBoundEntryCount; ++index) {
        createSizedFile(
            byteBoundCachePath
                + QLatin1Char('/')
                + QStringLiteral("%1.png").arg(index, 64, 16, QLatin1Char('0')),
            CacheMiB);
    }
    const QFileInfoList bytesBefore = QDir(byteBoundCachePath).entryInfoList(
        {QStringLiteral("*.png")}, QDir::Files);
    require(bytesBefore.size() == byteBoundEntryCount
                && fileBytes(bytesBefore) == nagi::wallpaper::MaximumDiskCacheBytes + CacheMiB,
            "byte-bound cache starts one MiB over its fixed cap");
    nagi::wallpaper::ThumbnailCache byteBoundCache(byteBoundCachePath);
    byteBoundCache.cleanup();
    const QFileInfoList bytesAfter = QDir(byteBoundCachePath).entryInfoList(
        {QStringLiteral("*.png")}, QDir::Files);
    require(bytesAfter.size() == byteBoundEntryCount - 1
                && fileBytes(bytesAfter) == nagi::wallpaper::MaximumDiskCacheBytes,
            "private disk LRU returns exactly to its 64 MiB byte cap");


    std::puts("wallpaper library tests passed");
    return 0;
}

#include "library.h"

#include <QCoreApplication>
#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QTemporaryDir>
#include <QTimer>

#include <cstdio>
#include <cstdlib>

namespace {

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

nagi::wallpaper::LibraryScanResult scan(
    nagi::wallpaper::LibraryScanner &scanner,
    const QStringList &roots,
    int *progressCount = nullptr)
{
    QEventLoop loop;
    QTimer timeout;
    timeout.setSingleShot(true);
    timeout.setInterval(10000);
    QObject::connect(&timeout, &QTimer::timeout, &loop, [&] {
        std::fprintf(stderr, "wallpaper library test timed out\n");
        std::exit(1);
    });
    QMetaObject::Connection progress;
    if (progressCount != nullptr) {
        progress = QObject::connect(
            &scanner,
            &nagi::wallpaper::LibraryScanner::progressChanged,
            &loop,
            [progressCount] { *progressCount += 1; });
    }
    const QMetaObject::Connection done = QObject::connect(
        &scanner, &nagi::wallpaper::LibraryScanner::finished, &loop, &QEventLoop::quit);
    timeout.start();
    scanner.start(roots);
    loop.exec();
    timeout.stop();
    QObject::disconnect(done);
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
    int progressCount = 0;
    const auto result = scan(scanner, {root}, &progressCount);
    require(result.status == QStringLiteral("truncated") && result.truncated,
            "image-count bound is explicit and observable");
    require(result.images.size() == nagi::wallpaper::MaximumLibraryImages,
            "library image projection stops at the fixed bound");
    require(result.visitedEntries <= nagi::wallpaper::MaximumTraversalEntries,
            "visited entry count stays within the traversal budget");
    require(result.directories.size() <= nagi::wallpaper::MaximumLibraryDirectories
                && result.watchedDirectories.size() <= nagi::wallpaper::MaximumWatchedDirectories,
            "directory and watcher models remain bounded");
    require(progressCount > 1, "large traversal yields across multiple event-loop slices");
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

    nagi::wallpaper::LibraryScanner cancelledScanner;
    bool cancelledFinished = false;
    QObject::connect(
        &cancelledScanner,
        &nagi::wallpaper::LibraryScanner::finished,
        &application,
        [&cancelledFinished] { cancelledFinished = true; });
    cancelledScanner.start({root});
    cancelledScanner.cancel();
    require(cancelledFinished && cancelledScanner.result().cancelled
                && cancelledScanner.result().status == QStringLiteral("cancelled"),
            "indexing cancellation releases page-owned traversal immediately");

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

    std::puts("wallpaper library tests passed");
    return 0;
}

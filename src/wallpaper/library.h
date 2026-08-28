#pragma once

#include "analyzer.h"

#include <QByteArray>
#include <QCache>
#include <QDateTime>
#include <QElapsedTimer>
#include <QDirIterator>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVector>

#include <functional>
#include <memory>

namespace nagi::wallpaper {

constexpr int MaximumLibraryRoots = 8;
constexpr int MaximumRootBytes = 1024;
constexpr int MaximumTraversalDepth = 8;
constexpr int MaximumTraversalEntries = 4096;
constexpr int MaximumLibraryImages = 512;
constexpr int MaximumLibraryDirectories = 512;
constexpr int MaximumEntriesPerSlice = 64;
constexpr int MaximumIndexMilliseconds = 3000;
constexpr int MaximumWatchedDirectories = 512;
constexpr int MaximumThumbnailEdge = 320;
constexpr int MaximumMemoryCacheBytes = 8 * 1024 * 1024;
constexpr qint64 MaximumDiskCacheBytes = 64 * 1024 * 1024;
constexpr int MaximumDiskCacheEntries = 512;
constexpr int ThumbnailCacheVersion = 1;

struct LibraryDirectory {
    QString id;
    QString parentId;
    QString name;
    QString breadcrumb;
    QString rootId;
};

struct LibraryImage {
    QString id;
    QString directoryId;
    QString name;
    QString path;
    qint64 byteSize = 0;
    qint64 modifiedMilliseconds = 0;
    int width = 0;
    int height = 0;
};

struct LibraryScanResult {
    QVector<LibraryDirectory> directories;
    QVector<LibraryImage> images;
    QStringList watchedDirectories;
    QString status = QStringLiteral("idle");
    int visitedEntries = 0;
    qint64 elapsedMilliseconds = 0;
    bool truncated = false;
    bool cancelled = false;
};

class LibraryScanner final : public QObject {
    Q_OBJECT

public:
    explicit LibraryScanner(QObject *parent = nullptr);
    ~LibraryScanner() override;

    void start(const QStringList &roots);
    void cancel();
    [[nodiscard]] bool running() const;
    [[nodiscard]] const LibraryScanResult &result() const;

signals:
    void progressChanged();
    void finished();

private:
    struct PendingDirectory {
        QString path;
        QString id;
        QString rootId;
        QString breadcrumb;
        int depth = 0;
    };

    void reset();
    void processSlice();
    bool beginNextDirectory();
    void acceptEntry(const QFileInfo &info);
    void finish(QString status, bool truncated = false);
    QString directoryId(const QString &path) const;
    QString imageId(const QFileInfo &info) const;

    QVector<PendingDirectory> pendingDirectories;
    std::unique_ptr<QDirIterator> iterator;
    PendingDirectory currentDirectory;
    LibraryScanResult scanResult;
    QElapsedTimer elapsed;
    quint64 generation = 0;
    bool isRunning = false;
};

struct ThumbnailResult {
    bool accepted = false;
    QString status;
    QString dataUrl;
    QString accent;
    QByteArray digest;
    int width = 0;
    int height = 0;
};

class ThumbnailCache final {
public:
    explicit ThumbnailCache(QString cacheRoot = {});

    ThumbnailResult load(
        const QString &path,
        const std::function<bool()> &cancelled = {},
        bool includePalette = true);
    void cleanup();
    [[nodiscard]] QString cacheDirectory() const;

private:
    QString cacheKey(const QByteArray &digest) const;
    QString cachePath(const QString &key) const;
    QByteArray readDisk(const QString &key);
    void writeDisk(const QString &key, const QByteArray &bytes);
    void touch(const QString &path) const;

    QString directory;
    QCache<QString, QByteArray> memory;
};

} // namespace nagi::wallpaper

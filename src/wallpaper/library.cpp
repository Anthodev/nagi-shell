#include "library.h"

#include <QBuffer>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QImageReader>
#include <QImageWriter>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>

#include <algorithm>

namespace nagi::wallpaper {
namespace {

constexpr qsizetype MaximumPathCharacters = 4096;

QString opaqueId(const char prefix, const QByteArray &material)
{
    const QByteArray digest = QCryptographicHash::hash(material, QCryptographicHash::Sha256)
                                  .toHex()
                                  .left(24);
    return QString(QChar::fromLatin1(prefix)) + QString::fromLatin1(digest);
}

bool supportedSuffix(const QString &suffix)
{
    const QString normalized = suffix.toLower();
    return normalized == QStringLiteral("jpg") || normalized == QStringLiteral("jpeg")
        || normalized == QStringLiteral("png") || normalized == QStringLiteral("webp")
        || normalized == QStringLiteral("bmp");
}

QString cleanRoot(const QString &candidate)
{
    if (candidate.isEmpty() || candidate.toUtf8().size() > MaximumRootBytes) {
        return {};
    }
    const QFileInfo info(candidate);
    if (!info.isAbsolute() || !info.exists() || !info.isDir() || info.isSymLink()
        || !info.isReadable()) {
        return {};
    }
    const QString absolute = QDir::cleanPath(info.absoluteFilePath());
    const QString canonical = info.canonicalFilePath();
    return canonical.isEmpty() || canonical != absolute
            || canonical.size() > MaximumPathCharacters
        ? QString{}
        : canonical;
}

QString rootName(const QString &path)
{
    const QFileInfo info(path);
    const QString name = info.fileName();
    return name.isEmpty() ? path : name;
}

QByteArray thumbnailBytes(const QString &path, int *width, int *height)
{
    QImageReader reader(path);
    reader.setDecideFormatFromContent(true);
    if (!reader.canRead() || reader.supportsAnimation()) {
        return {};
    }
    const QSize original = reader.size();
    if (!original.isValid() || original.isEmpty()) {
        return {};
    }
    if (width != nullptr) {
        *width = original.width();
    }
    if (height != nullptr) {
        *height = original.height();
    }
    const QSize target(MaximumThumbnailEdge, MaximumThumbnailEdge * 9 / 16);
    reader.setScaledSize(original.scaled(target, Qt::KeepAspectRatioByExpanding));
    QImage image = reader.read();
    if (image.isNull()) {
        return {};
    }
    if (image.width() > target.width() || image.height() > target.height()) {
        const int x = std::max(0, (image.width() - target.width()) / 2);
        const int y = std::max(0, (image.height() - target.height()) / 2);
        image = image.copy(x, y, std::min(target.width(), image.width()),
                           std::min(target.height(), image.height()));
    }
    image = image.convertToFormat(QImage::Format_RGB32);
    QByteArray encoded;
    QBuffer buffer(&encoded);
    if (!buffer.open(QIODevice::WriteOnly)) {
        return {};
    }
    QImageWriter writer(&buffer, "png");
    writer.setCompression(6);
    return writer.write(image) ? encoded : QByteArray{};
}

} // namespace

LibraryScanner::LibraryScanner(QObject *parent)
    : QObject(parent)
{
}

LibraryScanner::~LibraryScanner()
{
    cancel();
}

void LibraryScanner::reset()
{
    iterator.reset();
    pendingDirectories.clear();
    scanResult = {};
}

void LibraryScanner::start(const QStringList &roots)
{
    cancel();
    reset();
    generation += 1;
    QSet<QString> seenRoots;
    const qsizetype rootCount = std::min<qsizetype>(roots.size(), MaximumLibraryRoots);
    for (qsizetype index = 0; index < rootCount; ++index) {
        const QString canonical = cleanRoot(roots.at(index));
        if (canonical.isEmpty() || seenRoots.contains(canonical)) {
            continue;
        }
        seenRoots.insert(canonical);
        const QString id = directoryId(canonical);
        const QString label = rootName(canonical);
        scanResult.directories.append({id, {}, label, label, id});
        scanResult.watchedDirectories.append(canonical);
        pendingDirectories.append({canonical, id, id, label, 0});
    }
    scanResult.status = pendingDirectories.isEmpty() ? QStringLiteral("empty")
                                                     : QStringLiteral("indexing");
    elapsed.start();
    isRunning = true;
    const quint64 token = generation;
    QTimer::singleShot(0, this, [this, token] {
        if (token != generation) {
            return;
        }
        if (pendingDirectories.isEmpty()) {
            finish(QStringLiteral("empty"));
        } else {
            processSlice();
        }
    });
}

void LibraryScanner::cancel()
{
    generation += 1;
    iterator.reset();
    pendingDirectories.clear();
    if (isRunning) {
        isRunning = false;
        scanResult.cancelled = true;
        scanResult.status = QStringLiteral("cancelled");
        scanResult.elapsedMilliseconds = elapsed.isValid() ? elapsed.elapsed() : 0;
        emit finished();
    }
}

bool LibraryScanner::running() const
{
    return isRunning;
}

const LibraryScanResult &LibraryScanner::result() const
{
    return scanResult;
}

bool LibraryScanner::beginNextDirectory()
{
    while (!pendingDirectories.isEmpty()) {
        currentDirectory = pendingDirectories.takeFirst();
        if (currentDirectory.depth > MaximumTraversalDepth) {
            scanResult.truncated = true;
            continue;
        }
        iterator = std::make_unique<QDirIterator>(
            currentDirectory.path,
            QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot | QDir::Readable | QDir::NoSymLinks,
            QDirIterator::NoIteratorFlags);
        return true;
    }
    return false;
}

void LibraryScanner::acceptEntry(const QFileInfo &info)
{
    if (info.absoluteFilePath().size() > MaximumPathCharacters || info.isSymLink()) {
        return;
    }
    const QString canonical = info.canonicalFilePath();
    if (canonical.isEmpty() || canonical.size() > MaximumPathCharacters) {
        return;
    }
    if (info.isDir()) {
        if (scanResult.directories.size() >= MaximumLibraryDirectories
            || currentDirectory.depth >= MaximumTraversalDepth) {
            scanResult.truncated = true;
            return;
        }
        const QString id = directoryId(canonical);
        const auto duplicate = std::find_if(
            scanResult.directories.cbegin(), scanResult.directories.cend(),
            [&id](const LibraryDirectory &directory) { return directory.id == id; });
        if (duplicate != scanResult.directories.cend()) {
            return;
        }
        const QString label = info.fileName();
        const QString breadcrumb = currentDirectory.breadcrumb + QStringLiteral(" / ") + label;
        scanResult.directories.append(
            {id, currentDirectory.id, label, breadcrumb, currentDirectory.rootId});
        if (scanResult.watchedDirectories.size() < MaximumWatchedDirectories) {
            scanResult.watchedDirectories.append(canonical);
        }
        pendingDirectories.append(
            {canonical, id, currentDirectory.rootId, breadcrumb, currentDirectory.depth + 1});
        return;
    }
    if (!info.isFile() || !supportedSuffix(info.suffix()) || info.size() <= 0
        || info.size() > MaximumImageBytes || scanResult.images.size() >= MaximumLibraryImages) {
        if (scanResult.images.size() >= MaximumLibraryImages) {
            scanResult.truncated = true;
        }
        return;
    }
    QImageReader reader(canonical);
    reader.setDecideFormatFromContent(true);
    if (!reader.canRead() || reader.supportsAnimation()) {
        return;
    }
    const QSize size = reader.size();
    if (!size.isValid() || size.isEmpty()) {
        return;
    }
    scanResult.images.append({
        imageId(info),
        currentDirectory.id,
        info.fileName().left(255),
        canonical,
        info.size(),
        info.lastModified().toMSecsSinceEpoch(),
        size.width(),
        size.height(),
    });
}

void LibraryScanner::processSlice()
{
    if (!isRunning) {
        return;
    }
    int processed = 0;
    while (processed < MaximumEntriesPerSlice) {
        if (elapsed.elapsed() >= MaximumIndexMilliseconds
            || scanResult.visitedEntries >= MaximumTraversalEntries) {
            finish(QStringLiteral("truncated"), true);
            return;
        }
        if (!iterator && !beginNextDirectory()) {
            finish(scanResult.truncated ? QStringLiteral("truncated") : QStringLiteral("ready"),
                   scanResult.truncated);
            return;
        }
        if (!iterator->hasNext()) {
            iterator.reset();
            continue;
        }
        iterator->next();
        acceptEntry(iterator->fileInfo());
        scanResult.visitedEntries += 1;
        processed += 1;
    }
    scanResult.elapsedMilliseconds = elapsed.elapsed();
    emit progressChanged();
    const quint64 token = generation;
    QTimer::singleShot(0, this, [this, token] {
        if (token == generation) {
            processSlice();
        }
    });
}

void LibraryScanner::finish(QString status, bool truncated)
{
    iterator.reset();
    pendingDirectories.clear();
    isRunning = false;
    scanResult.status = std::move(status);
    scanResult.truncated = scanResult.truncated || truncated;
    scanResult.elapsedMilliseconds = elapsed.isValid() ? elapsed.elapsed() : 0;
    emit finished();
}

QString LibraryScanner::directoryId(const QString &path) const
{
    return opaqueId('d', path.toUtf8());
}

QString LibraryScanner::imageId(const QFileInfo &info) const
{
    QByteArray material = info.canonicalFilePath().toUtf8();
    material.append('\0');
    material.append(QByteArray::number(info.size()));
    material.append('\0');
    material.append(QByteArray::number(info.lastModified().toMSecsSinceEpoch()));
    return opaqueId('i', material);
}

ThumbnailCache::ThumbnailCache(QString cacheRoot)
    : directory(std::move(cacheRoot))
{
    memory.setMaxCost(MaximumMemoryCacheBytes);
    if (directory.isEmpty()) {
        directory = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
            + QStringLiteral("/nagi-shell/wallpaper-v") + QString::number(ThumbnailCacheVersion);
    }
    QDir().mkpath(directory);
    QFile::setPermissions(
        directory,
        QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
    cleanup();
}

ThumbnailResult ThumbnailCache::load(
    const QString &path,
    const std::function<bool()> &cancelled,
    bool includePalette)
{
    ThumbnailResult output;
    const FingerprintResult fingerprint = fingerprintSource(path, cancelled);
    if (!fingerprint.validation.accepted) {
        output.status = fingerprint.validation.status;
        return output;
    }
    if (cancelled && cancelled()) {
        output.status = QStringLiteral("Cancelled");
        return output;
    }
    QImageReader metadata(path);
    metadata.setDecideFormatFromContent(true);
    const QSize sourceSize = metadata.size();
    if (!metadata.canRead() || metadata.supportsAnimation() || !sourceSize.isValid()
        || sourceSize.isEmpty()) {
        output.status = QStringLiteral("Malformed");
        return output;
    }
    output.width = sourceSize.width();
    output.height = sourceSize.height();
    const QString key = cacheKey(fingerprint.digest);
    QByteArray encoded;
    if (const QByteArray *cached = memory.object(key); cached != nullptr) {
        encoded = *cached;
    } else {
        encoded = readDisk(key);
        if (encoded.isEmpty()) {
            encoded = thumbnailBytes(path, &output.width, &output.height);
            if (encoded.isEmpty()) {
                output.status = QStringLiteral("Malformed");
                return output;
            }
            writeDisk(key, encoded);
        }
        memory.insert(key, new QByteArray(encoded), encoded.size());
    }
    if (includePalette) {
        const SourceResult palette = analyzeVerifiedSource(path, fingerprint.digest, cancelled);
        if (palette.analysis.status == QStringLiteral("Cancelled")) {
            output.status = palette.analysis.status;
            return output;
        }
        output.accent = palette.analysis.accepted ? palette.analysis.accent : QString{};
    }
    output.accepted = true;
    output.status = QStringLiteral("Ready");
    output.dataUrl = QStringLiteral("data:image/png;base64,")
        + QString::fromLatin1(encoded.toBase64());
    output.accent = includePalette ? output.accent : QString{};
    output.digest = fingerprint.digest;
    return output;
}

void ThumbnailCache::cleanup()
{
    QDir cache(directory);
    QFileInfoList entries = cache.entryInfoList(
        {QStringLiteral("*.png")}, QDir::Files | QDir::Readable, QDir::Unsorted);
    std::sort(entries.begin(), entries.end(), [](const QFileInfo &left, const QFileInfo &right) {
        return left.lastModified() > right.lastModified();
    });
    qint64 bytes = 0;
    int retained = 0;
    for (const QFileInfo &entry : entries) {
        const bool validName = entry.completeBaseName().size() == 64;
        if (!validName || retained >= MaximumDiskCacheEntries
            || bytes + entry.size() > MaximumDiskCacheBytes) {
            QFile::remove(entry.absoluteFilePath());
            continue;
        }
        bytes += entry.size();
        retained += 1;
    }
}

QString ThumbnailCache::cacheDirectory() const
{
    return directory;
}

QString ThumbnailCache::cacheKey(const QByteArray &digest) const
{
    return QString::fromLatin1(digest.toHex());
}

QString ThumbnailCache::cachePath(const QString &key) const
{
    return directory + QLatin1Char('/') + key + QStringLiteral(".png");
}

QByteArray ThumbnailCache::readDisk(const QString &key)
{
    QFile file(cachePath(key));
    if (!file.open(QIODevice::ReadOnly) || file.size() <= 0 || file.size() > MaximumImageBytes) {
        return {};
    }
    QByteArray bytes = file.readAll();
    touch(file.fileName());
    return bytes;
}

void ThumbnailCache::writeDisk(const QString &key, const QByteArray &bytes)
{
    if (bytes.isEmpty() || bytes.size() > MaximumImageBytes) {
        return;
    }
    QSaveFile file(cachePath(key));
    if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size() || !file.commit()) {
        file.cancelWriting();
        return;
    }
    QFile::setPermissions(file.fileName(), QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    cleanup();
}

void ThumbnailCache::touch(const QString &path) const
{
    QFile file(path);
    if (file.open(QIODevice::ReadOnly)) {
        file.setFileTime(QDateTime::currentDateTimeUtc(), QFileDevice::FileModificationTime);
    }
}

} // namespace nagi::wallpaper

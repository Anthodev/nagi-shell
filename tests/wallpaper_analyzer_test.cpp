#include "analyzer.h"

#include <QCoreApplication>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QFile>
#include <QTemporaryDir>

#include <atomic>
#include <condition_variable>

#include <cstdio>
#include <cstdlib>
#include <future>
#include <mutex>

namespace {

QJsonObject run(const QString &helper, const QString &path)
{
    QProcess process;
    process.start(helper, {QStringLiteral("--analyze"), path});
    if (!process.waitForStarted() || !process.waitForFinished(5000)
        || process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        return {};
    }
    return QJsonDocument::fromJson(process.readAllStandardOutput().trimmed()).object();
}

[[noreturn]] void fail(const char *message)
{
    std::fprintf(stderr, "wallpaper analyzer test failed: %s\n", message);
    std::exit(1);
}

void require(bool condition, const char *message)
{
    if (!condition) {
        fail(message);
    }
}

void expect(
    const QString &helper,
    const QDir &fixtures,
    const char *name,
    bool accepted,
    const char *status,
    const char *accent = "")
{
    const QJsonObject first = run(helper, fixtures.filePath(QString::fromLatin1(name)));
    const QJsonObject second = run(helper, fixtures.filePath(QString::fromLatin1(name)));
    require(!first.isEmpty() && first == second, "analysis is deterministic");
    require(first.value(QStringLiteral("accepted")).toBool() == accepted, "acceptance matches fixture");
    require(first.value(QStringLiteral("status")).toString() == QString::fromLatin1(status),
            "status matches fixture");
    require(first.value(QStringLiteral("accent")).toString() == QString::fromLatin1(accent),
            "accent matches fixture");
}

QByteArray readFile(const QString &path)
{
    QFile file(path);
    require(file.open(QIODevice::ReadOnly), "fixture opens");
    return file.readAll();
}

void rewriteFile(const QString &path, const QByteArray &contents)
{
    QFile file(path);
    require(file.open(QIODevice::WriteOnly | QIODevice::Truncate), "temporary source opens for rewrite");
    require(file.write(contents) == contents.size(), "temporary source rewrite completes");
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    if (argc != 3) {
        std::fprintf(stderr, "usage: wallpaper-analyzer-test <helper> <fixture-directory>\n");
        return 2;
    }
    const QString helper = QString::fromLocal8Bit(argv[1]);
    const QDir fixtures(QString::fromLocal8Bit(argv[2]));

    expect(helper, fixtures, "colorful.png", true, "Ready", "#D94A38");
    expect(helper, fixtures, "dark.png", false, "Unsuitable");
    expect(helper, fixtures, "light.png", false, "Unsuitable");
    expect(helper, fixtures, "neutral.png", false, "Unsuitable");
    expect(helper, fixtures, "oversized.png", true, "Ready", "#1E6FD9");
    expect(helper, fixtures, "malformed.png", false, "Malformed");
    expect(helper, fixtures, "missing.png", false, "Missing");

    const auto cancelled = nagi::wallpaper::analyzeSource(
        fixtures.filePath(QStringLiteral("oversized.png")), [] { return true; });
    require(!cancelled.analysis.accepted && cancelled.analysis.status == QStringLiteral("Cancelled"),
            "analysis cancellation is observable before decode");

    QTemporaryDir temporary;
    require(temporary.isValid(), "temporary directory is available");
    const QString sourcePath = temporary.filePath(QStringLiteral("source.png"));
    const QByteArray colorful = readFile(fixtures.filePath(QStringLiteral("colorful.png")));
    const QByteArray changed = readFile(fixtures.filePath(QStringLiteral("oversized.png")));
    rewriteFile(sourcePath, colorful);

    const auto originalFingerprint = nagi::wallpaper::fingerprintSource(sourcePath);
    require(originalFingerprint.validation.accepted, "fingerprint-only stage accepts a valid source");
    rewriteFile(sourcePath, colorful);
    const auto identicalFingerprint = nagi::wallpaper::fingerprintSource(sourcePath);
    require(identicalFingerprint.validation.accepted
                && identicalFingerprint.digest == originalFingerprint.digest,
            "identical byte rewrite retains the source fingerprint");
    int extractionCount = 0;
    if (identicalFingerprint.digest != originalFingerprint.digest) {
        nagi::wallpaper::analyzeVerifiedSource(
            sourcePath, identicalFingerprint.digest, {}, [&extractionCount] { extractionCount += 1; });
    }
    require(extractionCount == 0, "identical byte rewrite performs no extraction");

    rewriteFile(sourcePath, changed);
    const auto changedFingerprint = nagi::wallpaper::fingerprintSource(sourcePath);
    require(changedFingerprint.validation.accepted
                && changedFingerprint.digest != originalFingerprint.digest,
            "changed bytes produce a new source fingerprint");
    const auto changedAnalysis = nagi::wallpaper::analyzeVerifiedSource(
        sourcePath, changedFingerprint.digest, {}, [&extractionCount] { extractionCount += 1; });
    require(changedAnalysis.analysis.accepted && extractionCount == 1,
            "changed bytes perform exactly one extraction");

    rewriteFile(sourcePath, colorful);
    const auto beforeReplacement = nagi::wallpaper::fingerprintSource(sourcePath);
    extractionCount = 0;
    const auto replacedDuringAnalysis = nagi::wallpaper::analyzeVerifiedSource(
        sourcePath,
        beforeReplacement.digest,
        {},
        [&] {
            extractionCount += 1;
            rewriteFile(sourcePath, changed);
        });
    require(!replacedDuringAnalysis.analysis.accepted
                && replacedDuringAnalysis.analysis.status == QStringLiteral("Changed")
                && extractionCount == 1,
            "analysis rejects a source whose identity changes before publication");

    rewriteFile(sourcePath, colorful);
    const auto beforeCancellation = nagi::wallpaper::fingerprintSource(sourcePath);
    std::atomic_bool cancellationRequested = false;
    std::mutex barrierMutex;
    std::condition_variable barrier;
    bool extractionEntered = false;
    bool releaseExtraction = false;
    auto oldAnalysis = std::async(std::launch::async, [&] {
        return nagi::wallpaper::analyzeVerifiedSource(
            sourcePath,
            beforeCancellation.digest,
            [&] { return cancellationRequested.load(); },
            [&] {
                std::unique_lock lock(barrierMutex);
                extractionEntered = true;
                barrier.notify_one();
                barrier.wait(lock, [&] { return releaseExtraction; });
            });
    });
    {
        std::unique_lock lock(barrierMutex);
        barrier.wait(lock, [&] { return extractionEntered; });
        require(QFile::remove(sourcePath), "source deletion succeeds while old analysis is blocked");
        cancellationRequested.store(true);
        releaseExtraction = true;
    }
    barrier.notify_one();
    const auto cancelledOldAnalysis = oldAnalysis.get();
    require(!cancelledOldAnalysis.analysis.accepted
                && cancelledOldAnalysis.analysis.status == QStringLiteral("Cancelled"),
            "terminal source invalidation cancels a blocked old analysis");

    std::puts("wallpaper analyzer tests passed");
    return 0;
}

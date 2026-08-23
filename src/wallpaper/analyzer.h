#pragma once

#include <QByteArray>
#include <QString>
#include <QtTypes>

#include <functional>
class QObject;


namespace nagi::wallpaper {

constexpr qint64 MaximumImageBytes = 32 * 1024 * 1024;
constexpr int MaximumDecodeEdge = 128;

struct AnalysisResult {
    bool accepted = false;
    QString accent;
    QString status;
};

struct FingerprintResult {
    AnalysisResult validation;
    QByteArray digest;
};

struct SourceResult {
    AnalysisResult analysis;
    QByteArray digest;
};

FingerprintResult fingerprintSource(
    const QString &path,
    const std::function<bool()> &cancelled = {});
SourceResult analyzeVerifiedSource(
    const QString &path,
    const QByteArray &expectedDigest,
    const std::function<bool()> &cancelled = {},
    const std::function<void()> &extractionStarted = {});
SourceResult analyzeSource(
    const QString &path,
    const std::function<bool()> &cancelled = {},
    const std::function<void()> &extractionStarted = {});

#ifdef NAGI_WALLPAPER_TESTING
namespace testing {

using FingerprintFunction = std::function<FingerprintResult(
    const QString &,
    const std::function<bool()> &)>;
using AnalyzeFunction = std::function<SourceResult(
    const QString &,
    const QByteArray &,
    const std::function<bool()> &)>;
using SnapshotFunction = std::function<void(const QString &, quint64)>;
using WorkFinishedFunction = std::function<void()>;

void setObserverHooks(
    FingerprintFunction fingerprint,
    AnalyzeFunction analyze,
    SnapshotFunction snapshot,
    WorkFinishedFunction workFinished);
void resetObserverHooks();
QObject *createObserver();

} // namespace testing
#endif

} // namespace nagi::wallpaper

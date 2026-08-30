#pragma once

#include <QByteArray>
#include <QString>
#include <QVector>

#include <optional>

namespace nagi::kwin {

inline constexpr int SnapshotProtocolVersion = 1;
inline constexpr qsizetype MaximumSnapshotLength = 65536;
inline constexpr qsizetype MaximumDesktopCount = 256;
inline constexpr qsizetype MaximumDesktopIdLength = 1024;
inline constexpr qsizetype MaximumDesktopNameLength = 256;
inline constexpr qsizetype HelperEpochLength = 32;

struct Desktop {
    QString id;
    QString name;
    int position;

    bool operator==(const Desktop &) const = default;
};

bool isValidHelperEpoch(const QString &helperEpoch);
std::optional<QByteArray> canonicalizeScriptSnapshot(
    const QString &payload,
    const QString &helperEpoch,
    QString *error);
QByteArray unavailableSnapshotJson(const QString &helperEpoch);

class SnapshotDeduplicator final {
public:
    bool shouldPublish(const QByteArray &snapshot);

private:
    QByteArray lastSnapshot;
};

} // namespace nagi::kwin

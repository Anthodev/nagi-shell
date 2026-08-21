#pragma once

#include <QByteArray>
#include <QString>
#include <QVariant>
#include <QVector>

#include <optional>

namespace nagi::kwin {

struct Desktop {
    QString id;
    QString name;
    int position;

    bool operator==(const Desktop &) const = default;
};

struct SignedDesktopTuple {
    qint32 position;
    QString id;
    QString name;
};

struct UnsignedDesktopTuple {
    quint32 position;
    QString id;
    QString name;
};

std::optional<QVector<Desktop>> normalizeSignedDesktops(
    const QVector<SignedDesktopTuple> &tuples,
    QString *error);
std::optional<QVector<Desktop>> normalizeUnsignedDesktops(
    const QVector<UnsignedDesktopTuple> &tuples,
    QString *error);
std::optional<QVector<Desktop>> decodeDesktopTuples(
    const QVariant &value,
    QString *error);
std::optional<QByteArray> availableSnapshotJson(
    const QVector<Desktop> &desktops,
    const QString &currentId,
    QString *error);
QByteArray unavailableSnapshotJson();

} // namespace nagi::kwin

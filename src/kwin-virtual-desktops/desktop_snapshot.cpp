#include "desktop_snapshot.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QJsonValue>
#include <QSet>

#include <algorithm>
#include <cmath>
#include <initializer_list>

namespace nagi::kwin {
namespace {

void setError(QString *error, const QString &message)
{
    if (error != nullptr) {
        *error = message;
    }
}

bool hasExactKeys(const QJsonObject &object, std::initializer_list<const char *> keys)
{
    if (object.size() != static_cast<qsizetype>(keys.size())) {
        return false;
    }
    return std::all_of(keys.begin(), keys.end(), [&object](const char *key) {
        return object.contains(QString::fromLatin1(key));
    });
}

bool validBoundedString(
    const QJsonValue &value,
    qsizetype maximumLength,
    bool allowEmpty)
{
    if (!value.isString()) {
        return false;
    }
    const QString string = value.toString();
    return (allowEmpty || !string.isEmpty()) && string.size() <= maximumLength;
}

std::optional<QVector<Desktop>> decodeDesktops(const QJsonValue &value, QString *error)
{
    if (!value.isArray()) {
        setError(error, QStringLiteral("desktops is not an array"));
        return std::nullopt;
    }

    const QJsonArray array = value.toArray();
    if (array.isEmpty() || array.size() > MaximumDesktopCount) {
        setError(error, QStringLiteral("desktop count is out of bounds"));
        return std::nullopt;
    }

    QVector<Desktop> desktops;
    desktops.reserve(array.size());
    QSet<QString> ids;
    QSet<int> positions;

    for (const QJsonValue &entry : array) {
        if (!entry.isObject()) {
            setError(error, QStringLiteral("desktop entry is not an object"));
            return std::nullopt;
        }

        const QJsonObject object = entry.toObject();
        if (!hasExactKeys(object, {"id", "name", "position"})) {
            setError(error, QStringLiteral("desktop entry schema is invalid"));
            return std::nullopt;
        }
        if (!validBoundedString(
                object.value(QStringLiteral("id")),
                MaximumDesktopIdLength,
                false)) {
            setError(error, QStringLiteral("desktop ID is invalid"));
            return std::nullopt;
        }
        if (!validBoundedString(
                object.value(QStringLiteral("name")),
                MaximumDesktopNameLength,
                true)) {
            setError(error, QStringLiteral("desktop name is invalid"));
            return std::nullopt;
        }

        const QJsonValue positionValue = object.value(QStringLiteral("position"));
        if (!positionValue.isDouble()) {
            setError(error, QStringLiteral("desktop position is invalid"));
            return std::nullopt;
        }
        const double numericPosition = positionValue.toDouble();
        if (!std::isfinite(numericPosition) || std::floor(numericPosition) != numericPosition
            || numericPosition < 0 || numericPosition >= array.size()) {
            setError(error, QStringLiteral("desktop position is out of bounds"));
            return std::nullopt;
        }

        const QString id = object.value(QStringLiteral("id")).toString();
        const int position = static_cast<int>(numericPosition);
        if (ids.contains(id) || positions.contains(position)) {
            setError(error, QStringLiteral("desktop ID or position is duplicated"));
            return std::nullopt;
        }

        ids.insert(id);
        positions.insert(position);
        desktops.append({
            id,
            object.value(QStringLiteral("name")).toString(),
            position,
        });
    }

    std::sort(desktops.begin(), desktops.end(), [](const Desktop &left, const Desktop &right) {
        return left.position < right.position;
    });
    return desktops;
}

QJsonArray encodeDesktops(const QVector<Desktop> &desktops)
{
    QJsonArray array;
    for (const Desktop &desktop : desktops) {
        array.append(QJsonObject{
            {QStringLiteral("id"), desktop.id},
            {QStringLiteral("name"), desktop.name},
            {QStringLiteral("position"), desktop.position},
        });
    }
    return array;
}

QByteArray encodeWireSnapshot(
    const QString &helperEpoch,
    bool available,
    const QString &currentId,
    bool showTransient,
    const QVector<Desktop> &desktops)
{
    return QJsonDocument(QJsonObject{
                             {QStringLiteral("version"), SnapshotProtocolVersion},
                             {QStringLiteral("helperEpoch"), helperEpoch},
                             {QStringLiteral("available"), available},
                             {QStringLiteral("currentId"),
                              available ? QJsonValue(currentId) : QJsonValue(QJsonValue::Null)},
                             {QStringLiteral("showTransient"), showTransient},
                             {QStringLiteral("desktops"), encodeDesktops(desktops)},
                         })
        .toJson(QJsonDocument::Compact);
}

} // namespace

bool isValidHelperEpoch(const QString &helperEpoch)
{
    if (helperEpoch.size() != HelperEpochLength) {
        return false;
    }
    return std::all_of(helperEpoch.cbegin(), helperEpoch.cend(), [](QChar character) {
        return (character >= QLatin1Char('0') && character <= QLatin1Char('9'))
            || (character >= QLatin1Char('a') && character <= QLatin1Char('f'));
    });
}

std::optional<QByteArray> canonicalizeScriptSnapshot(
    const QString &payload,
    const QString &helperEpoch,
    QString *error)
{
    if (!isValidHelperEpoch(helperEpoch)) {
        setError(error, QStringLiteral("helper epoch is invalid"));
        return std::nullopt;
    }
    if (payload.isEmpty() || payload.size() > MaximumSnapshotLength) {
        setError(error, QStringLiteral("snapshot length is out of bounds"));
        return std::nullopt;
    }

    const QByteArray encodedPayload = payload.toUtf8();
    if (encodedPayload.size() > MaximumSnapshotLength) {
        setError(error, QStringLiteral("snapshot byte length is out of bounds"));
        return std::nullopt;
    }

    QJsonParseError parseError{};
    const QJsonDocument document = QJsonDocument::fromJson(encodedPayload, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        setError(error, QStringLiteral("snapshot JSON is invalid"));
        return std::nullopt;
    }

    const QJsonObject object = document.object();
    if (!hasExactKeys(object, {"available", "currentId", "showTransient", "desktops"})
        || !object.value(QStringLiteral("available")).isBool()
        || !object.value(QStringLiteral("showTransient")).isBool()) {
        setError(error, QStringLiteral("snapshot schema is invalid"));
        return std::nullopt;
    }

    const bool available = object.value(QStringLiteral("available")).toBool();
    const bool showTransient = object.value(QStringLiteral("showTransient")).toBool();
    const QJsonValue currentValue = object.value(QStringLiteral("currentId"));
    const QJsonValue desktopsValue = object.value(QStringLiteral("desktops"));

    if (!available) {
        if (!currentValue.isNull() || showTransient || !desktopsValue.isArray()
            || !desktopsValue.toArray().isEmpty()) {
            setError(error, QStringLiteral("unavailable snapshot is not canonical"));
            return std::nullopt;
        }
        return unavailableSnapshotJson(helperEpoch);
    }

    if (!validBoundedString(currentValue, MaximumDesktopIdLength, false)) {
        setError(error, QStringLiteral("current desktop ID is invalid"));
        return std::nullopt;
    }

    const auto desktops = decodeDesktops(desktopsValue, error);
    if (!desktops) {
        return std::nullopt;
    }

    const QString currentId = currentValue.toString();
    const bool currentResolves = std::any_of(
        desktops->cbegin(),
        desktops->cend(),
        [&currentId](const Desktop &desktop) { return desktop.id == currentId; });
    if (!currentResolves) {
        setError(error, QStringLiteral("current desktop does not resolve"));
        return std::nullopt;
    }

    const QByteArray snapshot = encodeWireSnapshot(
        helperEpoch,
        true,
        currentId,
        showTransient,
        *desktops);
    if (snapshot.size() > MaximumSnapshotLength) {
        setError(error, QStringLiteral("canonical snapshot length is out of bounds"));
        return std::nullopt;
    }
    return snapshot;
}

QByteArray unavailableSnapshotJson(const QString &helperEpoch)
{
    return encodeWireSnapshot(helperEpoch, false, {}, false, {});
}

bool SnapshotDeduplicator::shouldPublish(const QByteArray &snapshot)
{
    if (snapshot == lastSnapshot) {
        return false;
    }
    lastSnapshot = snapshot;
    return true;
}

} // namespace nagi::kwin

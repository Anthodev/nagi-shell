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

struct OutputProjection {
    QString name;
    QString currentId;
    bool showTransient;
};

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

std::optional<QVector<OutputProjection>> decodeOutputs(
    const QJsonValue &value,
    const QSet<QString> &desktopIds,
    QString *error)
{
    if (!value.isArray()) {
        setError(error, QStringLiteral("outputs is not an array"));
        return std::nullopt;
    }

    const QJsonArray array = value.toArray();
    if (array.isEmpty() || array.size() > MaximumOutputCount) {
        setError(error, QStringLiteral("output count is out of bounds"));
        return std::nullopt;
    }

    QVector<OutputProjection> outputs;
    outputs.reserve(array.size());
    QSet<QString> names;
    bool transientSeen = false;

    for (const QJsonValue &entry : array) {
        if (!entry.isObject()) {
            setError(error, QStringLiteral("output entry is not an object"));
            return std::nullopt;
        }

        const QJsonObject object = entry.toObject();
        if (!hasExactKeys(object, {"name", "currentId", "showTransient"})
            || !validBoundedString(
                object.value(QStringLiteral("name")),
                MaximumOutputNameLength,
                false)
            || !validBoundedString(
                object.value(QStringLiteral("currentId")),
                MaximumDesktopIdLength,
                false)
            || !object.value(QStringLiteral("showTransient")).isBool()) {
            setError(error, QStringLiteral("output entry schema is invalid"));
            return std::nullopt;
        }

        const QString name = object.value(QStringLiteral("name")).toString();
        const QString currentId = object.value(QStringLiteral("currentId")).toString();
        const bool showTransient = object.value(QStringLiteral("showTransient")).toBool();
        if (names.contains(name)) {
            setError(error, QStringLiteral("output name is duplicated"));
            return std::nullopt;
        }
        if (!desktopIds.contains(currentId)) {
            setError(error, QStringLiteral("output current desktop does not resolve"));
            return std::nullopt;
        }
        if (showTransient && transientSeen) {
            setError(error, QStringLiteral("multiple outputs request feedback"));
            return std::nullopt;
        }

        names.insert(name);
        transientSeen = transientSeen || showTransient;
        outputs.append({name, currentId, showTransient});
    }
    return outputs;
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

QJsonArray encodeOutputs(const QVector<OutputProjection> &outputs)
{
    QJsonArray array;
    for (const OutputProjection &output : outputs) {
        array.append(QJsonObject{
            {QStringLiteral("name"), output.name},
            {QStringLiteral("currentId"), output.currentId},
            {QStringLiteral("showTransient"), output.showTransient},
        });
    }
    return array;
}

QByteArray encodeWireSnapshot(
    const QString &helperEpoch,
    const QVector<Desktop> &desktops,
    const QVector<OutputProjection> &outputs)
{
    return QJsonDocument(QJsonObject{
                             {QStringLiteral("version"), SnapshotProtocolVersion},
                             {QStringLiteral("helperEpoch"), helperEpoch},
                             {QStringLiteral("desktops"), encodeDesktops(desktops)},
                             {QStringLiteral("outputs"), encodeOutputs(outputs)},
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
    if (!hasExactKeys(object, {"desktops", "outputs"})
        || !object.value(QStringLiteral("desktops")).isArray()
        || !object.value(QStringLiteral("outputs")).isArray()) {
        setError(error, QStringLiteral("snapshot schema is invalid"));
        return std::nullopt;
    }

    const QJsonArray desktopArray = object.value(QStringLiteral("desktops")).toArray();
    const QJsonArray outputArray = object.value(QStringLiteral("outputs")).toArray();
    if (desktopArray.isEmpty() || outputArray.isEmpty()) {
        if (!desktopArray.isEmpty() || !outputArray.isEmpty()) {
            setError(error, QStringLiteral("unavailable snapshot is not canonical"));
            return std::nullopt;
        }
        return unavailableSnapshotJson(helperEpoch);
    }

    const auto desktops = decodeDesktops(desktopArray, error);
    if (!desktops) {
        return std::nullopt;
    }

    QSet<QString> desktopIds;
    desktopIds.reserve(desktops->size());
    for (const Desktop &desktop : *desktops) {
        desktopIds.insert(desktop.id);
    }

    const auto outputs = decodeOutputs(outputArray, desktopIds, error);
    if (!outputs) {
        return std::nullopt;
    }

    const QByteArray snapshot = encodeWireSnapshot(helperEpoch, *desktops, *outputs);
    if (snapshot.size() > MaximumSnapshotLength) {
        setError(error, QStringLiteral("canonical snapshot length is out of bounds"));
        return std::nullopt;
    }
    return snapshot;
}

QByteArray unavailableSnapshotJson(const QString &helperEpoch)
{
    return encodeWireSnapshot(helperEpoch, {}, {});
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

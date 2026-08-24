#include "desktop_snapshot.h"

#include <QDBusArgument>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>

#include <algorithm>
#include <limits>
#include <type_traits>

namespace nagi::kwin {
namespace {

void setError(QString *error, const QString &message)
{
    if (error != nullptr) {
        *error = message;
    }
}

template<typename Tuple>
std::optional<QVector<Desktop>> normalizeDesktops(
    const QVector<Tuple> &tuples,
    QString *error)
{
    if (tuples.isEmpty()) {
        setError(error, QStringLiteral("desktop list is empty"));
        return std::nullopt;
    }

    QVector<Desktop> desktops;
    desktops.reserve(tuples.size());
    QSet<QString> ids;
    QSet<int> positions;

    for (const Tuple &tuple : tuples) {
        if (tuple.id.isEmpty()) {
            setError(error, QStringLiteral("desktop ID is empty"));
            return std::nullopt;
        }

        if constexpr (std::is_signed_v<decltype(tuple.position)>) {
            if (tuple.position < 0) {
                setError(error, QStringLiteral("desktop position is negative"));
                return std::nullopt;
            }
        }

        const quint64 position = static_cast<quint64>(tuple.position);
        if (position >= static_cast<quint64>(tuples.size())
            || position > static_cast<quint64>(std::numeric_limits<int>::max())) {
            setError(error, QStringLiteral("desktop position is out of range"));
            return std::nullopt;
        }

        const int normalizedPosition = static_cast<int>(position);
        if (ids.contains(tuple.id) || positions.contains(normalizedPosition)) {
            setError(error, QStringLiteral("desktop ID or position is duplicated"));
            return std::nullopt;
        }

        ids.insert(tuple.id);
        positions.insert(normalizedPosition);
        desktops.append({tuple.id, tuple.name, normalizedPosition});
    }

    std::sort(desktops.begin(), desktops.end(), [](const Desktop &left, const Desktop &right) {
        return left.position < right.position;
    });

    return desktops;
}

template<typename Position, typename Tuple>
std::optional<QVector<Desktop>> decodeArgument(const QDBusArgument &argument, QString *error)
{
    QVector<Tuple> tuples;
    argument.beginArray();
    while (!argument.atEnd()) {
        Position position;
        QString id;
        QString name;
        argument.beginStructure();
        argument >> position >> id >> name;
        argument.endStructure();
        tuples.append({position, id, name});
    }
    argument.endArray();

    if constexpr (std::is_signed_v<Position>) {
        return normalizeSignedDesktops(tuples, error);
    } else {
        return normalizeUnsignedDesktops(tuples, error);
    }
}

} // namespace

std::optional<QVector<Desktop>> normalizeSignedDesktops(
    const QVector<SignedDesktopTuple> &tuples,
    QString *error)
{
    return normalizeDesktops(tuples, error);
}

std::optional<QVector<Desktop>> normalizeUnsignedDesktops(
    const QVector<UnsignedDesktopTuple> &tuples,
    QString *error)
{
    return normalizeDesktops(tuples, error);
}

std::optional<QVector<Desktop>> decodeDesktopTuples(
    const QVariant &value,
    QString *error)
{
    if (value.metaType() != QMetaType::fromType<QDBusArgument>()) {
        setError(error, QStringLiteral("desktops property is not a D-Bus argument"));
        return std::nullopt;
    }

    const QDBusArgument argument = value.value<QDBusArgument>();
    const QString signature = argument.currentSignature();
    if (signature == QStringLiteral("a(iss)")) {
        return decodeArgument<qint32, SignedDesktopTuple>(argument, error);
    }
    if (signature == QStringLiteral("a(uss)")) {
        return decodeArgument<quint32, UnsignedDesktopTuple>(argument, error);
    }

    setError(error, QStringLiteral("desktops property has an unsupported signature"));
    return std::nullopt;
}

std::optional<QByteArray> availableSnapshotJson(
    const QVector<Desktop> &desktops,
    const QString &currentId,
    bool showTransient,
    QString *error)
{
    const auto current = std::find_if(
        desktops.cbegin(),
        desktops.cend(),
        [&currentId](const Desktop &desktop) { return desktop.id == currentId; });
    if (currentId.isEmpty() || current == desktops.cend()) {
        setError(error, QStringLiteral("current desktop does not resolve"));
        return std::nullopt;
    }

    QJsonArray desktopArray;
    for (const Desktop &desktop : desktops) {
        desktopArray.append(QJsonObject{
            {QStringLiteral("id"), desktop.id},
            {QStringLiteral("name"), desktop.name},
            {QStringLiteral("position"), desktop.position},
        });
    }

    return QJsonDocument(QJsonObject{
                             {QStringLiteral("available"), true},
                             {QStringLiteral("currentId"), currentId},
                             {QStringLiteral("showTransient"), showTransient},
                             {QStringLiteral("desktops"), desktopArray},
                         })
        .toJson(QJsonDocument::Compact);
}

QByteArray unavailableSnapshotJson()
{
    return QJsonDocument(QJsonObject{
                             {QStringLiteral("available"), false},
                             {QStringLiteral("currentId"), QJsonValue::Null},
                             {QStringLiteral("showTransient"), false},
                             {QStringLiteral("desktops"), QJsonArray{}},
                         })
        .toJson(QJsonDocument::Compact);
}

} // namespace nagi::kwin

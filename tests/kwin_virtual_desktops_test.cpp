#include "desktop_snapshot.h"

#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QStringList>

namespace {

constexpr auto Epoch = "0123456789abcdef0123456789abcdef";

bool require(bool condition, const char *message)
{
    if (!condition) {
        qCritical("FAIL: %s", message);
    }
    return condition;
}

QString compact(const QJsonObject &object)
{
    return QString::fromUtf8(QJsonDocument(object).toJson(QJsonDocument::Compact));
}

QJsonObject validAvailable()
{
    return QJsonObject{
        {QStringLiteral("available"), true},
        {QStringLiteral("currentId"), QStringLiteral("first")},
        {QStringLiteral("showTransient"), false},
        {QStringLiteral("desktops"),
         QJsonArray{
             QJsonObject{
                 {QStringLiteral("id"), QStringLiteral("second")},
                 {QStringLiteral("name"), QStringLiteral("Desktop 2")},
                 {QStringLiteral("position"), 1},
             },
             QJsonObject{
                 {QStringLiteral("id"), QStringLiteral("first")},
                 {QStringLiteral("name"), QStringLiteral("Desktop \"1\"\n")},
                 {QStringLiteral("position"), 0},
             },
         }},
    };
}

bool rejected(const QJsonObject &object)
{
    QString error;
    return !nagi::kwin::canonicalizeScriptSnapshot(compact(object), QString::fromLatin1(Epoch), &error)
        && !error.isEmpty();
}

bool hasExactWireKeys(const QJsonObject &object)
{
    const QStringList keys{
        QStringLiteral("available"),
        QStringLiteral("currentId"),
        QStringLiteral("desktops"),
        QStringLiteral("helperEpoch"),
        QStringLiteral("showTransient"),
        QStringLiteral("version"),
    };
    if (object.size() != keys.size()) {
        return false;
    }
    for (const QString &key : keys) {
        if (!object.contains(key)) {
            return false;
        }
    }
    return true;
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    using namespace nagi::kwin;

    QString error;
    const auto available = canonicalizeScriptSnapshot(
        compact(validAvailable()),
        QString::fromLatin1(Epoch),
        &error);
    if (!require(available.has_value(), "valid available snapshot canonicalizes")) {
        return 1;
    }

    const QJsonObject wire = QJsonDocument::fromJson(*available).object();
    const QJsonArray wireDesktops = wire.value(QStringLiteral("desktops")).toArray();
    if (!require(hasExactWireKeys(wire), "wire has exactly the version-1 keys")
        || !require(wire.value(QStringLiteral("version")).toInt() == 1, "wire version is one")
        || !require(
            wire.value(QStringLiteral("helperEpoch")).toString() == QString::fromLatin1(Epoch),
            "wire carries the process helper epoch")
        || !require(wire.value(QStringLiteral("available")).toBool(), "available state is preserved")
        || !require(wireDesktops.size() == 2, "complete desktop list is preserved")
        || !require(
            wireDesktops.at(0).toObject().value(QStringLiteral("id")).toString()
                == QStringLiteral("first"),
            "desktops are canonicalized by dense position")
        || !require(
            wireDesktops.at(0).toObject().value(QStringLiteral("name")).toString()
                == QStringLiteral("Desktop \"1\"\n"),
            "desktop names remain JSON escaped")) {
        return 1;
    }

    const QByteArray unavailable = unavailableSnapshotJson(QString::fromLatin1(Epoch));
    const QJsonObject unavailableWire = QJsonDocument::fromJson(unavailable).object();
    if (!require(hasExactWireKeys(unavailableWire), "unavailable wire has the exact schema")
        || !require(!unavailableWire.value(QStringLiteral("available")).toBool(), "unavailable is false")
        || !require(unavailableWire.value(QStringLiteral("currentId")).isNull(), "unavailable current is null")
        || !require(
            !unavailableWire.value(QStringLiteral("showTransient")).toBool(),
            "unavailable never requests feedback")
        || !require(
            unavailableWire.value(QStringLiteral("desktops")).toArray().isEmpty(),
            "unavailable desktop list is empty")) {
        return 1;
    }

    QJsonObject canonicalUnavailable{
        {QStringLiteral("available"), false},
        {QStringLiteral("currentId"), QJsonValue::Null},
        {QStringLiteral("showTransient"), false},
        {QStringLiteral("desktops"), QJsonArray{}},
    };
    const auto parsedUnavailable = canonicalizeScriptSnapshot(
        compact(canonicalUnavailable),
        QString::fromLatin1(Epoch),
        &error);
    if (!require(
            parsedUnavailable && *parsedUnavailable == unavailable,
            "script unavailable state canonicalizes byte-identically")
        || !require(isValidHelperEpoch(QString::fromLatin1(Epoch)), "lowercase epoch is valid")
        || !require(
            !isValidHelperEpoch(QStringLiteral("0123456789ABCDEF0123456789ABCDEF")),
            "uppercase epoch is rejected")
        || !require(!isValidHelperEpoch(QStringLiteral("short")), "short epoch is rejected")
        || !require(
            !canonicalizeScriptSnapshot(
                compact(validAvailable()),
                QStringLiteral("invalid"),
                &error),
            "invalid helper epoch cannot enter the wire")) {
        return 1;
    }

    QJsonObject invalid = validAvailable();
    invalid.remove(QStringLiteral("showTransient"));
    if (!require(rejected(invalid), "missing top-level field is rejected")) {
        return 1;
    }
    invalid = validAvailable();
    invalid.insert(QStringLiteral("version"), 1);
    if (!require(rejected(invalid), "script cannot supply the public version")) {
        return 1;
    }

    const QStringList forbiddenOutputFields{
        QStringLiteral("output"),
        QStringLiteral("outputs"),
        QStringLiteral("outputName"),
        QStringLiteral("outputCount"),
        QStringLiteral("outputIndex"),
        QStringLiteral("activeOutputName"),
        QStringLiteral("screen"),
        QStringLiteral("screenName"),
        QStringLiteral("screenIndex"),
        QStringLiteral("connector"),
        QStringLiteral("model"),
        QStringLiteral("serial"),
        QStringLiteral("geometry"),
        QStringLiteral("token"),
    };
    for (const QString &field : forbiddenOutputFields) {
        invalid = validAvailable();
        invalid.insert(field, QStringLiteral("identity"));
        if (!require(rejected(invalid), "every output identity field is rejected")) {
            return 1;
        }
    }

    invalid = canonicalUnavailable;
    invalid.insert(QStringLiteral("currentId"), QStringLiteral("first"));
    if (!require(rejected(invalid), "unavailable current ID must be null")) {
        return 1;
    }
    invalid = canonicalUnavailable;
    invalid.insert(QStringLiteral("showTransient"), true);
    if (!require(rejected(invalid), "unavailable cannot request feedback")) {
        return 1;
    }
    invalid = canonicalUnavailable;
    invalid.insert(
        QStringLiteral("desktops"),
        validAvailable().value(QStringLiteral("desktops")));
    if (!require(rejected(invalid), "unavailable desktop list must be empty")) {
        return 1;
    }

    invalid = validAvailable();
    invalid.insert(QStringLiteral("currentId"), QStringLiteral("missing"));
    if (!require(rejected(invalid), "current desktop must resolve")) {
        return 1;
    }
    invalid = validAvailable();
    invalid.insert(QStringLiteral("desktops"), QJsonArray{});
    if (!require(rejected(invalid), "empty available desktop list is rejected")) {
        return 1;
    }

    QJsonArray tooMany;
    for (int position = 0; position <= MaximumDesktopCount; ++position) {
        tooMany.append(QJsonObject{
            {QStringLiteral("id"), QStringLiteral("desktop-%1").arg(position)},
            {QStringLiteral("name"), QStringLiteral("Desktop")},
            {QStringLiteral("position"), position},
        });
    }
    invalid = validAvailable();
    invalid.insert(QStringLiteral("desktops"), tooMany);
    if (!require(rejected(invalid), "desktop count is bounded")) {
        return 1;
    }

    QJsonArray entries = validAvailable().value(QStringLiteral("desktops")).toArray();
    QJsonObject first = entries.at(0).toObject();
    QJsonObject second = entries.at(1).toObject();
    second.insert(QStringLiteral("id"), first.value(QStringLiteral("id")));
    entries[1] = second;
    invalid = validAvailable();
    invalid.insert(QStringLiteral("desktops"), entries);
    if (!require(rejected(invalid), "duplicate desktop IDs are rejected")) {
        return 1;
    }

    entries = validAvailable().value(QStringLiteral("desktops")).toArray();
    second = entries.at(1).toObject();
    second.insert(QStringLiteral("position"), 1);
    entries[1] = second;
    invalid = validAvailable();
    invalid.insert(QStringLiteral("desktops"), entries);
    if (!require(rejected(invalid), "duplicate positions are rejected")) {
        return 1;
    }

    const QList<QJsonValue> invalidPositions{
        QJsonValue(-1),
        QJsonValue(2),
        QJsonValue(0.5),
        QJsonValue(QStringLiteral("0")),
    };
    for (const QJsonValue &position : invalidPositions) {
        entries = validAvailable().value(QStringLiteral("desktops")).toArray();
        second = entries.at(1).toObject();
        second.insert(QStringLiteral("position"), position);
        entries[1] = second;
        invalid = validAvailable();
        invalid.insert(QStringLiteral("desktops"), entries);
        if (!require(rejected(invalid), "non-dense desktop position is rejected")) {
            return 1;
        }
    }

    entries = validAvailable().value(QStringLiteral("desktops")).toArray();
    first = entries.at(0).toObject();
    first.insert(QStringLiteral("id"), QString(MaximumDesktopIdLength + 1, QLatin1Char('x')));
    entries[0] = first;
    invalid = validAvailable();
    invalid.insert(QStringLiteral("desktops"), entries);
    if (!require(rejected(invalid), "desktop ID length is bounded")) {
        return 1;
    }

    entries = validAvailable().value(QStringLiteral("desktops")).toArray();
    first = entries.at(0).toObject();
    first.insert(QStringLiteral("name"), QString(MaximumDesktopNameLength + 1, QLatin1Char('n')));
    entries[0] = first;
    invalid = validAvailable();
    invalid.insert(QStringLiteral("desktops"), entries);
    if (!require(rejected(invalid), "desktop name length is bounded")) {
        return 1;
    }

    entries = validAvailable().value(QStringLiteral("desktops")).toArray();
    first = entries.at(0).toObject();
    first.insert(QStringLiteral("outputName"), QStringLiteral("forbidden"));
    entries[0] = first;
    invalid = validAvailable();
    invalid.insert(QStringLiteral("desktops"), entries);
    if (!require(rejected(invalid), "desktop entries reject output identity")) {
        return 1;
    }

    if (!require(
            !canonicalizeScriptSnapshot(
                QString(MaximumSnapshotLength + 1, QLatin1Char('x')),
                QString::fromLatin1(Epoch),
                &error),
            "snapshot character length is bounded")) {
        return 1;
    }

    SnapshotDeduplicator deduplicator;
    if (!require(deduplicator.shouldPublish(unavailable), "first snapshot publishes")
        || !require(!deduplicator.shouldPublish(unavailable), "byte-identical snapshot deduplicates")
        || !require(deduplicator.shouldPublish(*available), "changed snapshot publishes")
        || !require(!deduplicator.shouldPublish(*available), "changed snapshot then deduplicates")) {
        return 1;
    }

    qInfo("desktop snapshot tests passed");
    return 0;
}

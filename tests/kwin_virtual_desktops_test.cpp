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

QJsonObject validSnapshot()
{
    return QJsonObject{
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
        {QStringLiteral("outputs"),
         QJsonArray{
             QJsonObject{
                 {QStringLiteral("name"), QStringLiteral("Virtual-2")},
                 {QStringLiteral("currentId"), QStringLiteral("second")},
                 {QStringLiteral("showTransient"), true},
             },
             QJsonObject{
                 {QStringLiteral("name"), QStringLiteral("Virtual-1")},
                 {QStringLiteral("currentId"), QStringLiteral("first")},
                 {QStringLiteral("showTransient"), false},
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

bool hasExactKeys(const QJsonObject &object, const QStringList &keys)
{
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

bool entriesHaveExactKeys(const QJsonArray &entries, const QStringList &keys)
{
    for (const QJsonValue &value : entries) {
        if (!value.isObject() || !hasExactKeys(value.toObject(), keys)) {
            return false;
        }
    }
    return true;
}

bool hasExactWireKeys(const QJsonObject &object)
{
    return hasExactKeys(
        object,
        {
            QStringLiteral("desktops"),
            QStringLiteral("helperEpoch"),
            QStringLiteral("outputs"),
            QStringLiteral("version"),
        });
}

QJsonObject outputByName(const QJsonObject &snapshot, const QString &name)
{
    for (const QJsonValue &value : snapshot.value(QStringLiteral("outputs")).toArray()) {
        const QJsonObject output = value.toObject();
        if (output.value(QStringLiteral("name")).toString() == name) {
            return output;
        }
    }
    return {};
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    using namespace nagi::kwin;

    QString error;
    const auto canonical = canonicalizeScriptSnapshot(
        compact(validSnapshot()),
        QString::fromLatin1(Epoch),
        &error);
    if (!require(canonical.has_value(), "valid divergent snapshot canonicalizes")) {
        return 1;
    }

    const QJsonObject wire = QJsonDocument::fromJson(*canonical).object();
    const QJsonArray wireDesktops = wire.value(QStringLiteral("desktops")).toArray();
    const QJsonArray wireOutputs = wire.value(QStringLiteral("outputs")).toArray();
    const QJsonObject firstDesktop = wireDesktops.at(0).toObject();
    const QJsonObject firstOutput = outputByName(wire, QStringLiteral("Virtual-1"));
    const QJsonObject secondOutput = outputByName(wire, QStringLiteral("Virtual-2"));
    if (!require(hasExactWireKeys(wire), "wire has exactly the version-2 keys")
        || !require(wire.value(QStringLiteral("version")).toInt() == 2, "wire version is two")
        || !require(
            wire.value(QStringLiteral("helperEpoch")).toString() == QString::fromLatin1(Epoch),
            "wire carries the process helper epoch")
        || !require(wireDesktops.size() == 2, "one shared desktop list is preserved")
        || !require(wireOutputs.size() == 2, "every output projection is preserved")
        || !require(
            entriesHaveExactKeys(
                wireDesktops,
                {
                    QStringLiteral("id"),
                    QStringLiteral("name"),
                    QStringLiteral("position"),
                }),
            "every desktop wire entry has exact keys")
        || !require(
            entriesHaveExactKeys(
                wireOutputs,
                {
                    QStringLiteral("currentId"),
                    QStringLiteral("name"),
                    QStringLiteral("showTransient"),
                }),
            "every output wire entry has exact keys")
        || !require(
            firstDesktop.value(QStringLiteral("id")).toString() == QStringLiteral("first")
                && firstDesktop.value(QStringLiteral("position")).toInt() == 0,
            "desktops are canonicalized by dense position")
        || !require(
            firstDesktop.value(QStringLiteral("name")).toString()
                == QStringLiteral("Desktop \"1\"\n"),
            "desktop names remain JSON escaped")
        || !require(
            wireOutputs.at(0).toObject().value(QStringLiteral("name")).toString()
                    == QStringLiteral("Virtual-2")
                && wireOutputs.at(1).toObject().value(QStringLiteral("name")).toString()
                    == QStringLiteral("Virtual-1"),
            "live output order is preserved")
        || !require(
            firstOutput.value(QStringLiteral("currentId")).toString() == QStringLiteral("first")
                && !firstOutput.value(QStringLiteral("showTransient")).toBool(),
            "first output remains independently available")
        || !require(
            secondOutput.value(QStringLiteral("currentId")).toString() == QStringLiteral("second")
                && secondOutput.value(QStringLiteral("showTransient")).toBool(),
            "divergent changed output alone requests feedback")) {
        return 1;
    }

    const QByteArray unavailable = unavailableSnapshotJson(QString::fromLatin1(Epoch));
    const QJsonObject unavailableWire = QJsonDocument::fromJson(unavailable).object();
    if (!require(hasExactWireKeys(unavailableWire), "unavailable wire has the exact schema")
        || !require(
            unavailableWire.value(QStringLiteral("version")).toInt() == 2
                && unavailableWire.value(QStringLiteral("helperEpoch")).toString()
                    == QString::fromLatin1(Epoch),
            "unavailable wire retains protocol identity")
        || !require(
            unavailableWire.value(QStringLiteral("desktops")).toArray().isEmpty()
                && unavailableWire.value(QStringLiteral("outputs")).toArray().isEmpty(),
            "unavailable wire has two canonical empty arrays")) {
        return 1;
    }

    const QJsonObject canonicalUnavailable{
        {QStringLiteral("desktops"), QJsonArray{}},
        {QStringLiteral("outputs"), QJsonArray{}},
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
                compact(validSnapshot()),
                QStringLiteral("invalid"),
                &error),
            "invalid helper epoch cannot enter the wire")) {
        return 1;
    }

    QJsonObject invalid = validSnapshot();
    invalid.remove(QStringLiteral("outputs"));
    if (!require(rejected(invalid), "missing top-level field is rejected")) {
        return 1;
    }
    invalid = validSnapshot();
    invalid.insert(QStringLiteral("version"), 2);
    if (!require(rejected(invalid), "script cannot supply the public version")) {
        return 1;
    }
    const QJsonObject versionOnePayload{
        {QStringLiteral("available"), true},
        {QStringLiteral("currentId"), QStringLiteral("first")},
        {QStringLiteral("showTransient"), false},
        {QStringLiteral("desktops"), validSnapshot().value(QStringLiteral("desktops"))},
    };
    if (!require(rejected(versionOnePayload), "version-1 consensus payload is rejected")) {
        return 1;
    }

    invalid = validSnapshot();
    invalid.insert(QStringLiteral("outputs"), QJsonArray{});
    if (!require(rejected(invalid), "desktops without outputs are not canonical unavailable")) {
        return 1;
    }
    invalid = validSnapshot();
    invalid.insert(QStringLiteral("desktops"), QJsonArray{});
    if (!require(rejected(invalid), "outputs without desktops are not canonical unavailable")) {
        return 1;
    }

    invalid = validSnapshot();
    invalid.insert(QStringLiteral("outputs"), QJsonObject{});
    if (!require(rejected(invalid), "outputs must be an array")) {
        return 1;
    }

    QJsonArray outputs = validSnapshot().value(QStringLiteral("outputs")).toArray();
    QJsonObject output = outputs.at(0).toObject();
    output.remove(QStringLiteral("showTransient"));
    outputs[0] = output;
    invalid = validSnapshot();
    invalid.insert(QStringLiteral("outputs"), outputs);
    if (!require(rejected(invalid), "output entries require exact keys")) {
        return 1;
    }

    outputs = validSnapshot().value(QStringLiteral("outputs")).toArray();
    output = outputs.at(0).toObject();
    output.insert(QStringLiteral("connector"), QStringLiteral("forbidden"));
    outputs[0] = output;
    invalid = validSnapshot();
    invalid.insert(QStringLiteral("outputs"), outputs);
    if (!require(rejected(invalid), "output entries reject extra identity fields")) {
        return 1;
    }

    outputs = validSnapshot().value(QStringLiteral("outputs")).toArray();
    output = outputs.at(0).toObject();
    output.insert(QStringLiteral("name"), QString{});
    outputs[0] = output;
    invalid = validSnapshot();
    invalid.insert(QStringLiteral("outputs"), outputs);
    if (!require(rejected(invalid), "output names cannot be empty")) {
        return 1;
    }

    outputs = validSnapshot().value(QStringLiteral("outputs")).toArray();
    output = outputs.at(0).toObject();
    output.insert(QStringLiteral("showTransient"), 1);
    outputs[0] = output;
    invalid = validSnapshot();
    invalid.insert(QStringLiteral("outputs"), outputs);
    if (!require(rejected(invalid), "output feedback flags must be boolean")) {
        return 1;
    }

    outputs = validSnapshot().value(QStringLiteral("outputs")).toArray();
    output = outputs.at(0).toObject();
    output.insert(QStringLiteral("currentId"), QStringLiteral("missing"));
    outputs[0] = output;
    invalid = validSnapshot();
    invalid.insert(QStringLiteral("outputs"), outputs);
    if (!require(rejected(invalid), "every output current desktop must resolve")) {
        return 1;
    }

    outputs = validSnapshot().value(QStringLiteral("outputs")).toArray();
    output = outputs.at(1).toObject();
    output.insert(
        QStringLiteral("name"),
        outputs.at(0).toObject().value(QStringLiteral("name")));
    outputs[1] = output;
    invalid = validSnapshot();
    invalid.insert(QStringLiteral("outputs"), outputs);
    if (!require(rejected(invalid), "output names are unique")) {
        return 1;
    }

    outputs = validSnapshot().value(QStringLiteral("outputs")).toArray();
    output = outputs.at(1).toObject();
    output.insert(QStringLiteral("showTransient"), true);
    outputs[1] = output;
    invalid = validSnapshot();
    invalid.insert(QStringLiteral("outputs"), outputs);
    if (!require(rejected(invalid), "at most one output can request feedback")) {
        return 1;
    }

    QJsonArray tooManyOutputs;
    for (int index = 0; index <= MaximumOutputCount; ++index) {
        tooManyOutputs.append(QJsonObject{
            {QStringLiteral("name"), QStringLiteral("Virtual-%1").arg(index)},
            {QStringLiteral("currentId"), QStringLiteral("first")},
            {QStringLiteral("showTransient"), false},
        });
    }
    invalid = validSnapshot();
    invalid.insert(QStringLiteral("outputs"), tooManyOutputs);
    if (!require(rejected(invalid), "output count is bounded")) {
        return 1;
    }

    QJsonArray maximumOutputs;
    for (qsizetype index = 0; index < MaximumOutputCount; ++index) {
        maximumOutputs.append(QJsonObject{
            {QStringLiteral("name"),
             index == 0
                 ? QString(MaximumOutputNameLength, QLatin1Char('x'))
                 : QStringLiteral("Virtual-%1").arg(index)},
            {QStringLiteral("currentId"), QStringLiteral("first")},
            {QStringLiteral("showTransient"), false},
        });
    }
    QJsonObject maximumOutputSnapshot = validSnapshot();
    maximumOutputSnapshot.insert(QStringLiteral("outputs"), maximumOutputs);
    if (!require(
            canonicalizeScriptSnapshot(
                compact(maximumOutputSnapshot),
                QString::fromLatin1(Epoch),
                &error)
                .has_value(),
            "maximum output count and name length are accepted")) {
        return 1;
    }

    const QString privateOutputName(
        MaximumOutputNameLength + 1,
        QLatin1Char('x'));
    outputs = validSnapshot().value(QStringLiteral("outputs")).toArray();
    output = outputs.at(0).toObject();
    output.insert(QStringLiteral("name"), privateOutputName);
    outputs[0] = output;
    invalid = validSnapshot();
    invalid.insert(QStringLiteral("outputs"), outputs);
    error.clear();
    const bool privateNameRejected = !canonicalizeScriptSnapshot(
        compact(invalid),
        QString::fromLatin1(Epoch),
        &error);
    if (!require(privateNameRejected && !error.isEmpty(), "output name length is bounded")
        || !require(!error.contains(privateOutputName), "diagnostics do not disclose output names")) {
        return 1;
    }

    QJsonArray tooManyDesktops;
    for (int position = 0; position <= MaximumDesktopCount; ++position) {
        tooManyDesktops.append(QJsonObject{
            {QStringLiteral("id"), QStringLiteral("desktop-%1").arg(position)},
            {QStringLiteral("name"), QStringLiteral("Desktop")},
            {QStringLiteral("position"), position},
        });
    }
    invalid = validSnapshot();
    invalid.insert(QStringLiteral("desktops"), tooManyDesktops);
    if (!require(rejected(invalid), "desktop count is bounded")) {
        return 1;
    }

    QJsonArray entries = validSnapshot().value(QStringLiteral("desktops")).toArray();
    QJsonObject first = entries.at(0).toObject();
    QJsonObject second = entries.at(1).toObject();
    second.insert(QStringLiteral("id"), first.value(QStringLiteral("id")));
    entries[1] = second;
    invalid = validSnapshot();
    invalid.insert(QStringLiteral("desktops"), entries);
    if (!require(rejected(invalid), "duplicate desktop IDs are rejected")) {
        return 1;
    }

    entries = validSnapshot().value(QStringLiteral("desktops")).toArray();
    second = entries.at(1).toObject();
    second.insert(QStringLiteral("position"), 1);
    entries[1] = second;
    invalid = validSnapshot();
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
        entries = validSnapshot().value(QStringLiteral("desktops")).toArray();
        second = entries.at(1).toObject();
        second.insert(QStringLiteral("position"), position);
        entries[1] = second;
        invalid = validSnapshot();
        invalid.insert(QStringLiteral("desktops"), entries);
        if (!require(rejected(invalid), "non-dense desktop position is rejected")) {
            return 1;
        }
    }

    entries = validSnapshot().value(QStringLiteral("desktops")).toArray();
    first = entries.at(0).toObject();
    first.insert(QStringLiteral("id"), QString(MaximumDesktopIdLength + 1, QLatin1Char('x')));
    entries[0] = first;
    invalid = validSnapshot();
    invalid.insert(QStringLiteral("desktops"), entries);
    if (!require(rejected(invalid), "desktop ID length is bounded")) {
        return 1;
    }

    entries = validSnapshot().value(QStringLiteral("desktops")).toArray();
    first = entries.at(0).toObject();
    first.insert(QStringLiteral("name"), QString(MaximumDesktopNameLength + 1, QLatin1Char('n')));
    entries[0] = first;
    invalid = validSnapshot();
    invalid.insert(QStringLiteral("desktops"), entries);
    if (!require(rejected(invalid), "desktop name length is bounded")) {
        return 1;
    }

    entries = validSnapshot().value(QStringLiteral("desktops")).toArray();
    first = entries.at(0).toObject();
    first.insert(QStringLiteral("outputName"), QStringLiteral("forbidden"));
    entries[0] = first;
    invalid = validSnapshot();
    invalid.insert(QStringLiteral("desktops"), entries);
    if (!require(rejected(invalid), "desktop entries reject output identity")) {
        return 1;
    }

    if (!require(
            !canonicalizeScriptSnapshot(
                QString(MaximumSnapshotLength + 1, QLatin1Char('x')),
                QString::fromLatin1(Epoch),
                &error),
            "snapshot character length is bounded")
        || !require(
            !canonicalizeScriptSnapshot(
                QString(MaximumSnapshotLength / 2, QChar(0x20ac)),
                QString::fromLatin1(Epoch),
                &error),
            "snapshot UTF-8 byte length is bounded")) {
        return 1;
    }

    SnapshotDeduplicator deduplicator;
    if (!require(deduplicator.shouldPublish(unavailable), "first snapshot publishes")
        || !require(!deduplicator.shouldPublish(unavailable), "byte-identical snapshot deduplicates")
        || !require(deduplicator.shouldPublish(*canonical), "changed snapshot publishes")
        || !require(!deduplicator.shouldPublish(*canonical), "changed snapshot then deduplicates")) {
        return 1;
    }

    qInfo("desktop snapshot tests passed");
    return 0;
}

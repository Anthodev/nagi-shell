#include "desktop_snapshot.h"

#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

#include <limits>

namespace {

bool require(bool condition, const char *message)
{
    if (!condition) {
        qCritical("FAIL: %s", message);
    }
    return condition;
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    using namespace nagi::kwin;

    QString error;
    const QVector<SignedDesktopTuple> signedTuples{
        {1, QStringLiteral("second"), QStringLiteral("Desktop 2")},
        {0, QStringLiteral("first"), QStringLiteral("Desktop \"1\"\n")},
    };
    const QVector<UnsignedDesktopTuple> unsignedTuples{
        {1, QStringLiteral("second"), QStringLiteral("Desktop 2")},
        {0, QStringLiteral("first"), QStringLiteral("Desktop \"1\"\n")},
    };

    const auto signedDesktops = normalizeSignedDesktops(signedTuples, &error);
    const auto unsignedDesktops = normalizeUnsignedDesktops(unsignedTuples, &error);
    if (!require(signedDesktops.has_value(), "signed tuples decode")
        || !require(unsignedDesktops.has_value(), "unsigned tuples decode")
        || !require(*signedDesktops == *unsignedDesktops, "signed and unsigned states match")
        || !require(signedDesktops->at(0).position == 0, "desktops are zero-based and ordered")) {
        return 1;
    }

    const auto json =
        availableSnapshotJson(*signedDesktops, QStringLiteral("first"), false, &error);
    if (!require(json.has_value(), "current desktop resolves")) {
        return 1;
    }
    const QJsonObject parsed = QJsonDocument::fromJson(*json).object();
    if (!require(parsed.value(QStringLiteral("available")).toBool(), "available snapshot is emitted")
        || !require(!parsed.value(QStringLiteral("showTransient")).toBool(), "initial snapshot suppresses feedback")
        || !require(
            parsed.value(QStringLiteral("desktops")).toArray().at(0).toObject().value(QStringLiteral("name")).toString()
                == QStringLiteral("Desktop \"1\"\n"),
            "desktop names are JSON escaped")) {
        return 1;
    }

    const QVector<SignedDesktopTuple> negative{
        {-1, QStringLiteral("first"), QStringLiteral("Desktop 1")},
    };
    const QVector<SignedDesktopTuple> signedOutOfRange{
        {1, QStringLiteral("first"), QStringLiteral("Desktop 1")},
    };
    const QVector<UnsignedDesktopTuple> unsignedOutOfRange{
        {std::numeric_limits<quint32>::max(), QStringLiteral("first"), QStringLiteral("Desktop 1")},
    };
    if (!require(!normalizeSignedDesktops(negative, &error), "negative position is rejected")
        || !require(!normalizeSignedDesktops(signedOutOfRange, &error), "signed out-of-range position is rejected")
        || !require(!normalizeUnsignedDesktops(unsignedOutOfRange, &error), "unsigned out-of-range position is rejected")
        || !require(
            !availableSnapshotJson(*signedDesktops, QStringLiteral("missing"), true, &error),
            "unknown current desktop is rejected")) {
        return 1;
    }

    qInfo("desktop snapshot tests passed");
    return 0;
}

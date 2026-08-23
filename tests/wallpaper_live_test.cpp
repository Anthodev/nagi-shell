#include <QCoreApplication>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>

#include <cstdio>

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    if (argc != 2) {
        std::fprintf(stderr, "usage: wallpaper-live-test <helper>\n");
        return 2;
    }

    QProcess helper;
    helper.start(QString::fromLocal8Bit(argv[1]), {QStringLiteral("--once")});
    if (!helper.waitForStarted() || !helper.waitForFinished(10000)
        || helper.exitStatus() != QProcess::NormalExit || helper.exitCode() != 0) {
        std::fprintf(stderr, "wallpaper live probe failed: helper did not complete\n");
        return 1;
    }
    const QJsonObject snapshot = QJsonDocument::fromJson(helper.readAllStandardOutput().trimmed()).object();
    const QString accent = snapshot.value(QStringLiteral("accent")).toString();
    const QString path = snapshot.value(QStringLiteral("imagePath")).toString();
    const QFileInfo source(path);
    const bool valid = snapshot.value(QStringLiteral("available")).toBool()
        && snapshot.value(QStringLiteral("status")).toString() == QStringLiteral("Ready")
        && source.isAbsolute() && source.isFile() && source.isReadable()
        && QRegularExpression(QStringLiteral("^#[0-9A-F]{6}$")).match(accent).hasMatch();
    if (!valid) {
        std::fprintf(stderr, "wallpaper live probe failed: source is not a readable supported image\n");
        return 1;
    }

    const QByteArray accentBytes = accent.toLatin1();
    std::printf(
        "wallpaper live probe: generation=%lld available=true status=Ready readable=true accent=%s\n",
        static_cast<long long>(snapshot.value(QStringLiteral("generation")).toInteger()),
        accentBytes.constData());
    return 0;
}

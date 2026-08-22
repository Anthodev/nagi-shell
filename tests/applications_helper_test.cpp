#define QT_NO_KEYWORDS

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QProcessEnvironment>
#include <QSaveFile>
#include <QSet>
#include <QThread>
#include <QTemporaryDir>

#include <cstdio>
#include <sys/stat.h>
#include <unistd.h>

namespace {
[[noreturn]] void fail(const char *message)
{
    std::fprintf(stderr, "FAIL: %s\n", message);
    std::fflush(stderr);
    std::exit(1);
}

void require(bool condition, const char *message)
{
    if (!condition) {
        fail(message);
    }
}

void writeFile(const QString &path, const QByteArray &contents, QFile::Permissions permissions = {})
{
    QFile file(path);
    require(file.open(QIODevice::WriteOnly | QIODevice::Truncate), "could not create fixture");
    require(file.write(contents) == contents.size(), "could not write fixture");
    file.close();
    if (permissions != QFile::Permissions {}) {
        require(file.setPermissions(permissions), "could not set fixture permissions");
    }
}

void writeDesktop(const QString &directory, const QString &name, const QByteArray &body)
{
    QDir().mkpath(directory);
    writeFile(directory + u'/' + name, body);
}

class HelperProcess {
public:
    HelperProcess(const QString &path, const QString &pinsPath, const QString &recencyPath,
                  const QProcessEnvironment &environment)
    {
        process.setProcessEnvironment(environment);
        process.start(path, {pinsPath, recencyPath});
        require(process.waitForStarted(3000), "helper did not start");
    }

    ~HelperProcess()
    {
        if (process.state() != QProcess::NotRunning) {
            send(QJsonObject {{QStringLiteral("op"), QStringLiteral("shutdown")}});
            process.waitForFinished(1000);
        }
    }

    QJsonObject next()
    {
        buffer.append(process.readAllStandardOutput());
        while (!buffer.contains('\n')) {
            if (!process.waitForReadyRead(3000)) {
                const QByteArray diagnostic = process.readAllStandardError();
                std::fprintf(stderr, "helper timeout after %d responses; state=%d exit=%d stderr=%s\n",
                             responseCount, static_cast<int>(process.state()), process.exitCode(),
                             diagnostic.constData());
                fail("helper response timed out");
            }
            buffer.append(process.readAllStandardOutput());
        }
        const qsizetype newline = buffer.indexOf('\n');
        const QByteArray line = buffer.first(newline);
        buffer.remove(0, newline + 1);
        QJsonParseError error {};
        const QJsonDocument document = QJsonDocument::fromJson(line, &error);
        require(error.error == QJsonParseError::NoError && document.isObject(),
                "helper returned invalid JSON");
        ++responseCount;
        return document.object();
    }

    QJsonObject request(const QJsonObject &command)
    {
        send(command);
        return next();
    }

private:
    void send(const QJsonObject &command)
    {
        QByteArray line = QJsonDocument(command).toJson(QJsonDocument::Compact);
        line.append('\n');
        require(process.write(line) == line.size(), "helper command write failed");
        require(process.waitForBytesWritten(1000), "helper command did not flush");
    }

    QProcess process;
    QByteArray buffer;
    int responseCount = 0;
};

QSet<QString> ids(const QJsonObject &generation)
{
    QSet<QString> result;
    const QJsonArray entries = generation.value(QStringLiteral("entries")).toArray();
    for (const QJsonValue &value : entries) {
        result.insert(value.toObject().value(QStringLiteral("id")).toString());
    }
    return result;
}

QFile::Permissions privatePermissions()
{
    return QFile::ReadOwner | QFile::WriteOwner;
}
}

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    require(application.arguments().size() == 2, "helper path argument is required");

    QTemporaryDir temporary;
    require(temporary.isValid(), "temporary directory is unavailable");
    const QString root = temporary.path();
    const QString highApplications = root + QStringLiteral("/data-high/applications");
    const QString lowApplications = root + QStringLiteral("/data-low/applications");
    const QString configBase = root + QStringLiteral("/config");
    const QString stateBase = root + QStringLiteral("/state");
    require(QDir().mkpath(configBase) && QDir().mkpath(stateBase), "could not create XDG bases");

    writeDesktop(highApplications, QStringLiteral("valid.desktop"),
                 "[Desktop Entry]\nType=Application\nName=Valid\nExec=/usr/bin/true\n");
    const QString launchedMarker = root + QStringLiteral("/launched");
    writeDesktop(highApplications, QStringLiteral("launchable.desktop"),
                 "[Desktop Entry]\nType=Application\nName=Launchable\nExec=/usr/bin/touch "
                     + launchedMarker.toUtf8() + "\n");
    writeDesktop(highApplications, QStringLiteral("precedence.desktop"),
                 "[Desktop Entry]\nType=Application\nName=Masked\nNoDisplay=true\nExec=/usr/bin/true\n");
    writeDesktop(lowApplications, QStringLiteral("precedence.desktop"),
                 "[Desktop Entry]\nType=Application\nName=Lower\nExec=/usr/bin/true\n");
    writeDesktop(highApplications, QStringLiteral("gnome-only.desktop"),
                 "[Desktop Entry]\nType=Application\nName=GNOME\nOnlyShowIn=GNOME;\nExec=/usr/bin/true\n");
    writeDesktop(highApplications, QStringLiteral("missing-tryexec.desktop"),
                 "[Desktop Entry]\nType=Application\nName=TryExec\nTryExec=/not/installed\nExec=/usr/bin/true\n");
    writeDesktop(highApplications, QStringLiteral("invalid-exec.desktop"),
                 "[Desktop Entry]\nType=Application\nName=Invalid Exec\nExec=/usr/bin/true %Z\n");
    writeDesktop(highApplications, QStringLiteral("org.example.InvalidDbus.desktop"),
                 "[Desktop Entry]\nType=Application\nName=Invalid D-Bus fallback\nDBusActivatable=true\nExec=/usr/bin/true %Z\n");
    writeDesktop(highApplications, QStringLiteral("terminal.desktop"),
                 "[Desktop Entry]\nType=Application\nName=Terminal\nTerminal=true\nExec=/usr/bin/true\n");
    writeDesktop(highApplications, QStringLiteral("no-launch.desktop"),
                 "[Desktop Entry]\nType=Application\nName=No launch\n");
    writeDesktop(highApplications, QStringLiteral("hidden.desktop"),
                 "[Desktop Entry]\nType=Application\nName=Hidden\nHidden=true\nExec=/usr/bin/true\n");
    writeDesktop(highApplications, QStringLiteral("wrong-type.desktop"),
                 "[Desktop Entry]\nType=Link\nName=Link\nURL=https://example.invalid\n");
    writeDesktop(highApplications, QStringLiteral("malformed.desktop"),
                 "not a desktop entry\n");
    writeDesktop(highApplications, QStringLiteral("org.example.Dbus.desktop"),
                 "[Desktop Entry]\nType=Application\nName=D-Bus\nDBusActivatable=true\n");

    const QString pinsPath = configBase + QStringLiteral("/nagi-shell/application-pins.json");
    const QString recencyPath = stateBase + QStringLiteral("/nagi-shell/application-recency.json");
    require(QDir().mkpath(QFileInfo(pinsPath).absolutePath()), "could not create pins directory");
    writeFile(pinsPath,
              "{\n  \"version\": 1,\n  \"desktopFileIds\": [\n    \"valid.desktop\"\n  ]\n}\n",
              privatePermissions());

    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    environment.insert(QStringLiteral("XDG_DATA_HOME"), root + QStringLiteral("/data-high"));
    environment.insert(QStringLiteral("XDG_DATA_DIRS"), root + QStringLiteral("/data-low"));
    environment.insert(QStringLiteral("XDG_CURRENT_DESKTOP"), QStringLiteral("KDE"));

    {
        HelperProcess helper(application.arguments().at(1), pinsPath, recencyPath, environment);
        const QJsonObject initialized = helper.next();
        require(initialized.value(QStringLiteral("type")) == QStringLiteral("initialized"),
                "helper did not initialize");
        const QJsonObject stores = initialized.value(QStringLiteral("stores")).toObject();
        require(stores.value(QStringLiteral("pins")).toObject().value(QStringLiteral("category"))
                    == QStringLiteral("loaded"),
                "valid pins were not loaded");
        require(stores.value(QStringLiteral("recency")).toObject().value(QStringLiteral("category"))
                    == QStringLiteral("missing"),
                "missing recency was not clean first-run state");

        const QJsonObject generation = helper.request(
            QJsonObject {{QStringLiteral("op"), QStringLiteral("scan")},
                         {QStringLiteral("generation"), 1}});
        require(generation.value(QStringLiteral("complete")).toBool(),
                "fixture discovery was incomplete");
        require(ids(generation)
                    == QSet<QString> {QStringLiteral("valid.desktop"),
                                      QStringLiteral("launchable.desktop"),
                                      QStringLiteral("org.example.Dbus.desktop")},
                "ineligible desktop entries were not excluded");
        const QJsonObject launched = helper.request(
            QJsonObject {{QStringLiteral("op"), QStringLiteral("launch")},
                         {QStringLiteral("requestId"), 11},
                         {QStringLiteral("desktopFileId"),
                          QStringLiteral("launchable.desktop")}});
        require(launched.value(QStringLiteral("type")) == QStringLiteral("launch-result")
                    && launched.value(QStringLiteral("requestId")).toInteger() == 11
                    && launched.value(QStringLiteral("accepted")).toBool()
                    && launched.value(QStringLiteral("category")) == QStringLiteral("none"),
                "eligible exact ID was not accepted by the structured launch path");
        QElapsedTimer launchWait;
        launchWait.start();
        while (!QFileInfo::exists(launchedMarker) && launchWait.elapsed() < 3000) {
            QThread::msleep(10);
        }
        require(QFileInfo::exists(launchedMarker), "accepted structured launch did not dispatch");

        require(QFile::remove(highApplications + QStringLiteral("/launchable.desktop")),
                "could not remove launch fixture");
        const QJsonObject vanished = helper.request(
            QJsonObject {{QStringLiteral("op"), QStringLiteral("launch")},
                         {QStringLiteral("requestId"), 12},
                         {QStringLiteral("desktopFileId"),
                          QStringLiteral("launchable.desktop")}});
        require(!vanished.value(QStringLiteral("accepted")).toBool()
                    && vanished.value(QStringLiteral("category")) == QStringLiteral("ineligible"),
                "vanished exact ID was not rejected");

        const QJsonObject ready = helper.request(
            QJsonObject {{QStringLiteral("op"), QStringLiteral("prepare-write")},
                         {QStringLiteral("store"), QStringLiteral("recency")},
                         {QStringLiteral("serial"), 2}});
        require(ready.value(QStringLiteral("success")).toBool(),
                "missing recency file was not prepared");

        struct stat status {};
        const QByteArray nativeRecency = QFile::encodeName(recencyPath);
        require(::lstat(nativeRecency.constData(), &status) == 0 && S_ISREG(status.st_mode)
                    && (status.st_mode & 0777) == 0600 && status.st_uid == getuid(),
                "prepared recency file is not private");

        const QJsonObject emptyVerified = helper.request(
            QJsonObject {{QStringLiteral("op"), QStringLiteral("verify-write")},
                         {QStringLiteral("store"), QStringLiteral("recency")},
                         {QStringLiteral("serial"), 2}});
        require(emptyVerified.value(QStringLiteral("success")).toBool(),
                "empty first-write store was not accepted");

        QSaveFile save(recencyPath);
        require(save.open(QIODevice::WriteOnly), "could not open atomic recency save");
        const QByteArray recency =
            "{\n  \"version\": 1,\n  \"desktopFileIds\": [\n    \"valid.desktop\"\n  ]\n}\n";
        require(save.write(recency) == recency.size() && save.commit(),
                "atomic recency save failed");
        const QJsonObject verified = helper.request(
            QJsonObject {{QStringLiteral("op"), QStringLiteral("verify-write")},
                         {QStringLiteral("store"), QStringLiteral("recency")},
                         {QStringLiteral("serial"), 2}});
        require(verified.value(QStringLiteral("success")).toBool(),
                "atomic recency save was not verified");

        QSaveFile interrupted(recencyPath);
        require(interrupted.open(QIODevice::WriteOnly), "could not open interrupted save");
        interrupted.write("partial");
        interrupted.cancelWriting();
        QFile unchanged(recencyPath);
        require(unchanged.open(QIODevice::ReadOnly) && unchanged.readAll() == recency,
                "interrupted atomic save changed the committed file");
    }

    QFile::remove(highApplications + QStringLiteral("/precedence.desktop"));
    {
        HelperProcess helper(application.arguments().at(1), pinsPath, recencyPath, environment);
        helper.next();
        const QJsonObject generation = helper.request(
            QJsonObject {{QStringLiteral("op"), QStringLiteral("scan")},
                         {QStringLiteral("generation"), 2}});
        require(ids(generation).contains(QStringLiteral("precedence.desktop")),
                "lower-precedence same-ID entry did not return");
    }

    const QString unsafeBase = root + QStringLiteral("/unsafe");
    require(QDir().mkpath(unsafeBase + QStringLiteral("/nagi-shell")),
            "could not create unsafe fixture directory");
    const QString unsafePins = unsafeBase + QStringLiteral("/nagi-shell/application-pins.json");
    const QByteArray nativePins = QFile::encodeName(pinsPath);
    const QByteArray nativeUnsafe = QFile::encodeName(unsafePins);
    require(::symlink(nativePins.constData(), nativeUnsafe.constData()) == 0,
            "could not create symlink fixture");
    {
        HelperProcess helper(application.arguments().at(1), unsafePins, recencyPath, environment);
        const QJsonObject stores = helper.next().value(QStringLiteral("stores")).toObject();
        const QJsonObject pins = stores.value(QStringLiteral("pins")).toObject();
        require(!pins.value(QStringLiteral("available")).toBool()
                    && pins.value(QStringLiteral("category")) == QStringLiteral("symlink"),
                "symlink store was not refused");
    }

    const QString oversizedBase = root + QStringLiteral("/oversized");
    const QString oversizedPins =
        oversizedBase + QStringLiteral("/nagi-shell/application-pins.json");
    require(QDir().mkpath(QFileInfo(oversizedPins).absolutePath()),
            "could not create oversized fixture directory");
    writeFile(oversizedPins, QByteArray(128 * 1024 + 1, 'x'), privatePermissions());
    {
        HelperProcess helper(application.arguments().at(1), oversizedPins, recencyPath, environment);
        const QJsonObject pins = helper.next()
                                     .value(QStringLiteral("stores"))
                                     .toObject()
                                     .value(QStringLiteral("pins"))
                                     .toObject();
        require(pins.value(QStringLiteral("available")).toBool()
                    && pins.value(QStringLiteral("category")) == QStringLiteral("oversized")
                    && !pins.contains(QStringLiteral("text")),
                "oversized store was read or disabled incorrectly");
    }

    require(QDir(highApplications).removeRecursively(),
            "could not replace discovery fixture directory");
    writeFile(highApplications, "not a directory");
    {
        HelperProcess helper(application.arguments().at(1), pinsPath, recencyPath, environment);
        helper.next();
        const QJsonObject generation = helper.request(
            QJsonObject {{QStringLiteral("op"), QStringLiteral("scan")},
                         {QStringLiteral("generation"), 3}});
        require(!generation.value(QStringLiteral("complete")).toBool()
                    && generation.value(QStringLiteral("failure")) == QStringLiteral("discovery"),
                "invalid discovery path became an authoritative empty generation");
    }

    qInfo("application helper tests passed");
    return 0;
}

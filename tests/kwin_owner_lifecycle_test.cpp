#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QFile>
#include <QFileDevice>
#include <QFileInfo>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QStringList>
#include <QThread>

#include <functional>
#include <utility>

namespace {

constexpr auto Service = "org.kde.KWin";
constexpr auto CallbackPath = "/WorkspaceConsensus";
constexpr auto CallbackInterface = "io.github.Anthodev.NagiShell.WorkspaceConsensus";

bool require(bool condition, const char *message)
{
    if (!condition) {
        qCritical("FAIL: %s", message);
    }
    return condition;
}

bool waitUntil(const std::function<bool()> &predicate, int timeoutMs)
{
    QElapsedTimer timer;
    timer.start();
    while (timer.elapsed() < timeoutMs) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
        if (predicate()) {
            return true;
        }
        QThread::msleep(1);
    }
    QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
    return predicate();
}

void spinEvents(int durationMs)
{
    QElapsedTimer timer;
    timer.start();
    while (timer.elapsed() < durationMs) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
        QThread::msleep(1);
    }
}

QString compact(const QJsonObject &object)
{
    return QString::fromUtf8(QJsonDocument(object).toJson(QJsonDocument::Compact));
}

QJsonObject projectionPayload(
    const QString &currentId = QStringLiteral("desktop-one"),
    bool showTransient = false)
{
    return QJsonObject{
        {QStringLiteral("desktops"),
         QJsonArray{
             QJsonObject{
                 {QStringLiteral("id"), QStringLiteral("desktop-one")},
                 {QStringLiteral("name"), QStringLiteral("Desktop 1")},
                 {QStringLiteral("position"), 0},
             },
             QJsonObject{
                 {QStringLiteral("id"), QStringLiteral("desktop-two")},
                 {QStringLiteral("name"), QStringLiteral("Desktop 2")},
                 {QStringLiteral("position"), 1},
             },
         }},
        {QStringLiteral("outputs"),
         QJsonArray{
             QJsonObject{
                 {QStringLiteral("name"), QStringLiteral("Virtual-1")},
                 {QStringLiteral("currentId"), currentId},
                 {QStringLiteral("showTransient"), showTransient},
             },
         }},
    };
}

QJsonObject replacementPayload()
{
    return QJsonObject{
        {QStringLiteral("desktops"),
         QJsonArray{
             QJsonObject{
                 {QStringLiteral("id"), QStringLiteral("new-owner-desktop")},
                 {QStringLiteral("name"), QStringLiteral("New Desktop")},
                 {QStringLiteral("position"), 0},
             },
         }},
        {QStringLiteral("outputs"),
         QJsonArray{
             QJsonObject{
                 {QStringLiteral("name"), QStringLiteral("Virtual-1")},
                 {QStringLiteral("currentId"), QStringLiteral("new-owner-desktop")},
                 {QStringLiteral("showTransient"), false},
             },
         }},
    };
}

QString extractJsonString(const QByteArray &source, const QByteArray &prefix)
{
    const qsizetype marker = source.indexOf(prefix);
    if (marker < 0) {
        return {};
    }
    const qsizetype start = marker + prefix.size();
    const qsizetype end = source.indexOf(';', start);
    if (end < 0) {
        return {};
    }

    const QByteArray literal = source.mid(start, end - start).trimmed();
    QJsonParseError error{};
    const QJsonDocument document = QJsonDocument::fromJson(
        QByteArray("[") + literal + QByteArray("]"),
        &error);
    if (error.error != QJsonParseError::NoError || !document.isArray()
        || document.array().size() != 1 || !document.array().at(0).isString()) {
        return {};
    }
    return document.array().at(0).toString();
}

class FakeScripting;

class FakeScript final : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.kwin.Script")

public:
    FakeScript(int id, FakeScripting *scripting);

public Q_SLOTS:
    Q_SCRIPTABLE void run();
    Q_SCRIPTABLE void stop();

private:
    int id;
    FakeScripting *scripting;
};

class FakeScripting final : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.kwin.Scripting")

public:
    explicit FakeScripting(QDBusConnection connection, QObject *parent = nullptr)
        : QObject(parent)
        , connection(std::move(connection))
    {
    }

    void recordRun(int id)
    {
        if (scripts.contains(id)) {
            runCount += 1;
        }
    }

    void recordStop(int id)
    {
        if (scripts.contains(id)) {
            stopCount += 1;
        }
    }

    void publish(
        const QJsonObject &payload,
        const QString &generationOverride = {},
        const QDBusConnection *senderOverride = nullptr) const
    {
        const QDBusConnection &sender = senderOverride == nullptr ? connection : *senderOverride;
        QDBusMessage message = QDBusMessage::createMethodCall(
            helperDestination,
            QString::fromLatin1(CallbackPath),
            QString::fromLatin1(CallbackInterface),
            QStringLiteral("Publish"));
        message << (generationOverride.isEmpty() ? scriptGeneration : generationOverride)
                << compact(payload);
        sender.asyncCall(message);
    }

public Q_SLOTS:
    Q_SCRIPTABLE int loadScript(const QString &filePath, const QString &pluginName)
    {
        loadCount += 1;
        lastScriptPath = filePath;
        lastPluginName = pluginName;

        QFile file(filePath);
        if (!file.open(QIODevice::ReadOnly)) {
            fixtureError = QStringLiteral("generated script was unreadable");
            return -1;
        }
        const QByteArray source = file.readAll();
        helperDestination = extractJsonString(
            source,
            QByteArrayLiteral("var helperDestination = "));
        scriptGeneration = extractJsonString(
            source,
            QByteArrayLiteral("var scriptGeneration = "));
        if (helperDestination.isEmpty()
            || !QRegularExpression(QStringLiteral("^[0-9a-f]{32}$"))
                    .match(scriptGeneration)
                    .hasMatch()
            || source.contains("@NAGI_")) {
            fixtureError = QStringLiteral("generated script tokens were invalid");
            return -1;
        }

        const QFileDevice::Permissions permissions = QFileInfo(filePath).permissions();
        const QFileDevice::Permissions forbidden = QFileDevice::ReadGroup
            | QFileDevice::WriteGroup | QFileDevice::ExeGroup | QFileDevice::ReadOther
            | QFileDevice::WriteOther | QFileDevice::ExeOther;
        privatePermissions = !(permissions & forbidden);

        const int id = nextScriptId++;
        auto *script = new FakeScript(id, this);
        const QString path = QStringLiteral("/Scripting/Script%1").arg(id);
        if (!connection.registerObject(
                path,
                script,
                QDBusConnection::ExportScriptableSlots)) {
            fixtureError = QStringLiteral("fake script object registration failed");
            delete script;
            return -1;
        }
        scripts.insert(id, script);
        pluginIds.insert(pluginName, id);
        return id;
    }

    Q_SCRIPTABLE bool unloadScript(const QString &pluginName)
    {
        unloadCount += 1;
        const auto plugin = pluginIds.find(pluginName);
        if (plugin == pluginIds.end()) {
            return false;
        }
        const int id = plugin.value();
        connection.unregisterObject(QStringLiteral("/Scripting/Script%1").arg(id));
        if (FakeScript *script = scripts.take(id)) {
            script->deleteLater();
        }
        pluginIds.erase(plugin);
        return true;
    }
public:

    QDBusConnection connection;
    QHash<int, FakeScript *> scripts;
    QHash<QString, int> pluginIds;
    QString helperDestination;
    QString scriptGeneration;
    QString lastScriptPath;
    QString lastPluginName;
    QString fixtureError;
    int nextScriptId = 0;
    int loadCount = 0;
    int runCount = 0;
    int stopCount = 0;
    int unloadCount = 0;
    bool privatePermissions = false;
};

FakeScript::FakeScript(int id, FakeScripting *scripting)
    : QObject(scripting)
    , id(id)
    , scripting(scripting)
{
}

void FakeScript::run()
{
    scripting->recordRun(id);
}

void FakeScript::stop()
{
    scripting->recordStop(id);
}

class FakeKWinOwner final {
public:
    explicit FakeKWinOwner(QString connectionName)
        : connectionName(std::move(connectionName))
        , connection(QDBusConnection::connectToBus(
              QDBusConnection::SessionBus,
              this->connectionName))
        , scripting(connection)
    {
        objectRegistered = connection.isConnected()
            && connection.registerObject(
                QStringLiteral("/Scripting"),
                &scripting,
                QDBusConnection::ExportScriptableSlots);
    }

    ~FakeKWinOwner()
    {
        if (connection.isConnected()) {
            connection.unregisterService(QString::fromLatin1(Service));
            connection.unregisterObject(QStringLiteral("/Scripting"));
        }
        QDBusConnection::disconnectFromBus(connectionName);
    }

    bool claim(
        QDBusConnectionInterface::ServiceQueueOptions queueOption,
        QDBusConnectionInterface::ServiceReplacementOptions replacementOption)
    {
        if (!objectRegistered || connection.interface() == nullptr) {
            return false;
        }
        const QDBusReply<QDBusConnectionInterface::RegisterServiceReply> reply =
            connection.interface()->registerService(
                QString::fromLatin1(Service),
                queueOption,
                replacementOption);
        return reply.isValid()
            && reply.value() == QDBusConnectionInterface::ServiceRegistered;
    }

    QString connectionName;
    QDBusConnection connection;
    FakeScripting scripting;
    bool objectRegistered = false;
};

class HelperRun final {
public:
    explicit HelperRun(QString helperPath)
        : helperPath(std::move(helperPath))
    {
        process.setProcessChannelMode(QProcess::SeparateChannels);
    }

    ~HelperRun()
    {
        if (process.state() != QProcess::NotRunning) {
            process.kill();
            process.waitForFinished(1000);
        }
    }

    bool start()
    {
        process.start(helperPath);
        return process.waitForStarted(1000);
    }

    void pump()
    {
        outputBuffer.append(process.readAllStandardOutput());
        while (true) {
            const qsizetype newline = outputBuffer.indexOf('\n');
            if (newline < 0) {
                return;
            }
            const QByteArray line = outputBuffer.first(newline);
            outputBuffer.remove(0, newline + 1);
            QJsonParseError error{};
            const QJsonDocument document = QJsonDocument::fromJson(line, &error);
            if (error.error != QJsonParseError::NoError || !document.isObject()) {
                invalidOutput = true;
                continue;
            }
            rawLines.append(line);
            snapshots.append(document.object());
        }
    }

    bool waitForSnapshots(qsizetype count, int timeoutMs = 1000)
    {
        return waitUntil(
            [this, count] {
                pump();
                return snapshots.size() >= count;
            },
            timeoutMs);
    }

    bool waitForExit(int timeoutMs)
    {
        return waitUntil(
            [this] {
                pump();
                return process.state() == QProcess::NotRunning;
            },
            timeoutMs);
    }

    void send(const QByteArray &command)
    {
        process.write(command);
        process.waitForBytesWritten(1000);
    }

    QString helperPath;
    QProcess process;
    QByteArray outputBuffer;
    QList<QByteArray> rawLines;
    QList<QJsonObject> snapshots;
    bool invalidOutput = false;
};

bool validEpoch(const QJsonObject &snapshot)
{
    return QRegularExpression(QStringLiteral("^[0-9a-f]{32}$"))
        .match(snapshot.value(QStringLiteral("helperEpoch")).toString())
        .hasMatch();
}

bool hasExactKeys(const QJsonObject &object, const QStringList &expected)
{
    if (object.size() != expected.size()) {
        return false;
    }
    for (const QString &key : expected) {
        if (!object.contains(key)) {
            return false;
        }
    }
    return true;
}

bool exactWireSchema(const QJsonObject &snapshot)
{
    if (!hasExactKeys(
            snapshot,
            {
                QStringLiteral("desktops"),
                QStringLiteral("helperEpoch"),
                QStringLiteral("outputs"),
                QStringLiteral("version"),
            })
        || !snapshot.value(QStringLiteral("version")).isDouble()
        || snapshot.value(QStringLiteral("version")).toDouble() != 2.0
        || !validEpoch(snapshot)
        || !snapshot.value(QStringLiteral("desktops")).isArray()
        || !snapshot.value(QStringLiteral("outputs")).isArray()) {
        return false;
    }

    const QJsonArray desktops = snapshot.value(QStringLiteral("desktops")).toArray();
    for (const QJsonValue &value : desktops) {
        if (!value.isObject()) {
            return false;
        }
        const QJsonObject desktop = value.toObject();
        if (!hasExactKeys(
                desktop,
                {
                    QStringLiteral("id"),
                    QStringLiteral("name"),
                    QStringLiteral("position"),
                })
            || !desktop.value(QStringLiteral("id")).isString()
            || !desktop.value(QStringLiteral("name")).isString()
            || !desktop.value(QStringLiteral("position")).isDouble()) {
            return false;
        }
    }

    const QJsonArray outputs = snapshot.value(QStringLiteral("outputs")).toArray();
    for (const QJsonValue &value : outputs) {
        if (!value.isObject()) {
            return false;
        }
        const QJsonObject output = value.toObject();
        if (!hasExactKeys(
                output,
                {
                    QStringLiteral("currentId"),
                    QStringLiteral("name"),
                    QStringLiteral("showTransient"),
                })
            || !output.value(QStringLiteral("currentId")).isString()
            || !output.value(QStringLiteral("name")).isString()
            || !output.value(QStringLiteral("showTransient")).isBool()) {
            return false;
        }
    }
    return true;
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

bool isCanonicalUnavailable(const QJsonObject &snapshot)
{
    return snapshot.value(QStringLiteral("desktops")).toArray().isEmpty()
        && snapshot.value(QStringLiteral("outputs")).toArray().isEmpty();
}

bool testPermanentInitializationFailure(const QString &helperPath)
{
    HelperRun helper(helperPath);
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    environment.insert(
        QStringLiteral("DBUS_SESSION_BUS_ADDRESS"),
        QStringLiteral("unix:path=/nonexistent/nagi-shell-session-bus-%1")
            .arg(QCoreApplication::applicationPid()));
    helper.process.setProcessEnvironment(environment);

    if (!require(helper.start(), "helper starts with an unreachable session bus")
        || !require(helper.waitForExit(1500), "permanent initialization failure exits promptly")
        || !require(
            helper.process.exitStatus() == QProcess::NormalExit,
            "permanent initialization failure exits normally")
        || !require(
            helper.process.exitCode() != 0,
            "permanent initialization failure exits nonzero")
        || !require(
            helper.process.state() == QProcess::NotRunning,
            "failed initialization leaves no live helper process")
        || !require(
            helper.snapshots.size() == 1,
            "failed initialization publishes one unavailable snapshot")
        || !require(
            exactWireSchema(helper.snapshots.constFirst()),
            "failed initialization preserves the wire schema")
        || !require(
            validEpoch(helper.snapshots.constFirst()),
            "failed initialization publishes a bounded helper epoch")
        || !require(
            isCanonicalUnavailable(helper.snapshots.constFirst()),
            "failed initialization stays canonically unavailable")) {
        return false;
    }
    return true;
}

bool testLifecycleAndReplacement(
    const QString &helperPath,
    FakeKWinOwner &firstOwner,
    FakeKWinOwner &secondOwner,
    const QDBusConnection &foreignConnection,
    QString *firstEpoch)
{
    HelperRun helper(helperPath);
    if (!require(helper.start(), "helper starts")
        || !require(
            waitUntil(
                [&] {
                    helper.pump();
                    return firstOwner.scripting.loadCount == 1
                        && firstOwner.scripting.runCount == 1
                        && !helper.snapshots.isEmpty();
                },
                1500),
            "first owner loads and runs one generated script")) {
        return false;
    }

    const QJsonObject initial = helper.snapshots.constFirst();
    *firstEpoch = initial.value(QStringLiteral("helperEpoch")).toString();
    if (!require(!helper.invalidOutput, "helper emits newline JSON only")
        || !require(exactWireSchema(initial), "initial wire schema is exact")
        || !require(validEpoch(initial), "helper epoch is 32 lowercase hex")
        || !require(initial.value(QStringLiteral("version")).toInt() == 2, "wire version is two")
        || !require(
            isCanonicalUnavailable(initial),
            "owner attach starts canonically unavailable")
        || !require(firstOwner.scripting.fixtureError.isEmpty(), "generated script fixture parsed")
        || !require(firstOwner.scripting.privatePermissions, "generated script is mode-private")
        || !require(
            QFileInfo::exists(firstOwner.scripting.lastScriptPath),
            "generated script remains for the owner lifetime")) {
        return false;
    }

    helper.send("{\"op\":\"unknown\"}\n");
    firstOwner.scripting.publish(projectionPayload(), {}, &foreignConnection);
    spinEvents(100);
    helper.pump();
    if (!require(helper.process.state() == QProcess::Running, "unknown command does not stop helper")
        || !require(helper.snapshots.size() == 1, "foreign callback is rejected")) {
        return false;
    }

    firstOwner.scripting.publish(projectionPayload());
    if (!require(helper.waitForSnapshots(2), "authenticated callback publishes")
        || !require(exactWireSchema(helper.snapshots.at(1)), "projection wire schema is exact")
        || !require(
            helper.snapshots.at(1).value(QStringLiteral("helperEpoch")).toString() == *firstEpoch,
            "helper epoch is stable across snapshots")
        || !require(
            helper.snapshots.at(1).value(QStringLiteral("outputs")).toArray().size() == 1,
            "one output projection is preserved")
        || !require(
            outputByName(helper.snapshots.at(1), QStringLiteral("Virtual-1"))
                    .value(QStringLiteral("currentId"))
                    .toString()
                == QStringLiteral("desktop-one"),
            "output current desktop is canonical")
        || !require(
            !outputByName(helper.snapshots.at(1), QStringLiteral("Virtual-1"))
                 .value(QStringLiteral("showTransient"))
                 .toBool(),
            "initial output projection suppresses feedback")) {
        return false;
    }

    const qsizetype beforeDedup = helper.snapshots.size();
    firstOwner.scripting.publish(projectionPayload());
    QJsonObject forbidden = projectionPayload(QStringLiteral("desktop-two"), true);
    forbidden.insert(QStringLiteral("outputName"), QStringLiteral("forbidden"));
    firstOwner.scripting.publish(forbidden);
    firstOwner.scripting.publish(
        projectionPayload(QStringLiteral("desktop-two"), true),
        QStringLiteral("00000000000000000000000000000000"));
    spinEvents(150);
    helper.pump();
    if (!require(helper.snapshots.size() == beforeDedup, "dedup, schema, and stale-token rejection are silent")) {
        return false;
    }

    firstOwner.scripting.publish(projectionPayload(QStringLiteral("desktop-two"), true));
    if (!require(helper.waitForSnapshots(beforeDedup + 1), "confirmed output switch publishes")) {
        return false;
    }
    const QJsonObject switchedSnapshot = helper.snapshots.constLast();
    const QJsonObject switchedOutput =
        outputByName(switchedSnapshot, QStringLiteral("Virtual-1"));
    if (!require(exactWireSchema(switchedSnapshot), "changed projection wire schema is exact")
        || !require(
            switchedOutput.value(QStringLiteral("currentId")).toString()
                    == QStringLiteral("desktop-two")
                && switchedOutput.value(QStringLiteral("showTransient")).toBool(),
            "changed output retains its current desktop and transient intent")) {
        return false;
    }

    const QString firstGeneration = firstOwner.scripting.scriptGeneration;
    const QString firstScriptPath = firstOwner.scripting.lastScriptPath;
    const qsizetype beforeReplacement = helper.snapshots.size();
    if (!require(
            secondOwner.claim(
                QDBusConnectionInterface::ReplaceExistingService,
                QDBusConnectionInterface::DontAllowReplacement),
            "replacement owner takes the KWin name")
        || !require(
            waitUntil(
                [&] {
                    helper.pump();
                    return firstOwner.scripting.stopCount == 1
                        && firstOwner.scripting.unloadCount == 1
                        && secondOwner.scripting.loadCount == 1
                        && secondOwner.scripting.runCount == 1
                        && helper.snapshots.size() >= beforeReplacement + 1;
                },
                2000),
            "owner replacement retires then attaches exactly once")) {
        return false;
    }

    const QJsonObject replacementUnavailable = helper.snapshots.at(beforeReplacement);
    if (!require(!QFileInfo::exists(firstScriptPath), "retired generation temp file is removed")
        || !require(
            exactWireSchema(replacementUnavailable)
                && isCanonicalUnavailable(replacementUnavailable),
            "canonical unavailable state publishes before replacement recovery")) {
        return false;
    }

    const qsizetype beforeStaleOwner = helper.snapshots.size();
    firstOwner.scripting.publish(projectionPayload(), firstGeneration);
    secondOwner.scripting.publish(replacementPayload(), firstGeneration);
    spinEvents(150);
    helper.pump();
    if (!require(
            helper.snapshots.size() == beforeStaleOwner,
            "retired sender and retired generation callbacks are rejected")) {
        return false;
    }

    secondOwner.scripting.publish(replacementPayload());
    if (!require(helper.waitForSnapshots(beforeStaleOwner + 1), "replacement owner publishes")) {
        return false;
    }
    const QJsonObject replacement = helper.snapshots.constLast();
    if (!require(exactWireSchema(replacement), "replacement wire schema is exact")
        || !require(
            outputByName(replacement, QStringLiteral("Virtual-1"))
                    .value(QStringLiteral("currentId"))
                    .toString()
                == QStringLiteral("new-owner-desktop"),
            "replacement projection is accepted")
        || !require(
            !outputByName(replacement, QStringLiteral("Virtual-1"))
                 .value(QStringLiteral("showTransient"))
                 .toBool(),
            "replacement recovery suppresses feedback")) {
        return false;
    }

    const QString secondScriptPath = secondOwner.scripting.lastScriptPath;
    helper.send("{\"op\":\"shutdown\"}\n");
    if (!require(helper.waitForExit(5000), "shutdown command exits helper")
        || !require(helper.process.exitStatus() == QProcess::NormalExit, "shutdown is a normal exit")
        || !require(helper.process.exitCode() == 0, "shutdown exits zero")
        || !require(secondOwner.scripting.stopCount == 1, "shutdown stops active script")
        || !require(secondOwner.scripting.unloadCount == 1, "shutdown unloads active plugin")
        || !require(!QFileInfo::exists(secondScriptPath), "shutdown removes generated script")
        || !require(helper.process.state() == QProcess::NotRunning, "shutdown leaves no helper process")) {
        return false;
    }
    return true;
}

bool testTimeoutAndEof(
    const QString &helperPath,
    FakeKWinOwner &owner,
    const QDBusConnection &foreignConnection,
    const QString &previousEpoch)
{
    const int initialLoads = owner.scripting.loadCount;
    const int initialRuns = owner.scripting.runCount;
    const int initialStops = owner.scripting.stopCount;
    const int initialUnloads = owner.scripting.unloadCount;

    HelperRun helper(helperPath);
    if (!require(helper.start(), "timeout helper starts")
        || !require(
            waitUntil(
                [&] {
                    helper.pump();
                    return owner.scripting.loadCount == initialLoads + 1
                        && owner.scripting.runCount == initialRuns + 1
                        && !helper.snapshots.isEmpty();
                },
                1500),
            "timeout generation loads and runs")) {
        return false;
    }

    const QJsonObject timeoutInitial = helper.snapshots.constFirst();
    const QString epoch = timeoutInitial.value(QStringLiteral("helperEpoch")).toString();
    if (!require(
            exactWireSchema(timeoutInitial) && isCanonicalUnavailable(timeoutInitial),
            "timeout generation starts canonically unavailable")
        || !require(validEpoch(timeoutInitial), "timeout helper epoch is valid")
        || !require(epoch != previousEpoch, "new helper process has a new epoch")) {
        return false;
    }

    QJsonObject invalid = replacementPayload();
    invalid.insert(QStringLiteral("screenIndex"), 0);
    owner.scripting.publish(invalid);
    owner.scripting.publish(replacementPayload(), {}, &foreignConnection);
    const QString scriptPath = owner.scripting.lastScriptPath;
    if (!require(
            waitUntil(
                [&] {
                    helper.pump();
                    return owner.scripting.stopCount == initialStops + 1
                        && owner.scripting.unloadCount == initialUnloads + 1
                        && !QFileInfo::exists(owner.scripting.lastScriptPath);
                },
                3500),
            "invalid first callbacks do not satisfy the snapshot timeout")
        || !require(helper.snapshots.size() == 1, "timeout remains canonically unavailable")
        || !require(helper.process.state() == QProcess::Running, "snapshot timeout does not crash helper")
        || !require(!QFileInfo::exists(scriptPath), "timeout removes the retired temp script")) {
        return false;
    }

    helper.process.closeWriteChannel();
    if (!require(helper.waitForExit(3000), "stdin EOF exits helper")
        || !require(helper.process.exitStatus() == QProcess::NormalExit, "EOF is a normal exit")
        || !require(helper.process.exitCode() == 0, "EOF exits zero")
        || !require(helper.process.state() == QProcess::NotRunning, "EOF leaves no helper process")) {
        return false;
    }
    return true;
}

bool testSignalTermination(const QString &helperPath, FakeKWinOwner &owner)
{
    const int initialLoads = owner.scripting.loadCount;
    const int initialRuns = owner.scripting.runCount;
    const int initialStops = owner.scripting.stopCount;
    const int initialUnloads = owner.scripting.unloadCount;

    HelperRun helper(helperPath);
    if (!require(helper.start(), "signal helper starts")
        || !require(
            waitUntil(
                [&] {
                    helper.pump();
                    return owner.scripting.loadCount == initialLoads + 1
                        && owner.scripting.runCount == initialRuns + 1
                        && !helper.snapshots.isEmpty();
                },
                1500),
            "signal generation loads and runs")) {
        return false;
    }

    if (!require(
            exactWireSchema(helper.snapshots.constFirst())
                && isCanonicalUnavailable(helper.snapshots.constFirst()),
            "signal generation starts canonically unavailable")) {
        return false;
    }

    const QString scriptPath = owner.scripting.lastScriptPath;
    helper.process.terminate();
    if (!require(helper.waitForExit(5000), "SIGTERM exits helper within the cleanup bound")
        || !require(helper.process.exitStatus() == QProcess::NormalExit, "SIGTERM is a normal exit")
        || !require(helper.process.exitCode() == 0, "SIGTERM exits zero")
        || !require(owner.scripting.stopCount == initialStops + 1, "SIGTERM stops active script")
        || !require(owner.scripting.unloadCount == initialUnloads + 1, "SIGTERM unloads active plugin")
        || !require(!QFileInfo::exists(scriptPath), "SIGTERM removes generated script")
        || !require(helper.process.state() == QProcess::NotRunning, "SIGTERM leaves no helper process")) {
        return false;
    }
    return true;
}


} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    if (application.arguments().size() != 2) {
        qCritical("usage: kwin-owner-lifecycle-test HELPER");
        return 2;
    }

    const QString suffix = QString::number(QCoreApplication::applicationPid());
    FakeKWinOwner firstOwner(QStringLiteral("nagi-workspace-owner-one-%1").arg(suffix));
    FakeKWinOwner secondOwner(QStringLiteral("nagi-workspace-owner-two-%1").arg(suffix));
    const QString foreignName = QStringLiteral("nagi-workspace-foreign-%1").arg(suffix);
    const QDBusConnection foreignConnection = QDBusConnection::connectToBus(
        QDBusConnection::SessionBus,
        foreignName);

    if (!require(firstOwner.objectRegistered && secondOwner.objectRegistered, "fake scripting objects register")
        || !require(foreignConnection.isConnected(), "foreign D-Bus sender connects")
        || !require(
            firstOwner.claim(
                QDBusConnectionInterface::DontQueueService,
                QDBusConnectionInterface::AllowReplacement),
            "first fake KWin owner registers")) {
        QDBusConnection::disconnectFromBus(foreignName);
        return 1;
    }

    QString firstEpoch;
    const QString helperPath = application.arguments().at(1);
    const bool initializationFailurePassed = testPermanentInitializationFailure(helperPath);
    const bool lifecyclePassed = initializationFailurePassed && testLifecycleAndReplacement(
        helperPath,
        firstOwner,
        secondOwner,
        foreignConnection,
        &firstEpoch);
    const bool timeoutPassed = lifecyclePassed
        && testTimeoutAndEof(
            helperPath,
            secondOwner,
            foreignConnection,
            firstEpoch);
    const bool signalPassed = timeoutPassed
        && testSignalTermination(helperPath, secondOwner);
    QDBusConnection::disconnectFromBus(foreignName);

    if (!signalPassed) {
        return 1;
    }
    qInfo("owner lifecycle tests passed");
    return 0;
}

#include "kwin_owner_lifecycle_test.moc"

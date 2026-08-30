#include "desktop_snapshot.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusContext>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusServiceWatcher>
#include <QDir>
#include <QFile>
#include <QFileDevice>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QRandomGenerator>
#include <QSet>
#include <QSocketNotifier>
#include <QTemporaryFile>
#include <QTimer>
#include <QVariant>

#include <array>
#include <cerrno>
#include <csignal>
#include <cstdio>
#include <fcntl.h>
#include <memory>
#include <unistd.h>

namespace {

constexpr auto KWinService = "org.kde.KWin";
constexpr auto ScriptingPath = "/Scripting";
constexpr auto ScriptingInterface = "org.kde.kwin.Scripting";
constexpr auto ScriptInterface = "org.kde.kwin.Script";
constexpr auto CallbackPath = "/WorkspaceConsensus";
constexpr auto ScriptTemplateName = "nagi-kwin-workspace-consensus.js.in";
constexpr auto DestinationPlaceholder = "@NAGI_HELPER_DESTINATION@";
constexpr auto GenerationPlaceholder = "@NAGI_SCRIPT_GENERATION@";
constexpr auto ReadyEvent = "ready";
constexpr int SnapshotTimeoutMs = 2000;
constexpr int DbusTimeoutMs = 2000;
constexpr int MaximumDiagnostics = 8;
constexpr qsizetype MaximumCommandLength = 4096;
volatile std::sig_atomic_t signalWriteFd = -1;

void handleTerminationSignal(int)
{
    const std::sig_atomic_t writeFd = signalWriteFd;
    if (writeFd < 0) {
        return;
    }
    const char byte = 1;
    const ssize_t ignored = ::write(static_cast<int>(writeFd), &byte, sizeof(byte));
    (void)ignored;
}

bool installTerminationPipe(
    std::array<int, 2> *pipeFds,
    struct sigaction *previousAction)
{
    if (::pipe2(pipeFds->data(), O_CLOEXEC | O_NONBLOCK) != 0) {
        return false;
    }
    signalWriteFd = (*pipeFds)[1];

    struct sigaction action {};
    action.sa_handler = handleTerminationSignal;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_RESTART;
    if (::sigaction(SIGTERM, &action, previousAction) != 0) {
        ::close((*pipeFds)[0]);
        ::close((*pipeFds)[1]);
        signalWriteFd = -1;
        return false;
    }
    return true;
}

QString randomToken()
{
    QByteArray bytes(16, '\0');
    QRandomGenerator *generator = QRandomGenerator::system();
    for (qsizetype offset = 0; offset < bytes.size(); offset += 4) {
        const quint32 value = generator->generate();
        bytes[offset] = static_cast<char>(value & 0xffU);
        bytes[offset + 1] = static_cast<char>((value >> 8U) & 0xffU);
        bytes[offset + 2] = static_cast<char>((value >> 16U) & 0xffU);
        bytes[offset + 3] = static_cast<char>((value >> 24U) & 0xffU);
    }
    return QString::fromLatin1(bytes.toHex());
}

QByteArray jsonStringLiteral(const QString &value)
{
    const QByteArray array = QJsonDocument(QJsonArray{value}).toJson(QJsonDocument::Compact);
    return array.mid(1, array.size() - 2);
}

class WorkspaceConsensusObserver final : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "io.github.Anthodev.NagiShell.WorkspaceConsensus")

public:
    explicit WorkspaceConsensusObserver(QObject *parent = nullptr)
        : QObject(parent)
        , bus(QDBusConnection::sessionBus())
        , watcher(
              QString::fromLatin1(KWinService),
              bus,
              QDBusServiceWatcher::WatchForOwnerChange,
              this)
        , inputNotifier(STDIN_FILENO, QSocketNotifier::Read, this)
        , helperEpoch(randomToken())
    {
        snapshotTimer.setSingleShot(true);
        snapshotTimer.setInterval(SnapshotTimeoutMs);
        connect(
            &watcher,
            &QDBusServiceWatcher::serviceOwnerChanged,
            this,
            &WorkspaceConsensusObserver::onServiceOwnerChanged);
        connect(
            &snapshotTimer,
            &QTimer::timeout,
            this,
            &WorkspaceConsensusObserver::onSnapshotTimeout);
        connect(
            &inputNotifier,
            &QSocketNotifier::activated,
            this,
            [this] { readCommands(); });
        QTimer::singleShot(0, this, &WorkspaceConsensusObserver::initialize);
    }

    ~WorkspaceConsensusObserver() override
    {
        shutdown(false);
    }

public Q_SLOTS:
    Q_SCRIPTABLE void Publish(const QString &generation, const QString &payload)
    {
        if (shuttingDown || activeOwner.isEmpty() || activeGeneration.isEmpty()
            || !scriptRunning || !calledFromDBus() || message().service() != activeOwner
            || generation != activeGeneration) {
            diagnose(QStringLiteral("rejected unauthenticated workspace callback"));
            return;
        }

        QString error;
        const auto snapshot = nagi::kwin::canonicalizeScriptSnapshot(
            payload,
            helperEpoch,
            &error);
        if (!snapshot) {
            diagnose(error);
            return;
        }

        snapshotTimer.stop();
        receivedFirstSnapshot = true;
        publishSnapshot(*snapshot);
    }

private:
    void failInitialization(const QString &message)
    {
        diagnose(message);
        shutdown(false);
        QCoreApplication::exit(2);
    }

    void initialize()
    {
        if (shuttingDown) {
            return;
        }
        publishSnapshot(nagi::kwin::unavailableSnapshotJson(helperEpoch));
        if (shuttingDown) {
            return;
        }
        if (!bus.isConnected()) {
            failInitialization(QStringLiteral("session bus is unavailable"));
            return;
        }

        helperDestination = bus.baseService();
        if (helperDestination.isEmpty()
            || !bus.registerObject(
                QString::fromLatin1(CallbackPath),
                this,
                QDBusConnection::ExportScriptableSlots)) {
            failInitialization(QStringLiteral("workspace callback registration failed"));
            return;
        }
        callbackRegistered = true;
        if (!publishReady()) {
            shutdown(false);
            QCoreApplication::exit(2);
            return;
        }


        const QString owner = currentServiceOwner();
        if (!owner.isEmpty()) {
            attachOwner(owner);
        }
    }

    QString currentServiceOwner() const
    {
        QDBusConnectionInterface *connectionInterface = bus.interface();
        if (connectionInterface == nullptr) {
            return {};
        }
        const QDBusReply<QString> reply = connectionInterface->serviceOwner(
            QString::fromLatin1(KWinService));
        return reply.isValid() ? reply.value() : QString{};
    }

    bool serviceIsCallable(const QString &service) const
    {
        if (service.isEmpty() || bus.interface() == nullptr) {
            return false;
        }
        const QDBusReply<bool> reply = bus.interface()->isServiceRegistered(service);
        return reply.isValid() && reply.value();
    }

    void onServiceOwnerChanged(
        const QString &,
        const QString &,
        const QString &newOwner)
    {
        if (shuttingDown || newOwner == activeOwner) {
            return;
        }

        detachOwner(true);
        publishSnapshot(nagi::kwin::unavailableSnapshotJson(helperEpoch));
        if (!newOwner.isEmpty()) {
            attachOwner(newOwner);
        }
    }

    void attachOwner(const QString &owner)
    {
        if (shuttingDown || owner.isEmpty() || owner == activeOwner) {
            return;
        }
        if (!activeOwner.isEmpty()) {
            detachOwner(true);
        }

        activeOwner = owner;
        publishSnapshot(nagi::kwin::unavailableSnapshotJson(helperEpoch));
        activeGeneration = randomToken();
        pluginName = QStringLiteral("nagi-workspace-consensus-%1").arg(activeGeneration);
        receivedFirstSnapshot = false;

        if (!renderScript()) {
            retireGeneration(false);
            return;
        }

        const QDBusMessage loadReply = callKWin(
            activeOwner,
            QString::fromLatin1(ScriptingPath),
            QString::fromLatin1(ScriptingInterface),
            QStringLiteral("loadScript"),
            {QVariant(temporaryScript->fileName()), QVariant(pluginName)});
        bool validScriptId = false;
        if (loadReply.type() == QDBusMessage::ReplyMessage && loadReply.arguments().size() == 1) {
            scriptId = loadReply.arguments().constFirst().toInt(&validScriptId);
        }
        if (!validScriptId || scriptId < 0) {
            diagnose(QStringLiteral("KWin workspace script failed to load"));
            scriptId = -1;
            retireGeneration(true);
            return;
        }

        scriptRunning = true;
        const QDBusMessage runReply = callKWin(
            activeOwner,
            scriptObjectPath(scriptId),
            QString::fromLatin1(ScriptInterface),
            QStringLiteral("run"));
        if (runReply.type() != QDBusMessage::ReplyMessage) {
            diagnose(QStringLiteral("KWin workspace script failed to run"));
            retireGeneration(true);
            return;
        }

        snapshotTimer.start();
    }

    bool renderScript()
    {
        QFile templateFile(
            QDir(QCoreApplication::applicationDirPath()).filePath(
                QString::fromLatin1(ScriptTemplateName)));
        if (!templateFile.open(QIODevice::ReadOnly)) {
            diagnose(QStringLiteral("workspace script template is unavailable"));
            return false;
        }

        QByteArray rendered = templateFile.readAll();
        const QByteArray destinationToken(DestinationPlaceholder);
        const QByteArray generationToken(GenerationPlaceholder);
        if (rendered.count(destinationToken) != 1 || rendered.count(generationToken) != 1) {
            diagnose(QStringLiteral("workspace script template is invalid"));
            return false;
        }
        rendered.replace(destinationToken, jsonStringLiteral(helperDestination));
        rendered.replace(generationToken, jsonStringLiteral(activeGeneration));

        auto candidate = std::make_unique<QTemporaryFile>(
            QDir::tempPath() + QStringLiteral("/nagi-workspace-consensus-XXXXXX.js"));
        candidate->setAutoRemove(true);
        if (!candidate->open()
            || !candidate->setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner)
            || candidate->write(rendered) != rendered.size() || !candidate->flush()) {
            diagnose(QStringLiteral("private workspace script creation failed"));
            return false;
        }
        candidate->close();
        temporaryScript = std::move(candidate);
        return true;
    }

    static QString scriptObjectPath(int id)
    {
        return QStringLiteral("/Scripting/Script%1").arg(id);
    }

    QDBusMessage callKWin(
        const QString &owner,
        const QString &path,
        const QString &interface,
        const QString &method,
        const QList<QVariant> &arguments = {}) const
    {
        QDBusMessage request = QDBusMessage::createMethodCall(owner, path, interface, method);
        request.setArguments(arguments);
        return bus.call(request, QDBus::Block, DbusTimeoutMs);
    }

    void onSnapshotTimeout()
    {
        if (shuttingDown || activeGeneration.isEmpty() || receivedFirstSnapshot) {
            return;
        }
        diagnose(QStringLiteral("first workspace snapshot timed out"));
        retireGeneration(true);
        publishSnapshot(nagi::kwin::unavailableSnapshotJson(helperEpoch));
    }

    void retireGeneration(bool attemptCleanup)
    {
        snapshotTimer.stop();
        activeGeneration.clear();
        receivedFirstSnapshot = false;

        const QString retiredPluginName = pluginName;
        const int retiredScriptId = scriptId;
        const bool shouldCallOwner = attemptCleanup && serviceIsCallable(activeOwner);
        pluginName.clear();
        scriptId = -1;
        scriptRunning = false;

        if (shouldCallOwner && retiredScriptId >= 0) {
            const QDBusMessage stopReply = callKWin(
                activeOwner,
                scriptObjectPath(retiredScriptId),
                QString::fromLatin1(ScriptInterface),
                QStringLiteral("stop"));
            if (stopReply.type() != QDBusMessage::ReplyMessage) {
                diagnose(QStringLiteral("KWin workspace script failed to stop"));
            }
        }
        if (shouldCallOwner && !retiredPluginName.isEmpty()) {
            const QDBusMessage unloadReply = callKWin(
                activeOwner,
                QString::fromLatin1(ScriptingPath),
                QString::fromLatin1(ScriptingInterface),
                QStringLiteral("unloadScript"),
                {QVariant(retiredPluginName)});
            if (unloadReply.type() != QDBusMessage::ReplyMessage) {
                diagnose(QStringLiteral("KWin workspace script failed to unload"));
            }
        }
        temporaryScript.reset();
    }

    void detachOwner(bool attemptCleanup)
    {
        retireGeneration(attemptCleanup);
        activeOwner.clear();
    }

    void readCommands()
    {
        std::array<char, 1024> chunk{};
        while (!shuttingDown) {
            const ssize_t count = ::read(STDIN_FILENO, chunk.data(), chunk.size());
            if (count > 0) {
                commandBuffer.append(chunk.data(), count);
                consumeCommands();
                continue;
            }
            if (count == 0) {
                shutdown(true);
                return;
            }
            if (errno == EINTR) {
                continue;
            }
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                return;
            }
            diagnose(QStringLiteral("workspace helper input failed"));
            shutdown(false);
            QCoreApplication::exit(2);
            return;
        }
    }

    void consumeCommands()
    {
        while (!shuttingDown) {
            if (discardingCommand) {
                const qsizetype newline = commandBuffer.indexOf('\n');
                if (newline < 0) {
                    commandBuffer.clear();
                    return;
                }
                commandBuffer.remove(0, newline + 1);
                discardingCommand = false;
                diagnose(QStringLiteral("oversized workspace helper command rejected"));
                continue;
            }

            const qsizetype newline = commandBuffer.indexOf('\n');
            if (newline < 0) {
                if (commandBuffer.size() > MaximumCommandLength) {
                    commandBuffer.clear();
                    discardingCommand = true;
                }
                return;
            }

            const QByteArray frame = commandBuffer.first(newline);
            commandBuffer.remove(0, newline + 1);
            if (frame.isEmpty() || frame.size() > MaximumCommandLength) {
                diagnose(QStringLiteral("invalid workspace helper command rejected"));
                continue;
            }
            handleCommand(frame);
        }
    }

    void handleCommand(const QByteArray &frame)
    {
        QJsonParseError error{};
        const QJsonDocument document = QJsonDocument::fromJson(frame, &error);
        if (error.error != QJsonParseError::NoError || !document.isObject()) {
            diagnose(QStringLiteral("invalid workspace helper command rejected"));
            return;
        }

        const QJsonObject command = document.object();
        if (command.size() == 1 && command.value(QStringLiteral("op")).isString()
            && command.value(QStringLiteral("op")).toString() == QStringLiteral("shutdown")) {
            shutdown(true);
            return;
        }
        diagnose(QStringLiteral("unknown workspace helper command rejected"));
    }

    void shutdown(bool quitApplication)
    {
        if (shuttingDown) {
            return;
        }
        shuttingDown = true;
        inputNotifier.setEnabled(false);
        detachOwner(true);
        if (callbackRegistered) {
            bus.unregisterObject(QString::fromLatin1(CallbackPath));
            callbackRegistered = false;
        }
        if (quitApplication) {
            QCoreApplication::quit();
        }
    }

    void publishSnapshot(const QByteArray &snapshot)
    {
        if (!snapshotDeduplicator.shouldPublish(snapshot)) {
            return;
        }
        const size_t expected = static_cast<size_t>(snapshot.size());
        if (std::fwrite(snapshot.constData(), 1, expected, stdout) != expected
            || std::fputc('\n', stdout) == EOF || std::fflush(stdout) != 0) {
            diagnose(QStringLiteral("workspace helper output failed"));
            shutdown(false);
            QCoreApplication::exit(2);
        }
    }

    bool publishReady()
    {
        const QByteArray frame = QJsonDocument(
                                     QJsonObject{
                                         {QStringLiteral("event"),
                                          QString::fromLatin1(ReadyEvent)},
                                         {QStringLiteral("helperEpoch"), helperEpoch},
                                         {QStringLiteral("version"), 1},
                                     })
                                     .toJson(QJsonDocument::Compact);
        const size_t expected = static_cast<size_t>(frame.size());
        return std::fwrite(frame.constData(), 1, expected, stderr) == expected
            && std::fputc('\n', stderr) != EOF && std::fflush(stderr) == 0;
    }

    void diagnose(const QString &message)
    {
        const QString bounded = message.left(256);
        if (emittedDiagnostics.size() >= MaximumDiagnostics
            || emittedDiagnostics.contains(bounded)) {
            return;
        }
        emittedDiagnostics.insert(bounded);
        const QByteArray encoded = bounded.toUtf8().left(256);
        std::fprintf(stderr, "nagi-shell KWin helper: %s\n", encoded.constData());
        std::fflush(stderr);
    }

    QDBusConnection bus;
    QDBusServiceWatcher watcher;
    QSocketNotifier inputNotifier;
    QTimer snapshotTimer;
    nagi::kwin::SnapshotDeduplicator snapshotDeduplicator;
    std::unique_ptr<QTemporaryFile> temporaryScript;
    QString helperEpoch;
    QString helperDestination;
    QString activeOwner;
    QString activeGeneration;
    QString pluginName;
    QSet<QString> emittedDiagnostics;
    QByteArray commandBuffer;
    int scriptId = -1;
    bool callbackRegistered = false;
    bool scriptRunning = false;
    bool receivedFirstSnapshot = false;
    bool discardingCommand = false;
    bool shuttingDown = false;
};

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    const int inputFlags = ::fcntl(STDIN_FILENO, F_GETFL, 0);
    if (inputFlags < 0 || ::fcntl(STDIN_FILENO, F_SETFL, inputFlags | O_NONBLOCK) < 0) {
        std::fprintf(stderr, "nagi-shell KWin helper: workspace helper input setup failed\n");
        return 2;
    }

    std::array<int, 2> pipeFds {-1, -1};
    struct sigaction previousTerminationAction {};
    if (!installTerminationPipe(&pipeFds, &previousTerminationAction)) {
        std::fprintf(stderr, "nagi-shell KWin helper: termination setup failed\n");
        return 2;
    }
    QSocketNotifier terminationNotifier(pipeFds[0], QSocketNotifier::Read);
    QObject::connect(&terminationNotifier, &QSocketNotifier::activated, &application, [&application] {
        application.quit();
    });

    WorkspaceConsensusObserver observer;
    const int result = application.exec();
    sigset_t terminationMask {};
    sigemptyset(&terminationMask);
    sigaddset(&terminationMask, SIGTERM);
    ::sigprocmask(SIG_BLOCK, &terminationMask, nullptr);
    signalWriteFd = -1;
    ::sigaction(SIGTERM, &previousTerminationAction, nullptr);
    ::close(pipeFds[0]);
    ::close(pipeFds[1]);
    return result;
}

#include "main.moc"

#define QT_NO_KEYWORDS

#include <KGlobalAccel>
#include <KGlobalShortcutInfo>

#include "registration_policy.h"

#include <QAction>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusReply>
#include <QDBusServiceWatcher>
#include <QFile>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeySequence>
#include <QLockFile>
#include <QSocketNotifier>
#include <QStandardPaths>
#include <QTimer>

#include <array>
#include <cerrno>
#include <csignal>
#include <fcntl.h>
#include <unistd.h>

namespace {
constexpr auto kComponentId = "io.github.Anthodev.NagiShell";
constexpr auto kComponentName = "Nagi Shell";
constexpr auto kActionId = "open-launcher";
constexpr auto kActionName = "Open Launcher";
constexpr auto kPreferredShortcut = "Meta+Space";
constexpr auto kServiceName = "org.kde.kglobalaccel";
constexpr qsizetype kMaximumOutputLineBytes = 512;

int signalWriteFd = -1;

void handleTerminationSignal(int)
{
    if (signalWriteFd < 0) {
        return;
    }
    const char byte = 1;
    const ssize_t ignored = ::write(signalWriteFd, &byte, sizeof(byte));
    (void)ignored;
}

bool installTerminationPipe(std::array<int, 2> *pipeFds)
{
    if (::pipe2(pipeFds->data(), O_CLOEXEC | O_NONBLOCK) != 0) {
        return false;
    }
    signalWriteFd = (*pipeFds)[1];

    struct sigaction action {};
    action.sa_handler = handleTerminationSignal;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_RESTART;
    if (::sigaction(SIGTERM, &action, nullptr) != 0) {
        ::close((*pipeFds)[0]);
        ::close((*pipeFds)[1]);
        signalWriteFd = -1;
        return false;
    }
    return true;
}

class ShortcutHelper final : public QObject {
public:
    explicit ShortcutHelper(QObject *parent = nullptr)
        : QObject(parent)
        , m_output()
        , m_action(this)
        , m_serviceWatcher(QString::fromLatin1(kServiceName), QDBusConnection::sessionBus(),
                           QDBusServiceWatcher::WatchForOwnerChange, this)
    {
        if (!m_output.open(STDOUT_FILENO, QIODevice::WriteOnly, QFileDevice::DontCloseHandle)) {
            QCoreApplication::exit(2);
            return;
        }

        m_action.setObjectName(QString::fromLatin1(kActionId));
        m_action.setText(QString::fromLatin1(kActionName));
        m_action.setProperty("componentName", QString::fromLatin1(kComponentId));
        m_action.setProperty("componentDisplayName", QString::fromLatin1(kComponentName));
        m_action.setAutoRepeat(false);

        connect(&m_action, &QAction::triggered, this, [this] {
            publish(QJsonObject {{QStringLiteral("type"), QStringLiteral("activation")},
                                 {QStringLiteral("action"), QStringLiteral("openLauncher")}});
        });
        connect(KGlobalAccel::self(), &KGlobalAccel::globalShortcutChanged, this,
                [this](QAction *action, const QKeySequence &) {
                    if (m_initialized && action == &m_action) {
                        publishState(true);
                    }
                });
        connect(&m_serviceWatcher, &QDBusServiceWatcher::serviceUnregistered, this,
                [this] { publishUnavailable(); });
        connect(&m_serviceWatcher, &QDBusServiceWatcher::serviceRegistered, this, [this] {
            QTimer::singleShot(250, this, [this] { publishState(true); });
        });

        registerAction();
    }

private:
    void registerAction()
    {
        const QKeySequence preferred =
            QKeySequence::fromString(QString::fromLatin1(kPreferredShortcut),
                                     QKeySequence::PortableText);
        const bool defaultRegistered = KGlobalAccel::self()->setDefaultShortcut(
            &m_action, {preferred}, KGlobalAccel::NoAutoloading);
        const QList<QKeySequence> persisted = KGlobalAccel::self()->globalShortcut(
            QString::fromLatin1(kComponentId), QString::fromLatin1(kActionId));
        const bool preferredAvailable = KGlobalAccel::isGlobalShortcutAvailable(preferred);
        const QList<QKeySequence> proposal =
            initialShortcutProposal(persisted, preferred, preferredAvailable);
        const bool actionRegistered = KGlobalAccel::self()->setShortcut(
            &m_action, proposal, KGlobalAccel::Autoloading);
        const QDBusReply<bool> serviceRegistered =
            QDBusConnection::sessionBus().interface()->isServiceRegistered(
                QString::fromLatin1(kServiceName));
        m_initialized = true;
        publishState(defaultRegistered && actionRegistered && serviceRegistered.isValid()
                     && serviceRegistered.value());
    }

    bool preferredConflict() const
    {
        const QKeySequence preferred =
            QKeySequence::fromString(QString::fromLatin1(kPreferredShortcut),
                                     QKeySequence::PortableText);
        const QList<KGlobalShortcutInfo> matches = KGlobalAccel::globalShortcutsByKey(preferred);
        for (const KGlobalShortcutInfo &match : matches) {
            if (match.componentUniqueName() != QString::fromLatin1(kComponentId)
                || match.uniqueName() != QString::fromLatin1(kActionId)) {
                return true;
            }
        }
        return false;
    }

    void publishState(bool available)
    {
        const QList<QKeySequence> active = KGlobalAccel::self()->shortcut(&m_action);
        QJsonValue activeShortcut = QJsonValue::Null;
        for (const QKeySequence &sequence : active) {
            if (!sequence.isEmpty()) {
                activeShortcut = sequence.toString(QKeySequence::PortableText);
                break;
            }
        }
        publish(QJsonObject {
            {QStringLiteral("type"), QStringLiteral("state")},
            {QStringLiteral("available"), available},
            {QStringLiteral("activeShortcut"), activeShortcut},
            {QStringLiteral("preferredShortcut"), QString::fromLatin1(kPreferredShortcut)},
            {QStringLiteral("preferredConflict"), preferredConflict()},
        });
    }

    void publishUnavailable()
    {
        publish(QJsonObject {
            {QStringLiteral("type"), QStringLiteral("state")},
            {QStringLiteral("available"), false},
            {QStringLiteral("activeShortcut"), QJsonValue::Null},
            {QStringLiteral("preferredShortcut"), QString::fromLatin1(kPreferredShortcut)},
            {QStringLiteral("preferredConflict"), false},
        });
    }

    void publish(const QJsonObject &message)
    {
        QByteArray line = QJsonDocument(message).toJson(QJsonDocument::Compact);
        if (line.isEmpty() || line.size() > kMaximumOutputLineBytes) {
            return;
        }
        line.append('\n');
        m_output.write(line);
        m_output.flush();
    }

    QFile m_output;
    QAction m_action;
    QDBusServiceWatcher m_serviceWatcher;
    bool m_initialized = false;
};
}

int main(int argc, char **argv)
{
    QCoreApplication::setApplicationName(QString::fromLatin1(kComponentId));
    QGuiApplication::setApplicationDisplayName(QString::fromLatin1(kComponentName));
    QGuiApplication application(argc, argv);

    const QString runtimeDirectory = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (runtimeDirectory.isEmpty()) {
        return 2;
    }
    QLockFile processLock(runtimeDirectory + QStringLiteral("/nagi-shell-launcher-shortcut.lock"));
    if (!processLock.tryLock(0)) {
        return 3;
    }

    std::array<int, 2> pipeFds {-1, -1};
    if (!installTerminationPipe(&pipeFds)) {
        return 2;
    }
    QSocketNotifier terminationNotifier(pipeFds[0], QSocketNotifier::Read);
    QObject::connect(&terminationNotifier, &QSocketNotifier::activated, &application, [&application] {
        application.quit();
    });

    ShortcutHelper helper;
    const int result = application.exec();
    signalWriteFd = -1;
    ::close(pipeFds[0]);
    ::close(pipeFds[1]);
    return result;
}

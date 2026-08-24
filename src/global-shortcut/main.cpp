#define QT_NO_KEYWORDS

#include <KGlobalAccel>
#include <KGlobalShortcutInfo>

#include "registration_policy.h"
#include "shortcut_contract.h"

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
constexpr auto kPreferredShortcut = "Meta+Space";
constexpr auto kServiceName = "org.kde.kglobalaccel";
constexpr qsizetype kMaximumOutputLineBytes = 4096;


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

class GlobalShortcutHelper final : public QObject {
public:
    explicit GlobalShortcutHelper(QObject *parent = nullptr)
        : QObject(parent)
        , m_output()
        , m_serviceWatcher(QString::fromLatin1(kServiceName), QDBusConnection::sessionBus(),
                           QDBusServiceWatcher::WatchForOwnerChange, this)
    {
        if (!m_output.open(STDOUT_FILENO, QIODevice::WriteOnly, QFileDevice::DontCloseHandle)) {
            QCoreApplication::exit(2);
            return;
        }

        for (qsizetype index = 0; index < std::ssize(kShortcutActionSpecs); ++index) {
            const ShortcutActionSpec &spec = kShortcutActionSpecs.at(index);
            auto *action = new QAction(this);
            action->setObjectName(QString::fromLatin1(spec.id));
            action->setText(QString::fromLatin1(spec.name));
            action->setProperty("componentName", QString::fromLatin1(kComponentId));
            action->setProperty("componentDisplayName", QString::fromLatin1(kComponentName));
            action->setAutoRepeat(false);
            connect(action, &QAction::triggered, this, [this, activation = spec.activation] {
                publish(QJsonObject {{QStringLiteral("type"), QStringLiteral("activation")},
                                     {QStringLiteral("action"),
                                      QString::fromLatin1(activation)}});
            });
            m_actions.at(index) = action;
        }

        connect(KGlobalAccel::self(), &KGlobalAccel::globalShortcutChanged, this,
                [this](QAction *action, const QKeySequence &) {
                    if (m_initialized && actionIndex(action) >= 0) {
                        publishState(true);
                    }
                });
        connect(&m_serviceWatcher, &QDBusServiceWatcher::serviceUnregistered, this,
                [this] { publishState(false); });
        connect(&m_serviceWatcher, &QDBusServiceWatcher::serviceRegistered, this, [this] {
            QTimer::singleShot(250, this, [this] { publishState(true); });
        });

        registerActions();
    }

private:
    qsizetype actionIndex(const QAction *action) const
    {
        for (qsizetype index = 0; index < std::ssize(m_actions); ++index) {
            if (m_actions.at(index) == action) {
                return index;
            }
        }
        return -1;
    }

    void registerActions()
    {
        bool actionsRegistered = true;
        for (qsizetype index = 0; index < std::ssize(kShortcutActionSpecs); ++index) {
            QAction *action = m_actions.at(index);
            const ShortcutActionSpec &spec = kShortcutActionSpecs.at(index);
            const QList<QKeySequence> persisted = KGlobalAccel::self()->globalShortcut(
                QString::fromLatin1(kComponentId), QString::fromLatin1(spec.id));
            QList<QKeySequence> proposal = persisted;
            if (spec.launcherDefault) {
                const QKeySequence preferred =
                    QKeySequence::fromString(QString::fromLatin1(kPreferredShortcut),
                                             QKeySequence::PortableText);
                actionsRegistered = KGlobalAccel::self()->setDefaultShortcut(
                                        action, {preferred}, KGlobalAccel::NoAutoloading)
                    && actionsRegistered;
                proposal = initialShortcutProposal(
                    persisted, preferred, KGlobalAccel::isGlobalShortcutAvailable(preferred));
            }
            actionsRegistered =
                KGlobalAccel::self()->setShortcut(action, proposal, KGlobalAccel::Autoloading)
                && actionsRegistered;
        }

        const QDBusReply<bool> serviceRegistered =
            QDBusConnection::sessionBus().interface()->isServiceRegistered(
                QString::fromLatin1(kServiceName));
        m_initialized = true;
        publishState(actionsRegistered && serviceRegistered.isValid()
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
                || match.uniqueName() != QStringLiteral("open-launcher")) {
                return true;
            }
        }
        return false;
    }

    void publishState(bool available)
    {
        ShortcutValues activeShortcuts {};
        for (qsizetype index = 0; index < std::ssize(kShortcutActionSpecs); ++index) {
            activeShortcuts.at(index) = QJsonValue::Null;
            if (!available) {
                continue;
            }
            const QList<QKeySequence> active = KGlobalAccel::self()->shortcut(m_actions.at(index));
            for (const QKeySequence &sequence : active) {
                if (!sequence.isEmpty()) {
                    activeShortcuts.at(index) =
                        sequence.toString(QKeySequence::PortableText);
                    break;
                }
            }
        }
        publish(shortcutStateMessage(available, activeShortcuts, preferredConflict(),
                                     QString::fromLatin1(kPreferredShortcut)));
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
    std::array<QAction *, kShortcutActionSpecs.size()> m_actions {};
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
    QLockFile processLock(runtimeDirectory + QStringLiteral("/nagi-shell-global-shortcut.lock"));
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

    GlobalShortcutHelper helper;
    const int result = application.exec();
    signalWriteFd = -1;
    ::close(pipeFds[0]);
    ::close(pipeFds[1]);
    return result;
}

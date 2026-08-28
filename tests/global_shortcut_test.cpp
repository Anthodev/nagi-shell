#define QT_NO_KEYWORDS

#include "../src/global-shortcut/registration_policy.h"
#include "../src/global-shortcut/shortcut_contract.h"

#include <QCoreApplication>
#include <QElapsedTimer>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QSet>
#include <QStringList>

#include <cstdio>

namespace {
constexpr auto kPreferred = "Meta+Space";

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

class HelperProcess {
public:
    explicit HelperProcess(const QString &path)
    {
        m_process.start(path);
        require(m_process.waitForStarted(3000), "shortcut helper did not start");
    }

    ~HelperProcess()
    {
        stop();
    }

    QJsonObject next(int timeout = 5000)
    {
        QElapsedTimer timer;
        timer.start();
        while (!m_buffer.contains('\n') && timer.elapsed() < timeout) {
            m_buffer.append(m_process.readAllStandardOutput());
            if (m_buffer.contains('\n')) {
                break;
            }
            m_process.waitForReadyRead(50);
            QCoreApplication::processEvents();
        }
        m_buffer.append(m_process.readAllStandardOutput());
        require(m_buffer.contains('\n'), "shortcut helper response timed out");
        const qsizetype newline = m_buffer.indexOf('\n');
        const QByteArray line = m_buffer.first(newline);
        m_buffer.remove(0, newline + 1);
        QJsonParseError error {};
        const QJsonDocument document = QJsonDocument::fromJson(line, &error);
        require(error.error == QJsonParseError::NoError && document.isObject(),
                "shortcut helper returned malformed JSON");
        return document.object();
    }

    void stop()
    {
        if (m_process.state() == QProcess::NotRunning) {
            return;
        }
        m_process.terminate();
        require(m_process.waitForFinished(3000), "shortcut helper ignored SIGTERM");
        require(m_process.exitStatus() == QProcess::NormalExit && m_process.exitCode() == 0,
                "shortcut helper did not shut down cleanly");
    }

private:
    QProcess m_process;
    QByteArray m_buffer;
};

void verifyRegistrationPolicy()
{
    const QKeySequence preferred = QKeySequence::fromString(QString::fromLatin1(kPreferred),
                                                            QKeySequence::PortableText);
    require(initialShortcutProposal({}, preferred, true) == QList<QKeySequence> {preferred},
            "free first registration did not propose the preferred key");
    require(initialShortcutProposal({}, preferred, false).isEmpty(),
            "occupied first registration did not remain unbound");

    const QList<QKeySequence> explicitUnbinding {QKeySequence()};
    require(initialShortcutProposal(explicitUnbinding, preferred, true) == explicitUnbinding,
            "saved explicit unbinding did not override the preferred key");

    const QKeySequence alternate = QKeySequence::fromString(QStringLiteral("Meta+Shift+Space"),
                                                             QKeySequence::PortableText);
    require(initialShortcutProposal({alternate}, preferred, true)
                == QList<QKeySequence> {alternate},
            "saved alternate binding did not override the preferred key");
}

void verifyMultiActionContract()
{
    require(kShortcutActionSpecs.size() == 7, "shortcut catalog does not contain seven actions");
    QSet<QString> ids;
    QSet<QString> activations;
    qsizetype launcherIndex = -1;
    for (qsizetype index = 0; index < std::ssize(kShortcutActionSpecs); ++index) {
        const ShortcutActionSpec &spec = kShortcutActionSpecs.at(index);
        ids.insert(QString::fromLatin1(spec.id));
        activations.insert(QString::fromLatin1(spec.activation));
        if (spec.launcherDefault) {
            require(launcherIndex < 0, "more than one action proposes a default shortcut");
            launcherIndex = index;
        }
    }
    require(ids.size() == 7 && activations.size() == 7,
            "shortcut catalog identifiers are not unique");
    require(launcherIndex >= 0
                && QString::fromLatin1(kShortcutActionSpecs.at(launcherIndex).activation)
                    == QStringLiteral("openLauncher"),
            "launcher is not the sole preferred-default action");

    ShortcutValues active {};
    for (QJsonValue &value : active) {
        value = QJsonValue::Null;
    }
    active.at(0) = QStringLiteral("Meta+Ctrl+D");
    active.at(launcherIndex) = QString::fromLatin1(kPreferred);
    const QJsonObject published =
        shortcutStateMessage(true, active, true, QString::fromLatin1(kPreferred));
    const QJsonObject actions = published.value(QStringLiteral("actions")).toObject();
    require(published.value(QStringLiteral("available")).toBool() && actions.size() == 7,
            "available state did not publish the complete catalog");
    require(actions.value(QStringLiteral("openDashboard"))
                    .toObject()
                    .value(QStringLiteral("activeShortcut"))
                == QStringLiteral("Meta+Ctrl+D"),
            "persisted dashboard assignment was not published");
    require(actions.value(QStringLiteral("openLauncher"))
                    .toObject()
                    .value(QStringLiteral("preferredConflict"))
                    .toBool(),
            "launcher conflict was not published");
    require(actions.value(QStringLiteral("openSession"))
                .toObject()
                .value(QStringLiteral("activeShortcut"))
                .isNull(),
            "explicitly unbound action did not remain unbound");

    active.at(0) = QStringLiteral("Meta+Ctrl+F12");
    const QJsonObject reassigned =
        shortcutStateMessage(true, active, false, QString::fromLatin1(kPreferred));
    require(reassigned != published
                && reassigned.value(QStringLiteral("actions"))
                           .toObject()
                           .value(QStringLiteral("openDashboard"))
                           .toObject()
                           .value(QStringLiteral("activeShortcut"))
                    == QStringLiteral("Meta+Ctrl+F12"),
            "live reassignment did not produce a new published state");
}

void verifyUnavailableState(const QJsonObject &state)
{
    require(state.size() == 3 && state.value(QStringLiteral("type")) == QStringLiteral("state")
                && !state.value(QStringLiteral("available")).toBool()
                && state.value(QStringLiteral("actions")).isObject(),
            "unavailable service state did not match the fixed envelope");

    const QJsonObject actions = state.value(QStringLiteral("actions")).toObject();
    const QStringList expected {
        QStringLiteral("openDashboard"),
        QStringLiteral("openLauncher"),
        QStringLiteral("openTray"),
        QStringLiteral("openHistory"),
        QStringLiteral("openAudio"),
        QStringLiteral("openSession"),
        QStringLiteral("openSystemSettings"),
    };
    require(actions.size() == expected.size(), "helper did not publish every shortcut action");
    for (const QString &name : expected) {
        require(actions.value(name).isObject(), "shortcut action state was missing");
        const QJsonObject action = actions.value(name).toObject();
        const bool launcher = name == QStringLiteral("openLauncher");
        require(action.size() == 3 && action.value(QStringLiteral("activeShortcut")).isNull()
                    && !action.value(QStringLiteral("preferredConflict")).toBool()
                    && (launcher
                            ? action.value(QStringLiteral("preferredShortcut"))
                                == QString::fromLatin1(kPreferred)
                            : action.value(QStringLiteral("preferredShortcut")).isNull()),
                "unavailable shortcut action did not match the fixed schema");
    }
}

void verifyUnavailableLifecycle(const QString &helperPath)
{
    for (int cycle = 0; cycle < 20; ++cycle) {
        {
            HelperProcess helper(helperPath);
            verifyUnavailableState(helper.next());

            QProcess duplicate;
            duplicate.start(helperPath);
            require(duplicate.waitForFinished(3000)
                        && duplicate.exitStatus() == QProcess::NormalExit
                        && duplicate.exitCode() == 3,
                    "process lock allowed a second shortcut helper");
            helper.stop();
        }

        {
            HelperProcess replacement(helperPath);
            verifyUnavailableState(replacement.next());
            replacement.stop();
        }
    }
}

}

int main(int argc, char **argv)
{
    QCoreApplication::setApplicationName(QStringLiteral("io.github.Anthodev.NagiShell.Test"));
    QGuiApplication application(argc, argv);
    require(application.arguments().size() == 2, "shortcut helper path argument is required");

    verifyRegistrationPolicy();
    verifyMultiActionContract();
    verifyUnavailableLifecycle(application.arguments().at(1));
    std::puts("global shortcut tests passed");
    return 0;
}

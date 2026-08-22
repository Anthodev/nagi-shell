#define QT_NO_KEYWORDS

#include "../src/launcher-shortcut/registration_policy.h"

#include <QCoreApplication>
#include <QElapsedTimer>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>

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

void verifyUnavailableLifecycle(const QString &helperPath)
{
    HelperProcess helper(helperPath);
    const QJsonObject state = helper.next();
    require(state.size() == 5 && state.value(QStringLiteral("type")) == QStringLiteral("state")
                && !state.value(QStringLiteral("available")).toBool()
                && state.value(QStringLiteral("activeShortcut")).isNull()
                && state.value(QStringLiteral("preferredShortcut"))
                    == QString::fromLatin1(kPreferred)
                && !state.value(QStringLiteral("preferredConflict")).toBool(),
            "unavailable service state did not match the fixed schema");

    QProcess duplicate;
    duplicate.start(helperPath);
    require(duplicate.waitForFinished(3000) && duplicate.exitCode() == 3,
            "process lock allowed a second shortcut helper");
    helper.stop();

    HelperProcess restarted(helperPath);
    require(!restarted.next().value(QStringLiteral("available")).toBool(),
            "helper restart did not recover after lock release");
}
}

int main(int argc, char **argv)
{
    QCoreApplication::setApplicationName(QStringLiteral("io.github.Anthodev.NagiShell.Test"));
    QGuiApplication application(argc, argv);
    require(application.arguments().size() == 2, "shortcut helper path argument is required");

    verifyRegistrationPolicy();
    verifyUnavailableLifecycle(application.arguments().at(1));
    std::puts("launcher shortcut tests passed");
    return 0;
}

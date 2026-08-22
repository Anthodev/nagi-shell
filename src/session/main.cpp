#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSocketNotifier>
#include <QTimer>

#include <array>
#include <cerrno>
#include <cstdio>
#include <limits>
#include <optional>
#include <unistd.h>

namespace {

constexpr int DbusTimeoutMs = 5000;
constexpr int RequestTimeoutMs = 5500;
constexpr qsizetype MaximumCommandBytes = 4096;
constexpr int MaximumDiagnostics = 4;

struct Operation {
    const char *service;
    const char *path;
    const char *interface;
    const char *method;
};

std::optional<Operation> operationFor(const QString &action)
{
    if (action == QStringLiteral("lock")) {
        return Operation{
            "org.freedesktop.ScreenSaver",
            "/ScreenSaver",
            "org.freedesktop.ScreenSaver",
            "Lock",
        };
    }
    if (action == QStringLiteral("suspend")) {
        return Operation{
            "org.kde.Solid.PowerManagement",
            "/org/kde/Solid/PowerManagement/Actions/SuspendSession",
            "org.kde.Solid.PowerManagement.Actions.SuspendSession",
            "suspendToRam",
        };
    }
    if (action == QStringLiteral("logout")) {
        return Operation{
            "org.kde.LogoutPrompt",
            "/LogoutPrompt",
            "org.kde.LogoutPrompt",
            "promptLogout",
        };
    }
    if (action == QStringLiteral("reboot")) {
        return Operation{
            "org.kde.LogoutPrompt",
            "/LogoutPrompt",
            "org.kde.LogoutPrompt",
            "promptReboot",
        };
    }
    if (action == QStringLiteral("powerOff")) {
        return Operation{
            "org.kde.LogoutPrompt",
            "/LogoutPrompt",
            "org.kde.LogoutPrompt",
            "promptShutDown",
        };
    }
    return std::nullopt;
}

QString normalizeFailure(const QDBusError &error)
{
    const QString name = error.name().toLower();
    if (name.contains(QStringLiteral("accessdenied"))
        || name.contains(QStringLiteral("notauthorized"))
        || name.contains(QStringLiteral("permissiondenied"))
        || name.contains(QStringLiteral("authentication"))) {
        return QStringLiteral("denied");
    }
    if (error.type() == QDBusError::NoReply || error.type() == QDBusError::Timeout
        || name.contains(QStringLiteral("timeout"))) {
        return QStringLiteral("timeout");
    }
    if (error.type() == QDBusError::ServiceUnknown
        || error.type() == QDBusError::UnknownObject
        || error.type() == QDBusError::UnknownInterface
        || error.type() == QDBusError::UnknownMethod
        || name.contains(QStringLiteral("serviceunknown"))
        || name.contains(QStringLiteral("namehasnoowner"))) {
        return QStringLiteral("unavailable");
    }
    return QStringLiteral("backend");
}

class SessionBridge final : public QObject {
    Q_OBJECT

public:
    explicit SessionBridge(QObject *parent = nullptr)
        : QObject(parent)
        , bus(QDBusConnection::sessionBus())
    {
        requestTimer.setSingleShot(true);
        requestTimer.setInterval(RequestTimeoutMs);
        connect(&requestTimer, &QTimer::timeout, this, [this] {
            if (pendingRequestId == 0) {
                return;
            }
            const int requestId = pendingRequestId;
            const QString action = pendingAction;
            clearPending();
            publishResult(requestId, action, QStringLiteral("timeout"));
        });

        stdinNotifier = new QSocketNotifier(STDIN_FILENO, QSocketNotifier::Read, this);
        connect(stdinNotifier, &QSocketNotifier::activated, this, [this] { readCommands(); });
        QTimer::singleShot(0, this, [this] {
            publishMessage(QJsonObject{{QStringLiteral("type"), QStringLiteral("ready")}});
        });
    }

private:
    void requestAction(int requestId, const QString &action)
    {
        const std::optional<Operation> operation = operationFor(action);
        if (!operation.has_value()) {
            return;
        }
        if (pendingRequestId != 0) {
            publishResult(requestId, action, QStringLiteral("busy"));
            return;
        }

        pendingRequestId = requestId;
        pendingAction = action;
        requestTimer.start();

        const Operation &target = operation.value();
        const QDBusMessage request = QDBusMessage::createMethodCall(
            QString::fromLatin1(target.service),
            QString::fromLatin1(target.path),
            QString::fromLatin1(target.interface),
            QString::fromLatin1(target.method));
        auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(request, DbusTimeoutMs), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, requestId, action] {
            const QDBusPendingReply<> reply = *watcher;
            watcher->deleteLater();
            if (pendingRequestId != requestId || pendingAction != action) {
                return;
            }
            const QString outcome = reply.isError() ? normalizeFailure(reply.error())
                                                    : QStringLiteral("accepted");
            clearPending();
            publishResult(requestId, action, outcome);
        });
    }

    void clearPending()
    {
        requestTimer.stop();
        pendingRequestId = 0;
        pendingAction.clear();
    }

    void handleCommand(const QJsonObject &command)
    {
        const QString operation = command.value(QStringLiteral("op")).toString();
        if (operation == QStringLiteral("shutdown")) {
            QCoreApplication::quit();
            return;
        }

        const QJsonValue requestValue = command.value(QStringLiteral("requestId"));
        const QString action = command.value(QStringLiteral("action")).toString();
        if (operation != QStringLiteral("action") || !requestValue.isDouble()
            || requestValue.toDouble() < 1
            || requestValue.toDouble() > std::numeric_limits<int>::max()
            || requestValue.toInt() != requestValue.toDouble() || !operationFor(action).has_value()) {
            diagnose(QStringLiteral("invalid command schema"));
            return;
        }
        requestAction(requestValue.toInt(), action);
    }

    void readCommands()
    {
        std::array<char, MaximumCommandBytes> bytes{};
        const ssize_t count = ::read(STDIN_FILENO, bytes.data(), bytes.size());
        if (count == 0) {
            QCoreApplication::quit();
            return;
        }
        if (count < 0) {
            if (errno != EAGAIN && errno != EINTR) {
                diagnose(QStringLiteral("stdin read failed"));
                QCoreApplication::exit(2);
            }
            return;
        }

        commandBuffer.append(bytes.data(), count);
        if (commandBuffer.size() > MaximumCommandBytes * 2) {
            diagnose(QStringLiteral("command buffer exceeded limit"));
            commandBuffer.clear();
        }
        while (true) {
            const qsizetype newline = commandBuffer.indexOf('\n');
            if (newline < 0) {
                return;
            }
            QByteArray line = commandBuffer.left(newline);
            commandBuffer.remove(0, newline + 1);
            if (line.endsWith('\r')) {
                line.chop(1);
            }
            if (line.isEmpty() || line.size() > MaximumCommandBytes) {
                diagnose(QStringLiteral("invalid command length"));
                continue;
            }
            QJsonParseError error;
            const QJsonDocument document = QJsonDocument::fromJson(line, &error);
            if (error.error != QJsonParseError::NoError || !document.isObject()) {
                diagnose(QStringLiteral("malformed command"));
                continue;
            }
            handleCommand(document.object());
        }
    }

    void publishResult(int requestId, const QString &action, const QString &outcome)
    {
        publishMessage(QJsonObject{
            {QStringLiteral("type"), QStringLiteral("result")},
            {QStringLiteral("requestId"), requestId},
            {QStringLiteral("action"), action},
            {QStringLiteral("outcome"), outcome},
        });
    }

    void publishMessage(const QJsonObject &message)
    {
        const QByteArray bytes = QJsonDocument(message).toJson(QJsonDocument::Compact);
        std::fwrite(bytes.constData(), 1, static_cast<size_t>(bytes.size()), stdout);
        std::fputc('\n', stdout);
        std::fflush(stdout);
    }

    void diagnose(const QString &message)
    {
        if (diagnosticCount >= MaximumDiagnostics || message == lastDiagnostic) {
            return;
        }
        lastDiagnostic = message;
        diagnosticCount += 1;
        const QByteArray bounded = message.left(256).toUtf8();
        std::fprintf(stderr, "nagi-shell session helper: %s\n", bounded.constData());
        std::fflush(stderr);
    }

    QDBusConnection bus;
    QSocketNotifier *stdinNotifier = nullptr;
    QTimer requestTimer;
    QByteArray commandBuffer;
    int pendingRequestId = 0;
    QString pendingAction;
    int diagnosticCount = 0;
    QString lastDiagnostic;
};

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    application.setApplicationName(QStringLiteral("nagi-session"));

    if (!QDBusConnection::sessionBus().isConnected()) {
        std::fprintf(stderr, "nagi-shell session helper: session bus unavailable\n");
        return 2;
    }

    SessionBridge bridge;
    return application.exec();
}

#include "main.moc"

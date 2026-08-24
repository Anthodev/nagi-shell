#define QT_NO_KEYWORDS

#include "../src/global-shortcut/shortcut_contract.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusArgument>
#include <QDBusMetaType>
#include <QDBusInterface>
#include <QDBusObjectPath>
#include <QDBusReply>
#include <QElapsedTimer>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeySequence>
#include <QProcess>

#include <cstdio>
#include <QSet>
#include <functional>
#include <stdexcept>

namespace {
constexpr auto kService = "org.kde.kglobalaccel";
constexpr auto kRootPath = "/kglobalaccel";
constexpr auto kRootInterface = "org.kde.KGlobalAccel";
constexpr auto kComponentId = "io.github.Anthodev.NagiShell";
constexpr auto kComponentName = "Nagi Shell";

void require(bool condition, const char *message)
{
    if (!condition) {
        throw std::runtime_error(message);
    }
}

class HelperProcess {
public:
    explicit HelperProcess(const QString &path)
        : path(path)
    {
        start();
    }

    ~HelperProcess()
    {
        stop();
    }

    void restart()
    {
        stop();
        start();
    }

    QJsonObject nextMatching(const std::function<bool(const QJsonObject &)> &predicate,
                             int timeout = 5000)
    {
        QElapsedTimer timer;
        timer.start();
        while (timer.elapsed() < timeout) {
            while (buffer.contains('\n')) {
                const qsizetype newline = buffer.indexOf('\n');
                const QByteArray line = buffer.first(newline);
                buffer.remove(0, newline + 1);
                QJsonParseError error {};
                const QJsonDocument document = QJsonDocument::fromJson(line, &error);
                if (error.error == QJsonParseError::NoError && document.isObject()
                    && predicate(document.object())) {
                    return document.object();
                }
            }
            process.waitForReadyRead(50);
            buffer.append(process.readAllStandardOutput());
            QCoreApplication::processEvents();
        }
        throw std::runtime_error("shortcut helper response timed out");
    }

    QJsonObject nextState()
    {
        return nextMatching([](const QJsonObject &message) {
            return message.value(QStringLiteral("type")) == QStringLiteral("state");
        });
    }

private:
    void start()
    {
        buffer.clear();
        process.start(path);
        require(process.waitForStarted(3000), "global shortcut helper did not start");
    }

    void stop()
    {
        if (process.state() == QProcess::NotRunning) {
            return;
        }
        process.terminate();
        require(process.waitForFinished(3000), "global shortcut helper ignored SIGTERM");
        require(process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0,
                "global shortcut helper did not stop cleanly");
    }

    QString path;
    QProcess process;
    QByteArray buffer;
};

QStringList actionId(const ShortcutActionSpec &spec,
                     const QString &componentUnique = QString::fromLatin1(kComponentId),
                     const QString &componentFriendly = QString::fromLatin1(kComponentName))
{
    return {
        componentUnique,
        QString::fromLatin1(spec.id),
        componentFriendly,
        QString::fromLatin1(spec.name),
    };
}

QList<int> shortcut(QDBusInterface &root, const ShortcutActionSpec &spec)
{
    const QDBusReply<QList<int>> reply = root.call(QStringLiteral("shortcut"), actionId(spec));
    require(reply.isValid(), "could not read persisted shortcut");
    return reply.value();
}

void setForeignShortcut(QDBusInterface &root, const ShortcutActionSpec &spec,
                        const QList<int> &keys,
                        const QString &componentUnique = QString::fromLatin1(kComponentId),
                        const QString &componentFriendly = QString::fromLatin1(kComponentName))
{
    const QDBusMessage reply =
        root.call(QStringLiteral("setForeignShortcut"),
                  actionId(spec, componentUnique, componentFriendly), QVariant::fromValue(keys));
    require(reply.type() != QDBusMessage::ErrorMessage, "could not update foreign shortcut");
}

QSet<QString> foreignOwnersForKey(QDBusInterface &root, int key)
{
    const QDBusMessage reply = root.call(QStringLiteral("getGlobalShortcutsByKey"), key);
    require(reply.type() == QDBusMessage::ReplyMessage && reply.arguments().size() == 1,
            "could not query shortcut owners");
    const QDBusArgument argument = reply.arguments().front().value<QDBusArgument>();
    QSet<QString> owners;
    argument.beginArray();
    while (!argument.atEnd()) {
        QString actionUnique;
        QString actionFriendly;
        QString componentUnique;
        QString componentFriendly;
        QString contextUnique;
        QString contextFriendly;
        QList<int> activeKeys;
        QList<int> defaultKeys;
        argument.beginStructure();
        argument >> actionUnique >> actionFriendly >> componentUnique >> componentFriendly
            >> contextUnique >> contextFriendly >> activeKeys >> defaultKeys;
        argument.endStructure();
        if (componentUnique != QString::fromLatin1(kComponentId)) {
            owners.insert(componentUnique + u'/' + actionUnique);
        }
    }
    argument.endArray();
    return owners;
}

class ShortcutRestorer {
public:
    ShortcutRestorer(QDBusInterface &root, const ShortcutActionSpec &spec)
        : root(root)
        , spec(spec)
        , original(shortcut(root, spec))
    {
    }

    ~ShortcutRestorer()
    {
        root.call(QStringLiteral("setForeignShortcut"), actionId(spec),
                  QVariant::fromValue(original));
    }

    const QList<int> &originalKeys() const
    {
        return original;
    }

private:
    QDBusInterface &root;
    const ShortcutActionSpec &spec;
    QList<int> original;
};

class ForeignConflictFixture {
public:
    ForeignConflictFixture(QDBusInterface &root, int key, bool install)
        : root(root)
        , spec { "nagi-test-meta-space", "Nagi Test Meta Space", "testMetaSpace", false }
        , componentUnique(QStringLiteral("org.example.NagiShellShortcutTest"))
        , componentFriendly(QStringLiteral("Nagi Shell Shortcut Test"))
        , installed(install)
    {
        if (!installed) {
            return;
        }
        setForeignShortcut(root, spec, {key}, componentUnique, componentFriendly);
    }

    ~ForeignConflictFixture()
    {
        if (installed) {
            root.call(QStringLiteral("unregister"), componentUnique,
                      QString::fromLatin1(spec.id));
        }
    }

    QString ownerIdentity() const
    {
        return componentUnique + u'/' + QString::fromLatin1(spec.id);
    }

private:
    QDBusInterface &root;
    ShortcutActionSpec spec;
    QString componentUnique;
    QString componentFriendly;
    bool installed;
};

QString activeShortcut(const QJsonObject &state, const char *activation)
{
    return state.value(QStringLiteral("actions"))
        .toObject()
        .value(QString::fromLatin1(activation))
        .toObject()
        .value(QStringLiteral("activeShortcut"))
        .toString();
}

bool preferredConflict(const QJsonObject &state)
{
    return state.value(QStringLiteral("actions"))
        .toObject()
        .value(QStringLiteral("openLauncher"))
        .toObject()
        .value(QStringLiteral("preferredConflict"))
        .toBool();
}
}

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    qDBusRegisterMetaType<QList<QStringList>>();
    try {
        require(application.arguments().size() == 2, "global shortcut helper path is required");
        QDBusInterface root(QString::fromLatin1(kService), QString::fromLatin1(kRootPath),
                            QString::fromLatin1(kRootInterface), QDBusConnection::sessionBus());
        require(root.isValid(), "KGlobalAccel service is unavailable");

        HelperProcess helper(application.arguments().at(1));
        const QJsonObject initial = helper.nextState();
        require(initial.value(QStringLiteral("available")).toBool(),
                "helper did not register against live KGlobalAccel");
        require(initial.value(QStringLiteral("actions")).toObject().size()
                    == kShortcutActionSpecs.size(),
                "helper did not publish seven live actions");

        const QDBusReply<QList<QStringList>> registered =
            root.call(QStringLiteral("allActionsForComponent"),
                      QStringList {QString::fromLatin1(kComponentId),
                                   QString::fromLatin1(kComponentName)});
        require(registered.isValid() && registered.value().size() == kShortcutActionSpecs.size(),
                "KGlobalAccel did not register all Nagi actions");

        const QDBusReply<QDBusObjectPath> componentPath =
            root.call(QStringLiteral("getComponent"), QString::fromLatin1(kComponentId));
        require(componentPath.isValid(), "KGlobalAccel component path is unavailable");
        QDBusInterface component(QString::fromLatin1(kService), componentPath.value().path(),
                                 QStringLiteral("org.kde.kglobalaccel.Component"),
                                 QDBusConnection::sessionBus());
        require(component.isValid(), "KGlobalAccel component interface is unavailable");

        for (const ShortcutActionSpec &spec : kShortcutActionSpecs) {
            const QDBusMessage invoked = component.call(QStringLiteral("invokeShortcut"),
                                                        QString::fromLatin1(spec.id));
            require(invoked.type() != QDBusMessage::ErrorMessage,
                    "KGlobalAccel shortcut activation failed");
            const QJsonObject activation = helper.nextMatching([&spec](const QJsonObject &message) {
                return message.value(QStringLiteral("type")) == QStringLiteral("activation")
                    && message.value(QStringLiteral("action"))
                        == QString::fromLatin1(spec.activation);
            });
            require(!activation.isEmpty(), "helper did not publish shortcut activation");
        }

        const ShortcutActionSpec &dashboard = kShortcutActionSpecs.front();
        ShortcutRestorer restoreDashboard(root, dashboard);
        const QKeySequence temporary =
            QKeySequence::fromString(QStringLiteral("Meta+Ctrl+F12"),
                                     QKeySequence::PortableText);
        const QList<int> temporaryKeys {temporary[0].toCombined()};
        setForeignShortcut(root, dashboard, temporaryKeys);
        QJsonObject changed = helper.nextMatching([](const QJsonObject &message) {
            return message.value(QStringLiteral("type")) == QStringLiteral("state")
                && activeShortcut(message, "openDashboard") == QStringLiteral("Meta+Ctrl+F12");
        });
        require(!changed.isEmpty(), "live dashboard reassignment was not published");

        helper.restart();
        require(activeShortcut(helper.nextState(), "openDashboard") == QStringLiteral("Meta+Ctrl+F12"),
                "persisted dashboard reassignment did not survive helper restart");

        setForeignShortcut(root, dashboard, {});
        const QJsonObject unbound = helper.nextMatching([](const QJsonObject &message) {
            return message.value(QStringLiteral("type")) == QStringLiteral("state")
                && activeShortcut(message, "openDashboard").isEmpty();
        });
        require(!unbound.isEmpty(), "explicit dashboard unbinding was not published");

        setForeignShortcut(root, dashboard, restoreDashboard.originalKeys());
        helper.nextMatching([&restoreDashboard](const QJsonObject &message) {
            const QString active = activeShortcut(message, "openDashboard");
            if (restoreDashboard.originalKeys().isEmpty()) {
                return active.isEmpty();
            }
            return !active.isEmpty();
        });

        const ShortcutActionSpec &launcher = kShortcutActionSpecs.at(1);
        const QKeySequence preferred =
            QKeySequence::fromString(QStringLiteral("Meta+Space"),
                                     QKeySequence::PortableText);
        const int preferredKey = preferred[0].toCombined();
        const QSet<QString> foreignOwnersBefore = foreignOwnersForKey(root, preferredKey);
        {
            ShortcutRestorer restoreLauncher(root, launcher);
            setForeignShortcut(root, launcher, {});
            helper.nextMatching([](const QJsonObject &message) {
                return message.value(QStringLiteral("type")) == QStringLiteral("state")
                    && activeShortcut(message, "openLauncher").isEmpty();
            });

            ForeignConflictFixture conflict(root, preferredKey, foreignOwnersBefore.isEmpty());
            const QSet<QString> foreignOwnersDuring = foreignOwnersForKey(root, preferredKey);
            require(!foreignOwnersDuring.isEmpty(),
                    "foreign Meta+Space conflict fixture or KRunner owner is missing");
            if (foreignOwnersBefore.isEmpty()) {
                require(foreignOwnersDuring.contains(conflict.ownerIdentity()),
                        "Meta+Space fixture was not registered under a foreign component");
            }

            helper.restart();
            const QJsonObject conflictState = helper.nextState();
            require(activeShortcut(conflictState, "openLauncher").isEmpty()
                        && preferredConflict(conflictState),
                    "foreign Meta+Space owner did not keep Launcher unbound and conflicted");
            require(foreignOwnersForKey(root, preferredKey) == foreignOwnersDuring,
                    "foreign Meta+Space owner changed during helper registration");
        }
        require(foreignOwnersForKey(root, preferredKey) == foreignOwnersBefore,
                "foreign Meta+Space owners were not restored exactly");

        std::puts("global shortcut live tests passed");
        return 0;
    } catch (const std::exception &error) {
        std::fprintf(stderr, "FAIL: %s\n", error.what());
        return 1;
    }
}

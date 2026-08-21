#include "desktop_snapshot.h"

#include <QCoreApplication>
#include <QDBusVariant>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusServiceWatcher>
#include <QTimer>
#include <QVariant>

#include <cstdio>

namespace {

constexpr auto Service = "org.kde.KWin";
constexpr auto ObjectPath = "/VirtualDesktopManager";
constexpr auto Interface = "org.kde.KWin.VirtualDesktopManager";
constexpr auto PropertiesInterface = "org.freedesktop.DBus.Properties";
constexpr int SnapshotTimeoutMs = 2000;
constexpr int MaximumDiagnostics = 8;

class KWinVirtualDesktopObserver final : public QObject {
    Q_OBJECT

public:
    explicit KWinVirtualDesktopObserver(QObject *parent = nullptr)
        : QObject(parent)
        , bus(QDBusConnection::sessionBus())
        , watcher(
              QString::fromLatin1(Service),
              bus,
              QDBusServiceWatcher::WatchForOwnerChange,
              this)
    {
        connect(
            &watcher,
            &QDBusServiceWatcher::serviceOwnerChanged,
            this,
            &KWinVirtualDesktopObserver::onServiceOwnerChanged);
        QTimer::singleShot(0, this, &KWinVirtualDesktopObserver::initialize);
    }

    ~KWinVirtualDesktopObserver() override
    {
        detachOwner();
    }

private slots:
    void onInvalidation(const QDBusMessage &message)
    {
        if (message.interface() == QString::fromLatin1(PropertiesInterface)) {
            const QList<QVariant> arguments = message.arguments();
            if (arguments.isEmpty()
                || arguments.constFirst().toString() != QString::fromLatin1(Interface)) {
                return;
            }
        }

        scheduleSnapshot();
    }

private:
    void initialize()
    {
        if (!bus.isConnected()) {
            diagnose(QStringLiteral("session bus is unavailable"));
            publishSnapshot(nagi::kwin::unavailableSnapshotJson());
            return;
        }
        if (!activeOwner.isEmpty()) {
            return;
        }

        const QString owner = currentServiceOwner();
        if (owner.isEmpty()) {
            publishSnapshot(nagi::kwin::unavailableSnapshotJson());
            return;
        }

        attachOwner(owner);
    }

    QString currentServiceOwner()
    {
        QDBusConnectionInterface *connectionInterface = bus.interface();
        if (connectionInterface == nullptr) {
            return {};
        }

        const QDBusReply<QString> reply = connectionInterface->serviceOwner(
            QString::fromLatin1(Service));
        return reply.isValid() ? reply.value() : QString{};
    }

    void onServiceOwnerChanged(
        const QString &,
        const QString &,
        const QString &newOwner)
    {
        if (newOwner == activeOwner) {
            return;
        }

        detachOwner();
        publishSnapshot(nagi::kwin::unavailableSnapshotJson());
        if (!newOwner.isEmpty()) {
            attachOwner(newOwner);
        }
    }

    void attachOwner(const QString &owner)
    {
        if (owner == activeOwner) {
            return;
        }
        if (!activeOwner.isEmpty()) {
            detachOwner();
        }

        activeOwner = owner;
        bool subscribed = true;
        const auto subscribe = [this, &owner, &subscribed](
                                   const char *interface,
                                   const char *signal) {
            subscribed &= bus.connect(
                owner,
                QString::fromLatin1(ObjectPath),
                QString::fromLatin1(interface),
                QString::fromLatin1(signal),
                this,
                SLOT(onInvalidation(QDBusMessage)));
        };

        subscribe(Interface, "currentChanged");
        subscribe(Interface, "desktopCreated");
        subscribe(Interface, "desktopDataChanged");
        subscribe(Interface, "desktopRemoved");
        subscribe(PropertiesInterface, "PropertiesChanged");
        if (!subscribed) {
            diagnose(QStringLiteral("one or more KWin signal subscriptions failed"));
        }

        scheduleSnapshot();
    }

    void detachOwner()
    {
        snapshotScheduled = false;
        if (activeOwner.isEmpty()) {
            return;
        }

        const auto unsubscribe = [this](const char *interface, const char *signal) {
            bus.disconnect(
                activeOwner,
                QString::fromLatin1(ObjectPath),
                QString::fromLatin1(interface),
                QString::fromLatin1(signal),
                this,
                SLOT(onInvalidation(QDBusMessage)));
        };

        unsubscribe(Interface, "currentChanged");
        unsubscribe(Interface, "desktopCreated");
        unsubscribe(Interface, "desktopDataChanged");
        unsubscribe(Interface, "desktopRemoved");
        unsubscribe(PropertiesInterface, "PropertiesChanged");
        activeOwner.clear();
    }

    void scheduleSnapshot()
    {
        if (snapshotScheduled || activeOwner.isEmpty()) {
            return;
        }

        snapshotScheduled = true;
        QTimer::singleShot(0, this, &KWinVirtualDesktopObserver::refreshSnapshot);
    }
    std::optional<QVariant> readProperty(
        const QString &owner,
        const QString &propertyName)
    {
        QDBusMessage request = QDBusMessage::createMethodCall(
            owner,
            QString::fromLatin1(ObjectPath),
            QString::fromLatin1(PropertiesInterface),
            QStringLiteral("Get"));
        request << QString::fromLatin1(Interface) << propertyName;
        const QDBusMessage reply = bus.call(request, QDBus::Block, SnapshotTimeoutMs);
        if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().size() != 1) {
            return std::nullopt;
        }

        const QVariant value = reply.arguments().constFirst();
        if (value.metaType() == QMetaType::fromType<QDBusVariant>()) {
            return value.value<QDBusVariant>().variant();
        }
        return value;
    }


    void refreshSnapshot()
    {
        snapshotScheduled = false;
        const QString requestedOwner = activeOwner;
        if (requestedOwner.isEmpty()) {
            return;
        }

        const auto desktopsValue = readProperty(
            requestedOwner,
            QStringLiteral("desktops"));
        const auto currentValue = readProperty(
            requestedOwner,
            QStringLiteral("current"));
        if (!desktopsValue || !currentValue) {
            diagnose(QStringLiteral("complete KWin property snapshot failed"));
            return;
        }

        if (currentServiceOwner() != requestedOwner || activeOwner != requestedOwner) {
            return;
        }
        if (currentValue->metaType() != QMetaType::fromType<QString>()) {
            diagnose(QStringLiteral("KWin current property has an invalid type"));
            return;
        }

        QString error;
        const auto desktops = nagi::kwin::decodeDesktopTuples(*desktopsValue, &error);
        if (!desktops) {
            diagnose(error);
            return;
        }

        const auto snapshot = nagi::kwin::availableSnapshotJson(
            *desktops,
            currentValue->toString(),
            &error);
        if (!snapshot) {
            diagnose(error);
            return;
        }

        publishSnapshot(*snapshot);
    }

    void publishSnapshot(const QByteArray &snapshot)
    {
        if (snapshot == lastSnapshot) {
            return;
        }

        lastSnapshot = snapshot;
        std::fwrite(snapshot.constData(), 1, static_cast<size_t>(snapshot.size()), stdout);
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
        const QByteArray boundedMessage = message.left(256).toUtf8();
        std::fprintf(stderr, "nagi-shell KWin helper: %s\n", boundedMessage.constData());
        std::fflush(stderr);
    }

    QDBusConnection bus;
    QDBusServiceWatcher watcher;
    QString activeOwner;
    QByteArray lastSnapshot;
    QString lastDiagnostic;
    bool snapshotScheduled = false;
    int diagnosticCount = 0;
};

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    KWinVirtualDesktopObserver observer;
    return application.exec();
}

#include "main.moc"

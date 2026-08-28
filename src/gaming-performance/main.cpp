#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusServiceWatcher>
#include <QDBusVariant>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTimer>
#include <QVariantMap>

#include <algorithm>
#include <cstdio>
#include <limits>
#include <optional>

namespace {
constexpr auto GameService = "com.feralinteractive.GameMode";
constexpr auto GamePath = "/com/feralinteractive/GameMode";
constexpr auto GameInterface = "com.feralinteractive.GameMode";
constexpr auto ModernService = "org.freedesktop.UPower.PowerProfiles";
constexpr auto ModernPath = "/org/freedesktop/UPower/PowerProfiles";
constexpr auto ModernInterface = "org.freedesktop.UPower.PowerProfiles";
constexpr auto LegacyService = "net.hadess.PowerProfiles";
constexpr auto LegacyPath = "/net/hadess/PowerProfiles";
constexpr auto LegacyInterface = "net.hadess.PowerProfiles";
constexpr auto PropertiesInterface = "org.freedesktop.DBus.Properties";
constexpr int DbusTimeoutMs = 2000;
constexpr int MaximumClientCount = 1000000;
constexpr int MaximumDiagnostics = 8;

struct PowerEndpoint {
    QString service;
    QString path;
    QString interface;
    QString owner;

    [[nodiscard]] bool available() const
    {
        return !owner.isEmpty();
    }
};

class GamingPerformanceObserver final : public QObject {
    Q_OBJECT

public:
    explicit GamingPerformanceObserver(QObject *parent = nullptr)
        : QObject(parent)
        , sessionBus(QDBusConnection::sessionBus())
        , systemBus(QDBusConnection::systemBus())
        , gameWatcher(QString::fromLatin1(GameService), sessionBus,
                      QDBusServiceWatcher::WatchForOwnerChange, this)
        , modernWatcher(QString::fromLatin1(ModernService), systemBus,
                        QDBusServiceWatcher::WatchForOwnerChange, this)
        , legacyWatcher(QString::fromLatin1(LegacyService), systemBus,
                        QDBusServiceWatcher::WatchForOwnerChange, this)
    {
        connect(&gameWatcher, &QDBusServiceWatcher::serviceOwnerChanged, this,
                &GamingPerformanceObserver::onGameOwnerChanged);
        connect(&modernWatcher, &QDBusServiceWatcher::serviceOwnerChanged, this,
                &GamingPerformanceObserver::onPowerOwnerChanged);
        connect(&legacyWatcher, &QDBusServiceWatcher::serviceOwnerChanged, this,
                &GamingPerformanceObserver::onPowerOwnerChanged);

        QTimer::singleShot(0, this, [this] {
            publish(QJsonObject{{QStringLiteral("type"), QStringLiteral("ready")}}, true);
            initialize();
        });
    }

    ~GamingPerformanceObserver() override
    {
        detachGame();
        detachPower();
    }

private slots:
    void onGameEvent(const QDBusMessage &message)
    {
        const QString event = message.member() == QStringLiteral("GameRegistered")
            ? QStringLiteral("registered")
            : message.member() == QStringLiteral("GameUnregistered")
            ? QStringLiteral("unregistered")
            : QString{};
        if (event.isEmpty() || message.arguments().size() != 2 || gameOwner.isEmpty()) {
            diagnose(QStringLiteral("invalid GameMode event"));
            return;
        }

        const auto count = readGameClientCount();
        if (!count.has_value()) {
            diagnose(QStringLiteral("invalid GameMode ClientCount"));
            return;
        }
        gameClientCount = *count;
        publishState(event, true);
    }

    void onGameOwnerChanged(const QString &, const QString &oldOwner, const QString &newOwner)
    {
        if (oldOwner == newOwner || (oldOwner.isEmpty() && newOwner == gameOwner)) {
            return;
        }

        const bool lostSource = !oldOwner.isEmpty();
        detachGame();
        gameClientCount = 0;
        if (lostSource) {
            publishState(QStringLiteral("sourceUnavailable"), true);
        }
        if (!newOwner.isEmpty()) {
            attachGame(newOwner);
        }
        publishState(QStringLiteral("snapshot"));
    }

    void onPowerPropertiesChanged(const QString &interface, const QVariantMap &changed,
                                  const QStringList &invalidated)
    {
        if (!powerEndpoint.available() || interface != powerEndpoint.interface) {
            return;
        }

        QString profile;
        if (changed.contains(QStringLiteral("ActiveProfile"))) {
            const QVariant value = changed.value(QStringLiteral("ActiveProfile"));
            if (value.metaType().id() != QMetaType::QString) {
                diagnose(QStringLiteral("invalid ActiveProfile event"));
                return;
            }
            profile = value.toString();
        } else if (invalidated.contains(QStringLiteral("ActiveProfile"))) {
            const auto current = readPowerProfile(powerEndpoint);
            if (!current.has_value()) {
                diagnose(QStringLiteral("invalid ActiveProfile refresh"));
                return;
            }
            profile = *current;
        } else {
            return;
        }

        if (!validProfile(profile)) {
            diagnose(QStringLiteral("unsupported ActiveProfile value"));
            return;
        }
        const bool nextPerformance = profile == QStringLiteral("performance");
        if (nextPerformance == performanceProfile) {
            return;
        }
        performanceProfile = nextPerformance;
        publishState(QStringLiteral("profile"), true);
    }

    void onPowerOwnerChanged(const QString &service, const QString &oldOwner,
                             const QString &newOwner)
    {
        if (oldOwner == newOwner) {
            return;
        }

        const PowerEndpoint next = preferredPowerEndpoint();
        if (sameEndpoint(next, powerEndpoint)) {
            if (powerEndpoint.owner != next.owner && service == powerEndpoint.service) {
                const bool lostSource = !oldOwner.isEmpty();
                detachPower();
                performanceProfile = false;
                if (lostSource) {
                    publishState(QStringLiteral("sourceUnavailable"), true);
                }
                if (next.available()) {
                    attachPower(next);
                }
                publishState(QStringLiteral("snapshot"));
            }
            return;
        }

        // When one alias disappears while the other remains, switch endpoints
        // atomically. Both names describe the same effective profile source.
        const bool replacementAvailable = next.available();
        const bool lostSource = powerEndpoint.available() && !replacementAvailable;
        detachPower();
        performanceProfile = false;
        if (replacementAvailable) {
            attachPower(next);
        }
        if (lostSource) {
            publishState(QStringLiteral("sourceUnavailable"), true);
        }
        publishState(QStringLiteral("snapshot"));
    }

private:
    void initialize()
    {
        if (!sessionBus.isConnected()) {
            diagnose(QStringLiteral("session bus unavailable"));
        } else {
            const QString owner = serviceOwner(sessionBus, QString::fromLatin1(GameService));
            if (!owner.isEmpty()) {
                attachGame(owner);
            }
        }

        if (!systemBus.isConnected()) {
            diagnose(QStringLiteral("system bus unavailable"));
        } else {
            const PowerEndpoint endpoint = preferredPowerEndpoint();
            if (endpoint.available()) {
                attachPower(endpoint);
            }
        }
        publishState(QStringLiteral("snapshot"), true);
    }

    static QString serviceOwner(const QDBusConnection &bus, const QString &service)
    {
        QDBusConnectionInterface *interface = bus.interface();
        if (interface == nullptr) {
            return {};
        }
        const QDBusReply<QString> reply = interface->serviceOwner(service);
        return reply.isValid() ? reply.value() : QString{};
    }

    void attachGame(const QString &owner)
    {
        if (owner.isEmpty()) {
            return;
        }
        const bool connected = sessionBus.connect(
            QString::fromLatin1(GameService), QString::fromLatin1(GamePath),
            QString::fromLatin1(GameInterface), QStringLiteral("GameRegistered"), this,
            SLOT(onGameEvent(QDBusMessage)))
            && sessionBus.connect(
                QString::fromLatin1(GameService), QString::fromLatin1(GamePath),
                QString::fromLatin1(GameInterface), QStringLiteral("GameUnregistered"), this,
                SLOT(onGameEvent(QDBusMessage)));
        if (!connected) {
            diagnose(QStringLiteral("could not observe GameMode"));
            detachGame();
            return;
        }

        gameOwner = owner;
        const auto count = readGameClientCount();
        if (!count.has_value()) {
            diagnose(QStringLiteral("could not read GameMode ClientCount"));
            detachGame();
            return;
        }
        gameClientCount = *count;
    }

    void detachGame()
    {
        if (!gameOwner.isEmpty()) {
            sessionBus.disconnect(QString::fromLatin1(GameService), QString::fromLatin1(GamePath),
                                  QString::fromLatin1(GameInterface), QStringLiteral("GameRegistered"),
                                  this, SLOT(onGameEvent(QDBusMessage)));
            sessionBus.disconnect(QString::fromLatin1(GameService), QString::fromLatin1(GamePath),
                                  QString::fromLatin1(GameInterface),
                                  QStringLiteral("GameUnregistered"), this,
                                  SLOT(onGameEvent(QDBusMessage)));
        }
        gameOwner.clear();
    }

    [[nodiscard]] std::optional<int> readGameClientCount() const
    {
        const QVariant value = readProperty(sessionBus, QString::fromLatin1(GameService),
                                            QString::fromLatin1(GamePath),
                                            QString::fromLatin1(GameInterface),
                                            QStringLiteral("ClientCount"));
        if (value.metaType().id() != QMetaType::Int) {
            return std::nullopt;
        }
        const int count = value.toInt();
        return count >= 0 && count <= MaximumClientCount ? std::optional<int>(count) : std::nullopt;
    }

    [[nodiscard]] PowerEndpoint preferredPowerEndpoint() const
    {
        const QString modernOwner = serviceOwner(systemBus, QString::fromLatin1(ModernService));
        if (!modernOwner.isEmpty()) {
            return {QString::fromLatin1(ModernService), QString::fromLatin1(ModernPath),
                    QString::fromLatin1(ModernInterface), modernOwner};
        }
        const QString legacyOwner = serviceOwner(systemBus, QString::fromLatin1(LegacyService));
        if (!legacyOwner.isEmpty()) {
            return {QString::fromLatin1(LegacyService), QString::fromLatin1(LegacyPath),
                    QString::fromLatin1(LegacyInterface), legacyOwner};
        }
        return {};
    }

    static bool sameEndpoint(const PowerEndpoint &left, const PowerEndpoint &right)
    {
        return left.service == right.service && left.path == right.path
            && left.interface == right.interface;
    }

    void attachPower(const PowerEndpoint &endpoint)
    {
        if (!endpoint.available()) {
            return;
        }
        if (!systemBus.connect(endpoint.service, endpoint.path,
                               QString::fromLatin1(PropertiesInterface),
                               QStringLiteral("PropertiesChanged"), this,
                               SLOT(onPowerPropertiesChanged(QString,QVariantMap,QStringList)))) {
            diagnose(QStringLiteral("could not observe Power Profiles"));
            return;
        }

        powerEndpoint = endpoint;
        const auto profile = readPowerProfile(endpoint);
        if (!profile.has_value() || !validProfile(*profile)) {
            diagnose(QStringLiteral("could not read ActiveProfile"));
            detachPower();
            return;
        }
        performanceProfile = *profile == QStringLiteral("performance");
    }

    void detachPower()
    {
        if (powerEndpoint.available()) {
            systemBus.disconnect(powerEndpoint.service, powerEndpoint.path,
                                 QString::fromLatin1(PropertiesInterface),
                                 QStringLiteral("PropertiesChanged"), this,
                                 SLOT(onPowerPropertiesChanged(QString,QVariantMap,QStringList)));
        }
        powerEndpoint = {};
    }

    [[nodiscard]] std::optional<QString> readPowerProfile(const PowerEndpoint &endpoint) const
    {
        const QVariant value = readProperty(systemBus, endpoint.service, endpoint.path,
                                            endpoint.interface, QStringLiteral("ActiveProfile"));
        return value.metaType().id() == QMetaType::QString
            ? std::optional<QString>(value.toString())
            : std::nullopt;
    }

    static QVariant readProperty(const QDBusConnection &bus, const QString &service,
                                 const QString &path, const QString &interface,
                                 const QString &property)
    {
        QDBusMessage call = QDBusMessage::createMethodCall(
            service, path, QString::fromLatin1(PropertiesInterface), QStringLiteral("Get"));
        call.setAutoStartService(false);
        call << interface << property;
        const QDBusMessage reply = bus.call(call, QDBus::Block, DbusTimeoutMs);
        if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().size() != 1) {
            return {};
        }
        const QVariant wrapped = reply.arguments().constFirst();
        return wrapped.canConvert<QDBusVariant>() ? qvariant_cast<QDBusVariant>(wrapped).variant()
                                                   : QVariant{};
    }

    static bool validProfile(const QString &profile)
    {
        return profile == QStringLiteral("performance") || profile == QStringLiteral("balanced")
            || profile == QStringLiteral("power-saver");
    }

    void publishState(const QString &event, bool force = false)
    {
        const int sourceCount = gameClientCount + (performanceProfile ? 1 : 0);
        QJsonObject message{
            {QStringLiteral("type"), QStringLiteral("state")},
            {QStringLiteral("available"), !gameOwner.isEmpty() || powerEndpoint.available()},
            {QStringLiteral("gameModeAvailable"), !gameOwner.isEmpty()},
            {QStringLiteral("powerProfilesAvailable"), powerEndpoint.available()},
            {QStringLiteral("gameClientCount"), gameClientCount},
            {QStringLiteral("performanceProfile"), performanceProfile},
            {QStringLiteral("sourceCount"), sourceCount},
            {QStringLiteral("event"), event},
        };
        publish(message, force);
    }

    void publish(const QJsonObject &message, bool force = false)
    {
        const QByteArray bytes = QJsonDocument(message).toJson(QJsonDocument::Compact);
        if (!force && message.value(QStringLiteral("type")) == QStringLiteral("state")
            && bytes == lastState) {
            return;
        }
        if (message.value(QStringLiteral("type")) == QStringLiteral("state")) {
            lastState = bytes;
        }
        std::fwrite(bytes.constData(), 1, static_cast<size_t>(bytes.size()), stdout);
        std::fputc('\n', stdout);
        std::fflush(stdout);
    }

    void diagnose(const QString &message)
    {
        if (diagnosticCount >= MaximumDiagnostics || message == lastDiagnostic) {
            return;
        }
        diagnosticCount += 1;
        lastDiagnostic = message;
        const QByteArray bounded = message.left(160).toUtf8();
        std::fprintf(stderr, "nagi-shell gaming performance helper: %s\n", bounded.constData());
        std::fflush(stderr);
    }

    QDBusConnection sessionBus;
    QDBusConnection systemBus;
    QDBusServiceWatcher gameWatcher;
    QDBusServiceWatcher modernWatcher;
    QDBusServiceWatcher legacyWatcher;
    QString gameOwner;
    PowerEndpoint powerEndpoint;
    QByteArray lastState;
    QString lastDiagnostic;
    int gameClientCount = 0;
    int diagnosticCount = 0;
    bool performanceProfile = false;
};
} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    application.setApplicationName(QStringLiteral("nagi-gaming-performance"));
    GamingPerformanceObserver observer;
    return application.exec();
}

#include "main.moc"

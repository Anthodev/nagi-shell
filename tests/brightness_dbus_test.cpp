#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusVirtualObject>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QTimer>
#include <QVariantMap>

#include <utility>
#include <functional>


namespace {

constexpr auto Service = "org.kde.ScreenBrightness";
constexpr auto RootPath = "/org/kde/ScreenBrightness";
constexpr auto RootInterface = "org.kde.ScreenBrightness";
constexpr auto DisplayInterface = "org.kde.ScreenBrightness.Display";
constexpr auto PropertiesInterface = "org.freedesktop.DBus.Properties";

struct FakeDisplay {
    QString label;
    bool isInternal = false;
    int maximum = 100;
    int brightness = 40;
};

struct CapturedWrite {
    int brightness = 0;
    quint32 flags = 0;
    QString context;
    QString client;
};

class FakeBrightnessService final : public QDBusVirtualObject {
public:
    explicit FakeBrightnessService(QDBusConnection bus, QObject *parent = nullptr)
        : QDBusVirtualObject(parent)
        , bus(std::move(bus))
    {
        displays.insert(QStringLiteral("display0"),
                        FakeDisplay{QStringLiteral("Main Display"), false, 100, 40});
        displays.insert(QStringLiteral("display1"),
                        FakeDisplay{QStringLiteral("Internal Panel"), true, 200, 80});
        displays.insert(QStringLiteral("invalid0"),
                        FakeDisplay{QStringLiteral("Invalid"), false, 0, 0});
    }

    QString introspect(const QString &) const override
    {
        return {};
    }

    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override
    {
        if (message.interface() == QString::fromLatin1(PropertiesInterface)
            && message.member() == QStringLiteral("GetAll")) {
            return handleGetAll(message, connection);
        }
        if (message.interface() == QString::fromLatin1(DisplayInterface)
            && message.member() == QStringLiteral("SetBrightnessWithContext")) {
            return handleSetBrightness(message, connection);
        }
        connection.send(message.createErrorReply(QDBusError::UnknownMethod,
                                                 QStringLiteral("unsupported fixture call")));
        return true;
    }

    void confirmWrite(const QString &name)
    {
        const CapturedWrite write = writes.value(name);
        displays[name].brightness = write.brightness;
        sendBrightnessChanged(name, write.brightness, write.client, write.context);
    }

    void sendExternalChange(const QString &name, int brightness, const QString &client,
                            const QString &context)
    {
        displays[name].brightness = brightness;
        sendBrightnessChanged(name, brightness, client, context);
    }

    void sendRangeChange(const QString &name, int maximum, int brightness)
    {
        displays[name].maximum = maximum;
        displays[name].brightness = brightness;
        QDBusMessage signal = QDBusMessage::createSignal(
            QString::fromLatin1(RootPath), QString::fromLatin1(RootInterface),
            QStringLiteral("BrightnessRangeChanged"));
        signal << name << maximum << brightness;
        bus.send(signal);
    }

    void removeDisplay(const QString &name)
    {
        displays.remove(name);
        QDBusMessage signal = QDBusMessage::createSignal(
            QString::fromLatin1(RootPath), QString::fromLatin1(RootInterface),
            QStringLiteral("DisplayRemoved"));
        signal << name;
        bus.send(signal);
    }

    void addDisplay(const QString &name, const FakeDisplay &display)
    {
        displays.insert(name, display);
        QDBusMessage signal = QDBusMessage::createSignal(
            QString::fromLatin1(RootPath), QString::fromLatin1(RootInterface),
            QStringLiteral("DisplayAdded"));
        signal << name;
        bus.send(signal);
    }

    void replaceDisplays()
    {
        displays.clear();
        displays.insert(QStringLiteral("display9"),
                        FakeDisplay{QStringLiteral("Replacement"), false, 100, 25});
        writes.clear();
    }

    int writeCount = 0;
    QHash<QString, CapturedWrite> writes;

private:
    bool handleGetAll(const QDBusMessage &message, const QDBusConnection &connection)
    {
        const QList<QVariant> arguments = message.arguments();
        if (arguments.size() != 1) {
            return false;
        }
        const QString requestedInterface = arguments.constFirst().toString();
        QVariantMap properties;
        if (message.path() == QString::fromLatin1(RootPath)
            && requestedInterface == QString::fromLatin1(RootInterface)) {
            QStringList names = displays.keys();
            names.sort();
            properties.insert(QStringLiteral("DisplaysDBusNames"), names);
        } else if (requestedInterface == QString::fromLatin1(DisplayInterface)) {
            const QString prefix = QString::fromLatin1(RootPath) + QLatin1Char('/');
            if (!message.path().startsWith(prefix)) {
                return false;
            }
            const QString name = message.path().mid(prefix.size());
            const auto display = displays.constFind(name);
            if (display == displays.cend()) {
                connection.send(message.createErrorReply(QDBusError::UnknownObject,
                                                         QStringLiteral("missing display")));
                return true;
            }
            properties.insert(QStringLiteral("Label"), display->label);
            properties.insert(QStringLiteral("IsInternal"), display->isInternal);
            properties.insert(QStringLiteral("MaxBrightness"), display->maximum);
            properties.insert(QStringLiteral("Brightness"), display->brightness);
        } else {
            connection.send(message.createErrorReply(QDBusError::UnknownInterface,
                                                     QStringLiteral("unknown interface")));
            return true;
        }
        connection.send(message.createReply(QVariantList{properties}));
        return true;
    }

    bool handleSetBrightness(const QDBusMessage &message, const QDBusConnection &connection)
    {
        const QString prefix = QString::fromLatin1(RootPath) + QLatin1Char('/');
        const QString name = message.path().startsWith(prefix)
            ? message.path().mid(prefix.size()) : QString{};
        const QList<QVariant> arguments = message.arguments();
        if (!displays.contains(name) || arguments.size() != 3) {
            connection.send(message.createErrorReply(QDBusError::InvalidArgs,
                                                     QStringLiteral("invalid write")));
            return true;
        }
        CapturedWrite write;
        write.brightness = arguments.at(0).toInt();
        write.flags = arguments.at(1).toUInt();
        write.context = arguments.at(2).toString();
        write.client = message.service();
        writes.insert(name, write);
        writeCount += 1;
        connection.send(message.createReply());
        return true;
    }

    void sendBrightnessChanged(const QString &name, int brightness, const QString &client,
                               const QString &context)
    {
        QDBusMessage signal = QDBusMessage::createSignal(
            QString::fromLatin1(RootPath), QString::fromLatin1(RootInterface),
            QStringLiteral("BrightnessChanged"));
        signal << name << brightness << client << context;
        bus.send(signal);
    }

    QDBusConnection bus;
    QHash<QString, FakeDisplay> displays;
};

class BrightnessDbusTest final : public QObject {
    Q_OBJECT

public:
    BrightnessDbusTest(QString helperPath, QObject *parent = nullptr)
        : QObject(parent)
        , helperPath(std::move(helperPath))
        , bus(QDBusConnection::sessionBus())
        , service(bus, this)
    {
    }

    void start()
    {
        if (!bus.isConnected()
            || !bus.registerVirtualObject(QStringLiteral("/"), &service,
                                          QDBusConnection::SubPath)
            || !bus.registerService(QString::fromLatin1(Service))) {
            fail("could not register fake brightness service");
            return;
        }

        connect(&helper, &QProcess::readyReadStandardOutput, this,
                &BrightnessDbusTest::readOutput);
        connect(&helper, &QProcess::readyReadStandardError, this, [this] {
            diagnostics.append(helper.readAllStandardError());
        });
        connect(&helper, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) {
            fail("brightness helper process failed");
        });
        connect(&helper, &QProcess::finished, this,
                [this](int exitCode, QProcess::ExitStatus status) {
                    if (stage != Stage::Cleanup || exitCode != 0
                        || status != QProcess::NormalExit) {
                        fail("brightness helper exited unexpectedly");
                        return;
                    }
                    timeout.stop();
                    require(diagnostics.count('\n') <= 8,
                            "helper diagnostics remain bounded");
                    require(!diagnostics.contains("secret-client")
                                && !diagnostics.contains("secret-context"),
                            "raw source data never reaches diagnostics");
                    qInfo("brightness D-Bus tests passed");
                    QCoreApplication::exit(0);
                });

        timeout.setSingleShot(true);
        timeout.setInterval(20000);
        connect(&timeout, &QTimer::timeout, this,
                [this] { fail("brightness D-Bus test timed out"); });
        timeout.start();
        helper.start(helperPath);
    }

private:
    enum class Stage {
        Initial,
        InvalidCommands,
        FirstPending,
        SecondPending,
        SecondConfirmed,
        FirstConfirmed,
        Noop,
        External,
        Unknown,
        Range,
        RemovalPending,
        RemovedOne,
        Empty,
        Added,
        Unavailable,
        Replaced,
        Stale,
        TimeoutPending,
        Cleanup,
    };

    static QJsonObject displayWithLabel(const QJsonObject &state, const QString &label)
    {
        for (const QJsonValue value : state.value(QStringLiteral("displays")).toArray()) {
            const QJsonObject display = value.toObject();
            if (display.value(QStringLiteral("label")).toString() == label) {
                return display;
            }
        }
        return {};
    }

    static QJsonObject displayWithKey(const QJsonObject &state, const QString &key)
    {
        for (const QJsonValue value : state.value(QStringLiteral("displays")).toArray()) {
            const QJsonObject display = value.toObject();
            if (display.value(QStringLiteral("key")).toString() == key) {
                return display;
            }
        }
        return {};
    }

    static bool fuzzyRatio(const QJsonObject &object, double expected)
    {
        return qAbs(object.value(QStringLiteral("ratio")).toDouble() - expected) < 0.000001;
    }

    void readOutput()
    {
        output.append(helper.readAllStandardOutput());
        while (true) {
            const qsizetype newline = output.indexOf('\n');
            if (newline < 0) {
                return;
            }
            const QByteArray line = output.left(newline);
            output.remove(0, newline + 1);
            const QJsonObject message = QJsonDocument::fromJson(line).object();
            if (message.value(QStringLiteral("type")) == QStringLiteral("ready")) {
                continue;
            }
            require(message.value(QStringLiteral("type")) == QStringLiteral("state"),
                    "helper publishes only ready or complete state messages");
            require(!line.contains("secret-client") && !line.contains("secret-context")
                        && !line.contains("nagi-shell:"),
                    "state output never exposes raw source or generated context");
            processState(message);
        }
    }

    void processState(const QJsonObject &state)
    {
        const QJsonObject request = state.value(QStringLiteral("request")).toObject();
        const QJsonObject change = state.value(QStringLiteral("change")).toObject();
        if (stage == Stage::Initial) {
            if (!state.value(QStringLiteral("available")).toBool()) {
                return;
            }
            require(state.value(QStringLiteral("supported")).toBool(),
                    "valid displays make brightness supported");
            require(state.value(QStringLiteral("generation")).toInt() == 1,
                    "initial owner receives generation one");
            require(state.value(QStringLiteral("displays")).toArray().size() == 2,
                    "invalid range is excluded from coherent initial list");
            const QJsonObject external = displayWithLabel(state, QStringLiteral("Main Display"));
            const QJsonObject internal = displayWithLabel(state, QStringLiteral("Internal Panel"));
            require(!external.isEmpty() && !external.value(QStringLiteral("isInternal")).toBool()
                        && fuzzyRatio(external, 0.4),
                    "external display label, flag, and ratio normalize");
            require(!internal.isEmpty() && internal.value(QStringLiteral("isInternal")).toBool()
                        && fuzzyRatio(internal, 0.4),
                    "internal display label, flag, and ratio normalize");
            firstKey = external.value(QStringLiteral("key")).toString();
            secondKey = internal.value(QStringLiteral("key")).toString();
            stage = Stage::InvalidCommands;
            helper.write("not-json\n");
            helper.write("{\"action\":\"setBrightness\",\"requestId\":90,\"displayKey\":\""
                         + firstKey.toUtf8() + "\",\"ratio\":2}\n");
            helper.write("{\"action\":\"setBrightness\",\"requestId\":91,\"displayKey\":\"99:missing\",\"ratio\":0.5}\n");
            return;
        }
        if (stage == Stage::InvalidCommands) {
            const int requestId = request.value(QStringLiteral("requestId")).toInt();
            const QString outcome = request.value(QStringLiteral("outcome")).toString();
            sawInvalid = sawInvalid || (requestId == 90 && outcome == QStringLiteral("invalid"));
            sawStale = sawStale || (requestId == 91 && outcome == QStringLiteral("stale"));
            if (!sawInvalid || !sawStale) {
                return;
            }
            require(service.writeCount == 0,
                    "invalid ratios and stale keys cannot reach D-Bus");
            stage = Stage::FirstPending;
            sendSet(1, firstKey, 0.7);
            return;
        }
        if (stage == Stage::FirstPending && request.value(QStringLiteral("requestId")).toInt() == 1
            && request.value(QStringLiteral("outcome")).toString() == QStringLiteral("pending")) {
            const QJsonObject display = displayWithKey(state, firstKey);
            require(display.value(QStringLiteral("pending")).toBool() && fuzzyRatio(display, 0.4),
                    "pending write preserves the prior confirmed ratio");
            waitForWrites(1, 100, [this] {
                const CapturedWrite write = service.writes.value(QStringLiteral("display0"));
                require(write.brightness == 70 && write.flags == 1
                            && write.context == QStringLiteral("nagi-shell:1")
                            && !write.client.isEmpty(),
                        "write uses per-display method, suppression flag, and generated context");
                stage = Stage::SecondPending;
                sendSet(2, secondKey, 0.6);
            });
            return;
        }
        if (stage == Stage::SecondPending && request.value(QStringLiteral("requestId")).toInt() == 2
            && request.value(QStringLiteral("outcome")).toString() == QStringLiteral("pending")) {
            const QJsonObject first = displayWithKey(state, firstKey);
            const QJsonObject second = displayWithKey(state, secondKey);
            require(first.value(QStringLiteral("pending")).toBool()
                        && second.value(QStringLiteral("pending")).toBool()
                        && fuzzyRatio(first, 0.4) && fuzzyRatio(second, 0.4),
                    "independent display writes remain pending without optimistic values");
            waitForWrites(2, 100, [this] {
                const CapturedWrite write = service.writes.value(QStringLiteral("display1"));
                require(write.brightness == 120 && write.flags == 1
                            && write.context == QStringLiteral("nagi-shell:2"),
                        "second write uses its own fixed display and context");
                stage = Stage::SecondConfirmed;
                service.confirmWrite(QStringLiteral("display1"));
            });
            return;
        }
        if (stage == Stage::SecondConfirmed
            && change.value(QStringLiteral("requestId")).toInt() == 2) {
            require(change.value(QStringLiteral("origin")).toString() == QStringLiteral("self")
                        && fuzzyRatio(change, 0.6),
                    "matching source and context confirm self-originated logical state");
            require(displayWithKey(state, firstKey).value(QStringLiteral("pending")).toBool(),
                    "unrelated pending display remains pending");
            stage = Stage::FirstConfirmed;
            service.confirmWrite(QStringLiteral("display0"));
            return;
        }
        if (stage == Stage::FirstConfirmed
            && change.value(QStringLiteral("requestId")).toInt() == 1) {
            require(change.value(QStringLiteral("origin")).toString() == QStringLiteral("self")
                        && fuzzyRatio(change, 0.7),
                    "first request confirms only after signal and refreshed snapshot");
            stage = Stage::Noop;
            sendSet(3, firstKey, 0.7);
            return;
        }
        if (stage == Stage::Noop && request.value(QStringLiteral("requestId")).toInt() == 3) {
            require(request.value(QStringLiteral("outcome")).toString() == QStringLiteral("noop")
                        && service.writeCount == 2 && change.isEmpty(),
                    "same-value request completes locally without D-Bus or transient change");
            const CapturedWrite write = service.writes.value(QStringLiteral("display0"));
            stage = Stage::External;
            service.sendExternalChange(QStringLiteral("display0"), 65, write.client,
                                       QStringLiteral("secret-context"));
            return;
        }
        if (stage == Stage::External && change.value(QStringLiteral("key")).toString() == firstKey) {
            require(change.value(QStringLiteral("origin")).toString() == QStringLiteral("external")
                        && change.value(QStringLiteral("requestId")).toInt() == 0
                        && fuzzyRatio(change, 0.65),
                    "mismatched context cannot be classified as self-originated");
            stage = Stage::Unknown;
            service.sendExternalChange(QStringLiteral("display0"), 66, QString{}, QString{});
            return;
        }
        if (stage == Stage::Unknown && change.value(QStringLiteral("key")).toString() == firstKey) {
            require(change.value(QStringLiteral("origin")).toString() == QStringLiteral("unknown")
                        && fuzzyRatio(change, 0.66),
                    "empty raw source data normalizes to unknown origin");
            stage = Stage::Range;
            service.sendRangeChange(QStringLiteral("display1"), 400, 100);
            return;
        }
        if (stage == Stage::Range) {
            const QJsonObject display = displayWithKey(state, secondKey);
            if (display.isEmpty() || !fuzzyRatio(display, 0.25)) {
                return;
            }
            require(change.isEmpty(), "range invalidation refreshes without inventing a change");
            stage = Stage::RemovalPending;
            sendSet(6, firstKey, 0.5);
            return;
        }
        if (stage == Stage::RemovalPending
            && request.value(QStringLiteral("requestId")).toInt() == 6
            && request.value(QStringLiteral("outcome")).toString() == QStringLiteral("pending")) {
            waitForWrites(3, 100, [this] {
                stage = Stage::RemovedOne;
                service.removeDisplay(QStringLiteral("display0"));
            });
            return;
        }
        if (stage == Stage::RemovedOne) {
            if (request.value(QStringLiteral("requestId")).toInt() != 6
                    || request.value(QStringLiteral("outcome")).toString() !=
                    QStringLiteral("stale") || !displayWithKey(state, firstKey).isEmpty()
                    || state.value(QStringLiteral("displays")).toArray().size() != 1) {
                return;
            }
            require(service.writeCount == 3,
                    "display removal cancels one pending fixed-target request");
            stage = Stage::Empty;
            service.removeDisplay(QStringLiteral("display1"));
            return;
        }
        if (stage == Stage::Empty) {
            if (!state.value(QStringLiteral("available")).toBool()
                || state.value(QStringLiteral("supported")).toBool()
                || !state.value(QStringLiteral("displays")).toArray().isEmpty()) {
                return;
            }
            stage = Stage::Added;
            service.addDisplay(QStringLiteral("display1"),
                               FakeDisplay{QStringLiteral("Restored"), true, 400, 100});
            return;
        }
        if (stage == Stage::Added) {
            const QJsonObject display = displayWithLabel(state, QStringLiteral("Restored"));
            if (display.isEmpty()) {
                return;
            }
            require(fuzzyRatio(display, 0.25)
                        && display.value(QStringLiteral("key")).toString() == secondKey,
                    "display re-addition refreshes range within the owner generation");
            stage = Stage::Unavailable;
            bus.unregisterService(QString::fromLatin1(Service));
            return;
        }
        if (stage == Stage::Unavailable) {
            if (state.value(QStringLiteral("available")).toBool()) {
                return;
            }
            require(!state.value(QStringLiteral("supported")).toBool()
                        && state.value(QStringLiteral("generation")).toInt() == 0
                        && state.value(QStringLiteral("displays")).toArray().isEmpty(),
                    "service loss explicitly clears every display and key");
            service.replaceDisplays();
            stage = Stage::Replaced;
            QTimer::singleShot(0, this, [this] {
                require(bus.registerService(QString::fromLatin1(Service)),
                        "replacement owner registers");
            });
            return;
        }
        if (stage == Stage::Replaced) {
            const QJsonObject display = displayWithLabel(state, QStringLiteral("Replacement"));
            if (display.isEmpty()) {
                return;
            }
            replacementKey = display.value(QStringLiteral("key")).toString();
            require(state.value(QStringLiteral("generation")).toInt() == 2
                        && replacementKey != firstKey && replacementKey != secondKey,
                    "replacement owner receives fresh generation-scoped keys");
            stage = Stage::Stale;
            sendSet(4, firstKey, 0.5);
            return;
        }
        if (stage == Stage::Stale && request.value(QStringLiteral("requestId")).toInt() == 4) {
            require(request.value(QStringLiteral("outcome")).toString() == QStringLiteral("stale")
                        && service.writeCount == 3,
                    "old-generation key is rejected without D-Bus access");
            stage = Stage::TimeoutPending;
            sendSet(5, replacementKey, 0.75);
            return;
        }
        if (stage == Stage::TimeoutPending
            && request.value(QStringLiteral("requestId")).toInt() == 5
            && request.value(QStringLiteral("outcome")).toString() == QStringLiteral("timeout")) {
            const QJsonObject display = displayWithKey(state, replacementKey);
            require(!display.value(QStringLiteral("pending")).toBool()
                        && display.value(QStringLiteral("failure")).toString()
                            == QStringLiteral("timeout")
                        && fuzzyRatio(display, 0.25),
                    "write timeout keeps confirmed state and reports bounded failure");
            stage = Stage::Cleanup;
            helper.closeWriteChannel();
        }
    }

    void waitForWrites(int expected, int attempts, const std::function<void()> &continuation)
    {
        if (service.writeCount >= expected) {
            continuation();
            return;
        }
        if (attempts <= 0) {
            fail("brightness write did not reach D-Bus");
        }
        QTimer::singleShot(10, this, [this, expected, attempts, continuation] {
            waitForWrites(expected, attempts - 1, continuation);
        });
    }

    void sendSet(int requestId, const QString &key, double ratio)
    {
        const QJsonObject command{
            {QStringLiteral("action"), QStringLiteral("setBrightness")},
            {QStringLiteral("requestId"), requestId},
            {QStringLiteral("displayKey"), key},
            {QStringLiteral("ratio"), ratio},
        };
        helper.write(QJsonDocument(command).toJson(QJsonDocument::Compact) + '\n');
    }

    void require(bool condition, const char *message)
    {
        if (!condition) {
            fail(message);
        }
    }

    [[noreturn]] void fail(const char *message)
    {
        std::fprintf(stderr, "FAIL: %s\n", message);
        if (helper.state() != QProcess::NotRunning) {
            helper.kill();
            helper.waitForFinished(1000);
        }
        diagnostics.append(helper.readAllStandardError());
        if (!diagnostics.isEmpty()) {
            std::fprintf(stderr, "helper stderr: %s\n", diagnostics.constData());
        }
        std::exit(1);
    }

    QString helperPath;
    QDBusConnection bus;
    FakeBrightnessService service;
    QProcess helper;
    QTimer timeout;
    QByteArray output;
    QByteArray diagnostics;
    QString firstKey;
    QString secondKey;
    QString replacementKey;
    Stage stage = Stage::Initial;
    bool sawInvalid = false;
    bool sawStale = false;
};

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    if (argc != 2) {
        qCritical("expected brightness helper path");
        return 2;
    }
    BrightnessDbusTest test(QString::fromLocal8Bit(argv[1]));
    QTimer::singleShot(0, &test, [&test] { test.start(); });
    return application.exec();
}

#include "brightness_dbus_test.moc"

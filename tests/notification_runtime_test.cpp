#include "notification_text.h"
#include "runtime.h"

#include <QCoreApplication>
#include <QMetaObject>

#include <cstdio>
#include <cstdlib>
#include <memory>

using nagi::notifications::NotificationRuntime;
using nagi::notifications::normalizeBody;
using nagi::notifications::normalizeDesktopEntry;
using nagi::notifications::normalizeIconName;
using nagi::notifications::normalizePlainText;

namespace {

[[noreturn]] void fail(const char *message)
{
    std::fprintf(stderr, "notification runtime test failed: %s\n", message);
    std::exit(1);
}

void require(bool condition, const char *message)
{
    if (!condition) {
        fail(message);
    }
}

class FakeNotification final : public QObject {
    Q_OBJECT
    Q_PROPERTY(uint id MEMBER protocolId CONSTANT)
    Q_PROPERTY(QString appName MEMBER appName NOTIFY appNameChanged)
    Q_PROPERTY(QString summary MEMBER summary NOTIFY summaryChanged)
    Q_PROPERTY(QString body MEMBER body NOTIFY bodyChanged)
    Q_PROPERTY(int urgency MEMBER urgency NOTIFY urgencyChanged)
    Q_PROPERTY(QString desktopEntry MEMBER desktopEntry NOTIFY desktopEntryChanged)
    Q_PROPERTY(QString appIcon MEMBER appIcon NOTIFY appIconChanged)
    Q_PROPERTY(bool resident MEMBER resident NOTIFY residentChanged)
    Q_PROPERTY(bool transient MEMBER transient NOTIFY transientChanged)
    Q_PROPERTY(qint64 expireTimeout MEMBER expireTimeout NOTIFY expireTimeoutChanged)
    Q_PROPERTY(bool lastGeneration MEMBER lastGeneration CONSTANT)

public:
    explicit FakeNotification(uint id, QObject *parent = nullptr)
        : QObject(parent)
        , protocolId(id)
    {
    }

    Q_INVOKABLE void expire()
    {
        ++expireCalls;
        emit closed(1);
    }

    Q_INVOKABLE void dismiss()
    {
        ++dismissCalls;
        emit closed(2);
    }

    void changed()
    {
        emit appNameChanged();
        emit summaryChanged();
        emit bodyChanged();
        emit urgencyChanged();
        emit desktopEntryChanged();
        emit appIconChanged();
        emit residentChanged();
        emit transientChanged();
        emit expireTimeoutChanged();
    }

    uint protocolId;
    QString appName = QStringLiteral("App");
    QString summary = QStringLiteral("Summary");
    QString body = QStringLiteral("Body");
    int urgency = 1;
    QString desktopEntry = QStringLiteral("org.example.App");
    QString appIcon = QStringLiteral("example-app");
    bool resident = false;
    bool transient = false;
    qint64 expireTimeout = 0;
    bool lastGeneration = false;
    int expireCalls = 0;
    int dismissCalls = 0;

signals:
    void appNameChanged();
    void summaryChanged();
    void bodyChanged();
    void urgencyChanged();
    void desktopEntryChanged();
    void appIconChanged();
    void residentChanged();
    void transientChanged();
    void expireTimeoutChanged();
    void closed(int reason);
};

void bind(NotificationRuntime &runtime, FakeNotification &notification)
{
    QObject::connect(&notification, &FakeNotification::closed, &runtime,
                     [&runtime, &notification](int reason) {
                         runtime.closeNotification(&notification, reason);
                     });
}

void startGeneration(NotificationRuntime &runtime)
{
    const quint64 generation = runtime.beginGeneration();
    runtime.finishGeneration(generation);
}

void attach(NotificationRuntime &runtime, FakeNotification &notification)
{
    bind(runtime, notification);
    runtime.attachNotification(&notification, 1);
}

void drainEvents()
{
    QCoreApplication::processEvents();
}

} // namespace

namespace nagi::notifications {

class NotificationRuntimeTest {
public:
    static void processDue(NotificationRuntime &runtime)
    {
        runtime.processDueDeadlines();
    }

    static void setServerOwned(NotificationRuntime &runtime, bool owned)
    {
        runtime.setServerOwned(owned);
    }

    static void exhaustHistoryAfterNext(NotificationRuntime &runtime)
    {
        runtime.nextHistorySequence = std::numeric_limits<quint64>::max();
    }

    static void exhaustLiveAfterNext(NotificationRuntime &runtime)
    {
        runtime.nextLiveSequence = std::numeric_limits<quint64>::max();
    }
};

} // namespace nagi::notifications

namespace {

void testNormalization()
{
    require(normalizePlainText(QStringLiteral("A\r\nB\tC\0D"), 256, false)
                == QStringLiteral("A\nB�C�D"),
            "plain controls were not normalized");
    require(normalizeBody(
                QStringLiteral("<b>Bold</b> <a href=\"file:///secret\">link</a>"
                               "<img src=\"https://invalid\" alt=\"ALT\"/>"))
                == QStringLiteral("Bold linkALT"),
            "markup was not reduced to plain text");
    require(normalizeBody(QStringLiteral("before<broken>inside</other>after"))
                == QStringLiteral("beforeinsideafter"),
            "malformed markup fallback retained tag spans");
    require(normalizePlainText(QString(300, QChar(0x20ac)), 256, false).toUtf8().size() == 255,
            "UTF-8 byte bound split a code point");
    require(normalizePlainText(QString(2048, QLatin1Char('s')), 1024, false).size() == 1024,
            "summary UTF-8 byte bound was not enforced");
    require(normalizeBody(QString(8192, QLatin1Char('b'))).size() == 4096,
            "body UTF-8 byte bound was not enforced");
    require(normalizeBody(QStringLiteral("A\tB\nC\u0001D")) == QStringLiteral("A\tB\nC�D"),
            "body whitespace and controls were not normalized independently");
    require(normalizeDesktopEntry(QString(1024, QLatin1Char('d'))).size() == 512,
            "desktop-entry UTF-8 byte bound was not enforced");
    require(normalizeIconName(QString(1024, QLatin1Char('i'))).size() == 512,
            "icon-name UTF-8 byte bound was not enforced");
    require(normalizeDesktopEntry(QStringLiteral("org.example.App"))
                == QStringLiteral("org.example.App"),
            "valid desktop entry was rejected");
    require(normalizeDesktopEntry(QStringLiteral("/tmp/private")).isEmpty(),
            "path-like desktop entry was retained");
    require(normalizeIconName(QStringLiteral("theme-icon")) == QStringLiteral("theme-icon"),
            "valid icon name was rejected");
    require(normalizeIconName(QStringLiteral("../secret")).isEmpty(),
            "path-like icon name was retained");
}

void testLifecycleAndExpiry()
{
    qint64 now = 100;
    NotificationRuntime runtime([&now] { return now; }, false);
    startGeneration(runtime);

    FakeNotification notification(1);
    notification.appName = QStringLiteral("App\0Name");
    notification.body = QStringLiteral("<b>Body</b>");
    notification.expireTimeout = 50;
    attach(runtime, notification);

    require(runtime.liveCount() == 1 && runtime.historyCount() == 1,
            "fresh notification was not admitted");
    const QVariantMap initial = runtime.historySnapshot(0);
    require(initial.value(QStringLiteral("appName")).toString() == QStringLiteral("App�Name"),
            "snapshot app name was not normalized");
    require(initial.value(QStringLiteral("body")).toString() == QStringLiteral("Body"),
            "snapshot body was not normalized");
    require(initial.value(QStringLiteral("firstAdmittedMonotonicMs")).toLongLong() == 100,
            "admission did not use monotonic time");
    require(initial.value(QStringLiteral("historyCutoffMonotonicMs")).toLongLong() == 86'400'100,
            "history cutoff was not exactly 24 hours");
    require(runtime.activeTimerCount() == 1, "single deadline scheduler was not armed");
    require(!runtime.actionsSupported() && !runtime.canAct(initial.value("firstAdmissionSequence"))
                && runtime.actionsFor(initial.value("firstAdmissionSequence")).isEmpty(),
            "actions were exposed before the gate passed");

    now = 149;
    nagi::notifications::NotificationRuntimeTest::processDue(runtime);
    require(runtime.liveCount() == 1, "notification expired before its millisecond deadline");
    now = 150;
    nagi::notifications::NotificationRuntimeTest::processDue(runtime);
    require(notification.expireCalls == 1 && runtime.liveCount() == 0,
            "explicit millisecond expiry did not close the live notification");
    require(runtime.historyCount() == 1
                && runtime.historySnapshot(0).value("state").toString() == QStringLiteral("expired"),
            "expiry did not retain a text-only snapshot");

    const quint64 generation = runtime.beginGeneration();
    runtime.finishGeneration(generation);
    require(runtime.historyCount() == 0, "reload retained a closed snapshot");
}

void testReplacementAndCloseReasons()
{
    qint64 now = 0;
    NotificationRuntime runtime([&now] { return now; }, false);
    startGeneration(runtime);

    FakeNotification notification(7);
    notification.expireTimeout = 0;
    attach(runtime, notification);
    const QVariantMap admitted = runtime.historySnapshot(0);
    const QString originalKey = admitted.value("firstAdmissionSequence").toString();
    require(runtime.historyIndex(originalKey) == 0,
            "history record key did not resolve to its view index");

    now = 500;
    notification.summary = QStringLiteral("Replacement");
    notification.resident = true;
    notification.changed();
    runtime.updateNotification(&notification);
    drainEvents();
    const QVariantMap replaced = runtime.historySnapshot(0);
    require(replaced.value("firstAdmissionSequence").toString() == originalKey
                && replaced.value("firstAdmittedMonotonicMs").toLongLong() == 0
                && replaced.value("summary").toString() == QStringLiteral("Replacement")
                && replaced.value("resident").toBool(),
            "same-ID replacement changed identity, age, or failed to substitute fields");

    notification.transient = true;
    runtime.updateNotification(&notification);
    drainEvents();
    require(runtime.historyCount() == 0 && runtime.liveCount() == 1,
            "non-transient to transient replacement did not remove history only");

    now = 700;
    notification.transient = false;
    runtime.updateNotification(&notification);
    drainEvents();
    const QVariantMap readmitted = runtime.historySnapshot(0);
    require(runtime.historyCount() == 1
                && readmitted.value("firstAdmissionSequence").toString() != originalKey
                && readmitted.value("firstAdmittedMonotonicMs").toLongLong() == 700,
            "transient to non-transient replacement was not a fresh admission");

    emit notification.closed(3);
    require(runtime.liveCount() == 0 && runtime.historyCount() == 0,
            "sender closure did not remove live state and history");

    FakeNotification dismissed(8);
    attach(runtime, dismissed);
    const QString dismissedKey = runtime.historySnapshot(0).value("firstAdmissionSequence").toString();
    require(runtime.dismiss(dismissedKey) && dismissed.dismissCalls == 1
                && runtime.liveCount() == 0 && runtime.historyCount() == 0,
            "service-mediated dismissal did not remove state immediately");

    FakeNotification expired(10);
    expired.expireTimeout = 1;
    attach(runtime, expired);
    const QString expiredKey = runtime.historySnapshot(0).value("firstAdmissionSequence").toString();
    now += 1;
    nagi::notifications::NotificationRuntimeTest::processDue(runtime);
    require(runtime.historyCount() == 1 && runtime.liveCount() == 0
                && runtime.historySnapshot(0).value("state").toString()
                    == QStringLiteral("expired"),
            "expiry fixture did not retain its text-only history row");
    require(runtime.dismiss(expiredKey) && runtime.historyCount() == 0
                && runtime.historyIndex(expiredKey) == -1 && !runtime.dismiss(expiredKey),
            "local dismissal did not remove an expired row or reject its stale key");

    FakeNotification undefinedClose(9);
    attach(runtime, undefinedClose);
    emit undefinedClose.closed(4);
    require(runtime.liveCount() == 0 && runtime.historyCount() == 0,
            "undefined close reason did not fail closed");
}

void testTransientPresentationContract()
{
    qint64 now = 0;
    NotificationRuntime runtime([&now] { return now; }, false);
    startGeneration(runtime);

    QVector<QString> requestedTokens;
    QVector<int> requestedGenerations;
    QVector<int> requestedRevisions;
    QVector<QString> invalidatedTokens;
    QObject::connect(
        &runtime, &NotificationRuntime::transientRequested, &runtime,
        [&](const QString &sourceToken, int sourceGeneration, int revision) {
            requestedTokens.append(sourceToken);
            requestedGenerations.append(sourceGeneration);
            requestedRevisions.append(revision);
        });
    QObject::connect(
        &runtime, &NotificationRuntime::transientInvalidated, &runtime,
        [&](const QString &sourceToken, int sourceGeneration) {
            require(sourceGeneration == 1, "notification source generation was not bounded");
            invalidatedTokens.append(sourceToken);
        });

    FakeNotification notification(20);
    notification.appName = QStringLiteral("Messages");
    notification.summary = QStringLiteral("Review requested");
    notification.body = QString(8192, QLatin1Char('b'));
    notification.appIcon = QString(1024, QLatin1Char('i'));
    attach(runtime, notification);

    require(requestedTokens.size() == 1 && requestedGenerations.constFirst() == 1
                && requestedRevisions.constFirst() == 1,
            "fresh notification did not emit one bounded transient identity");
    const QString sourceToken = requestedTokens.constFirst();
    const QString recordKey =
        runtime.historySnapshot(0).value("firstAdmissionSequence").toString();
    const QVariantMap initial = runtime.resolveTransient(sourceToken, 1, 1);
    require(initial.size() == 4
                && initial.value("appName").toString() == QStringLiteral("Messages")
                && initial.value("summary").toString() == QStringLiteral("Review requested")
                && initial.value("body").toString().size() == 4096
                && initial.value("appIconName").toString().size() == 512,
            "transient resolver did not expose the bounded normalized presentation");

    notification.summary = QStringLiteral("Intermediate");
    runtime.updateNotification(&notification);
    notification.summary = QStringLiteral("Latest");
    runtime.updateNotification(&notification);
    drainEvents();
    require(requestedTokens.size() == 2 && requestedTokens.constLast() == sourceToken
                && requestedRevisions.constLast() == 2
                && runtime.resolveTransient(sourceToken, 1, 1).isEmpty()
                && runtime.resolveTransient(sourceToken, 1, 2).value("summary").toString()
                    == QStringLiteral("Latest"),
            "same-source replacement did not coalesce to one exact latest revision");
    require(runtime.historyCount() == 1
                && runtime.historySnapshot(0).value("firstAdmissionSequence").toString()
                    == recordKey,
            "transient presentation changed notification history identity or count");

    FakeNotification protocolTransient(21);
    protocolTransient.transient = true;
    protocolTransient.appName = QStringLiteral("Transient sender");
    protocolTransient.body.clear();
    protocolTransient.appIcon.clear();
    attach(runtime, protocolTransient);
    require(requestedTokens.size() == 3 && requestedTokens.constLast() != sourceToken
                && runtime.historyCount() == 1,
            "independent protocol-transient notification was merged or admitted to history");
    const QVariantMap protocolTransientProjection =
        runtime.resolveTransient(requestedTokens.constLast(), 1, 1);
    require(protocolTransientProjection.contains("body")
                && protocolTransientProjection.value("body").toString().isEmpty()
                && protocolTransientProjection.contains("appIconName")
                && protocolTransientProjection.value("appIconName").toString().isEmpty(),
            "missing notification body or icon did not preserve the empty fallback");
    const QString protocolTransientToken = requestedTokens.constLast();
    emit protocolTransient.closed(3);
    require(invalidatedTokens.contains(protocolTransientToken)
                && runtime.resolveTransient(protocolTransientToken, 1, 1).isEmpty(),
            "closed transient notification remained resolvable");

    const int requestsBeforeReload = requestedTokens.size();
    notification.lastGeneration = true;
    const quint64 generation = runtime.beginGeneration();
    runtime.attachNotification(&notification, generation);
    runtime.finishGeneration(generation);
    require(requestedTokens.size() == requestsBeforeReload && runtime.historyCount() == 1,
            "last-generation handoff replayed a transient or failed history reconciliation");

    emit notification.closed(3);
    require(invalidatedTokens.contains(sourceToken)
                && runtime.resolveTransient(sourceToken, 1, 2).isEmpty(),
            "notification closure did not invalidate the live source");
}

void testUrgencyAndAgePrecedence()
{
    qint64 now = 0;
    NotificationRuntime runtime([&now] { return now; }, false);
    startGeneration(runtime);

    FakeNotification critical(1);
    critical.urgency = 2;
    critical.expireTimeout = 1;
    attach(runtime, critical);
    now = 86'400'000;
    nagi::notifications::NotificationRuntimeTest::processDue(runtime);
    require(critical.expireCalls == 0 && runtime.liveCount() == 1 && runtime.historyCount() == 0,
            "critical precedence or exact history age bound failed");

    FakeNotification low(2);
    low.urgency = 0;
    low.expireTimeout = -2;
    attach(runtime, low);
    now += 4'999;
    nagi::notifications::NotificationRuntimeTest::processDue(runtime);
    require(low.expireCalls == 0, "low default expiry fired early");
    ++now;
    nagi::notifications::NotificationRuntimeTest::processDue(runtime);
    require(low.expireCalls == 1, "invalid timeout did not normalize to low default");

    FakeNotification normal(3);
    normal.urgency = 1;
    normal.expireTimeout = -1;
    attach(runtime, normal);
    now += 10'000;
    nagi::notifications::NotificationRuntimeTest::processDue(runtime);
    require(normal.expireCalls == 1, "normal default expiry was not 10 seconds");
}

void testCapacityAndBounds()
{
    qint64 now = 0;
    NotificationRuntime runtime([&now] { return now; }, false);
    startGeneration(runtime);
    std::vector<std::unique_ptr<FakeNotification>> notifications;

    for (uint id = 1; id <= 50; ++id) {
        auto notification = std::make_unique<FakeNotification>(id);
        notification->urgency = 0;
        bind(runtime, *notification);
        runtime.attachNotification(notification.get(), 1);
        notifications.push_back(std::move(notification));
        ++now;
    }
    require(runtime.liveCount() == 50 && runtime.historyCount() == 50,
            "independent live and history caps were not reached exactly");
    require(runtime.dashboardModel()->rowCount() == 4,
            "dashboard projection exceeded or missed its four-record bound");

    auto newest = std::make_unique<FakeNotification>(51);
    newest->urgency = 0;
    bind(runtime, *newest);
    runtime.attachNotification(newest.get(), 1);
    require(notifications.front()->expireCalls == 1 && runtime.liveCount() == 50
                && runtime.historyCount() == 50,
            "count eviction did not make the oldest live identity the capacity victim");
    notifications.push_back(std::move(newest));

    auto provisionalCritical = std::make_unique<FakeNotification>(52);
    provisionalCritical->urgency = 2;
    provisionalCritical->transient = true;
    provisionalCritical->expireTimeout = 0;
    bind(runtime, *provisionalCritical);
    runtime.attachNotification(provisionalCritical.get(), 1);
    require(provisionalCritical->expireCalls == 1 && runtime.liveCount() == 50,
            "capacity did not override critical never-expire transient state");

    require(runtime.historyModel()->rowCount() <= 50 && runtime.dashboardModel()->rowCount() <= 4,
            "model projections exceeded their bounds");
}

void testReloadRestartAndOwnershipFailure()
{
    qint64 now = 0;
    NotificationRuntime runtime([&now] { return now; }, false);
    nagi::notifications::NotificationRuntimeTest::setServerOwned(runtime, true);
    startGeneration(runtime);

    FakeNotification carried(10);
    carried.expireTimeout = 100;
    attach(runtime, carried);
    const QString oldKey = runtime.historySnapshot(0).value("firstAdmissionSequence").toString();

    now = 50;
    carried.lastGeneration = true;
    const quint64 generation = runtime.beginGeneration();
    runtime.attachNotification(&carried, generation);
    runtime.finishGeneration(generation);
    const QVariantMap reloaded = runtime.historySnapshot(0);
    require(runtime.liveCount() == 1 && runtime.historyCount() == 1
                && reloaded.value("firstAdmissionSequence").toString() != oldKey
                && reloaded.value("firstAdmittedMonotonicMs").toLongLong() == 50,
            "reload did not reconcile carried live state as a fresh history generation");

    now = 100;
    nagi::notifications::NotificationRuntimeTest::processDue(runtime);
    require(carried.expireCalls == 1,
            "reload restarted or lost the process-scoped live expiry deadline");

    FakeNotification expired(11);
    expired.expireTimeout = 1;
    bind(runtime, expired);
    runtime.attachNotification(&expired, generation);
    now = 101;
    nagi::notifications::NotificationRuntimeTest::processDue(runtime);
    require(runtime.historySnapshot(0).value("state").toString() == QStringLiteral("expired"),
            "ownership fixture did not create an expired snapshot");

    FakeNotification live(12);
    live.expireTimeout = 0;
    bind(runtime, live);
    runtime.attachNotification(&live, generation);
    require(runtime.liveCount() == 1 && runtime.historyCount() == 3,
            "ownership fixture did not create mixed history state");
    nagi::notifications::NotificationRuntimeTest::setServerOwned(runtime, false);
    require(runtime.liveCount() == 0 && runtime.historyCount() == 2
                && runtime.historySnapshot(0).value("state").toString() == QStringLiteral("expired")
                && runtime.failureCategory() == QStringLiteral("ownership"),
            "ownership failure did not clear affected live state while preserving expired history");

    NotificationRuntime restarted([&now] { return now; }, false);
    require(restarted.liveCount() == 0 && restarted.historyCount() == 0,
            "new process runtime reconstructed memory-only state");
}

void testSequenceExhaustion()
{
    qint64 now = 0;
    NotificationRuntime runtime([&now] { return now; }, false);
    startGeneration(runtime);
    nagi::notifications::NotificationRuntimeTest::exhaustHistoryAfterNext(runtime);

    FakeNotification last(1);
    FakeNotification excluded(2);
    attach(runtime, last);
    attach(runtime, excluded);
    require(runtime.historyCount() == 1 && runtime.liveCount() == 2
                && runtime.historySnapshot(0).value("firstAdmissionSequence").toString()
                    == QString::number(std::numeric_limits<quint64>::max()),
            "history sequence exhaustion wrapped, reused, or broke live handling");

    NotificationRuntime liveRuntime([&now] { return now; }, false);
    startGeneration(liveRuntime);
    nagi::notifications::NotificationRuntimeTest::exhaustLiveAfterNext(liveRuntime);
    FakeNotification finalLive(3);
    FakeNotification rejectedLive(4);
    attach(liveRuntime, finalLive);
    attach(liveRuntime, rejectedLive);
    require(liveRuntime.liveCount() == 1 && liveRuntime.historyCount() == 1
                && rejectedLive.expireCalls == 1,
            "live sequence exhaustion wrapped, reused, or admitted stale history");
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    testNormalization();
    testLifecycleAndExpiry();
    testReplacementAndCloseReasons();
    testTransientPresentationContract();
    testUrgencyAndAgePrecedence();
    testCapacityAndBounds();
    testReloadRestartAndOwnershipFailure();
    testSequenceExhaustion();
    qInfo("notification runtime tests passed");
    return 0;
}

#include "notification_runtime_test.moc"

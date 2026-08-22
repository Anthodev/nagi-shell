#include "runtime.h"

#include "notification_text.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusReply>
#include <QMetaObject>
#include <QSet>

#include <algorithm>

namespace nagi::notifications {
namespace {

constexpr auto NotificationServiceName = "org.freedesktop.Notifications";

QVariant snapshotValue(const NotificationSnapshot &snapshot, int role)
{
    switch (role) {
    case NotificationHistoryModel::FirstAdmissionSequenceRole:
        return QString::number(snapshot.firstAdmissionSequence);
    case NotificationHistoryModel::FirstAdmittedMonotonicMsRole:
        return snapshot.firstAdmittedMonotonicMs;
    case NotificationHistoryModel::HistoryCutoffMonotonicMsRole:
        return snapshot.historyCutoffMonotonicMs;
    case NotificationHistoryModel::StateRole:
        return snapshot.live ? QStringLiteral("live") : QStringLiteral("expired");
    case NotificationHistoryModel::AppNameRole:
        return snapshot.appName;
    case NotificationHistoryModel::SummaryRole:
        return snapshot.summary;
    case NotificationHistoryModel::BodyRole:
        return snapshot.body;
    case NotificationHistoryModel::UrgencyRole:
        return snapshot.urgency;
    case NotificationHistoryModel::DesktopEntryRole:
        return snapshot.desktopEntry;
    case NotificationHistoryModel::AppIconNameRole:
        return snapshot.appIconName;
    case NotificationHistoryModel::ResidentRole:
        return snapshot.resident;
    default:
        return {};
    }
}

} // namespace

NotificationHistoryModel::NotificationHistoryModel(NotificationRuntime *runtime, int limit,
                                                   QObject *parent)
    : QAbstractListModel(parent)
    , runtime(runtime)
    , limit(limit)
{
}

int NotificationHistoryModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    return qMin(limit, runtime->history().size());
}

QVariant NotificationHistoryModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= rowCount()) {
        return {};
    }
    return snapshotValue(runtime->history().at(index.row()), role);
}

QHash<int, QByteArray> NotificationHistoryModel::roleNames() const
{
    return {
        {FirstAdmissionSequenceRole, "firstAdmissionSequence"},
        {FirstAdmittedMonotonicMsRole, "firstAdmittedMonotonicMs"},
        {HistoryCutoffMonotonicMsRole, "historyCutoffMonotonicMs"},
        {StateRole, "state"},
        {AppNameRole, "appName"},
        {SummaryRole, "summary"},
        {BodyRole, "body"},
        {UrgencyRole, "urgency"},
        {DesktopEntryRole, "desktopEntry"},
        {AppIconNameRole, "appIconName"},
        {ResidentRole, "resident"},
    };
}

void NotificationHistoryModel::reset()
{
    beginResetModel();
    endResetModel();
}

NotificationRuntime::NotificationRuntime(QObject *parent)
    : NotificationRuntime({}, true, parent)
{
}

NotificationRuntime::NotificationRuntime(std::function<qint64()> monotonicNow,
                                         bool watchServerOwnership, QObject *parent)
    : QObject(parent)
    , monotonicNow(std::move(monotonicNow))
    , fullHistoryModel(this, MaxHistory, this)
    , recentHistoryModel(this, 4, this)
    , ownershipMonitoringEnabled(watchServerOwnership)
    , serviceWatcher(this)
{
    deadlineTimer.setParent(this);
    elapsedTimer.start();
    deadlineTimer.setSingleShot(true);
    deadlineTimer.setTimerType(Qt::PreciseTimer);
    connect(&deadlineTimer, &QTimer::timeout, this, &NotificationRuntime::processDueDeadlines);

    if (ownershipMonitoringEnabled) {
        serviceWatcher.setConnection(QDBusConnection::sessionBus());
        serviceWatcher.setWatchMode(QDBusServiceWatcher::WatchForOwnerChange);
        serviceWatcher.addWatchedService(QString::fromLatin1(NotificationServiceName));
        connect(&serviceWatcher, &QDBusServiceWatcher::serviceOwnerChanged, this,
                &NotificationRuntime::refreshServerOwnership);
        QTimer::singleShot(0, this, &NotificationRuntime::refreshServerOwnership);
    }
}


QAbstractItemModel *NotificationRuntime::historyModel()
{
    return &fullHistoryModel;
}

QAbstractItemModel *NotificationRuntime::dashboardModel()
{
    return &recentHistoryModel;
}

int NotificationRuntime::liveCount() const
{
    return liveAssociations.size();
}

int NotificationRuntime::historyCount() const
{
    return historySnapshots.size();
}

bool NotificationRuntime::serverOwned() const
{
    return ownsNotificationServer;
}

QString NotificationRuntime::failureCategory() const
{
    return ownsNotificationServer ? QStringLiteral("none") : QStringLiteral("ownership");
}

bool NotificationRuntime::actionsSupported() const
{
    // Quickshell 0.3.0, 0.3.1, and the inspected master all retain stale labels on
    // same-identifier replacement. This gate deliberately has no runtime override.
    return false;
}

int NotificationRuntime::activeTimerCount() const
{
    return deadlineTimer.isActive() ? 1 : 0;
}

quint64 NotificationRuntime::beginGeneration()
{
    if (currentGeneration != std::numeric_limits<quint64>::max()) {
        ++currentGeneration;
    }
    reconcilingGeneration = true;
    bufferedNotifications.clear();

    for (auto association = liveAssociations.begin(); association != liveAssociations.end();
         ++association) {
        association->recordKey.reset();
        association->seenInGeneration = false;
        association->updateQueued = false;
    }
    if (!historySnapshots.isEmpty()) {
        historySnapshots.clear();
        notifyHistoryReset();
    }
    armScheduler();
    return currentGeneration;
}

void NotificationRuntime::attachNotification(QObject *notification, quint64 generation)
{
    if (notification == nullptr || generation != currentGeneration) {
        return;
    }

    if (reconcilingGeneration) {
        bufferedNotifications.append(
            {notification, notification->property("lastGeneration").toBool()});
        return;
    }
    admitFresh(notification);
}

void NotificationRuntime::updateNotification(QObject *notification)
{
    if (notification == nullptr) {
        return;
    }
    const quint32 protocolId = notification->property("id").toUInt();
    const auto association = liveAssociations.constFind(protocolId);
    if (association == liveAssociations.cend() || association->notification != notification
        || reconcilingGeneration) {
        return;
    }
    queueReplacement(protocolId, notification);
}

void NotificationRuntime::closeNotification(QObject *notification, int reason)
{
    if (notification == nullptr) {
        return;
    }
    const quint32 protocolId = notification->property("id").toUInt();
    const auto association = liveAssociations.find(protocolId);
    if (association == liveAssociations.end() || association->notification != notification) {
        return;
    }

    const int previousLiveCount = liveAssociations.size();
    const std::optional<quint64> recordKey = association->recordKey;
    if (recordKey.has_value()) {
        if (reason == 1) {
            markSnapshotExpired(*recordKey);
        } else {
            removeSnapshot(*recordKey);
        }
        notifyHistoryReset();
    }

    eraseAssociation(protocolId);
    notifyLiveCountIfChanged(previousLiveCount);
    armScheduler();
}

void NotificationRuntime::finishGeneration(quint64 generation)
{
    if (!reconcilingGeneration || generation != currentGeneration) {
        return;
    }

    QVector<QPointer<QObject>> carried;
    QVector<QPointer<QObject>> fresh;
    QSet<quint32> carriedIds;
    QSet<quint32> freshIds;
    for (const BufferedNotification &buffered : std::as_const(bufferedNotifications)) {
        QObject *notification = buffered.notification.data();
        if (notification == nullptr) {
            continue;
        }
        const quint32 protocolId = notification->property("id").toUInt();
        if (protocolId == 0) {
            continue;
        }
        if (buffered.carried) {
            if (!carriedIds.contains(protocolId)) {
                carriedIds.insert(protocolId);
                carried.append(notification);
            }
        } else if (!freshIds.contains(protocolId)) {
            freshIds.insert(protocolId);
            fresh.append(notification);
        }
    }
    bufferedNotifications.clear();

    std::sort(carried.begin(), carried.end(), [](const auto &left, const auto &right) {
        return left->property("id").toUInt() > right->property("id").toUInt();
    });
    admitCarried(carried);

    QVector<quint32> staleIds;
    staleIds.reserve(liveAssociations.size());
    for (auto association = liveAssociations.cbegin(); association != liveAssociations.cend();
         ++association) {
        if (!association->seenInGeneration) {
            staleIds.append(association.key());
        }
    }
    const int previousLiveCount = liveAssociations.size();
    for (quint32 protocolId : std::as_const(staleIds)) {
        eraseAssociation(protocolId);
    }
    notifyLiveCountIfChanged(previousLiveCount);

    reconcilingGeneration = false;
    for (const QPointer<QObject> &notification : std::as_const(fresh)) {
        if (notification != nullptr) {
            admitFresh(notification);
        }
    }
    armScheduler();
}

bool NotificationRuntime::dismiss(const QVariant &recordKeyValue)
{
    const auto recordKey = parseRecordKey(recordKeyValue);
    if (!recordKey.has_value()) {
        return false;
    }

    for (auto association = liveAssociations.begin(); association != liveAssociations.end();
         ++association) {
        if (association->recordKey != recordKey || association->notification == nullptr) {
            continue;
        }
        QObject *notification = association->notification.data();
        if (!QMetaObject::invokeMethod(notification, "dismiss", Qt::DirectConnection)) {
            const quint32 protocolId = association.key();
            const int previousLiveCount = liveAssociations.size();
            removeSnapshot(*recordKey);
            eraseAssociation(protocolId);
            notifyHistoryReset();
            notifyLiveCountIfChanged(previousLiveCount);
            armScheduler();
        }
        return true;
    }

    if (snapshotIndex(*recordKey) < 0) {
        return false;
    }
    removeSnapshot(*recordKey);
    notifyHistoryReset();
    armScheduler();
    return true;
}

int NotificationRuntime::historyIndex(const QVariant &recordKeyValue) const
{
    const auto recordKey = parseRecordKey(recordKeyValue);
    return recordKey.has_value() ? snapshotIndex(*recordKey) : -1;
}

bool NotificationRuntime::canAct(const QVariant &recordKey) const
{
    Q_UNUSED(recordKey)
    return false;
}

QVariantList NotificationRuntime::actionsFor(const QVariant &recordKey) const
{
    Q_UNUSED(recordKey)
    return {};
}

QVariantMap NotificationRuntime::historySnapshot(int index) const
{
    if (index < 0 || index >= historySnapshots.size()) {
        return {};
    }
    const NotificationSnapshot &snapshot = historySnapshots.at(index);
    QVariantMap value {
        {QStringLiteral("firstAdmissionSequence"),
         QString::number(snapshot.firstAdmissionSequence)},
        {QStringLiteral("firstAdmittedMonotonicMs"), snapshot.firstAdmittedMonotonicMs},
        {QStringLiteral("historyCutoffMonotonicMs"), snapshot.historyCutoffMonotonicMs},
        {QStringLiteral("state"),
         snapshot.live ? QStringLiteral("live") : QStringLiteral("expired")},
        {QStringLiteral("appName"), snapshot.appName},
        {QStringLiteral("summary"), snapshot.summary},
        {QStringLiteral("body"), snapshot.body},
        {QStringLiteral("urgency"), snapshot.urgency},
        {QStringLiteral("resident"), snapshot.resident},
    };
    if (!snapshot.desktopEntry.isEmpty()) {
        value.insert(QStringLiteral("desktopEntry"), snapshot.desktopEntry);
    }
    if (!snapshot.appIconName.isEmpty()) {
        value.insert(QStringLiteral("appIconName"), snapshot.appIconName);
    }
    return value;
}

QVariantMap NotificationRuntime::resolveTransient(const QString &sourceToken, int sourceGeneration,
                                                  int revision) const
{
    if (sourceToken.isEmpty() || sourceGeneration <= 0 || revision <= 0) {
        return {};
    }
    for (auto association = liveAssociations.cbegin(); association != liveAssociations.cend();
         ++association) {
        if (!association->transientPresentationValid
            || association->transientSourceToken != sourceToken
            || association->transientSourceGeneration != sourceGeneration
            || association->transientRevision != revision) {
            continue;
        }
        return {
            {QStringLiteral("appName"), association->transientAppName},
            {QStringLiteral("summary"), association->transientSummary},
        };
    }
    return {};
}

const QVector<NotificationSnapshot> &NotificationRuntime::history() const
{
    return historySnapshots;
}

NotificationRuntime::NormalizedNotification NotificationRuntime::normalize(QObject *notification) const
{
    NormalizedNotification normalized;
    normalized.protocolId = notification->property("id").toUInt();
    normalized.appName = normalizePlainText(notification->property("appName").toString(), 256, false);
    normalized.summary = normalizePlainText(notification->property("summary").toString(), 1024, false);
    normalized.body = normalizeBody(notification->property("body").toString());
    normalized.urgency = normalizeUrgency(notification->property("urgency"));
    normalized.desktopEntry = normalizeDesktopEntry(notification->property("desktopEntry").toString());
    normalized.appIconName = normalizeIconName(notification->property("appIcon").toString());
    normalized.resident = notification->property("resident").toBool();
    normalized.transient = notification->property("transient").toBool();
    normalized.expireTimeoutMs = notification->property("expireTimeout").toLongLong();
    return normalized;
}

QString NotificationRuntime::normalizeUrgency(const QVariant &value) const
{
    bool valid = false;
    const int urgency = value.toInt(&valid);
    if (!valid) {
        return QStringLiteral("normal");
    }
    if (urgency == 0) {
        return QStringLiteral("low");
    }
    if (urgency == 2) {
        return QStringLiteral("critical");
    }
    return QStringLiteral("normal");
}

qint64 NotificationRuntime::currentMonotonicMs() const
{
    return monotonicNow ? monotonicNow() : elapsedTimer.elapsed();
}

qint64 NotificationRuntime::expiryDelay(const NormalizedNotification &notification)
{
    if (notification.urgency == QLatin1String("critical") || notification.expireTimeoutMs == 0) {
        return -1;
    }
    if (notification.expireTimeoutMs > 0) {
        return notification.expireTimeoutMs;
    }
    if (notification.expireTimeoutMs < -1 && !invalidTimeoutReported) {
        invalidTimeoutReported = true;
        qWarning("notification-invalid-timeout");
    }
    return notification.urgency == QLatin1String("low") ? 5000 : 10000;
}

std::optional<quint64> NotificationRuntime::allocateHistorySequence()
{
    if (historySequenceExhausted) {
        if (!historyExhaustionReported) {
            historyExhaustionReported = true;
            qWarning("notification-history-sequence-exhausted");
        }
        return std::nullopt;
    }
    const quint64 allocated = nextHistorySequence;
    if (nextHistorySequence == std::numeric_limits<quint64>::max()) {
        historySequenceExhausted = true;
    } else {
        ++nextHistorySequence;
    }
    return allocated;
}

std::optional<quint64> NotificationRuntime::allocateLiveSequence()
{
    if (liveSequenceExhausted) {
        if (!liveExhaustionReported) {
            liveExhaustionReported = true;
            qWarning("notification-live-sequence-exhausted");
        }
        return std::nullopt;
    }
    const quint64 allocated = nextLiveSequence;
    if (nextLiveSequence == std::numeric_limits<quint64>::max()) {
        liveSequenceExhausted = true;
    } else {
        ++nextLiveSequence;
    }
    return allocated;
}

std::optional<quint64> NotificationRuntime::parseRecordKey(const QVariant &recordKey) const
{
    bool valid = false;
    const quint64 parsed = recordKey.toString().toULongLong(&valid);
    if (!valid || parsed == 0) {
        return std::nullopt;
    }
    return parsed;
}

int NotificationRuntime::snapshotIndex(quint64 recordKey) const
{
    for (int index = 0; index < historySnapshots.size(); ++index) {
        if (historySnapshots.at(index).firstAdmissionSequence == recordKey) {
            return index;
        }
    }
    return -1;
}

NotificationSnapshot NotificationRuntime::makeSnapshot(
    const NormalizedNotification &notification, quint64 recordKey, qint64 admittedAt) const
{
    return {
        recordKey,
        admittedAt,
        admittedAt + HistoryLifetimeMs,
        true,
        notification.appName,
        notification.summary,
        notification.body,
        notification.urgency,
        notification.desktopEntry,
        notification.appIconName,
        notification.resident,
    };
}

std::optional<quint64> NotificationRuntime::admitHistory(
    const NormalizedNotification &notification, qint64 admittedAt)
{
    if (notification.transient) {
        return std::nullopt;
    }
    const auto recordKey = allocateHistorySequence();
    if (!recordKey.has_value()) {
        return std::nullopt;
    }
    historySnapshots.prepend(makeSnapshot(notification, *recordKey, admittedAt));
    pruneHistory(admittedAt);
    return snapshotIndex(*recordKey) >= 0 ? recordKey : std::nullopt;
}

void NotificationRuntime::admitCarried(const QVector<QPointer<QObject>> &notifications)
{
    const qint64 admittedAt = currentMonotonicMs();
    bool historyChanged = false;

    for (auto iterator = notifications.crbegin(); iterator != notifications.crend(); ++iterator) {
        QObject *notification = iterator->data();
        if (notification == nullptr) {
            continue;
        }
        const quint32 protocolId = notification->property("id").toUInt();
        auto association = liveAssociations.find(protocolId);
        if (association == liveAssociations.end() || association->notification != notification) {
            expireNotification(notification);
            continue;
        }

        association->seenInGeneration = true;
        const NormalizedNotification normalized = normalize(notification);
        association->transient = normalized.transient;
        association->urgency = normalized.urgency;
        if (!normalized.transient) {
            association->recordKey = admitHistory(normalized, admittedAt);
            historyChanged = historyChanged || association->recordKey.has_value();
        }
    }
    if (historyChanged) {
        notifyHistoryReset();
    }
}

void NotificationRuntime::admitFresh(QObject *notification)
{
    const NormalizedNotification normalized = normalize(notification);
    if (normalized.protocolId == 0) {
        expireNotification(notification);
        return;
    }

    auto existing = liveAssociations.find(normalized.protocolId);
    if (existing != liveAssociations.end()) {
        if (existing->notification == notification) {
            queueReplacement(normalized.protocolId, notification);
        }
        return;
    }

    const auto liveSequence = allocateLiveSequence();
    if (!liveSequence.has_value()) {
        expireNotification(notification);
        return;
    }

    const qint64 acceptedAt = currentMonotonicMs();
    const std::optional<quint64> recordKey = admitHistory(normalized, acceptedAt);
    if (recordKey.has_value()) {
        notifyHistoryReset();
    }

    LiveAssociation provisional;
    provisional.liveAdmissionSequence = *liveSequence;
    provisional.notification = notification;
    provisional.recordKey = recordKey;
    provisional.transientSourceToken = transientSourceToken(*liveSequence);
    provisional.urgency = normalized.urgency;
    provisional.transient = normalized.transient;
    provisional.seenInGeneration = true;

    if (liveAssociations.size() >= MaxLive) {
        bool provisionalVictim = true;
        quint32 victimId = 0;
        int victimClass = provisionalCapacityClass(normalized, recordKey);
        quint64 victimSequence = provisional.liveAdmissionSequence;

        for (auto association = liveAssociations.cbegin(); association != liveAssociations.cend();
             ++association) {
            const int candidateClass = capacityClass(*association);
            if (candidateClass < victimClass
                || (candidateClass == victimClass
                    && association->liveAdmissionSequence < victimSequence)) {
                provisionalVictim = false;
                victimId = association.key();
                victimClass = candidateClass;
                victimSequence = association->liveAdmissionSequence;
            }
        }

        if (provisionalVictim) {
            if (recordKey.has_value()) {
                markSnapshotExpired(*recordKey);
                notifyHistoryReset();
            }
            expireNotification(notification);
            armScheduler();
            return;
        }

        QObject *victim = liveAssociations.value(victimId).notification.data();
        if (victim == nullptr || !expireNotification(victim)
            || liveAssociations.size() >= MaxLive) {
            if (recordKey.has_value()) {
                markSnapshotExpired(*recordKey);
                notifyHistoryReset();
            }
            expireNotification(notification);
            armScheduler();
            return;
        }
    }

    const int previousLiveCount = liveAssociations.size();
    scheduleExpiry(provisional, normalized, acceptedAt);
    liveAssociations.insert(normalized.protocolId, provisional);
    notifyLiveCountIfChanged(previousLiveCount);
    dispatchPresentation(liveAssociations[normalized.protocolId], normalized);
    armScheduler();
}

void NotificationRuntime::processReplacement(quint32 protocolId, QObject *notification)
{
    auto association = liveAssociations.find(protocolId);
    if (association == liveAssociations.end() || association->notification != notification) {
        return;
    }

    const bool wasTransient = association->transient;
    const std::optional<quint64> oldRecordKey = association->recordKey;
    const NormalizedNotification normalized = normalize(notification);
    const qint64 acceptedAt = currentMonotonicMs();
    const int historyBefore = historySnapshots.size();
    pruneHistory(acceptedAt);
    bool historyChanged = historyBefore != historySnapshots.size();

    if (wasTransient && !normalized.transient) {
        association->recordKey = admitHistory(normalized, acceptedAt);
        historyChanged = historyChanged || association->recordKey.has_value();
    } else if (!wasTransient && normalized.transient) {
        if (oldRecordKey.has_value() && snapshotIndex(*oldRecordKey) >= 0) {
            removeSnapshot(*oldRecordKey);
            historyChanged = true;
        }
        association->recordKey.reset();
    } else if (!normalized.transient && association->recordKey.has_value()) {
        const int index = snapshotIndex(*association->recordKey);
        if (index >= 0) {
            const NotificationSnapshot previous = historySnapshots.at(index);
            NotificationSnapshot replacement = makeSnapshot(
                normalized, previous.firstAdmissionSequence, previous.firstAdmittedMonotonicMs);
            replacement.historyCutoffMonotonicMs = previous.historyCutoffMonotonicMs;
            historySnapshots[index] = std::move(replacement);
            historyChanged = true;
        } else {
            association->recordKey.reset();
        }
    }

    association->transient = normalized.transient;
    association->urgency = normalized.urgency;
    scheduleExpiry(*association, normalized, acceptedAt);
    if (historyChanged) {
        notifyHistoryReset();
    }
    dispatchPresentation(*association, normalized);
    armScheduler();
}

QString NotificationRuntime::transientSourceToken(quint64 liveAdmissionSequence)
{
    return QStringLiteral("notification-") + QString::number(liveAdmissionSequence);
}

void NotificationRuntime::dispatchPresentation(
    LiveAssociation &association, const NormalizedNotification &notification)
{
    if (association.transientRevision == std::numeric_limits<int>::max()) {
        invalidatePresentation(association);
        return;
    }
    association.transientAppName = notification.appName;
    association.transientSummary = notification.summary;
    ++association.transientRevision;
    association.transientPresentationValid = true;
    emit transientRequested(association.transientSourceToken,
                            association.transientSourceGeneration,
                            association.transientRevision);
}

void NotificationRuntime::invalidatePresentation(LiveAssociation &association)
{
    if (!association.transientPresentationValid) {
        return;
    }
    association.transientPresentationValid = false;
    association.transientAppName.clear();
    association.transientSummary.clear();
    emit transientInvalidated(association.transientSourceToken,
                              association.transientSourceGeneration);
}

void NotificationRuntime::scheduleExpiry(LiveAssociation &association,
                                         const NormalizedNotification &notification,
                                         qint64 acceptedAt)
{
    const qint64 delay = expiryDelay(notification);
    association.expiryDeadlineMonotonicMs = delay < 0 ? -1 : acceptedAt + delay;
}

void NotificationRuntime::pruneHistory(qint64 now)
{
    for (int index = historySnapshots.size() - 1; index >= 0; --index) {
        if (historySnapshots.at(index).historyCutoffMonotonicMs <= now) {
            const quint64 recordKey = historySnapshots.at(index).firstAdmissionSequence;
            historySnapshots.removeAt(index);
            clearRecordLink(recordKey);
        }
    }
    while (historySnapshots.size() > MaxHistory) {
        const quint64 recordKey = historySnapshots.constLast().firstAdmissionSequence;
        historySnapshots.removeLast();
        clearRecordLink(recordKey);
    }
}

void NotificationRuntime::removeSnapshot(quint64 recordKey)
{
    const int index = snapshotIndex(recordKey);
    if (index < 0) {
        return;
    }
    historySnapshots.removeAt(index);
    clearRecordLink(recordKey);
}

void NotificationRuntime::markSnapshotExpired(quint64 recordKey)
{
    const int index = snapshotIndex(recordKey);
    if (index >= 0) {
        historySnapshots[index].live = false;
    }
}

void NotificationRuntime::clearRecordLink(quint64 recordKey)
{
    for (auto association = liveAssociations.begin(); association != liveAssociations.end();
         ++association) {
        if (association->recordKey == recordKey) {
            association->recordKey.reset();
        }
    }
}

void NotificationRuntime::clearLiveStateForOwnershipFailure()
{
    if (liveAssociations.isEmpty()) {
        return;
    }
    const int previousLiveCount = liveAssociations.size();
    QVector<quint64> liveRecordKeys;
    for (auto association = liveAssociations.begin(); association != liveAssociations.end();
         ++association) {
        invalidatePresentation(*association);
        if (association->recordKey.has_value()) {
            liveRecordKeys.append(*association->recordKey);
        }
    }
    for (quint64 recordKey : std::as_const(liveRecordKeys)) {
        removeSnapshot(recordKey);
    }
    liveAssociations.clear();
    notifyHistoryReset();
    notifyLiveCountIfChanged(previousLiveCount);
    armScheduler();
}

void NotificationRuntime::setServerOwned(bool owned)
{
    if (ownsNotificationServer == owned) {
        return;
    }
    ownsNotificationServer = owned;
    if (!owned) {
        clearLiveStateForOwnershipFailure();
        qWarning("notification-server-ownership-failure");
    }
    emit serverOwnershipChanged();
}

void NotificationRuntime::notifyHistoryReset()
{
    fullHistoryModel.reset();
    recentHistoryModel.reset();
    emit historyCountChanged();
}

void NotificationRuntime::notifyLiveCountIfChanged(int previousCount)
{
    if (previousCount != liveAssociations.size()) {
        emit liveCountChanged();
    }
}

void NotificationRuntime::armScheduler()
{
    const bool wasActive = deadlineTimer.isActive();
    qint64 earliest = -1;
    for (auto association = liveAssociations.cbegin(); association != liveAssociations.cend();
         ++association) {
        const qint64 deadline = association->expiryDeadlineMonotonicMs;
        if (deadline >= 0 && (earliest < 0 || deadline < earliest)) {
            earliest = deadline;
        }
    }
    for (const NotificationSnapshot &snapshot : std::as_const(historySnapshots)) {
        if (earliest < 0 || snapshot.historyCutoffMonotonicMs < earliest) {
            earliest = snapshot.historyCutoffMonotonicMs;
        }
    }

    if (earliest < 0) {
        deadlineTimer.stop();
    } else {
        const qint64 remaining = qMax<qint64>(0, earliest - currentMonotonicMs());
        deadlineTimer.start(static_cast<int>(qMin<qint64>(remaining,
                                                          std::numeric_limits<int>::max())));
    }
    if (wasActive != deadlineTimer.isActive()) {
        emit activeTimerCountChanged();
    }
}

int NotificationRuntime::capacityClass(const LiveAssociation &association) const
{
    if (association.transient || !association.recordKey.has_value()
        || snapshotIndex(*association.recordKey) < 0) {
        return 0;
    }
    if (association.urgency == QLatin1String("low")) {
        return 1;
    }
    if (association.urgency == QLatin1String("critical")) {
        return 3;
    }
    return 2;
}

int NotificationRuntime::provisionalCapacityClass(
    const NormalizedNotification &notification, const std::optional<quint64> &recordKey) const
{
    if (notification.transient || !recordKey.has_value() || snapshotIndex(*recordKey) < 0) {
        return 0;
    }
    if (notification.urgency == QLatin1String("low")) {
        return 1;
    }
    if (notification.urgency == QLatin1String("critical")) {
        return 3;
    }
    return 2;
}

bool NotificationRuntime::expireNotification(QObject *notification)
{
    return notification != nullptr
        && QMetaObject::invokeMethod(notification, "expire", Qt::DirectConnection);
}

void NotificationRuntime::eraseAssociation(quint32 protocolId)
{
    auto association = liveAssociations.find(protocolId);
    if (association == liveAssociations.end()) {
        return;
    }
    invalidatePresentation(*association);
    liveAssociations.erase(association);
}

void NotificationRuntime::queueReplacement(quint32 protocolId, QObject *notification)
{
    auto association = liveAssociations.find(protocolId);
    if (association == liveAssociations.end() || association->updateQueued) {
        return;
    }
    association->updateQueued = true;
    const QPointer<QObject> guardedNotification(notification);
    QMetaObject::invokeMethod(
        this,
        [this, protocolId, guardedNotification] {
            auto current = liveAssociations.find(protocolId);
            if (current == liveAssociations.end()) {
                return;
            }
            current->updateQueued = false;
            if (guardedNotification != nullptr && current->notification == guardedNotification) {
                processReplacement(protocolId, guardedNotification.data());
            }
        },
        Qt::QueuedConnection);
}

void NotificationRuntime::processDueDeadlines()
{
    const qint64 now = currentMonotonicMs();
    QVector<quint32> dueIds;
    for (auto association = liveAssociations.cbegin(); association != liveAssociations.cend();
         ++association) {
        if (association->expiryDeadlineMonotonicMs >= 0
            && association->expiryDeadlineMonotonicMs <= now) {
            dueIds.append(association.key());
        }
    }

    for (quint32 protocolId : std::as_const(dueIds)) {
        auto association = liveAssociations.find(protocolId);
        if (association == liveAssociations.end()
            || association->expiryDeadlineMonotonicMs < 0
            || association->expiryDeadlineMonotonicMs > now) {
            continue;
        }
        QObject *notification = association->notification.data();
        if (notification == nullptr || !expireNotification(notification)) {
            const int previousLiveCount = liveAssociations.size();
            if (association->recordKey.has_value()) {
                removeSnapshot(*association->recordKey);
                notifyHistoryReset();
            }
            eraseAssociation(protocolId);
            notifyLiveCountIfChanged(previousLiveCount);
        }
    }

    const int previousHistoryCount = historySnapshots.size();
    pruneHistory(now);
    if (previousHistoryCount != historySnapshots.size()) {
        notifyHistoryReset();
    }
    armScheduler();
}

void NotificationRuntime::refreshServerOwnership()
{
    if (!ownershipMonitoringEnabled) {
        return;
    }
    QDBusConnectionInterface *interface = QDBusConnection::sessionBus().interface();
    if (interface == nullptr) {
        setServerOwned(false);
        return;
    }
    const QDBusReply<QString> owner = interface->serviceOwner(
        QString::fromLatin1(NotificationServiceName));
    if (!owner.isValid() || owner.value().isEmpty()) {
        setServerOwned(false);
        return;
    }
    setServerOwned(owner.value() == QDBusConnection::sessionBus().baseService());
}

} // namespace nagi::notifications

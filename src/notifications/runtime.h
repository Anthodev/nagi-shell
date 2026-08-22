#pragma once

#include <QAbstractListModel>
#include <QDBusServiceWatcher>
#include <QElapsedTimer>
#include <QHash>
#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QVariantList>

#include <functional>
#include <limits>
#include <optional>

namespace nagi::notifications {

struct NotificationSnapshot {
    quint64 firstAdmissionSequence = 0;
    qint64 firstAdmittedMonotonicMs = 0;
    qint64 historyCutoffMonotonicMs = 0;
    bool live = true;
    QString appName;
    QString summary;
    QString body;
    QString urgency;
    QString desktopEntry;
    QString appIconName;
    bool resident = false;
};

class NotificationRuntime;

class NotificationHistoryModel final : public QAbstractListModel {
    Q_OBJECT

public:
    enum Role {
        FirstAdmissionSequenceRole = Qt::UserRole + 1,
        FirstAdmittedMonotonicMsRole,
        HistoryCutoffMonotonicMsRole,
        StateRole,
        AppNameRole,
        SummaryRole,
        BodyRole,
        UrgencyRole,
        DesktopEntryRole,
        AppIconNameRole,
        ResidentRole,
    };

    NotificationHistoryModel(NotificationRuntime *runtime, int limit, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    void reset();

private:
    NotificationRuntime *runtime;
    int limit;
};

class NotificationRuntime final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QAbstractItemModel *historyModel READ historyModel CONSTANT)
    Q_PROPERTY(QAbstractItemModel *dashboardModel READ dashboardModel CONSTANT)
    Q_PROPERTY(int liveCount READ liveCount NOTIFY liveCountChanged)
    Q_PROPERTY(int historyCount READ historyCount NOTIFY historyCountChanged)
    Q_PROPERTY(bool serverOwned READ serverOwned NOTIFY serverOwnershipChanged)
    Q_PROPERTY(QString failureCategory READ failureCategory NOTIFY serverOwnershipChanged)
    Q_PROPERTY(bool actionsSupported READ actionsSupported CONSTANT)
    Q_PROPERTY(int activeTimerCount READ activeTimerCount NOTIFY activeTimerCountChanged)

public:
    explicit NotificationRuntime(QObject *parent = nullptr);
    NotificationRuntime(std::function<qint64()> monotonicNow, bool watchServerOwnership,
                        QObject *parent = nullptr);


    QAbstractItemModel *historyModel();
    QAbstractItemModel *dashboardModel();
    int liveCount() const;
    int historyCount() const;
    bool serverOwned() const;
    QString failureCategory() const;
    bool actionsSupported() const;
    int activeTimerCount() const;

    Q_INVOKABLE quint64 beginGeneration();
    Q_INVOKABLE void attachNotification(QObject *notification, quint64 generation);
    Q_INVOKABLE void updateNotification(QObject *notification);
    Q_INVOKABLE void closeNotification(QObject *notification, int reason);
    Q_INVOKABLE void finishGeneration(quint64 generation);
    Q_INVOKABLE bool dismiss(const QVariant &recordKey);
    Q_INVOKABLE bool canAct(const QVariant &recordKey) const;
    Q_INVOKABLE QVariantList actionsFor(const QVariant &recordKey) const;
    Q_INVOKABLE QVariantMap historySnapshot(int index) const;
    Q_INVOKABLE void refreshServerOwnership();

signals:
    void liveCountChanged();
    void historyCountChanged();
    void serverOwnershipChanged();
    void activeTimerCountChanged();
    void presentationRequested(const QVariantMap &snapshot);

private slots:
    void processDueDeadlines();

private:
    friend class NotificationHistoryModel;
    friend class NotificationRuntimeTest;

    struct NormalizedNotification {
        quint32 protocolId = 0;
        QString appName;
        QString summary;
        QString body;
        QString urgency;
        QString desktopEntry;
        QString appIconName;
        bool resident = false;
        bool transient = false;
        qint64 expireTimeoutMs = -1;
    };

    struct LiveAssociation {
        quint64 liveAdmissionSequence = 0;
        QPointer<QObject> notification;
        std::optional<quint64> recordKey;
        QString urgency;
        bool transient = false;
        qint64 expiryDeadlineMonotonicMs = -1;
        bool updateQueued = false;
        bool seenInGeneration = false;
    };

    struct BufferedNotification {
        QPointer<QObject> notification;
        bool carried = false;
    };

    static constexpr int MaxLive = 50;
    static constexpr int MaxHistory = 50;
    static constexpr qint64 HistoryLifetimeMs = 86'400'000;

    const QVector<NotificationSnapshot> &history() const;
    NormalizedNotification normalize(QObject *notification) const;
    QString normalizeUrgency(const QVariant &value) const;
    qint64 currentMonotonicMs() const;
    qint64 expiryDelay(const NormalizedNotification &notification);
    std::optional<quint64> allocateHistorySequence();
    std::optional<quint64> allocateLiveSequence();
    std::optional<quint64> parseRecordKey(const QVariant &recordKey) const;
    int snapshotIndex(quint64 recordKey) const;
    NotificationSnapshot makeSnapshot(const NormalizedNotification &notification, quint64 recordKey,
                                      qint64 admittedAt) const;
    std::optional<quint64> admitHistory(const NormalizedNotification &notification, qint64 admittedAt);
    void admitCarried(const QVector<QPointer<QObject>> &notifications);
    void admitFresh(QObject *notification);
    void processReplacement(quint32 protocolId, QObject *notification);
    void dispatchPresentation(const NormalizedNotification &notification,
                              const std::optional<quint64> &recordKey);
    void scheduleExpiry(LiveAssociation &association,
                        const NormalizedNotification &notification, qint64 acceptedAt);
    void pruneHistory(qint64 now);
    void removeSnapshot(quint64 recordKey);
    void markSnapshotExpired(quint64 recordKey);
    void clearRecordLink(quint64 recordKey);
    void clearLiveStateForOwnershipFailure();
    void setServerOwned(bool owned);
    void notifyHistoryReset();
    void notifyLiveCountIfChanged(int previousCount);
    void armScheduler();
    int capacityClass(const LiveAssociation &association) const;
    int provisionalCapacityClass(const NormalizedNotification &notification,
                                 const std::optional<quint64> &recordKey) const;
    bool expireNotification(QObject *notification);
    void eraseAssociation(quint32 protocolId);
    void queueReplacement(quint32 protocolId, QObject *notification);

    std::function<qint64()> monotonicNow;
    QElapsedTimer elapsedTimer;
    QTimer deadlineTimer;
    NotificationHistoryModel fullHistoryModel;
    NotificationHistoryModel recentHistoryModel;
    QHash<quint32, LiveAssociation> liveAssociations;
    QVector<NotificationSnapshot> historySnapshots;
    QVector<BufferedNotification> bufferedNotifications;
    quint64 nextHistorySequence = 1;
    quint64 nextLiveSequence = 1;
    quint64 currentGeneration = 0;
    bool historySequenceExhausted = false;
    bool liveSequenceExhausted = false;
    bool invalidTimeoutReported = false;
    bool historyExhaustionReported = false;
    bool liveExhaustionReported = false;
    bool reconcilingGeneration = false;
    bool ownsNotificationServer = false;
    bool ownershipMonitoringEnabled = false;
    QDBusServiceWatcher serviceWatcher;
};

} // namespace nagi::notifications

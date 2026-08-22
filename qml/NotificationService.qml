pragma ComponentBehavior: Bound

import Nagi.Notifications 1.0
import Quickshell
import Quickshell.Services.Notifications
import QtQuick

// Owns the protocol server. Raw notification objects remain private to this boundary;
// consumers receive only native-runtime models and normalized presentation events.
Scope {
    id: root

    readonly property var historyModel: NotificationRuntime.historyModel
    readonly property var dashboardModel: NotificationRuntime.dashboardModel
    readonly property int liveCount: NotificationRuntime.liveCount
    readonly property int historyCount: NotificationRuntime.historyCount
    readonly property bool serverOwned: NotificationRuntime.serverOwned
    readonly property string failureCategory: NotificationRuntime.failureCategory
    readonly property bool actionsSupported: false
    readonly property int activeTimerCount: NotificationRuntime.activeTimerCount

    property var generation: NotificationRuntime.beginGeneration()
    property var watchers: ({})

    signal transientRequested(string sourceToken, int sourceGeneration, int revision)
    signal transientInvalidated(string sourceToken, int sourceGeneration)

    function dismiss(recordKey) {
        return NotificationRuntime.dismiss(recordKey);
    }

    function historyIndex(recordKey) {
        return NotificationRuntime.historyIndex(recordKey);
    }

    function canAct(recordKey) {
        return false;
    }

    function actionsFor(recordKey) {
        return [];
    }

    function resolveTransient(sourceToken, sourceGeneration, revision) {
        const normalized = NotificationRuntime.resolveTransient(sourceToken, sourceGeneration,
                                                                revision);
        if (normalized === null || typeof normalized !== "object" || Array.isArray(normalized)
                || typeof normalized.appName !== "string" || typeof normalized.summary
                !== "string") {
            return null;
        }
        return {
            "detail": normalized.summary,
            "iconName": "preferences-desktop-notification-symbolic",
            "primary": normalized.appName !== "" ? normalized.appName : "Notification",
            "value": ""
        };
    }

    function watchNotification(notification) {
        notification.tracked = true;
        const key = `n${notification.id}`;
        const previous = watchers[key];
        if (previous !== undefined) {
            previous.destroy();
        }
        const watcher = watcherComponent.createObject(root, {
                                                          "notification": notification,
                                                          "watcherKey": key
                                                      });
        if (watcher === null) {
            notification.expire();
            return;
        }
        watchers[key] = watcher;
        NotificationRuntime.attachNotification(notification, generation);
    }

    function forgetWatcher(watcherKey, watcher) {
        if (watchers[watcherKey] === watcher) {
            delete watchers[watcherKey];
        }
        watcher.destroy();
    }

    function closeNotification(notification, reason, watcherKey, watcher) {
        NotificationRuntime.closeNotification(notification, reason);
        forgetWatcher(watcherKey, watcher);
    }

    function clearWatchers() {
        const current = watchers;
        watchers = {};
        for (const key of Object.keys(current)) {
            current[key].destroy();
        }
    }

    Component.onCompleted: Qt.callLater(() => NotificationRuntime.finishGeneration(generation))

    NotificationServer {
        id: server

        keepOnReload: true
        bodySupported: true
        actionsSupported: false
        persistenceSupported: false
        bodyMarkupSupported: false
        bodyHyperlinksSupported: false
        bodyImagesSupported: false
        imageSupported: false
        actionIconsSupported: false
        inlineReplySupported: false
        extraHints: []

        onNotification: notification => root.watchNotification(notification)
        Component.onCompleted: NotificationRuntime.refreshServerOwnership()
    }

    Connections {
        target: NotificationRuntime

        function onTransientRequested(sourceToken, sourceGeneration, revision) {
            root.transientRequested(sourceToken, sourceGeneration, revision);
        }

        function onTransientInvalidated(sourceToken, sourceGeneration) {
            root.transientInvalidated(sourceToken, sourceGeneration);
        }

        function onServerOwnershipChanged() {
            if (!NotificationRuntime.serverOwned) {
                root.clearWatchers();
            }
        }
    }

    Component {
        id: watcherComponent

        Scope {
            id: watcher

            required property var notification
            required property string watcherKey

            Connections {
                target: watcher.notification
                ignoreUnknownSignals: true

                function onAppNameChanged() {
                    NotificationRuntime.updateNotification(watcher.notification);
                }

                function onSummaryChanged() {
                    NotificationRuntime.updateNotification(watcher.notification);
                }

                function onBodyChanged() {
                    NotificationRuntime.updateNotification(watcher.notification);
                }

                function onUrgencyChanged() {
                    NotificationRuntime.updateNotification(watcher.notification);
                }

                function onDesktopEntryChanged() {
                    NotificationRuntime.updateNotification(watcher.notification);
                }

                function onAppIconChanged() {
                    NotificationRuntime.updateNotification(watcher.notification);
                }

                function onResidentChanged() {
                    NotificationRuntime.updateNotification(watcher.notification);
                }

                function onTransientChanged() {
                    NotificationRuntime.updateNotification(watcher.notification);
                }

                function onExpireTimeoutChanged() {
                    NotificationRuntime.updateNotification(watcher.notification);
                }

                function onClosed(reason) {
                    root.closeNotification(watcher.notification, reason, watcher.watcherKey,
                                           watcher);
                }

                function onDestroyed() {
                    root.forgetWatcher(watcher.watcherKey, watcher);
                }
            }
        }
    }
}

pragma ComponentBehavior: Bound

import Nagi.Notifications 1.0
import Quickshell
import Quickshell.Services.Notifications
import QtQuick

// Owns the protocol server. Raw notification objects remain private to this boundary;
// consumers receive only native-runtime models and normalized presentation events.
Scope {
    id: root
    property bool popupsEnabled: true
    property bool doNotDisturb: false
    property string criticalMode: "bypass"
    property bool dashboardVisible: true
    property bool historyVisible: true

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
    property var admittedPopups: ({})

    signal transientRequested(string sourceToken, int sourceGeneration, int revision)
    signal transientInvalidated(string sourceToken, int sourceGeneration)

    function dismiss(recordKey) {
        return NotificationRuntime.dismiss(recordKey);
    }
    function clearHistory() {
        NotificationRuntime.clearHistory();
    }

    function popupAllowed(urgency) {
        return popupsEnabled && (!doNotDisturb || (urgency === "critical" && criticalMode
                                                   === "bypass"));
    }

    function reevaluatePopups() {
        const current = admittedPopups;
        const retained = {};
        for (const key of Object.keys(current)) {
            const identity = current[key];
            if (popupAllowed(identity.urgency)) {
                retained[key] = identity;
            } else {
                transientInvalidated(identity.sourceToken, identity.sourceGeneration);
            }
        }
        admittedPopups = retained;
    }

    function admitPopup(sourceToken, sourceGeneration, revision, urgency) {
        const key = sourceToken + ":" + sourceGeneration;
        if (popupAllowed(urgency)) {
            admittedPopups[key] = {
                "sourceToken": sourceToken,
                "sourceGeneration": sourceGeneration,
                "revision": revision,
                "urgency": urgency
            };
            admittedPopups = Object.assign({}, admittedPopups);
            transientRequested(sourceToken, sourceGeneration, revision);
        } else if (admittedPopups[key] !== undefined) {
            delete admittedPopups[key];
            admittedPopups = Object.assign({}, admittedPopups);
            transientInvalidated(sourceToken, sourceGeneration);
        }
    }

    onPopupsEnabledChanged: reevaluatePopups()
    onDoNotDisturbChanged: reevaluatePopups()
    onCriticalModeChanged: reevaluatePopups()

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
                || typeof normalized.appName !== "string" || typeof normalized.summary !== "string"
                || typeof normalized.body !== "string" || typeof normalized.appIconName
                !== "string") {
            return null;
        }
        return {
            "appIconName": normalized.appIconName,
            "body": normalized.body,
            "detail": normalized.summary,
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
        admittedPopups = {};
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
            root.admitPopup(sourceToken, sourceGeneration, revision,
                            NotificationRuntime.currentTransientUrgency);
        }

        function onTransientInvalidated(sourceToken, sourceGeneration) {
            const key = sourceToken + ":" + sourceGeneration;
            delete root.admittedPopups[key];
            root.admittedPopups = Object.assign({}, root.admittedPopups);
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

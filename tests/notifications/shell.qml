import Nagi.Notifications 1.0
import Quickshell
import QtQuick
import "qml"

ShellRoot {
    QtObject {
        id: test

        property string mode: Quickshell.env("NAGI_NOTIFICATION_TEST_MODE") ?? "normal"
        property int stage: 0
        property string firstKey: ""
        property bool started: false
        property bool ownershipFailureReported: false
        property string transientToken: ""
        property int transientGeneration: 0
        property int transientRevision: 0
        property int transientRequests: 0
        property int transientInvalidations: 0
        property int nativeTransientRequests: 0
        property int soakCycle: 0
        property int soakPreloadIndex: 0
        property string soakOldestKey: ""
        property string soakAdmissionKey: ""
        property string soakTransientToken: ""
        property int soakTransientGeneration: 0
        property int soakTransientRevision: 0
        property real lastSoakSequence: 0
        property int reloadSettleAttempts: 0
        readonly property int maximumLiveCount: 50
        readonly property int maximumHistoryCount: 50
        readonly property int maximumDashboardCount: 4
        readonly property int maximumReloadSettleAttempts: 100

        function fail(message) {
            console.error(`notification-harness-failure:${message}`);
            Qt.exit(1);
        }

        function require(condition, message) {
            if (!condition) {
                fail(message);
                return false;
            }
            return true;
        }
        function objectCount(value) {
            return Object.keys(value).length;
        }
        function dashboardModelCount() {
            return service.dashboardModel === null ? 0 : service.dashboardModel.rowCount();
        }

        function requireSoakBounds(label) {
            return require(service.generation === 1, label + "-stale-generation") && require(
                        service.liveCount >= 0 && service.liveCount <= maximumLiveCount, label
                        + "-live-bound") && require(service.historyCount >= 0
                                                    && service.historyCount <= maximumHistoryCount,
                                                    label + "-history-bound") && require(
                        historyView.rowCount === service.historyCount, label
                        + "-history-model-bound") && require(dashboardModelCount() === Math.min(
                                                                 service.historyCount,
                                                                 maximumDashboardCount), label
                                                             + "-dashboard-model-bound") && require(
                        objectCount(service.watchers) === service.liveCount, label
                        + "-watcher-bound") && require(objectCount(service.admittedPopups)
                                                       === service.liveCount, label
                                                       + "-mailbox-bound") && require(
                        service.activeTimerCount >= 0 && service.activeTimerCount <= 1, label
                        + "-scheduler-bound");
        }

        function requireSoakState(expectedLive, expectedHistory, expectedTimer, label) {
            return requireSoakBounds(label) && require(service.liveCount === expectedLive, label
                                                       + "-live-count") && require(
                        service.historyCount === expectedHistory, label + "-history-count")
                    && require(service.activeTimerCount === expectedTimer, label + "-timer-count");
        }

        function historyContains(recordKey) {
            for (let index = 0; index < service.historyCount; index += 1) {
                if (NotificationRuntime.historySnapshot(index).firstAdmissionSequence
                        === recordKey) {
                    return true;
                }
            }
            return false;
        }

        function rememberBoundSequence(snapshot, label) {
            const sequence = Number(snapshot.firstAdmissionSequence);
            if (!require(Number.isInteger(sequence) && sequence > lastSoakSequence, label
                         + "-fresh-sequence")) {
                return false;
            }
            lastSoakSequence = sequence;
            return true;
        }

        function rememberSoakAdmission(snapshot, label) {
            if (!rememberBoundSequence(snapshot, label)) {
                return false;
            }
            soakAdmissionKey = snapshot.firstAdmissionSequence;
            soakTransientToken = transientToken;
            soakTransientGeneration = transientGeneration;
            soakTransientRevision = transientRevision;
            return require(soakTransientToken !== "" && service.resolveTransient(soakTransientToken,
                                                                                 soakTransientGeneration,
                                                                                 soakTransientRevision)
                           !== null, label + "-transient-owned");
        }

        function requireSoakTransientReleased(label) {
            return require(service.resolveTransient(soakTransientToken, soakTransientGeneration,
                                                    soakTransientRevision) === null, label
                           + "-transient-retained");
        }

        function start() {
            if (mode === "ownership") {
                if (!service.serverOwned && !ownershipFailureReported) {
                    ownershipFailureReported = true;
                    console.warn("notification-harness-ownership-failed");
                }
                return;
            }
            if (!service.serverOwned || started) {
                return;
            }
            started = true;
            if (mode === "restart") {
                if (require(service.liveCount === 0 && service.historyCount === 0,
                            "restart-not-empty") && require(objectCount(service.watchers) === 0
                                                            && objectCount(service.admittedPopups)
                                                            === 0 && service.activeTimerCount === 0
                                                            && dashboardModelCount() === 0,
                                                            "restart-cleanup-not-empty")) {
                    console.warn("notification-harness-restarted");
                }
                return;
            }
            if (service.generation > 1) {
                Qt.callLater(verifyReload);
                return;
            }
            service.popupsEnabled = true;
            service.doNotDisturb = false;
            service.criticalMode = "bypass";
            console.warn("notification-harness-ready");
        }

        function verifyReload() {
            const reconciled = service.liveCount === 1 && service.historyCount === 1 && objectCount(
                      service.watchers) === 1 && objectCount(service.admittedPopups) === 0
                  && service.activeTimerCount === 1 && dashboardModelCount() === 1;
            if (!reconciled) {
                reloadSettleAttempts += 1;
                if (reloadSettleAttempts > maximumReloadSettleAttempts) {
                    fail("reload-mailbox-did-not-reconcile");
                    return;
                }
                Qt.callLater(verifyReload);
                return;
            }
            console.warn("notification-harness-reloaded");
        }

        function advance() {
            if (mode !== "normal" || service.generation > 1) {
                return;
            }
            if (historyView.rowCount !== service.historyCount) {
                Qt.callLater(test.advance);
                return;
            }
            if (stage >= 12 && stage <= 20 && !requireSoakBounds("soak-" + soakCycle + "-stage-"
                                                                 + stage)) {
                return;
            }
            const snapshot = NotificationRuntime.historySnapshot(0);
            if (stage === 0 && service.historyCount === 1) {
                const expectedKeys = ["appIconName", "appName", "body", "desktopEntry",
                                      "firstAdmissionSequence", "firstAdmittedMonotonicMs",
                                      "historyCutoffMonotonicMs", "resident", "state", "summary",
                                      "urgency"];
                const transient = service.resolveTransient(transientToken, transientGeneration,
                                                           transientRevision);
                if (!require(nativeTransientRequests === 1,
                             "nagi-first-notify-native-admission-count") || !require(
                            transientRequests === 1 && transientToken !== "",
                            "nagi-first-notify-popup-request-count")) {
                    return;
                }
                if (!require(Object.keys(snapshot).sort().join(",") === expectedKeys.sort().join(","),
                             "snapshot-fields") || !require(snapshot.appName === "App�Name",
                                                            "app-normalization") || !require(
                            snapshot.body === "Bold linkALT", "body-normalization") || !require(
                            transient !== null, "transient-projection-missing") || !require(
                            transient.body === snapshot.body, "transient-body-projection") ||
                        !require(transient.appIconName === snapshot.appIconName,
                                 "transient-icon-projection") || !require(transient.primary
                                                                          === snapshot.appName,
                                                                          "transient-app-projection")
                        || !require(transient.detail === snapshot.summary,
                                    "transient-summary-projection") || !require(snapshot.state
                                                                                === "live" &&
                                                                                !service.actionsSupported
                                                                                && !service.canAct(
                                                                                    snapshot.firstAdmissionSequence)
                                                                                && service.actionsFor(
                                                                                    snapshot.firstAdmissionSequence).length
                                                                                === 0 && historyView.visibleActionCount
                                                                                === 0, "initial-contract")) {
                    return;
                }
                firstKey = snapshot.firstAdmissionSequence;
                historyView.focusInitialControl();
                service.doNotDisturb = true;
                const dndInvalidations = transientInvalidations;
                service.doNotDisturb = false;
                if (!require(dndInvalidations > 0, "dnd-did-not-invalidate-normal-popup") ||
                        !require(dndInvalidations === 1, "dnd-invalidated-popup-more-than-once")) {
                    return;
                }
                stage = 1;
                console.warn("notification-harness-received");
                return;
            }
            if (stage === 1 && service.historyCount === 1 && snapshot.summary === "Replacement") {
                if (!require(snapshot.firstAdmissionSequence === firstKey,
                             "replacement-key-changed")) {
                    return;
                }
                stage = 2;
                console.warn("notification-harness-replaced");
                return;
            }
            if (stage === 2 && service.historyCount === 0 && service.liveCount === 1) {
                stage = 3;
                console.warn("notification-harness-transient");
                return;
            }
            if (stage === 3 && service.historyCount === 1) {
                if (!require(snapshot.firstAdmissionSequence !== firstKey,
                             "readmission-key-reused")) {
                    return;
                }
                stage = 4;
                console.warn("notification-harness-readmitted");
                return;
            }
            if (stage === 4 && service.historyCount === 0 && service.liveCount === 0) {
                stage = 5;
                console.warn("notification-harness-closed");
                return;
            }
            if (stage === 5 && service.historyCount === 1 && snapshot.summary === "Unknown") {
                stage = 6;
                console.warn("notification-harness-unknown");
                return;
            }
            if (stage === 6 && service.historyCount === 0 && service.liveCount === 0) {
                stage = 7;
                console.warn("notification-harness-unknown-closed");
                return;
            }
            if (stage === 7 && service.historyCount === 1 && snapshot.summary === "Expiry"
                    && snapshot.state === "live") {
                stage = 8;
                console.warn("notification-harness-expiry-admitted");
                return;
            }
            if (stage === 8 && service.historyCount === 1 && snapshot.state === "expired"
                    && service.liveCount === 0) {
                stage = 9;
                console.warn("notification-harness-expired");
                return;
            }
            if (stage === 9 && service.historyCount === 2 && snapshot.summary === "Dismiss") {
                stage = 10;
                historyView.focusRow(0, Qt.ShortcutFocusReason);
                Qt.callLater(function () {
                    if (!historyView.dismissCurrent()) {
                        fail("dismiss-dispatch-failed");
                    }
                });
                return;
            }
            if (stage === 10 && service.historyCount === 1 && service.liveCount === 0) {
                stage = 11;
                service.clearHistory();
                return;
            }
            if (stage === 11 && service.historyCount === 0 && service.liveCount === 0) {
                if (!require(service.activeTimerCount === 0 && objectCount(service.watchers) === 0
                             && objectCount(service.admittedPopups) === 0, "pre-soak-cleanup")) {
                    return;
                }
                stage = 12;
                console.warn("notification-harness-dismissed");
                return;
            }
            if (stage === 12 && soakPreloadIndex < maximumHistoryCount && service.historyCount
                    === soakPreloadIndex + 1 && service.liveCount === soakPreloadIndex + 1
                    && snapshot.summary === "Retained " + soakPreloadIndex) {
                const completedPreload = soakPreloadIndex;
                if (!requireSoakState(completedPreload + 1, completedPreload + 1, 1,
                                      "soak-preload-" + completedPreload) || !rememberBoundSequence(
                            snapshot, "soak-preload-" + completedPreload)) {
                    return;
                }
                soakPreloadIndex += 1;
                if (soakPreloadIndex === maximumHistoryCount) {
                    soakOldestKey = NotificationRuntime.historySnapshot(maximumHistoryCount
                                                                        - 1).firstAdmissionSequence;
                    if (!require(soakOldestKey !== "", "soak-preload-oldest-key")) {
                        return;
                    }
                    stage = 13;
                }
                console.warn("notification-harness-soak-preload:" + completedPreload + ":");
                return;
            }
            if (stage === 13 && soakCycle < 100 && service.historyCount === maximumHistoryCount
                    && service.liveCount === maximumLiveCount && snapshot.summary === "Soak "
                    + soakCycle + " admitted") {
                if (!requireSoakState(maximumLiveCount, maximumHistoryCount, 1, "soak-" + soakCycle
                                      + "-admitted") || !require(!historyContains(soakOldestKey),
                                                                 "soak-" + soakCycle
                                                                 + "-oldest-history-not-pruned") ||
                        !rememberSoakAdmission(snapshot, "soak-" + soakCycle + "-admitted")) {
                    return;
                }
                stage = 14;
                console.warn("notification-harness-soak-admitted:" + soakCycle + ":");
                return;
            }
            if (stage === 14 && service.historyCount === maximumHistoryCount && service.liveCount
                    === maximumLiveCount && snapshot.summary === "Soak " + soakCycle
                    + " replaced") {
                if (!requireSoakState(maximumLiveCount, maximumHistoryCount, 1, "soak-" + soakCycle
                                      + "-replaced") || !require(snapshot.firstAdmissionSequence
                                                                 === soakAdmissionKey, "soak-"
                                                                 + soakCycle
                                                                 + "-replacement-key-changed") ||
                        !require(transientToken === soakTransientToken && transientGeneration
                                 === soakTransientGeneration && transientRevision
                                 > soakTransientRevision, "soak-" + soakCycle
                                 + "-replacement-generation")) {
                    return;
                }
                soakTransientRevision = transientRevision;
                stage = 15;
                console.warn("notification-harness-soak-replaced:" + soakCycle + ":");
                return;
            }
            if (stage === 15 && service.historyCount === maximumHistoryCount - 1 && service.liveCount
                    === maximumLiveCount - 1) {
                if (!requireSoakState(maximumLiveCount - 1, maximumHistoryCount - 1, 1, "soak-"
                                      + soakCycle + "-closed") || !require(!historyContains(
                                                                               soakAdmissionKey),
                                                                           "soak-" + soakCycle
                                                                           + "-closed-history-retained")
                        || !requireSoakTransientReleased("soak-" + soakCycle + "-closed")) {
                    return;
                }
                stage = 16;
                console.warn("notification-harness-soak-closed:" + soakCycle + ":");
                return;
            }
            if (stage === 16 && service.historyCount === maximumHistoryCount && service.liveCount
                    === maximumLiveCount && snapshot.summary === "Soak " + soakCycle + " expiry"
                    && snapshot.state === "live") {
                if (!requireSoakState(maximumLiveCount, maximumHistoryCount, 1, "soak-" + soakCycle
                                      + "-expiry-admitted") || !rememberSoakAdmission(snapshot,
                                                                                      "soak-" + soakCycle
                                                                                      + "-expiry-admitted")) {
                    return;
                }
                stage = 17;
                console.warn("notification-harness-soak-expiry-admitted:" + soakCycle + ":");
                return;
            }
            if (stage === 17 && service.historyCount === maximumHistoryCount && service.liveCount
                    === maximumLiveCount - 1 && snapshot.state === "expired") {
                if (!requireSoakState(maximumLiveCount - 1, maximumHistoryCount, 1, "soak-"
                                      + soakCycle + "-expired") || !requireSoakTransientReleased(
                            "soak-" + soakCycle + "-expired")) {
                    return;
                }
                stage = 18;
                console.warn("notification-harness-soak-expired:" + soakCycle + ":");
                if (!service.dismiss(soakAdmissionKey)) {
                    fail("soak-" + soakCycle + "-expired-clear-dispatch");
                }
                return;
            }
            if (stage === 18 && service.historyCount === maximumHistoryCount - 1 && service.liveCount
                    === maximumLiveCount - 1) {
                if (!requireSoakState(maximumLiveCount - 1, maximumHistoryCount - 1, 1, "soak-"
                                      + soakCycle + "-cleared") || !require(!historyContains(
                                                                                soakAdmissionKey),
                                                                            "soak-" + soakCycle
                                                                            + "-expired-history-retained")
                        || !requireSoakTransientReleased("soak-" + soakCycle + "-cleared")) {
                    return;
                }
                stage = 19;
                console.warn("notification-harness-soak-cleared:" + soakCycle + ":");
                return;
            }
            if (stage === 19 && service.historyCount === maximumHistoryCount && service.liveCount
                    === maximumLiveCount && snapshot.summary === "Soak " + soakCycle
                    + " retained") {
                const completedCycle = soakCycle;
                if (!requireSoakState(maximumLiveCount, maximumHistoryCount, 1, "soak-"
                                      + completedCycle + "-retained") || !rememberBoundSequence(
                            snapshot, "soak-" + completedCycle + "-retained")) {
                    return;
                }
                soakOldestKey = NotificationRuntime.historySnapshot(maximumHistoryCount
                                                                    - 1).firstAdmissionSequence;
                if (!require(soakOldestKey !== "" && historyContains(soakOldestKey), "soak-"
                             + completedCycle + "-next-oldest-key")) {
                    return;
                }
                soakCycle += 1;
                stage = soakCycle < 100 ? 13 : 20;
                console.warn("notification-harness-soak-terminal:" + completedCycle + ":");
                if (stage === 20) {
                    Qt.callLater(test.advance);
                }
                return;
            }
            if (stage === 20) {
                if (service.historyCount > 0 || service.liveCount > 0) {
                    if (!require(service.historyCount === service.liveCount,
                                 "soak-final-drain-count-mismatch")) {
                        return;
                    }
                    const drainKey = snapshot.firstAdmissionSequence;
                    if (!require(drainKey !== "" && service.dismiss(drainKey),
                                 "soak-final-drain-dispatch")) {
                        return;
                    }
                    Qt.callLater(test.advance);
                    return;
                }
                if (!requireSoakState(0, 0, 0, "soak-final-drain")) {
                    return;
                }
                stage = 21;
                console.warn("notification-harness-soak-drained");
                return;
            }
            if (stage === 21 && service.historyCount === 1 && service.liveCount === 1
                    && snapshot.summary === "Reload") {
                stage = 22;
                console.warn("notification-harness-reload-ready");
            }
        }
    }

    NotificationService {
        id: service
        onTransientRequested: (sourceToken, sourceGeneration, revision) => {
            test.transientRequests += 1;
            test.transientToken = sourceToken;
            test.transientGeneration = sourceGeneration;
            test.transientRevision = revision;
        }
        onTransientInvalidated: (sourceToken, sourceGeneration) => {
            test.transientInvalidations += 1;
        }

        onServerOwnedChanged: {
            if (test.mode === "ownership" && serverOwned) {
                console.warn("notification-harness-ownership-recovered");
            } else {
                Qt.callLater(test.start);
            }
        }
    }

    NotificationHistoryView {
        id: historyView

        width: implicitWidth
        height: implicitHeight
        service: service
        ownerEpoch: 1
    }

    Connections {
        target: NotificationRuntime

        function onHistoryCountChanged() {
            Qt.callLater(test.advance);
        }

        function onTransientRequested(sourceToken, sourceGeneration, revision) {
            test.nativeTransientRequests += 1;
        }
    }

    function verifyPopupPolicy() {
        service.doNotDisturb = true;
        require(!service.popupAllowed("normal"),
                "normal notifications bypassed initial Do Not Disturb");
        require(service.popupAllowed("critical"),
                "critical notifications did not bypass Do Not Disturb by default");
        service.admitPopup("policy-normal", 1, 1, "normal");
        require(transientRequests === 0, "Do Not Disturb admitted a normal notification transient");
        service.admitPopup("policy-critical", 1, 1, "critical");
        require(transientRequests === 1, "critical notification did not bypass Do Not Disturb");
        service.criticalMode = "silence";
        require(!service.popupAllowed("critical") && transientInvalidations === 1,
                "total silence did not invalidate the admitted critical transient");
        service.popupsEnabled = false;
        service.doNotDisturb = false;
        require(!service.popupAllowed("critical"),
                "disabled popups admitted a critical notification");
        service.popupsEnabled = true;
        service.criticalMode = "bypass";
        transientRequests = 0;
        transientInvalidations = 0;
    }

    Timer {
        interval: 20
        running: !test.started || test.mode === "ownership"
        repeat: true
        onTriggered: test.start()
    }

    Component.onCompleted: {
        verifyPopupPolicy();
        Qt.callLater(test.start);
    }
}

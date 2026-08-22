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
                            "restart-not-empty")) {
                    console.warn("notification-harness-restarted");
                }
                return;
            }
            if (service.generation > 1) {
                Qt.callLater(verifyReload);
                return;
            }
            console.warn("notification-harness-ready");
        }

        function verifyReload() {
            if (require(service.liveCount === 1 && service.historyCount === 1,
                        "reload-did-not-reconcile")) {
                console.warn("notification-harness-reloaded");
            }
        }

        function advance() {
            if (mode !== "normal" || service.generation > 1) {
                return;
            }
            if (historyView.rowCount !== service.historyCount) {
                Qt.callLater(test.advance);
                return;
            }
            const snapshot = NotificationRuntime.historySnapshot(0);
            if (stage === 0 && service.historyCount === 1) {
                const expectedKeys = ["appIconName", "appName", "body", "desktopEntry",
                                      "firstAdmissionSequence", "firstAdmittedMonotonicMs",
                                      "historyCutoffMonotonicMs", "resident", "state", "summary",
                                      "urgency"];
                if (!require(Object.keys(snapshot).sort().join(",") === expectedKeys.sort().join(","),
                             "snapshot-fields") || !require(snapshot.appName === "App�Name",
                                                            "app-normalization") || !require(
                            snapshot.body === "Bold linkALT", "body-normalization") || !require(
                            snapshot.state === "live" && !service.actionsSupported &&
                            !service.canAct(snapshot.firstAdmissionSequence) && service.actionsFor(
                                snapshot.firstAdmissionSequence).length === 0
                            && historyView.visibleActionCount === 0, "initial-contract")) {
                    return;
                }
                firstKey = snapshot.firstAdmissionSequence;
                historyView.focusInitialControl();
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
                console.warn("notification-harness-dismissed");
                return;
            }
            if (stage === 11 && service.historyCount === 2 && snapshot.summary === "Reload") {
                stage = 12;
                console.warn("notification-harness-reload-ready");
            }
        }
    }

    NotificationService {
        id: service

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

        width: Theme.size.islandExpandedWidth
        height: Theme.size.islandExpandedHeight
        service: service
        ownerEpoch: 1
    }

    Connections {
        target: NotificationRuntime

        function onHistoryCountChanged() {
            Qt.callLater(test.advance);
        }
    }

    Timer {
        interval: 20
        running: !test.started || test.mode === "ownership"
        repeat: true
        onTriggered: test.start()
    }

    Component.onCompleted: Qt.callLater(test.start)
}

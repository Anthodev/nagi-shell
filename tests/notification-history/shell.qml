//@ pragma UseQApplication
import Quickshell
import QtQuick
import QtQuick.Window
import "qml"

ShellRoot {
    id: test

    readonly property bool liveMode: Quickshell.env("NAGI_HISTORY_TEST_MODE") === "live"
    property int step: 0
    property int retryAttempts: 0
    property string dismissedKey: ""
    property real cancelledEpoch: 0
    readonly property int maximumRetryAttempts: 500

    function advance() {
        Qt.callLater(test.runStep);
    }

    function awaitState(condition, message) {
        if (condition) {
            retryAttempts = 0;
            return true;
        }
        retryAttempts += 1;
        require(retryAttempts <= maximumRetryAttempts, message);
        retry.restart();
        return false;
    }

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function requireHistoryLayout(count) {
        const expectedHeight = count === 0 ? Theme.size.controlHeightLg :
                                             historyView.firstRowsExtent(Math.min(count,
                                                                                  historyView.maximumVisibleRows));
        require(historyView.rowCount === count, "history did not render the requested row count "
                + count);
        require(historyView.historyViewportHeight === expectedHeight,
                "history viewport height was not exact for " + count + " rows");
        require(historyView.historyScrollVisible === (count > historyView.maximumVisibleRows),
                "history scrollbar threshold was wrong for " + count + " rows");
        if (count === 0) {
            require(historyView.contentWidth === Theme.spacing.xxl * 6,
                    "empty history width was not compact");
        }
    }

    function appendHistory(sequence) {
        history.append({
                           "firstAdmissionSequence": String(sequence),
                           "state": "live",
                           "appName": "Layout " + sequence,
                           "summary": "Notification " + sequence,
                           "body": "Controlled layout row."
                       });
    }

    function restoreBehaviorRows() {
        historyView.selectedRecordKey = "";
        historyView.fallbackIndex = 0;
        historyView.restoreListFocus = true;
        history.clear();
        history.append({
                           "firstAdmissionSequence": "2",
                           "state": "expired",
                           "appName": "Mail",
                           "summary": "Build finished",
                           "body": "The controlled verification run completed."
                       });
        history.append({
                           "firstAdmissionSequence": "1",
                           "state": "live",
                           "appName": "Messages",
                           "summary": "Review requested",
                           "body": "Please check the latest notification history changes."
                       });
    }

    function runStep() {
        if (liveMode) {
            historyView.focusInitialControl();
            console.warn("notification-history-live-ready");
            return;
        }

        if (step === 0) {
            history.clear();
        } else if (step === 1) {
            if (!awaitState(historyView.rowCount === 0, "empty history layout did not settle")) {
                return;
            }
            requireHistoryLayout(0);
            appendHistory(1);
        } else if (step === 2) {
            if (!awaitState(historyView.rowCount === 1, "single history row did not settle")) {
                return;
            }
            requireHistoryLayout(1);
            for (let sequence = 2; sequence <= 5; ++sequence) {
                appendHistory(sequence);
            }
        } else if (step === 3) {
            if (!awaitState(historyView.rowCount === 5, "five history rows did not settle")) {
                return;
            }
            requireHistoryLayout(5);
            appendHistory(6);
        } else if (step === 4) {
            if (!awaitState(historyView.rowCount === 6, "six history rows did not settle")) {
                return;
            }
            requireHistoryLayout(6);
            require(historyView.implicitWidth === historyView.contentWidth + Theme.spacing.lg * 2,
                    "history width did not hug meaningful row content");
            restoreBehaviorRows();
        } else if (step === 5) {
            if (!awaitState(historyView.rowCount === 2, "history rows did not render")) {
                return;
            }
            historyView.focusInitialControl();
        } else if (step === 6) {
            if (!awaitState(historyView.historyFocused && historyView.currentRecordKey === "2",
                            "initial history focus did not reach the newest row")) {
                return;
            }
            require(historyView.currentRowUsesPlainText,
                    "history content is not forced to plain text");
            require(historyView.visibleActionCount === 0 && !fakeService.actionsSupported,
                    "notification actions appeared while the dependency gate is closed");
            history.setProperty(0, "summary", "<b>Replacement remains text</b>");
            history.insert(0, {
                               "firstAdmissionSequence": "3",
                               "state": "live",
                               "appName": "Calendar",
                               "summary": "Meeting moved",
                               "body": "The review starts at 15:30."
                           });
        } else if (step === 7) {
            if (!awaitState(historyView.rowCount === 3 && historyView.currentRecordKey === "2"
                            && historyView.historyFocused,
                            "concurrent update stole history selection or focus")) {
                return;
            }
            require(historyView.currentRowUsesPlainText,
                    "replacement changed the row's plain-text rendering mode");
            require(historyView.dismissCurrent(), "selected expired row was not dismissed");
        } else if (step === 8) {
            if (!awaitState(historyView.rowCount === 2 && dismissedKey === "2"
                            && historyView.currentRecordKey === "1" && historyView.historyFocused,
                            "dismissal did not remove immediately and focus the nearest row")) {
                return;
            }
            history.clear();
        } else if (step === 9) {
            if (!awaitState(historyView.rowCount === 0 && historyView.emptyStateVisible
                            && historyView.backFocused,
                            "empty history did not show compact text and preserve keyboard flow")) {
                return;
            }
            historyView.requestBack();
        } else if (step === 10) {
            require(cancelledEpoch === 42,
                    "Back did not carry the current Interactive owner epoch");
            console.warn("notification history view tests passed");
            Qt.exit(0);
            return;
        }

        step += 1;
        advance();
    }

    ListModel {
        id: history

        ListElement {
            firstAdmissionSequence: "2"
            state: "expired"
            appName: "Mail"
            summary: "Build finished"
            body: "The controlled verification run completed."
        }

        ListElement {
            firstAdmissionSequence: "1"
            state: "live"
            appName: "Messages"
            summary: "Review requested"
            body: "Please check the latest notification history changes."
        }
    }

    QtObject {
        id: fakeService

        readonly property var historyModel: history
        readonly property int historyCount: history.count
        readonly property bool serverOwned: true
        readonly property bool actionsSupported: false

        function dismiss(recordKey) {
            const index = historyIndex(recordKey);
            if (index < 0) {
                return false;
            }
            test.dismissedKey = String(recordKey);
            history.remove(index);
            return true;
        }

        function historyIndex(recordKey) {
            const key = String(recordKey);
            for (let index = 0; index < history.count; index += 1) {
                if (String(history.get(index).firstAdmissionSequence) === key) {
                    return index;
                }
            }
            return -1;
        }
    }

    Window {
        id: window

        visible: true
        color: "transparent"
        width: historyView.implicitWidth
        height: 900

        IslandPanel {
            anchors.fill: parent
            radius: Theme.radius.xl
        }

        NotificationHistoryView {
            id: historyView

            anchors.fill: parent
            ownerEpoch: 42
            service: fakeService
            onCancelled: epoch => {
                test.cancelledEpoch = epoch;
            }
        }
    }

    Timer {
        id: retry

        interval: 10
        onTriggered: test.runStep()
    }

    Component.onCompleted: advance()
}

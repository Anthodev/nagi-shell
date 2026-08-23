pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

// Stable session-operation boundary for presentation. It exposes only bounded
// action and outcome enums; D-Bus details remain private to SessionBridge.
Scope {
    id: root

    required property string helperPath

    // Verification seam. Production owns one native SessionBridge.
    property var bridge: null
    // Quickshell.reload(false) performs a soft configuration reload, preserving
    // reusable windows. Injection keeps this platform seam directly verifiable.
    property var reloadController: Quickshell

    readonly property bool backendReady: engine.currentBridge !== null && engine.currentBridge.ready
    readonly property bool pending: engine.pendingRequestId !== 0
    readonly property string pendingAction: engine.pendingAction
    readonly property string failure: engine.failure
    readonly property int activeTimerCount: root.bridge === null ? nativeBridge.activeTimerCount : 0
    readonly property bool shellRestartReady: root.reloadController !== null
                                              && typeof root.reloadController.reload === "function"

    signal operationFinished(int requestId, string action, string outcome)

    function clearFailure() {
        engine.failure = "none";
    }

    function requestAction(action) {
        return engine.requestAction(action);
    }

    onBridgeChanged: engine.reset()
    Component.onDestruction: engine.cleanup()

    SessionBridge {
        id: nativeBridge

        helperPath: root.helperPath
        enabled: root.bridge === null
    }

    Connections {
        target: engine.currentBridge
        ignoreUnknownSignals: true

        function onFatalFailure() {
            engine.failPending("backend");
        }

        function onResultReceived(result) {
            engine.acceptResult(result);
        }
    }

    QtObject {
        id: engine

        property var currentBridge: root.bridge === null ? nativeBridge : root.bridge
        property int nextRequestId: 1
        property int pendingRequestId: 0
        property string pendingAction: "none"
        property string failure: "none"

        function acceptResult(result) {
            if (result === null || typeof result !== "object" || Array.isArray(result)
                    || result.requestId !== pendingRequestId || result.action !== pendingAction ||
                    !validOutcome(result.outcome)) {
                return;
            }

            const requestId = pendingRequestId;
            const action = pendingAction;
            pendingRequestId = 0;
            pendingAction = "none";
            failure = result.outcome === "accepted" ? "none" : result.outcome;
            root.operationFinished(requestId, action, result.outcome);
        }

        function allocateRequestId() {
            const requestId = nextRequestId;
            nextRequestId = nextRequestId >= 2147483647 ? 1 : nextRequestId + 1;
            return requestId;
        }

        function cleanup() {
            currentBridge = null;
            reset();
        }

        function failPending(outcome) {
            if (pendingRequestId === 0) {
                failure = outcome;
                return;
            }
            acceptResult({
                             "requestId": pendingRequestId,
                             "action": pendingAction,
                             "outcome": outcome
                         });
        }

        function requestAction(action) {
            if (pendingRequestId !== 0 || !validAction(action)) {
                return 0;
            }

            const requestId = allocateRequestId();
            if (action === "restartShell") {
                if (!root.shellRestartReady) {
                    return 0;
                }
                failure = "none";
                root.reloadController.reload(false);
                return requestId;
            }

            if (currentBridge === null || !currentBridge.ready || !currentBridge.requestAction(
                        requestId, action)) {
                return 0;
            }
            pendingRequestId = requestId;
            pendingAction = action;
            failure = "none";
            return requestId;
        }

        function reset() {
            pendingRequestId = 0;
            pendingAction = "none";
            failure = "none";
        }

        function validAction(action) {
            return action === "lock" || action === "suspend" || action === "logout" || action
                    === "reboot" || action === "powerOff" || action === "restartShell";
        }

        function validOutcome(outcome) {
            return outcome === "accepted" || outcome === "busy" || outcome === "denied" || outcome
                    === "unavailable" || outcome === "timeout" || outcome === "backend";
        }
    }
}

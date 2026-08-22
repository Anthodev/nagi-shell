import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    property int entryRequests: 0
    property real cancelledEpoch: 0
    property int dispatchedRequestId: 0
    property real dispatchedEpoch: 0

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    QtObject {
        id: fakeBridge

        property bool ready: true
        property var commands: []

        signal resultReceived(var result)
        signal fatalFailure

        function requestAction(requestId, action) {
            const next = commands.slice();
            next.push({
                          "requestId": requestId,
                          "action": action
                      });
            commands = next;
            return true;
        }
    }

    SessionService {
        id: service

        helperPath: ""
        bridge: fakeBridge
        onOperationFinished: function (requestId, action, outcome) {
            require(requestId > 0 && action !== "" && outcome !== "",
                    "service emits bounded operation results");
        }
    }

    SessionEntry {
        id: entry

        onOpenRequested: test.entryRequests += 1
    }

    SessionView {
        id: view

        ownerEpoch: 41
        service: service
        onActionDispatched: function (requestId, epoch) {
            test.dispatchedRequestId = requestId;
            test.dispatchedEpoch = epoch;
        }
        onCancelled: epoch => test.cancelledEpoch = epoch
    }

    function run() {
        require(service.backendReady && !service.pending && service.failure === "none",
                "ready bridge produces an idle normalized service");
        require(entry.label === "Session", "dashboard exposes one concise Session entry");
        entry.openRequested();
        require(entryRequests === 1, "Session entry emits one explicit open request");

        require(!view.requestAction("invalid"), "unknown session actions are rejected");
        require(view.requestAction("lock"), "explicit lock activation is dispatched");
        const lockRequest = service.pending ? fakeBridge.commands[0].requestId : 0;
        require(lockRequest > 0 && fakeBridge.commands.length === 1 && dispatchedRequestId
                === lockRequest && dispatchedEpoch === 41,
                "view binds one request identity to the current session owner");
        require(!view.requestAction("suspend") && fakeBridge.commands.length === 1,
                "repeated activation is blocked while an operation is pending");

        fakeBridge.resultReceived({
                                      "requestId": lockRequest,
                                      "action": "lock",
                                      "outcome": "denied"
                                  });
        require(!service.pending && service.failure === "denied",
                "denial keeps the session task visible with a normalized failure");
        require(view.failureText(service.failure).indexOf("Permission denied") === 0,
                "denial copy is actionable and contains no backend payload");

        require(view.requestAction("logout"), "logout confirmation request is dispatched");
        const logoutRequest = fakeBridge.commands[1].requestId;
        fakeBridge.resultReceived({
                                      "requestId": lockRequest,
                                      "action": "lock",
                                      "outcome": "accepted"
                                  });
        require(service.pending, "stale backend completion cannot finish a newer request");
        fakeBridge.resultReceived({
                                      "requestId": logoutRequest,
                                      "action": "logout",
                                      "outcome": "accepted"
                                  });
        require(!service.pending && service.failure === "none" && dispatchedRequestId
                === logoutRequest && dispatchedEpoch === 41,
                "accepted platform handoff retains the matching owner identity for the surface");
        require(view.requestAction("reboot"), "a later destructive action can start cleanly");
        fakeBridge.fatalFailure();
        require(!service.pending && service.failure === "backend",
                "helper loss cleans up pending state without completing the owner");
        require(view.failureText(service.failure).indexOf("session action failed") > 0,
                "backend failure offers an actionable fallback");

        view.cancelled(view.ownerEpoch);
        require(cancelledEpoch === 41 && fakeBridge.commands.length === 3,
                "cancellation carries the owner epoch and dispatches no side effect");
        require(service.activeTimerCount === 0,
                "injected service leaves no production timers active");

        console.warn("session service and view tests passed");
        Qt.exit(0);
    }

    Component.onCompleted: Qt.callLater(run)
}

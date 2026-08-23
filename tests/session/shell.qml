import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    property int entryRequests: 0
    property real cancelledEpoch: 0
    property int dispatchedRequestId: 0
    property real dispatchedEpoch: 0
    property int reloadCalls: 0
    property bool reloadWasHard: true

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function collectObjects(item, name, matches) {
        if (item === null || item === undefined || matches.indexOf(item) !== -1) {
            return;
        }
        if (item.objectName === name) {
            matches.push(item);
        }
        if (item.children !== undefined) {
            for (let index = 0; index < item.children.length; index += 1) {
                collectObjects(item.children[index], name, matches);
            }
        }
        if (item.contentItem !== undefined && item.contentItem !== null) {
            collectObjects(item.contentItem, name, matches);
        }
    }

    QtObject {
        id: fakeReloadController

        function reload(hard) {
            test.reloadCalls += 1;
            test.reloadWasHard = hard;
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
        reloadController: fakeReloadController
        onOperationFinished: function (requestId, action, outcome) {
            require(requestId > 0 && action !== "" && outcome !== "",
                    "service emits bounded operation results");
        }
    }

    QtObject {
        id: serviceWithoutShellRestartCapability

        property bool backendReady: true
        property bool pending: false
        property string pendingAction: "none"
        property string failure: "none"

        function clearFailure() {
        }

        function requestAction(action) {
            return 0;
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

    SessionView {
        id: capabilityFallbackView

        active: false
        ownerEpoch: 42
        service: serviceWithoutShellRestartCapability
    }

    function run() {
        require(service.backendReady && !service.pending && service.failure === "none",
                "ready bridge produces an idle normalized service");
        require(typeof Quickshell.reload === "function",
                "installed Quickshell exposes the reload(bool) QML API");
        require(entry.label === "Session", "dashboard exposes one concise Session entry");
        entry.openRequested();
        require(entryRequests === 1, "Session entry emits one explicit open request");
        const fallbackButtons = [];
        collectObjects(capabilityFallbackView, "sessionActionButton", fallbackButtons);
        require(fallbackButtons.length === 6,
                "duck-typed session service still creates all action cells");
        for (let index = 0; index < fallbackButtons.length; ++index) {
            const button = fallbackButtons[index];
            if (button.Accessible.name === "Restart shell") {
                require(!button.enabled,
                        "missing shellRestartReady capability disables shell restart");
            } else {
                require(button.enabled,
                        "missing shell restart capability does not disable system actions");
            }
        }

        const actionButtons = [];
        collectObjects(view, "sessionActionButton", actionButtons);
        require(actionButtons.length === 6, "Session exposes six action cells");
        const labels = [];
        for (let index = 0; index < actionButtons.length; index += 1) {
            const button = actionButtons[index];
            labels.push(button.Accessible.name);
            const contentChildren = button.contentItem.children;
            const contentTop = contentChildren[0].mapToItem(button, 0, 0).y;
            const lastContent = contentChildren[contentChildren.length - 1];
            const contentBottom = lastContent.mapToItem(button, 0, lastContent.height).y;
            const contentCenterY = (contentTop + contentBottom) / 2;
            require(Math.abs(contentCenterY - button.height / 2) <= 1, "action cell " + index
                    + " centers its icon and label vertically");
            const focusRings = [];
            collectObjects(button, "islandFocusRing", focusRings);
            require(focusRings.length === 1 && focusRings[0].controlRadius
                    === button.background.radius && focusRings[0].radius
                    === button.background.radius + Theme.size.focusRingGap
                    && button.background.radius === Theme.radius.md, "action cell " + index
                    + " focus ring follows its medium owner curve");
        }
        require(labels.indexOf("Restart") >= 0 && labels.indexOf("Restart shell") >= 0
                && labels.indexOf("Restart") !== labels.indexOf("Restart shell"),
                "shell restart is distinct from the system Restart action");
        require(view.actionContentWidth === view.actions.length * view.actionCellWidth + (
                    view.actions.length - 1) * view.actionGap && view.implicitWidth
                === view.actionContentWidth + Theme.spacing.lg * 2,
                "Session width hugs its six cells, gaps, and shared frame padding");
        const shellRestartIcon = IconResolver.resolve("restartShell", "normal", "", "");
        const systemRestartIcon = IconResolver.resolve("restart", "normal", "", "");
        require(shellRestartIcon.kind === "nagi" && shellRestartIcon.source.endsWith(
                    "/restart-shell.svg") && systemRestartIcon.kind === "system"
                && shellRestartIcon.source !== systemRestartIcon.source,
                "shell restart uses distinct Nagi artwork from the system reboot convention");

        require(view.requestAction("restartShell"),
                "explicit shell restart activation is dispatched");
        require(reloadCalls === 1 && !reloadWasHard && fakeBridge.commands.length === 0 && !service.pending,
                "shell restart calls Quickshell.reload(false) exactly once without system reboot");

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

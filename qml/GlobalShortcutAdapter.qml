pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: root

    required property var coordinator
    required property string helperPath
    property bool historyEnabled: true

    readonly property bool available: state.available
    readonly property var actions: state.actions
    readonly property string activeShortcut: actionState("openLauncher").activeShortcut
    readonly property string preferredShortcut: "Meta+Space"
    readonly property bool preferredConflict: actionState("openLauncher").preferredConflict
    readonly property bool helperRunning: helper.running

    readonly property int maximumLineLength: 4096
    readonly property int maximumDiagnostics: 4
    readonly property var actionNames: ["openDashboard", "openLauncher", "openTray", "openHistory",
        "openAudio", "openSession", "openSystemSettings"]

    signal activationReceived(string action)
    signal controlCenterRequested

    function exactKeys(message, expected) {
        const keys = Object.keys(message).sort();
        const wanted = expected.slice().sort();
        return JSON.stringify(keys) === JSON.stringify(wanted);
    }
    function emptyActions() {
        const result = {};
        for (let index = 0; index < actionNames.length; index += 1) {
            result[actionNames[index]] = Object.freeze({
                                                           "activeShortcut": "",
                                                           "preferredShortcut": actionNames[index]
                                                           === "openLauncher"
                                                           ? root.preferredShortcut : "",
                                                           "preferredConflict": false
                                                       });
        }
        return Object.freeze(result);
    }

    function actionState(action) {
        return state.actions[action] ?? Object.freeze({
                                                          "activeShortcut": "",
                                                          "preferredShortcut": "",
                                                          "preferredConflict": false
                                                      });
    }

    function dispatchActivation(action) {
        switch (action) {
        case "openDashboard":
            return root.coordinator.openDashboard(null);
        case "openLauncher":
            return root.coordinator.openLauncher(null);
        case "openTray":
            return root.coordinator.openTray(null);
        case "openHistory":
            return root.historyEnabled && root.coordinator.openHistory(null);
        case "openAudio":
            return root.coordinator.openAudio(null);
        case "openSession":
            return root.coordinator.openSession(null);
        case "openSystemSettings":
            root.controlCenterRequested();
            return true;
        default:
            return false;
        }
    }

    function acceptLine(line) {
        if (typeof line !== "string" || line.length === 0 || line.length > maximumLineLength) {
            warnBounded("invalid helper line length");
            return;
        }

        let message;
        try {
            message = JSON.parse(line);
        } catch (error) {
            warnBounded("malformed helper line");
            return;
        }
        if (message === null || typeof message !== "object" || Array.isArray(message)
                || typeof message.type !== "string") {
            warnBounded("invalid helper message");
            return;
        }

        if (message.type === "activation") {
            if (!exactKeys(message, ["type", "action"]) || actionNames.indexOf(message.action) ===
                    -1) {
                warnBounded("invalid activation");
                return;
            }
            root.activationReceived(message.action);
            root.dispatchActivation(message.action);
            return;
        }
        if (message.type === "state") {
            if (!exactKeys(message, ["type", "available", "actions"]) || typeof message.available
                    !== "boolean" || message.actions === null || typeof message.actions
                    !== "object" || Array.isArray(message.actions) || !exactKeys(message.actions,
                                                                                 actionNames)) {
                warnBounded("invalid shortcut state");
                return;
            }
            const next = {};
            for (let index = 0; index < actionNames.length; index += 1) {
                const name = actionNames[index];
                const value = message.actions[name];
                const launcher = name === "openLauncher";
                if (value === null || typeof value !== "object" || Array.isArray(value) || !exactKeys(
                            value, ["activeShortcut", "preferredShortcut", "preferredConflict"]) ||
                        !(value.activeShortcut === null || (typeof value.activeShortcut
                                                            === "string"
                                                            && value.activeShortcut.length > 0
                                                            && value.activeShortcut.length <= 64))
                        || !(value.preferredShortcut === null || (launcher
                                                                  && value.preferredShortcut
                                                                  === root.preferredShortcut))
                        || typeof value.preferredConflict !== "boolean" || (!launcher && (
                                                                                value.preferredShortcut
                                                                                !== null
                                                                                || value.preferredConflict))
                        || (!message.available && (value.activeShortcut !== null
                                                   || value.preferredConflict))) {
                    warnBounded("invalid shortcut action state");
                    return;
                }
                next[name] = Object.freeze({
                                               "activeShortcut": value.activeShortcut ?? "",
                                               "preferredShortcut": value.preferredShortcut ?? "",
                                               "preferredConflict": value.preferredConflict
                                           });
            }
            state.available = message.available;
            state.actions = Object.freeze(next);
            state.restartAttempts = 0;
            return;
        }
        warnBounded("unknown helper message");
    }

    function clearAvailability() {
        state.available = false;
        state.actions = emptyActions();
    }

    function warnBounded(message) {
        if (state.diagnosticCount >= maximumDiagnostics) {
            return;
        }
        state.diagnosticCount += 1;
        console.warn("Global shortcut adapter: " + message);
    }

    QtObject {
        id: state

        property bool available: false
        property var actions: root.emptyActions()
        property bool startAllowed: false
        property bool destroying: false
        property int restartAttempts: 0
        property int diagnosticCount: 0
    }

    Timer {
        id: restartTimer

        interval: Math.min(5000, 250 * Math.pow(2, Math.min(state.restartAttempts, 5)))
        onTriggered: state.startAllowed = true
    }

    Process {
        id: helper

        command: [root.helperPath]
        running: state.startAllowed && root.helperPath !== ""

        stdout: SplitParser {
            onRead: data => root.acceptLine(data)
        }

        stderr: SplitParser {
            onRead: data => root.warnBounded("helper diagnostic")
        }

        onStarted: root.clearAvailability()
        onExited: function (exitCode, exitStatus) {
            root.clearAvailability();
            if (!state.destroying && root.helperPath !== "") {
                state.restartAttempts += 1;
                state.startAllowed = false;
                restartTimer.restart();
            }
        }
    }

    Component.onCompleted: state.startAllowed = true
    Component.onDestruction: {
        state.destroying = true;
        restartTimer.stop();
        helper.running = false;
        root.clearAvailability();
    }
}

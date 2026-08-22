pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: root

    required property var coordinator
    required property string helperPath

    readonly property bool available: state.available
    readonly property string activeShortcut: state.activeShortcut
    readonly property string preferredShortcut: "Meta+Space"
    readonly property bool preferredConflict: state.preferredConflict
    readonly property bool helperRunning: helper.running

    readonly property int maximumLineLength: 512
    readonly property int maximumDiagnostics: 4

    signal activationReceived

    function exactKeys(message, expected) {
        const keys = Object.keys(message).sort();
        const wanted = expected.slice().sort();
        return JSON.stringify(keys) === JSON.stringify(wanted);
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
            if (!exactKeys(message, ["type", "action"]) || message.action !== "openLauncher") {
                warnBounded("invalid activation");
                return;
            }
            root.activationReceived();
            root.coordinator.openLauncher(null);
            return;
        }
        if (message.type === "state") {
            if (!exactKeys(message, ["type", "available", "activeShortcut", "preferredShortcut",
                                     "preferredConflict"]) || typeof message.available
                    !== "boolean" || !(message.activeShortcut === null || (
                                           typeof message.activeShortcut === "string"
                                           && message.activeShortcut.length > 0
                                           && message.activeShortcut.length <= 64))
                    || message.preferredShortcut !== root.preferredShortcut
                    || typeof message.preferredConflict !== "boolean" || (!message.available && (
                                                                              message.activeShortcut
                                                                              !== null
                                                                              || message.preferredConflict))) {
                warnBounded("invalid shortcut state");
                return;
            }
            state.available = message.available;
            state.activeShortcut = message.activeShortcut ?? "";
            state.preferredConflict = message.preferredConflict;
            state.restartAttempts = 0;
            return;
        }
        warnBounded("unknown helper message");
    }

    function clearAvailability() {
        state.available = false;
        state.activeShortcut = "";
        state.preferredConflict = false;
    }

    function warnBounded(message) {
        if (state.diagnosticCount >= maximumDiagnostics) {
            return;
        }
        state.diagnosticCount += 1;
        console.warn("Launcher shortcut adapter: " + message);
    }

    QtObject {
        id: state

        property bool available: false
        property string activeShortcut: ""
        property bool preferredConflict: false
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

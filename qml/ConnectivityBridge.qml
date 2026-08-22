pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

// Bounded JSON-lines wrapper for the Nagi-owned D-Bus helper. The helper
// contains every NetworkManager and BlueZ object path, property, and error.
Scope {
    id: root

    required property string helperPath
    property bool enabled: true

    readonly property bool ready: state.ready
    readonly property int activeTimerCount: restartTimer.running ? 1 : 0
    readonly property int maximumLineLength: 4096
    readonly property int maximumDiagnostics: 4

    signal snapshotReceived(var snapshot)
    signal fatalFailure

    function setEnabled(adapter, requestId, enabled) {
        return send({
                        "op": "set",
                        "adapter": adapter,
                        "requestId": requestId,
                        "enabled": enabled
                    });
    }

    function send(command) {
        if (!state.ready || !helper.running) {
            return false;
        }
        const line = JSON.stringify(command);
        if (line.length === 0 || line.length > root.maximumLineLength) {
            return false;
        }
        helper.write(line + "\n");
        return true;
    }

    function acceptLine(line) {
        if (typeof line !== "string" || line.length === 0 || line.length > root.maximumLineLength) {
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
        if (message.type === "ready") {
            state.ready = true;
            state.restartAttempts = 0;
            return;
        }
        if (message.type !== "state" || !validAdapterState(message.wifi) || !validAdapterState(
                    message.bluetooth)) {
            warnBounded("invalid helper state");
            return;
        }

        root.snapshotReceived({
                                  "wifi": normalizedAdapterState(message.wifi),
                                  "bluetooth": normalizedAdapterState(message.bluetooth)
                              });
    }

    function normalizedAdapterState(candidate) {
        return {
            "available": candidate.available,
            "enabled": candidate.enabled,
            "hardwareEnabled": candidate.hardwareEnabled,
            "pending": candidate.pending,
            "failure": candidate.failure,
            "requestId": candidate.requestId
        };
    }

    function validAdapterState(candidate) {
        return candidate !== null && typeof candidate === "object" && !Array.isArray(candidate)
                && typeof candidate.available === "boolean" && typeof candidate.enabled
                === "boolean" && typeof candidate.hardwareEnabled === "boolean"
                && typeof candidate.pending === "boolean" && validFailure(candidate.failure)
                && Number.isInteger(candidate.requestId) && candidate.requestId >= 0
                && candidate.requestId <= 2147483647 && (!candidate.available ? !candidate.enabled
                                                                                && !candidate.hardwareEnabled
                                                                                && !candidate.pending :
                                                                                true);
    }

    function validFailure(failure) {
        return failure === "none" || failure === "unavailable" || failure === "hardware" || failure
                === "denied" || failure === "timeout" || failure === "backend";
    }

    function warnBounded(message) {
        if (state.diagnosticCount >= root.maximumDiagnostics) {
            return;
        }
        state.diagnosticCount += 1;
        console.warn("Connectivity bridge: " + message);
    }

    function forwardDiagnostic(message) {
        if (state.diagnosticCount >= root.maximumDiagnostics) {
            return;
        }
        state.diagnosticCount += 1;
        const bounded = typeof message === "string" ? message.slice(0, 256) :
                                                      "invalid helper diagnostic";
        console.warn("Connectivity helper: " + bounded);
    }

    function failBridge() {
        state.ready = false;
        root.fatalFailure();
    }

    onEnabledChanged: {
        if (enabled) {
            state.restartAttempts = 0;
            state.restartAllowed = true;
        } else {
            restartTimer.stop();
            state.restartAllowed = false;
            state.ready = false;
        }
    }

    QtObject {
        id: state

        property bool ready: false
        property bool restartAllowed: true
        property bool destroying: false
        property int restartAttempts: 0
        property int diagnosticCount: 0
    }

    Timer {
        id: restartTimer

        interval: 250 * Math.pow(2, Math.max(0, state.restartAttempts - 1))
        onTriggered: state.restartAllowed = true
    }

    Process {
        id: helper

        command: [root.helperPath]
        stdinEnabled: true
        running: root.enabled && root.helperPath !== "" && state.restartAllowed

        stdout: SplitParser {
            onRead: data => root.acceptLine(data)
        }

        stderr: SplitParser {
            onRead: data => root.forwardDiagnostic(data)
        }

        onStarted: state.ready = false
        onExited: function (exitCode, exitStatus) {
            root.failBridge();
            if (!state.destroying && root.enabled && state.restartAttempts < 3) {
                state.restartAttempts += 1;
                state.restartAllowed = false;
                restartTimer.restart();
            } else {
                state.restartAllowed = false;
            }
        }
    }

    Component.onDestruction: {
        state.destroying = true;
        restartTimer.stop();
        if (helper.running && state.ready) {
            helper.write("{\"op\":\"shutdown\"}\n");
        }
        helper.running = false;
        state.ready = false;
    }
}

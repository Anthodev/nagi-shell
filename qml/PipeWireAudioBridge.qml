pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

// Bounded JSON-lines wrapper for the Nagi-owned libpipewire confirmation
// bridge. Raw PipeWire parameters never cross this boundary.
Scope {
    id: root

    required property string helperPath
    property bool enabled: false

    readonly property bool ready: state.ready
    readonly property int activeTimerCount: restartTimer.running ? 1 : 0
    readonly property int maximumLineLength: 4096
    readonly property int maximumDiagnostics: 4

    signal stateConfirmed(string role, int nodeId, int generation, int requestId, string kind,
                          real volume, bool muted)
    signal roleUnavailable(string role, int generation)
    signal requestFailed(string role, int generation, int requestId, string kind, string reason)
    signal fatalFailure

    function track(role, nodeId, generation) {
        return send({
                        "op": "track",
                        "role": role,
                        "nodeId": nodeId,
                        "generation": generation
                    });
    }

    function untrack(role, generation) {
        return send({
                        "op": "untrack",
                        "role": role,
                        "generation": generation
                    });
    }

    function setVolume(role, nodeId, generation, requestId, value, finalValue) {
        return send({
                        "op": "setVolume",
                        "role": role,
                        "nodeId": nodeId,
                        "generation": generation,
                        "requestId": requestId,
                        "value": value,
                        "final": finalValue
                    });
    }

    function setMute(role, nodeId, generation, requestId, muted) {
        return send({
                        "op": "setMute",
                        "role": role,
                        "nodeId": nodeId,
                        "generation": generation,
                        "requestId": requestId,
                        "muted": muted
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
            warnBounded("invalid bridge line length");
            return;
        }

        let message;
        try {
            message = JSON.parse(line);
        } catch (error) {
            warnBounded("malformed bridge line");
            return;
        }
        if (message === null || typeof message !== "object" || Array.isArray(message)
                || typeof message.type !== "string") {
            warnBounded("invalid bridge message");
            return;
        }

        if (message.type === "ready") {
            state.ready = true;
            state.restartAttempts = 0;
            return;
        }
        if (message.type === "fatal") {
            failBridge();
            return;
        }
        if (message.type === "unavailable") {
            if (validRole(message.role) && validPositiveInteger(message.generation)) {
                root.roleUnavailable(message.role, message.generation);
            } else {
                warnBounded("invalid unavailable message");
            }
            return;
        }
        if (message.type === "failure") {
            if (validRole(message.role) && validPositiveInteger(message.generation)
                    && validPositiveInteger(message.requestId) && validKind(message.kind)) {
                root.requestFailed(message.role, message.generation, message.requestId, message.kind,
                                   "backend");
            } else {
                warnBounded("invalid failure message");
            }
            return;
        }
        if (message.type !== "state" || !validRole(message.role) || !validNodeId(message.nodeId) ||
                !validPositiveInteger(message.generation) || !validNonNegativeInteger(
                    message.requestId) || !validKind(message.kind) || typeof message.volume
                !== "number" || !Number.isFinite(message.volume) || message.volume < 0
                || typeof message.muted !== "boolean") {
            warnBounded("invalid state message");
            return;
        }
        root.stateConfirmed(message.role, message.nodeId, message.generation, message.requestId,
                            message.kind, message.volume, message.muted);
    }

    function validRole(role) {
        return role === "output" || role === "input";
    }

    function validKind(kind) {
        return kind === "external" || kind === "volume" || kind === "mute";
    }

    function validNodeId(value) {
        return Number.isInteger(value) && value >= 0 && value <= 2147483647;
    }

    function validPositiveInteger(value) {
        return Number.isInteger(value) && value > 0 && value <= 2147483647;
    }

    function validNonNegativeInteger(value) {
        return Number.isInteger(value) && value >= 0 && value <= 2147483647;
    }

    function warnBounded(message) {
        if (state.diagnosticCount >= root.maximumDiagnostics) {
            return;
        }
        state.diagnosticCount += 1;
        console.warn("PipeWire audio bridge: " + message);
    }

    function forwardDiagnostic(message) {
        if (state.diagnosticCount >= root.maximumDiagnostics) {
            return;
        }
        state.diagnosticCount += 1;
        const bounded = typeof message === "string" ? message.slice(0, 256) :
                                                      "invalid helper diagnostic";
        console.warn("PipeWire audio helper: " + bounded);
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
        property int restartAttempts: 0
        property int diagnosticCount: 0
        property bool destroying: false
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

pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

// Bounded JSON-lines boundary for the fixed PowerDevil ScreenBrightness helper.
// Raw D-Bus identities, contexts, child names, and property types stay native.
Scope {
    id: root

    required property string helperPath
    property bool enabled: true

    readonly property bool ready: state.ready
    readonly property int activeTimerCount: restartTimer.running ? 1 : 0
    readonly property int maximumLineLength: 32768
    readonly property int maximumDiagnostics: 4
    readonly property int maximumDisplays: 32

    signal snapshotReceived(var snapshot)
    signal fatalFailure

    function setBrightness(requestId, displayKey, ratio) {
        return send({
                        "action": "setBrightness",
                        "requestId": requestId,
                        "displayKey": displayKey,
                        "ratio": ratio
                    });
    }

    function send(command) {
        if (!state.ready || !helper.running) {
            return false;
        }
        const line = JSON.stringify(command);
        if (line.length === 0 || line.length > maximumLineLength) {
            return false;
        }
        helper.write(line + "\n");
        return true;
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
        if (message.type === "ready") {
            state.ready = true;
            state.restartAttempts = 0;
            return;
        }
        const snapshot = normalizeSnapshot(message);
        if (snapshot === null) {
            warnBounded("invalid helper state");
            return;
        }
        root.snapshotReceived(snapshot);
    }

    function normalizeSnapshot(candidate) {
        if (candidate.type !== "state" || typeof candidate.available !== "boolean"
                || typeof candidate.supported !== "boolean" || !Number.isInteger(
                    candidate.generation) || candidate.generation < 0 || candidate.generation
                > 2147483647 || !Array.isArray(candidate.displays) || candidate.displays.length
                > maximumDisplays) {
            return null;
        }
        if (!candidate.available) {
            if (candidate.supported || candidate.generation !== 0 || candidate.displays.length !== 0
                    || candidate.change !== null || candidate.request !== null) {
                return null;
            }
            return unavailableSnapshot();
        }
        if (candidate.generation <= 0 || candidate.supported !== (candidate.displays.length > 0)) {
            return null;
        }

        const displays = [];
        const byKey = {};
        for (let index = 0; index < candidate.displays.length; index += 1) {
            const display = normalizeDisplay(candidate.displays[index], candidate.generation);
            if (display === null || byKey["$" + display.key] !== undefined) {
                return null;
            }
            byKey["$" + display.key] = display;
            displays.push(display);
        }

        const change = normalizeChange(candidate.change, byKey);
        if (candidate.change !== null && change === null) {
            return null;
        }
        const request = normalizeRequest(candidate.request);
        if (candidate.request !== null && request === null) {
            return null;
        }
        return {
            "available": true,
            "supported": displays.length > 0,
            "generation": candidate.generation,
            "displays": displays,
            "change": change,
            "request": request
        };
    }

    function normalizeDisplay(candidate, generation) {
        if (candidate === null || typeof candidate !== "object" || Array.isArray(candidate)
                || typeof candidate.key !== "string" || candidate.key.length === 0 || candidate.key.length
                > 160 || !candidate.key.startsWith(generation + ":") || typeof candidate.label
                !== "string" || candidate.label.length > 128 || typeof candidate.isInternal
                !== "boolean" || typeof candidate.ratio !== "number" || !Number.isFinite(
                    candidate.ratio) || candidate.ratio < 0 || candidate.ratio > 1
                || typeof candidate.pending !== "boolean" || !validFailure(candidate.failure)) {
            return null;
        }
        return {
            "key": candidate.key,
            "label": candidate.label,
            "isInternal": candidate.isInternal,
            "ratio": candidate.ratio,
            "pending": candidate.pending,
            "failure": candidate.failure
        };
    }

    function normalizeChange(candidate, byKey) {
        if (candidate === null) {
            return null;
        }
        if (typeof candidate !== "object" || Array.isArray(candidate) || typeof candidate.key !== "string"
                || byKey["$" + candidate.key] === undefined || typeof candidate.ratio !== "number"
                || !Number.isFinite(candidate.ratio) || candidate.ratio < 0 || candidate.ratio > 1
                || Math.abs(byKey["$" + candidate.key].ratio - candidate.ratio) > 0.000001 || (
                    candidate.origin !== "self" && candidate.origin !== "external"
                    && candidate.origin !== "unknown") || !Number.isInteger(candidate.requestId)
                || candidate.requestId < 0 || candidate.requestId > 2147483647 || (candidate.origin
                                                                                   === "self"
                                                                                   ? candidate.requestId
                                                                                     <= 0 : candidate.requestId
                                                                                     !== 0)) {
            return null;
        }
        return {
            "key": candidate.key,
            "ratio": candidate.ratio,
            "origin": candidate.origin,
            "requestId": candidate.requestId
        };
    }

    function normalizeRequest(candidate) {
        if (candidate === null) {
            return null;
        }
        if (typeof candidate !== "object" || Array.isArray(candidate) || !Number.isInteger(
                    candidate.requestId) || candidate.requestId <= 0 || candidate.requestId
                > 2147483647 || !validOutcome(candidate.outcome)) {
            return null;
        }
        return {
            "requestId": candidate.requestId,
            "outcome": candidate.outcome
        };
    }

    function unavailableSnapshot() {
        return {
            "available": false,
            "supported": false,
            "generation": 0,
            "displays": [],
            "change": null,
            "request": null
        };
    }

    function validFailure(failure) {
        return failure === "none" || failure === "timeout" || failure === "backend" || failure
                === "unavailable";
    }

    function validOutcome(outcome) {
        return outcome === "pending" || outcome === "confirmed" || outcome === "noop" || outcome
                === "busy" || outcome === "stale" || outcome === "invalid" || outcome === "timeout"
                || outcome === "backend" || outcome === "unavailable";
    }

    function warnBounded(message) {
        if (state.diagnosticCount >= maximumDiagnostics) {
            return;
        }
        state.diagnosticCount += 1;
        console.warn("Brightness bridge: " + message);
    }

    function forwardDiagnostic(message) {
        if (state.diagnosticCount >= maximumDiagnostics) {
            return;
        }
        state.diagnosticCount += 1;
        const bounded = typeof message === "string" ? message.slice(0, 256) :
                                                      "invalid helper diagnostic";
        console.warn("Brightness helper: " + bounded);
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
            helper.write("{\"action\":\"shutdown\"}\n");
        }
        helper.running = false;
        state.ready = false;
    }
}

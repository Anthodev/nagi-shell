pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

// Bounded identity-free JSON-lines boundary for the passive GameMode and
// Power Profiles observer. The helper is absent while observer interest is off.
Scope {
    id: root

    required property string helperPath
    property bool enabled: true

    readonly property bool ready: state.ready
    readonly property int activeTimerCount: restartTimer.running ? 1 : 0
    readonly property int maximumLineLength: 4096
    readonly property int maximumDiagnostics: 4
    readonly property int maximumClientCount: 1000000

    signal snapshotReceived(var snapshot)
    signal fatalFailure

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
                || typeof candidate.gameModeAvailable !== "boolean"
                || typeof candidate.powerProfilesAvailable !== "boolean" || !Number.isInteger(
                    candidate.gameClientCount) || candidate.gameClientCount < 0
                || candidate.gameClientCount > maximumClientCount
                || typeof candidate.performanceProfile !== "boolean" || !Number.isInteger(
                    candidate.sourceCount) || candidate.sourceCount < 0 || candidate.sourceCount
                > maximumClientCount + 1 || !validEvent(candidate.event) || candidate.available !== (
                    candidate.gameModeAvailable || candidate.powerProfilesAvailable)
                || candidate.sourceCount !== candidate.gameClientCount + (
                    candidate.performanceProfile ? 1 : 0) || (!candidate.gameModeAvailable
                                                              && candidate.gameClientCount !== 0)
                || (!candidate.powerProfilesAvailable && candidate.performanceProfile)) {
            return null;
        }
        return {
            "available": candidate.available,
            "gameModeAvailable": candidate.gameModeAvailable,
            "powerProfilesAvailable": candidate.powerProfilesAvailable,
            "gameClientCount": candidate.gameClientCount,
            "performanceProfile": candidate.performanceProfile,
            "sourceCount": candidate.sourceCount,
            "event": candidate.event
        };
    }

    function validEvent(event) {
        return event === "snapshot" || event === "registered" || event === "unregistered" || event
                === "profile" || event === "sourceUnavailable";
    }

    function warnBounded(message) {
        if (state.diagnosticCount >= maximumDiagnostics) {
            return;
        }
        state.diagnosticCount += 1;
        console.warn("Gaming performance bridge: " + message);
    }

    function forwardDiagnostic(message) {
        if (state.diagnosticCount >= maximumDiagnostics) {
            return;
        }
        state.diagnosticCount += 1;
        const bounded = typeof message === "string" ? message.slice(0, 192) :
                                                      "invalid helper diagnostic";
        console.warn("Gaming performance helper: " + bounded);
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
        running: root.enabled && root.helperPath !== "" && state.restartAllowed

        stdout: SplitParser {
            onRead: data => root.acceptLine(data)
        }

        stderr: SplitParser {
            onRead: data => root.forwardDiagnostic(data)
        }

        onStarted: state.ready = false
        onExited: {
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
        state.restartAllowed = false;
    }
}

pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: adapter

    required property string helperPath

    readonly property bool available: state.snapshot.available
    readonly property var desktops: state.snapshot.desktops
    readonly property string currentId: state.snapshot.currentId === null ? "" :
                                                                            state.snapshot.currentId
    readonly property string currentName: {
        const current = adapter.currentDesktop();
        return current === null ? "" : current.name;
    }
    readonly property int currentPosition: {
        const current = adapter.currentDesktop();
        return current === null ? -1 : current.position;
    }

    readonly property int maximumLineLength: 65536
    readonly property int maximumDiagnostics: 4

    function acceptSnapshotLine(line) {
        if (typeof line !== "string" || line.length === 0) {
            warnBounded("empty snapshot line");
            return;
        }
        if (line.length > maximumLineLength) {
            warnBounded("oversized snapshot line");
            return;
        }

        let candidate;
        try {
            candidate = JSON.parse(line);
        } catch (error) {
            warnBounded("malformed snapshot line");
            return;
        }

        const normalized = normalizeSnapshot(candidate);
        if (normalized === null) {
            warnBounded("invalid snapshot schema");
            return;
        }

        const serialized = JSON.stringify(normalized);
        if (serialized === state.serializedSnapshot) {
            return;
        }

        state.serializedSnapshot = serialized;
        state.snapshot = normalized;
    }

    function currentDesktop() {
        if (!available) {
            return null;
        }

        for (let index = 0; index < desktops.length; index += 1) {
            if (desktops[index].id === currentId) {
                return desktops[index];
            }
        }

        return null;
    }

    function normalizeSnapshot(candidate) {
        if (candidate === null || typeof candidate !== "object" || Array.isArray(candidate)
                || typeof candidate.available !== "boolean" || !Array.isArray(candidate.desktops)) {
            return null;
        }

        if (!candidate.available) {
            if (candidate.currentId !== null || candidate.desktops.length !== 0) {
                return null;
            }
            return {
                "available": false,
                "currentId": null,
                "desktops": []
            };
        }

        if (typeof candidate.currentId !== "string" || candidate.currentId.length === 0
                || candidate.desktops.length === 0) {
            return null;
        }

        const normalizedDesktops = [];
        const ids = {};
        const positions = {};
        let currentFound = false;
        for (let index = 0; index < candidate.desktops.length; index += 1) {
            const desktop = candidate.desktops[index];
            if (desktop === null || typeof desktop !== "object" || Array.isArray(desktop)
                    || typeof desktop.id !== "string" || desktop.id.length === 0
                    || typeof desktop.name !== "string" || !Number.isInteger(desktop.position)
                    || desktop.position < 0 || desktop.position >= candidate.desktops.length
                    || ids["$" + desktop.id] === true || positions[desktop.position] === true) {
                return null;
            }

            ids["$" + desktop.id] = true;
            positions[desktop.position] = true;
            currentFound = currentFound || desktop.id === candidate.currentId;
            normalizedDesktops.push({
                                        "id": desktop.id,
                                        "name": desktop.name,
                                        "position": desktop.position
                                    });
        }

        if (!currentFound) {
            return null;
        }

        normalizedDesktops.sort((left, right) => left.position - right.position);
        for (let index = 0; index < normalizedDesktops.length; index += 1) {
            if (normalizedDesktops[index].position !== index) {
                return null;
            }
        }

        return {
            "available": true,
            "currentId": candidate.currentId,
            "desktops": normalizedDesktops
        };
    }

    function publishUnavailable() {
        acceptSnapshotLine("{\"available\":false,\"currentId\":null,\"desktops\":[]}");
    }

    function warnBounded(message) {
        if (state.diagnosticCount >= maximumDiagnostics) {
            return;
        }

        state.diagnosticCount += 1;
        console.warn("KWin virtual desktop adapter: " + message);
    }

    function forwardHelperDiagnostic(message) {
        if (state.diagnosticCount >= maximumDiagnostics) {
            return;
        }

        const boundedMessage = typeof message === "string" ? message.slice(0, 256) :
                                                             "invalid helper diagnostic";
        state.diagnosticCount += 1;
        console.warn("KWin virtual desktop helper: " + boundedMessage);
    }

    QtObject {
        id: state

        property int diagnosticCount: 0
        property string serializedSnapshot:
        "{\"available\":false,\"currentId\":null,\"desktops\":[]}"
        property var snapshot: ({
                                    "available": false,
                                    "currentId": null,
                                    "desktops": []
                                })
    }

    Process {
        id: helper

        command: [adapter.helperPath]
        running: true

        stdout: SplitParser {
            onRead: data => adapter.acceptSnapshotLine(data)
        }

        stderr: SplitParser {
            onRead: data => adapter.forwardHelperDiagnostic(data)
        }

        onExited: function (exitCode, exitStatus) {
            adapter.publishUnavailable();
            adapter.warnBounded("helper exited");
        }
    }

    Component.onDestruction: {
        helper.running = false;
        state.snapshot = {
            "available": false,
            "currentId": null,
            "desktops": []
        };
        state.serializedSnapshot = "";
    }
}

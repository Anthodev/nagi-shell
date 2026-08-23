pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

// Normalized JSON-lines boundary for the read-only Plasma wallpaper helper.
// The source path remains internal; presentation consumes only Theme's palette snapshot.
Scope {
    id: bridge

    required property string helperPath

    readonly property int generation: state.generation
    readonly property bool available: state.available
    readonly property string status: state.status
    readonly property string accent: state.accent
    readonly property int activeTimerCount: 0
    QtObject {
        id: state

        readonly property int maximumLineLength: 4096
        readonly property int maximumDiagnostics: 4
        property int generation: 0
        property bool available: false
        property string status: "Unavailable"
        property string imagePath: ""
        property string accent: ""
        property int diagnosticCount: 0

        function acceptSnapshotLine(line) {
            if (typeof line !== "string" || line.length === 0 || line.length > maximumLineLength) {
                warnBounded("invalid snapshot line length");
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
            if (normalized === null || normalized.generation <= generation) {
                if (normalized === null) {
                    warnBounded("invalid snapshot schema");
                }
                return;
            }

            available = normalized.available;
            status = normalized.status;
            imagePath = normalized.imagePath;
            accent = normalized.accent;
            Theme.wallpaperPalette = normalized.available ? Object.freeze({
                                                                              "accent": normalized.accent
                                                                          }) : null;
            generation = normalized.generation;
        }

        function normalizeSnapshot(candidate) {
            if (candidate === null || typeof candidate !== "object" || Array.isArray(candidate) ||
                    !Number.isInteger(candidate.generation) || candidate.generation <= 0
                    || candidate.generation > 2147483647 || typeof candidate.available
                    !== "boolean" || !validStatus(candidate.status) || typeof candidate.imagePath
                    !== "string" || candidate.imagePath.length > 4096 || typeof candidate.accent
                    !== "string") {
                return null;
            }
            if (candidate.available) {
                if (candidate.status !== "Ready" || !candidate.imagePath.startsWith("/") || !
                        /^#[0-9A-F]{6}$/.test(candidate.accent)) {
                    return null;
                }
            } else if (candidate.status === "Ready" || candidate.imagePath !== ""
                       || candidate.accent !== "") {
                return null;
            }
            return {
                "generation": candidate.generation,
                "available": candidate.available,
                "status": candidate.status,
                "imagePath": candidate.imagePath,
                "accent": candidate.accent
            };
        }

        function validStatus(candidateStatus) {
            return candidateStatus === "Ready" || candidateStatus === "UnsupportedPlugin"
                    || candidateStatus === "UnsupportedSource" || candidateStatus === "Missing"
                    || candidateStatus === "Unreadable" || candidateStatus === "Unavailable";
        }

        function publishUnavailable() {
            available = false;
            status = "Unavailable";
            imagePath = "";
            accent = "";
            Theme.wallpaperPalette = null;
        }

        function warnBounded(message) {
            if (diagnosticCount >= maximumDiagnostics) {
                return;
            }
            diagnosticCount += 1;
            console.warn("Wallpaper palette bridge: " + message);
        }
    }

    Process {
        id: helper

        command: [bridge.helperPath]
        running: bridge.helperPath !== ""

        stdout: SplitParser {
            onRead: data => state.acceptSnapshotLine(data)
        }

        stderr: SplitParser {
            onRead: data => state.warnBounded("helper diagnostic suppressed")
        }

        onExited: {
            state.publishUnavailable();
            state.warnBounded("helper exited");
        }
    }

    Component.onDestruction: {
        helper.running = false;
        Theme.wallpaperPalette = null;
    }
}

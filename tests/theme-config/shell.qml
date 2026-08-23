import Quickshell
import Quickshell.Io
import QtQuick
import "qml"

// Exercises the real XDG path and FileView watcher. Process is test-only: it
// creates permission and deletion failures that QML file writes cannot express.
ShellRoot {
    id: test

    property string stage: "default"
    property var preservedSnapshot: null
    property int publishedSnapshots: 0

    function fail(message) {
        console.error("FAIL: " + message + " (stage=" + stage + ")");
        Qt.exit(1);
        throw new Error(message);
    }

    function require(condition, message) {
        if (!condition) {
            fail(message);
        }
    }

    function colorString(value) {
        return String(value).toUpperCase();
    }

    function validateSnapshot(snapshot) {
        require(snapshot !== null && Object.isFrozen(snapshot), "snapshot is a frozen object");
        require(snapshot.mode === "wallpaper" || snapshot.mode === "accent",
                "snapshot mode is bounded");
        require(snapshot.source === "wallpaper" || snapshot.source === "configured"
                || snapshot.source === "fallback", "snapshot source is bounded");
        const roles = ["accent", "accentHover", "accentPressed", "accentForeground", "focusRing",
                       "progressFill", "surfaceHover", "surfaceActive"];
        for (let index = 0; index < roles.length; index += 1) {
            require(/^#[0-9A-F]{6}$/.test(snapshot[roles[index]]), roles[index] + " is published");
        }
        require(snapshot.contrast.accentOnSurface >= 3, "accent meets the non-text floor");
        require(snapshot.contrast.accentForeground >= 4.5,
                "accent foreground meets the text floor");
        require(snapshot.contrast.focusRingOnSurface >= 3, "focus ring meets the non-text floor");
        require(snapshot.contrast.progressOnTrack >= 3, "progress fill meets the non-text floor");
        require(snapshot.contrast.surfaceHoverOnBase >= 1.08, "hover tint meets its state floor");
        require(snapshot.contrast.surfaceActiveOnBase >= 1.16, "active tint meets its state floor");
    }

    function writeFixture(nextStage, content, atomic) {
        stage = nextStage;
        fixtureWriter.atomicWrites = atomic;
        fixtureWriter.setText(content);
    }

    function settle(next) {
        stage = next;
        settleTimer.restart();
    }

    function defaultStage() {
        validateSnapshot(Theme.snapshot);
        require(Theme.configPath === Quickshell.env("XDG_CONFIG_HOME") + "/nagi-shell/theme.conf",
                "theme uses the isolated XDG path");
        require(Theme.snapshot.mode === "wallpaper" && Theme.snapshot.source === "fallback",
                "missing configuration uses wallpaper mode and official fallback");
        require(Theme.snapshot.accent === "#5B6FF5", "official fallback accent is exact");
        require(colorString(Theme.snapshot.accent) === "#5B6FF5",
                "canonical accent resolves dynamically");
        writeFixture("accent-one", "[theme]\nmode=accent\naccent=#FF8A00\n", true);
    }

    function accentOneStage() {
        validateSnapshot(Theme.snapshot);
        require(Theme.snapshot.mode === "accent" && Theme.snapshot.source === "configured",
                "valid accent mode is applied");
        require(Theme.snapshot.configuredAccent === "#FF8A00" && Theme.snapshot.accent === "#FF8A00",
                "valid configured accent is preserved when already accessible");
        require(Theme.snapshot.accentHover !== Theme.snapshot.accent
                && Theme.snapshot.accentPressed !== Theme.snapshot.accent
                && Theme.snapshot.surfaceHover !== Theme.snapshot.surfaceActive,
                "accent family and state surfaces are derived");
        const generation = Theme.snapshot.generation;
        writeFixture("accent-two", "[theme]\nmode=accent\naccent=#CC24C78A\n", true);
        preservedSnapshot = generation;
    }

    function accentTwoStage() {
        validateSnapshot(Theme.snapshot);
        require(Theme.snapshot.generation > preservedSnapshot,
                "hot reload publishes a new generation");
        require(Theme.snapshot.configuredAccent === "#CC24C78A" && Theme.snapshot.source
                === "configured", "eight-digit accent reloads live and remains identified");
        preservedSnapshot = Theme.snapshot;
        writeFixture("malformed-json", "{\"mode\":\"accent\",\"accent\":\n", false);
    }

    function malformedJsonStage() {
        require(Theme.snapshot === preservedSnapshot,
                "malformed JSON preserves the last valid snapshot");
        writeFixture("oversized", "x".repeat(4097), false);
    }

    function oversizedStage() {
        require(Theme.snapshot === preservedSnapshot,
                "oversized configuration preserves the last valid snapshot");
        writeFixture("partial", "[theme]\nmode=accent\naccent=#12", false);
    }

    function partialStage() {
        require(Theme.snapshot === preservedSnapshot,
                "partial write preserves the last valid snapshot");
        writeFixture("partial-recovered", "[theme]\nmode=accent\naccent=#A855F7\n", false);
    }

    function partialRecoveredStage() {
        validateSnapshot(Theme.snapshot);
        require(Theme.snapshot !== preservedSnapshot && Theme.snapshot.configuredAccent
                === "#A855F7", "a completed write recovers without restart");
        preservedSnapshot = Theme.snapshot;
        stage = "unreadable";
        fixtureCommand.command = ["chmod", "000", Theme.configPath];
        fixtureCommand.running = true;
    }

    function unreadableStage() {
        require(Theme.snapshot === preservedSnapshot,
                "unreadable configuration preserves the last valid snapshot");
        stage = "restore-readable";
        fixtureCommand.command = ["chmod", "600", Theme.configPath];
        fixtureCommand.running = true;
    }

    function restoreReadableStage() {
        preservedSnapshot = Theme.snapshot;
        stage = "missing";
        fixtureCommand.command = ["rm", "-f", Theme.configPath];
        fixtureCommand.running = true;
    }

    function missingStage() {
        require(Theme.snapshot === preservedSnapshot,
                "removed configuration preserves the last valid snapshot");
        writeFixture("wallpaper-default", "[theme]\nmode=wallpaper\n", true);
    }

    function wallpaperDefaultStage() {
        validateSnapshot(Theme.snapshot);
        require(Theme.snapshot.mode === "wallpaper" && Theme.snapshot.source === "fallback"
                && Theme.snapshot.accent === "#5B6FF5",
                "wallpaper mode defaults to official fallback");
        writeFixture("wallpaper-configured", "[theme]\nmode=wallpaper\naccent=#FF8A00\n", true);
    }

    function wallpaperConfiguredStage() {
        require(Theme.snapshot.source === "configured" && Theme.snapshot.configuredAccent
                === "#FF8A00", "configured accent is wallpaper mode's first fallback");
        Theme.wallpaperPalette = {
            "accent": "#22D3EE"
        };
        settle("wallpaper-injected");
    }

    function wallpaperInjectedStage() {
        validateSnapshot(Theme.snapshot);
        require(Theme.snapshot.source === "wallpaper" && Theme.snapshot.wallpaperAccent
                === "#22D3EE", "wallpaper accent takes precedence in wallpaper mode");
        Theme.wallpaperPalette = {
            "accent": "#000022"
        };
        settle("wallpaper-unsuitable");
    }

    function wallpaperUnsuitableStage() {
        validateSnapshot(Theme.snapshot);
        require(Theme.snapshot.source === "configured" && Theme.snapshot.wallpaperAccent
                === "#000022" && Theme.snapshot.configuredAccent === "#FF8A00",
                "unsuitable wallpaper derivation falls through to configured accent");
        writeFixture("accent-precedence", "[theme]\nmode=accent\naccent=#F59E0B\n", true);
    }

    function accentPrecedenceStage() {
        validateSnapshot(Theme.snapshot);
        require(Theme.snapshot.mode === "accent" && Theme.snapshot.source === "configured"
                && Theme.snapshot.configuredAccent === "#F59E0B",
                "accent mode ignores an injected wallpaper palette");
        Theme.wallpaperPalette = null;
        require(Theme.snapshot.source === "configured",
                "removing wallpaper input keeps fixed accent mode");
        require(publishedSnapshots >= 7, "all valid changes were observable as atomic snapshots");
        console.log("theme configuration tests passed");
        Qt.exit(0);
    }

    function runSettledStage() {
        switch (stage) {
        case "accent-one":
            accentOneStage();
            break;
        case "accent-two":
            accentTwoStage();
            break;
        case "malformed-json":
            malformedJsonStage();
            break;
        case "oversized":
            oversizedStage();
            break;
        case "partial":
            partialStage();
            break;
        case "partial-recovered":
            partialRecoveredStage();
            break;
        case "unreadable":
            unreadableStage();
            break;
        case "missing":
            missingStage();
            break;
        case "wallpaper-default":
            wallpaperDefaultStage();
            break;
        case "wallpaper-configured":
            wallpaperConfiguredStage();
            break;
        case "wallpaper-injected":
            wallpaperInjectedStage();
            break;
        case "wallpaper-unsuitable":
            wallpaperUnsuitableStage();
            break;
        case "accent-precedence":
            accentPrecedenceStage();
            break;
        default:
            fail("unexpected settled stage");
        }
    }

    Component.onCompleted: Qt.callLater(test.defaultStage)

    Connections {
        target: Theme

        function onSnapshotChanged() {
            test.publishedSnapshots += 1;
            test.validateSnapshot(Theme.snapshot);
        }
    }

    FileView {
        id: fixtureWriter

        path: Theme.configPath
        blockWrites: true
        printErrors: false
        onSaved: test.settle(test.stage)
        onSaveFailed: function (error) {
            test.fail("fixture write failed");
        }
    }

    Process {
        id: fixtureCommand

        onExited: function (exitCode, exitStatus) {
            test.require(exitCode === 0, "fixture command succeeded");
            if (test.stage === "restore-readable") {
                test.restoreReadableStage();
            } else {
                test.settle(test.stage);
            }
        }
    }

    Timer {
        id: settleTimer

        interval: 200
        onTriggered: test.runSettledStage()
    }

    Timer {
        interval: 10000
        running: true
        onTriggered: test.fail("theme configuration test timed out")
    }
}

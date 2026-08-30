pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import "qml"

ShellRoot {
    id: test

    readonly property string epochA: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    readonly property string epochB: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    readonly property string fixtureStem: Quickshell.cacheDir + "/nagi-adapter-" + Date.now()
    readonly property string fixtureScriptPath: fixtureStem + ".py"
    readonly property string fixtureLogPath: fixtureStem + ".log"
    readonly property string fixtureShutdownPath: fixtureStem + ".shutdown"

    property int workspaceChangeCount: 0
    property int workspaceInvalidationCount: 0
    property string lastSourceToken: ""
    property int lastSourceGeneration: 0
    property int lastRevision: 0
    property bool protocolComplete: false

    property string lifecycleStage: "setup"
    property int lifecycleAvailableCount: 0
    property int lifecycleUnavailableCount: 0
    property int lifecycleChangeCount: 0
    property int lifecycleInvalidationCount: 0

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function snapshotLine(epoch, currentId, showTransient, desktops) {
        return JSON.stringify({
                                  "version": 1,
                                  "helperEpoch": epoch,
                                  "available": true,
                                  "currentId": currentId,
                                  "showTransient": showTransient,
                                  "desktops": desktops
                              });
    }

    function unavailableLine(epoch) {
        return JSON.stringify({
                                  "version": 1,
                                  "helperEpoch": epoch,
                                  "available": false,
                                  "currentId": null,
                                  "showTransient": false,
                                  "desktops": []
                              });
    }

    function fixtureScript() {
        return `#!/usr/bin/env python3
import json
import pathlib
import signal
import sys
import time

script = pathlib.Path(__file__)
counter_path = script.with_suffix(".count")
log_path = script.with_suffix(".log")
marker_path = script.with_suffix(".shutdown")

try:
    launch = int(counter_path.read_text(encoding="utf-8")) + 1
except (FileNotFoundError, ValueError):
    launch = 1

counter_path.write_text(str(launch), encoding="utf-8")
with log_path.open("a", encoding="utf-8") as stream:
    stream.write(f"{launch} {time.monotonic():.6f}\\n")

def snapshot(epoch):
    return {
        "version": 1,
        "helperEpoch": epoch,
        "available": True,
        "currentId": "first",
        "showTransient": False,
        "desktops": [
            {"id": "first", "name": "Desktop 1", "position": 0},
            {"id": "second", "name": "Desktop 2", "position": 1},
        ],
    }

def unavailable(epoch):
    return {
        "version": 1,
        "helperEpoch": epoch,
        "available": False,
        "currentId": None,
        "showTransient": False,
        "desktops": [],
    }

def publish(message):
    sys.stdout.write(json.dumps(message, separators=(",", ":")) + "\\n")
    sys.stdout.flush()

def publish_ready(epoch):
    sys.stderr.write(json.dumps({
        "event": "ready",
        "helperEpoch": epoch,
        "version": 1,
    }, separators=(",", ":")) + "\\n")
    sys.stderr.flush()

epoch = f"{launch:032x}"
publish(unavailable(epoch))
if launch == 1:
    publish_ready("not-an-epoch")
    while True:
        time.sleep(1)

if launch == 2:
    time.sleep(0.1)
    raise SystemExit(1)

if launch == 3:
    publish_ready(epoch)
    publish(snapshot(epoch))
    time.sleep(0.1)
    raise SystemExit(1)

if launch in (4, 5, 6):
    time.sleep(0.02)
    raise SystemExit(1)

shutdown_reason = "eof"
def handle_sigterm(signum, frame):
    global shutdown_reason
    shutdown_reason = "sigterm"
    raise SystemExit(0)

signal.signal(signal.SIGTERM, handle_sigterm)
publish_ready(epoch)
publish(snapshot(epoch))
try:
    for line in sys.stdin:
        if line == '{"op":"shutdown"}\\n':
            shutdown_reason = "shutdown"
            break
finally:
    marker_path.write_text(f"{shutdown_reason}\\nexit\\n", encoding="utf-8")
`;
    }

    function runProtocolTests() {
        const firstDesktop = {
            "id": "first",
            "name": "Desktop 1",
            "position": 0
        };
        const secondDesktop = {
            "id": "second",
            "name": "Desktop 2",
            "position": 1
        };
        const initial = snapshotLine(epochA, "first", false, [secondDesktop, firstDesktop]);

        const malformedEpochs = ["", "a".repeat(31), "a".repeat(33),
                                 "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                                 "gggggggggggggggggggggggggggggggg", 7];
        for (let index = 0; index < malformedEpochs.length; index += 1) {
            adapter.acceptSnapshotLine(unavailableLine(malformedEpochs[index]));
        }
        const wrongVersion = JSON.parse(unavailableLine(epochA));
        wrongVersion.version = 2;
        adapter.acceptSnapshotLine(JSON.stringify(wrongVersion));
        adapter.acceptSnapshotLine("not json");
        adapter.acceptSnapshotLine("{\"version\":1");
        adapter.acceptSnapshotLine("x".repeat(adapter.maximumLineLength + 1));
        require(!adapter.available,
                "malformed versions, epochs, JSON, and line bounds preserve unavailable state");

        adapter.acceptSnapshotLine(initial);
        require(adapter.available && adapter.desktops.length === 2 && adapter.desktops[0].id
                === "first", "valid shared state is ordered and available");
        require(adapter.currentId === "first" && adapter.currentName === "Desktop 1"
                && adapter.currentPosition === 0, "shared current desktop resolves coherently");
        require(workspaceChangeCount === 0 && adapter.resolveTransient(adapter.transientSourceToken,
                                                                       1, 1) === null,
                "startup synchronization never creates a transient");

        adapter.acceptSnapshotLine(snapshotLine(epochB, "second", true, [firstDesktop,
                                                                         secondDesktop]));
        require(adapter.currentId === "first", "a different live helper epoch is rejected");

        const outputTopLevel = JSON.parse(snapshotLine(epochA, "second", true, [firstDesktop,
                                                                                secondDesktop]));
        outputTopLevel.outputName = "DP-1";
        adapter.acceptSnapshotLine(JSON.stringify(outputTopLevel));
        const outputDesktop = JSON.parse(snapshotLine(epochA, "second", true, [firstDesktop,
                                                                               secondDesktop]));
        outputDesktop.desktops[0].outputId = "forbidden";
        adapter.acceptSnapshotLine(JSON.stringify(outputDesktop));
        require(adapter.currentId === "first",
                "output-related fields are rejected at every wire level");

        const oversizedId = "i".repeat(1025);
        adapter.acceptSnapshotLine(snapshotLine(epochA, oversizedId, false, [
                                                    {
                                                        "id": oversizedId,
                                                        "name": "Bounded",
                                                        "position": 0
                                                    }
                                                ]));
        adapter.acceptSnapshotLine(snapshotLine(epochA, "first", false, [
                                                    {
                                                        "id": "first",
                                                        "name": "n".repeat(257),
                                                        "position": 0
                                                    }
                                                ]));
        const tooManyDesktops = [];
        for (let index = 0; index < 257; index += 1) {
            tooManyDesktops.push({
                                     "id": "desktop-" + index,
                                     "name": "Desktop",
                                     "position": index
                                 });
        }
        adapter.acceptSnapshotLine(snapshotLine(epochA, "desktop-0", false, tooManyDesktops));
        adapter.acceptSnapshotLine(snapshotLine(epochA, "first", false, [
                                                    {
                                                        "id": "first",
                                                        "name": "Desktop 1",
                                                        "position": 1
                                                    },
                                                    {
                                                        "id": "second",
                                                        "name": "Desktop 2",
                                                        "position": 1
                                                    }
                                                ]));
        require(adapter.currentId === "first" && adapter.desktops.length === 2,
                "ID, name, count, and dense-position bounds reject atomically");

        adapter.acceptSnapshotLine(snapshotLine(epochA, "second", false, [firstDesktop,
                                                                          secondDesktop]));
        require(adapter.currentId === "second" && workspaceChangeCount === 0
                && workspaceInvalidationCount === 1,
                "non-transient shared change invalidates stale feedback once");

        adapter.acceptSnapshotLine(snapshotLine(epochA, "first", true, [firstDesktop,
                                                                        secondDesktop]));
        require(workspaceChangeCount === 1 && lastSourceToken === "workspace-current"
                && lastSourceGeneration === 1 && lastRevision === 3,
                "one confirmed shared switch publishes one scoped revision");
        const switched = adapter.resolveTransient(lastSourceToken, lastSourceGeneration,
                                                  lastRevision);
        require(switched !== null && switched.primary === "Desktop 1" && switched.detail
                === "Current desktop" && switched.value === "1 / 2",
                "exact confirmed revision resolves its presentation");

        const renamedFirst = {
            "id": "first",
            "name": "Focus",
            "position": 0
        };
        adapter.acceptSnapshotLine(snapshotLine(epochA, "first", false, [renamedFirst,
                                                                         secondDesktop]));
        require(workspaceChangeCount === 1 && workspaceInvalidationCount === 2
                && adapter.resolveTransient(lastSourceToken, 1, 4) === null,
                "non-transient metadata change retires the prior presentation");

        adapter.acceptSnapshotLine(unavailableLine(epochA));
        require(!adapter.available && adapter.desktops.length === 0 && adapter.currentId === ""
                && adapter.currentName === "" && adapter.currentPosition === -1,
                "canonical divergence suppresses the shared projection globally");
        require(workspaceInvalidationCount === 3,
                "global unavailability invalidates the source exactly once");
        adapter.acceptSnapshotLine(unavailableLine(epochA));
        require(workspaceInvalidationCount === 3,
                "duplicate unavailable snapshots create no signal storm");

        adapter.acceptSnapshotLine(initial);
        require(adapter.available && workspaceChangeCount === 1 && workspaceInvalidationCount === 3,
                "reconvergence starts a fresh generation without replay");
        require(adapter.resolveTransient(adapter.transientSourceToken, 2, 1) === null,
                "recovery revision is not transient-resolvable");
        adapter.acceptSnapshotLine(snapshotLine(epochA, "second", true, [firstDesktop,
                                                                         secondDesktop]));
        require(workspaceChangeCount === 2 && lastSourceGeneration === 2 && lastRevision === 2,
                "post-recovery switch uses a fresh generation at revision two");
        protocolComplete = true;
    }

    function parseLaunchLog(contents) {
        const stripped = contents.trim();
        if (stripped === "")
            return [];
        const lines = stripped.split("\n");
        const records = [];
        for (let index = 0; index < lines.length; index += 1) {
            const columns = lines[index].trim().split(/\s+/);
            records.push({
                             "launch": Number(columns[0]),
                             "time": Number(columns[1])
                         });
        }
        return records;
    }

    function requireDelay(records, rightIndex, minimum, maximum, label) {
        const delay = records[rightIndex].time - records[rightIndex - 1].time;
        require(delay >= minimum && delay <= maximum, label + " delay stays bounded (observed "
                + delay + " seconds)");
    }

    function verifyLifecycle(records) {
        require(records.length === 6,
                "finite recovery exhausts after one live and five terminating launches");
        for (let index = 0; index < records.length; index += 1) {
            require(records[index].launch === index + 1 && Number.isFinite(records[index].time),
                    "lifecycle launch log is ordered and finite");
        }
        requireDelay(records, 1, 2.1, 3.5, "live pre-ready watchdog plus 250 ms restart");
        requireDelay(records, 2, 0.4, 1.3, "second pre-ready 500 ms restart");
        requireDelay(records, 3, 0.28, 0.9, "genuine-readiness reset to 250 ms");
        requireDelay(records, 4, 0.43, 1.3, "post-ready 500 ms restart");
        requireDelay(records, 5, 0.85, 2.0, "post-ready 1000 ms restart");
        require(lifecycleAvailableCount === 1 && lifecycleUnavailableCount === 1,
                "startup unavailable placeholders never reset or become available");
        require(lifecycleChangeCount === 0 && lifecycleInvalidationCount === 1,
                "ready recovery invalidates once and pre-ready exhaustion stays unavailable");
    }

    Timer {
        id: protocolTimer
        interval: 50
        onTriggered: test.runProtocolTests()
    }

    Timer {
        id: lifecycleCheckTimer
        interval: 7000
        onTriggered: {
            test.lifecycleStage = "verify-exhaustion";
            lifecycleLog.reload();
        }
    }

    Timer {
        id: destructionDestroyTimer
        interval: 40
        onTriggered: {
            destructionLoader.active = false;
            test.lifecycleStage = "verify-destruction";
            destructionCheckTimer.start();
        }
    }

    Timer {
        id: destructionCheckTimer
        interval: 50
        onTriggered: destructionMarker.reload()
    }

    Timer {
        id: destructionTimeout
        interval: 1500
        onTriggered: test.require(false, "destruction helper did not publish a valid line")
    }

    FileView {
        id: fixtureScriptWriter
        path: test.fixtureScriptPath
        atomicWrites: true
        printErrors: false
        onSaved: fixtureChmod.running = true
        onSaveFailed: function (error) {
            test.require(false, "could not write lifecycle helper fixture");
        }
    }

    FileView {
        id: destructionMarker
        path: test.fixtureShutdownPath
        printErrors: false
        onLoaded: {
            if (test.lifecycleStage !== "verify-destruction") {
                return;
            }
            const records = text().trim().split("\n");
            if (records.length !== 2
                    || (records[0] !== "shutdown" && records[0] !== "eof"
                        && records[0] !== "sigterm") || records[1] !== "exit") {
                destructionCheckTimer.restart();
                return;
            }
            destructionTimeout.stop();
            lifecycleLog.reload();
        }
        onLoadFailed: function (error) {
            if (test.lifecycleStage === "verify-destruction")
                destructionCheckTimer.restart();
        }
    }

    FileView {
        id: lifecycleLog
        path: test.fixtureLogPath
        printErrors: false
        onLoaded: {
            const records = test.parseLaunchLog(text());
            if (test.lifecycleStage === "verify-exhaustion") {
                test.verifyLifecycle(records);
                lifecycleLoader.active = false;
                test.lifecycleStage = "destruction-live";
                destructionLoader.active = true;
                destructionTimeout.start();
                return;
            }
            if (test.lifecycleStage === "verify-destruction") {
                test.require(records.length === 7 && records[6].launch === 7,
                             "destruction creates no replacement helper");
                test.require(test.protocolComplete,
                             "protocol and lifecycle contracts both completed");
                console.warn("adapter boundary and lifecycle tests passed");
                Qt.exit(0);
            }
        }
        onLoadFailed: function (error) {
            if (test.lifecycleStage === "verify-exhaustion" || test.lifecycleStage
                    === "verify-destruction")
                test.require(false, "could not read lifecycle launch log");
        }
    }

    Process {
        id: fixtureChmod
        command: ["chmod", "0700", test.fixtureScriptPath]
        onExited: function (exitCode, exitStatus) {
            test.require(exitCode === 0, "could not make lifecycle helper executable");
            test.lifecycleStage = "lifecycle-live";
            lifecycleLoader.active = true;
            lifecycleCheckTimer.start();
        }
    }

    KWinVirtualDesktopAdapter {
        id: adapter
        helperPath: "/usr/bin/cat"
        onConfirmedWorkspaceChanged: function (sourceToken, sourceGeneration, revision) {
            test.workspaceChangeCount += 1;
            test.lastSourceToken = sourceToken;
            test.lastSourceGeneration = sourceGeneration;
            test.lastRevision = revision;
        }
        onConfirmedWorkspaceInvalidated: function (sourceToken, sourceGeneration) {
            test.workspaceInvalidationCount += 1;
        }
    }

    Loader {
        id: lifecycleLoader
        active: false
        sourceComponent: Component {
            KWinVirtualDesktopAdapter {
                helperPath: test.fixtureScriptPath
                onAvailableChanged: {
                    if (available)
                    test.lifecycleAvailableCount += 1;
                    else
                    test.lifecycleUnavailableCount += 1;
                }
                onConfirmedWorkspaceChanged: function (sourceToken, sourceGeneration, revision) {
                    test.lifecycleChangeCount += 1;
                }
                onConfirmedWorkspaceInvalidated: function (sourceToken, sourceGeneration) {
                    test.lifecycleInvalidationCount += 1;
                }
            }
        }
    }

    Loader {
        id: destructionLoader
        active: false
        sourceComponent: Component {
            KWinVirtualDesktopAdapter {
                helperPath: test.fixtureScriptPath
                onAvailableChanged: {
                    if (available && test.lifecycleStage === "destruction-live") {
                        destructionTimeout.stop();
                        destructionDestroyTimer.start();
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        fixtureScriptWriter.setText(test.fixtureScript());
        protocolTimer.start();
    }
}

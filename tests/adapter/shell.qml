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
    property var lastSourceToken: null
    property var lastOutputToken: null
    property var lastInvalidatedSourceToken: null
    property int lastInvalidatedSourceGeneration: 0
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

    function snapshotLine(epoch, desktops, outputs) {
        return JSON.stringify({
                                  "version": 2,
                                  "helperEpoch": epoch,
                                  "desktops": desktops,
                                  "outputs": outputs
                              });
    }

    function unavailableLine(epoch) {
        return snapshotLine(epoch, [], []);
    }

    function output(name, currentId, showTransient) {
        return {
            "name": name,
            "currentId": currentId,
            "showTransient": showTransient
        };
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
        "version": 2,
        "helperEpoch": epoch,
        "desktops": [
            {"id": "first", "name": "Desktop 1", "position": 0},
            {"id": "second", "name": "Desktop 2", "position": 1},
        ],
        "outputs": [
            {"name": "Lifecycle-1", "currentId": "first", "showTransient": False},
        ],
    }

def unavailable(epoch):
    return {
        "version": 2,
        "helperEpoch": epoch,
        "desktops": [],
        "outputs": [],
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
        const thirdDesktop = {
            "id": "third",
            "name": "Desktop 3",
            "position": 2
        };
        const desktops = [thirdDesktop, firstDesktop, secondDesktop];
        const initialOutputs = [output("Panel-A", "first", false),
                                output("Panel-B", "second", false),
                                output("Panel-C", "third", false)];
        const initial = snapshotLine(epochA, desktops, initialOutputs);

        const unavailable = adapter.projectionFor(screenA);
        require(adapter.outputCount === 0 && adapter.desktopCount === 0 && !unavailable.available
                && unavailable.currentId === "" && unavailable.currentPosition === -1
                && unavailable.desktops.length === 0 && adapter.outputTokenFor(screenA) === null,
                "canonical startup exposes one output-local unavailable projection");

        const malformedEpochs = ["", "a".repeat(31), "a".repeat(33),
                                 "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                                 "gggggggggggggggggggggggggggggggg", 7];
        for (let index = 0; index < malformedEpochs.length; index += 1) {
            adapter.acceptSnapshotLine(unavailableLine(malformedEpochs[index]));
        }
        const wrongVersion = JSON.parse(unavailableLine(epochA));
        wrongVersion.version = 1;
        adapter.acceptSnapshotLine(JSON.stringify(wrongVersion));
        adapter.acceptSnapshotLine("not json");
        adapter.acceptSnapshotLine("{\"version\":2");
        adapter.acceptSnapshotLine("x".repeat(adapter.maximumLineLength + 1));
        require(adapter.outputCount === 0,
                "malformed versions, epochs, JSON, and line bounds preserve unavailable state");

        adapter.acceptSnapshotLine(initial);
        const projectionA = adapter.projectionFor(screenA);
        const projectionB = adapter.projectionFor(screenB);
        const projectionC = adapter.projectionFor(screenC);
        const projectionKeys = Object.keys(projectionA).sort().join(",");
        require(adapter.outputCount === 3 && adapter.desktopCount === 3
                && projectionA.available && projectionA.currentId === "first"
                && projectionA.currentPosition === 0 && projectionB.currentId === "second"
                && projectionB.currentPosition === 1 && projectionC.currentId === "third"
                && projectionC.currentPosition === 2
                && projectionA.desktops[0].id === "first"
                && projectionA.desktops === projectionB.desktops
                && projectionKeys === "available,currentId,currentName,currentPosition,desktops",
                "three divergent outputs expose exact normalized screen-local projections");
        const outputTokenA = adapter.outputTokenFor(screenA);
        const outputTokenB = adapter.outputTokenFor(screenB);
        const outputTokenC = adapter.outputTokenFor(screenC);
        require(outputTokenA !== null && outputTokenB !== null && outputTokenC !== null
                && outputTokenA !== outputTokenB && outputTokenA !== outputTokenC
                && outputTokenB !== outputTokenC && outputTokenA !== "Panel-A"
                && String(outputTokenA).indexOf("Panel-A") === -1
                && projectionA.outputName === undefined && projectionA.name === undefined,
                "projection and output-token APIs never expose raw output identity");
        require(workspaceChangeCount === 0 && workspaceInvalidationCount === 0
                && adapter.resolveTransient("Panel-A", 1, 1) === null,
                "startup synchronization never creates feedback");

        adapter.acceptSnapshotLine(snapshotLine(epochB, desktops, [
                                                    output("Panel-A", "second", true),
                                                    output("Panel-B", "second", false),
                                                    output("Panel-C", "third", false)
                                                ]));
        require(adapter.projectionFor(screenA).currentId === "first",
                "a different live helper epoch is rejected");

        const invalidPayloads = [];
        const extraTopLevel = JSON.parse(initial);
        extraTopLevel.available = true;
        invalidPayloads.push(extraTopLevel);
        invalidPayloads.push({
                                 "version": 1,
                                 "helperEpoch": epochA,
                                 "available": true,
                                 "currentId": "first",
                                 "showTransient": false,
                                 "desktops": desktops
                             });
        invalidPayloads.push({
                                 "version": 2,
                                 "helperEpoch": epochA,
                                 "desktops": desktops,
                                 "outputs": []
                             });
        const outputExtraField = JSON.parse(initial);
        outputExtraField.outputs[0].connector = "forbidden";
        invalidPayloads.push(outputExtraField);
        invalidPayloads.push({
                                 "version": 2,
                                 "helperEpoch": epochA,
                                 "desktops": desktops,
                                 "outputs": [output("Panel-A", "first", false),
                                             output("Panel-A", "second", false)]
                             });
        invalidPayloads.push({
                                 "version": 2,
                                 "helperEpoch": epochA,
                                 "desktops": desktops,
                                 "outputs": [output("Panel-A", "missing", false)]
                             });
        invalidPayloads.push({
                                 "version": 2,
                                 "helperEpoch": epochA,
                                 "desktops": desktops,
                                 "outputs": [output("Panel-A", "second", true),
                                             output("Panel-B", "third", true)]
                             });
        const tooManyOutputs = [];
        for (let index = 0; index < 65; index += 1) {
            tooManyOutputs.push(output("Panel-" + index, "first", false));
        }
        invalidPayloads.push({
                                 "version": 2,
                                 "helperEpoch": epochA,
                                 "desktops": desktops,
                                 "outputs": tooManyOutputs
                             });
        invalidPayloads.push({
                                 "version": 2,
                                 "helperEpoch": epochA,
                                 "desktops": [{
                                         "id": "first",
                                         "name": "Desktop 1",
                                         "position": 1
                                     }, {
                                         "id": "second",
                                         "name": "Desktop 2",
                                         "position": 1
                                     }],
                                 "outputs": [output("Panel-A", "first", false)]
                             });
        for (let index = 0; index < invalidPayloads.length; index += 1) {
            adapter.acceptSnapshotLine(JSON.stringify(invalidPayloads[index]));
        }
        require(adapter.outputCount === 3 && adapter.projectionFor(screenA) === projectionA
                && adapter.outputTokenFor(screenB) === outputTokenB
                && workspaceChangeCount === 0 && workspaceInvalidationCount === 0,
                "exact v2 keys, bounds, references, and single-feedback rules reject atomically");

        const renamedThird = {
            "id": "third",
            "name": "Focus",
            "position": 2
        };
        const renamedDesktops = [secondDesktop, renamedThird, firstDesktop];
        adapter.acceptSnapshotLine(snapshotLine(epochA, renamedDesktops, [
                                                    output("Panel-C", "third", false),
                                                    output("Panel-A", "first", false),
                                                    output("Panel-B", "second", false)
                                                ]));
        require(adapter.projectionFor(screenC).currentName === "Focus"
                && adapter.projectionFor(screenA).desktops[2].name === "Focus"
                && adapter.outputTokenFor(screenA) === outputTokenA
                && adapter.outputTokenFor(screenB) === outputTokenB
                && adapter.outputTokenFor(screenC) === outputTokenC
                && workspaceChangeCount === 0 && workspaceInvalidationCount === 0,
                "desktop structure and output order refresh every projection silently");

        adapter.acceptSnapshotLine(snapshotLine(epochA, renamedDesktops, [
                                                    output("Panel-C", "third", false),
                                                    output("Panel-A", "first", false),
                                                    output("Panel-B", "third", true)
                                                ]));
        require(workspaceChangeCount === 1 && workspaceInvalidationCount === 0
                && lastOutputToken === outputTokenB && lastSourceToken !== "Panel-B"
                && String(lastSourceToken).indexOf("Panel-B") === -1
                && lastSourceGeneration === 1 && lastRevision === 3
                && adapter.projectionFor(screenA).currentId === "first"
                && adapter.projectionFor(screenB).currentId === "third"
                && adapter.projectionFor(screenC).currentId === "third",
                "only the genuinely changed feedback output emits its opaque identity");
        const firstLifecycleSourceToken = lastSourceToken;
        const switched = adapter.resolveTransient(lastSourceToken, lastSourceGeneration,
                                                  lastRevision);
        require(switched !== null && switched.primary === "Focus" && switched.detail
                === "Current desktop" && switched.value === "3 / 3"
                && adapter.resolveTransient(lastSourceToken, 2, lastRevision) === null
                && adapter.resolveTransient(lastSourceToken, 1, lastRevision - 1) === null
                && adapter.resolveTransient(outputTokenB, 1, lastRevision) === null,
                "only the exact opaque source generation and revision resolve feedback");

        adapter.acceptSnapshotLine(snapshotLine(epochA, renamedDesktops, [
                                                    output("Panel-A", "first", false),
                                                    output("Panel-B", "third", false),
                                                    output("Panel-C", "third", true)
                                                ]));
        require(workspaceChangeCount === 1 && workspaceInvalidationCount === 0
                && adapter.resolveTransient(firstLifecycleSourceToken, 1, 3) === switched,
                "showTransient without a real output change neither emits nor rewrites feedback");

        const structurallyRenamedThird = {
            "id": "third",
            "name": "Deep Focus",
            "position": 2
        };
        const structurallyChangedDesktops = [secondDesktop, structurallyRenamedThird, firstDesktop];
        adapter.acceptSnapshotLine(snapshotLine(epochA, structurallyChangedDesktops, [
                                                    output("Panel-C", "third", false),
                                                    output("Panel-A", "first", false),
                                                    output("Panel-B", "third", false)
                                                ]));
        require(workspaceChangeCount === 1 && workspaceInvalidationCount === 1
                && lastInvalidatedSourceToken === firstLifecycleSourceToken
                && lastInvalidatedSourceGeneration === 1
                && adapter.projectionFor(screenB).currentName === "Deep Focus"
                && adapter.resolveTransient(firstLifecycleSourceToken, 1, 3) === null,
                "silent structural projection changes invalidate and unresolve retained feedback");

        adapter.acceptSnapshotLine(snapshotLine(epochA, structurallyChangedDesktops, [
                                                    output("Panel-A", "second", false),
                                                    output("Panel-C", "third", false)
                                                ]));
        require(adapter.outputCount === 2 && !adapter.projectionFor(screenB).available
                && adapter.outputTokenFor(screenB) === null
                && adapter.outputTokenFor(screenA) === outputTokenA
                && adapter.outputTokenFor(screenC) === outputTokenC
                && workspaceInvalidationCount === 2
                && lastInvalidatedSourceToken === firstLifecycleSourceToken
                && adapter.resolveTransient(firstLifecycleSourceToken, 1, 3) === null,
                "removing one output invalidates only its opaque source and leaves peers live");
        adapter.acceptSnapshotLine(snapshotLine(epochA, structurallyChangedDesktops, [
                                                    output("Panel-A", "second", false),
                                                    output("Panel-C", "third", false)
                                                ]));
        require(workspaceInvalidationCount === 2,
                "duplicate output-removal snapshots create no invalidation storm");

        adapter.acceptSnapshotLine(snapshotLine(epochA, structurallyChangedDesktops, [
                                                    output("Panel-A", "second", false),
                                                    output("Panel-B", "second", true),
                                                    output("Panel-C", "third", false)
                                                ]));
        const replacementOutputTokenB = adapter.outputTokenFor(screenB);
        require(adapter.outputCount === 3 && adapter.projectionFor(screenB).currentId === "second"
                && replacementOutputTokenB !== null && replacementOutputTokenB !== outputTokenB
                && workspaceChangeCount === 1 && workspaceInvalidationCount === 2,
                "hotplug recovery uses a fresh opaque output token without replaying feedback");
        adapter.acceptSnapshotLine(snapshotLine(epochA, structurallyChangedDesktops, [
                                                    output("Panel-A", "second", false),
                                                    output("Panel-B", "first", true),
                                                    output("Panel-C", "third", false)
                                                ]));
        require(workspaceChangeCount === 2 && lastOutputToken === replacementOutputTokenB
                && lastSourceToken === firstLifecycleSourceToken && lastSourceGeneration === 2
                && lastRevision === 2
                && adapter.resolveTransient(firstLifecycleSourceToken, 1, 3) === null
                && adapter.resolveTransient(lastSourceToken, 2, 2) !== null,
                "recovered output advances only its source generation and rejects stale tuples");

        const preUnavailableTokenA = adapter.outputTokenFor(screenA);
        const preUnavailableTokenB = adapter.outputTokenFor(screenB);
        const preUnavailableTokenC = adapter.outputTokenFor(screenC);
        adapter.acceptSnapshotLine(unavailableLine(epochA));
        require(adapter.outputCount === 0 && adapter.desktopCount === 0
                && !adapter.projectionFor(screenA).available
                && !adapter.projectionFor(screenB).available
                && !adapter.projectionFor(screenC).available
                && adapter.outputTokenFor(screenA) === null
                && workspaceInvalidationCount === 5,
                "canonical helper unavailability invalidates each live output independently");
        adapter.acceptSnapshotLine(unavailableLine(epochA));
        require(workspaceInvalidationCount === 5,
                "duplicate canonical unavailability is idempotent");

        adapter.acceptSnapshotLine(initial);
        require(adapter.outputCount === 3 && workspaceChangeCount === 2
                && workspaceInvalidationCount === 5
                && adapter.outputTokenFor(screenA) !== preUnavailableTokenA
                && adapter.outputTokenFor(screenB) !== preUnavailableTokenB
                && adapter.outputTokenFor(screenC) !== preUnavailableTokenC,
                "helper recovery rebuilds fresh output identities without feedback replay");
        adapter.acceptSnapshotLine(snapshotLine(epochA, desktops, [
                                                    output("Panel-A", "first", false),
                                                    output("Panel-B", "second", false),
                                                    output("Panel-C", "second", true)
                                                ]));
        require(workspaceChangeCount === 3 && lastSourceGeneration === 2 && lastRevision === 2
                && lastOutputToken === adapter.outputTokenFor(screenC),
                "peer recovery generation and revision advance independently");
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

    QtObject {
        id: screenA
        readonly property string name: "Panel-A"
    }

    QtObject {
        id: screenB
        readonly property string name: "Panel-B"
    }

    QtObject {
        id: screenC
        readonly property string name: "Panel-C"
    }

    KWinVirtualDesktopAdapter {
        id: adapter
        helperPath: "/usr/bin/cat"
        onConfirmedWorkspaceChanged: function (sourceToken, sourceGeneration, revision,
                                               outputToken) {
            test.workspaceChangeCount += 1;
            test.lastSourceToken = sourceToken;
            test.lastSourceGeneration = sourceGeneration;
            test.lastRevision = revision;
            test.lastOutputToken = outputToken;
        }
        onConfirmedWorkspaceInvalidated: function (sourceToken, sourceGeneration) {
            test.workspaceInvalidationCount += 1;
            test.lastInvalidatedSourceToken = sourceToken;
            test.lastInvalidatedSourceGeneration = sourceGeneration;
        }
    }

    Loader {
        id: lifecycleLoader
        active: false
        sourceComponent: Component {
            KWinVirtualDesktopAdapter {
                helperPath: test.fixtureScriptPath
                onOutputCountChanged: {
                    if (outputCount > 0)
                    test.lifecycleAvailableCount += 1;
                    else
                    test.lifecycleUnavailableCount += 1;
                }
                onConfirmedWorkspaceChanged: function (sourceToken, sourceGeneration, revision,
                                                       outputToken) {
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
                onOutputCountChanged: {
                    if (outputCount > 0 && test.lifecycleStage === "destruction-live") {
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

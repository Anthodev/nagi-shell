pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: adapter

    required property string helperPath
    readonly property var helper: state.helperController === null ? null :
                                                                    state.helperController.helperProcess

    readonly property int desktopCount: state.snapshot.desktops.length
    readonly property int outputCount: state.records.length

    signal confirmedWorkspaceChanged(var sourceToken, int sourceGeneration, int revision,
                                     var outputToken)
    signal confirmedWorkspaceInvalidated(var sourceToken, int sourceGeneration)

    readonly property int maximumLineLength: 65536
    readonly property int maximumDiagnostics: 4
    readonly property int maximumDesktopCount: 256
    readonly property int maximumOutputCount: 64
    readonly property int maximumSourceVersion: 2147483647
    readonly property int maximumRetiredHelperEpochs: 16
    readonly property int maximumRetiredOutputSources: 64
    readonly property string helperReadyEvent: "ready"
    readonly property int helperReadinessTimeoutMs: 2000

    function exactKeys(candidate, expected) {
        const keys = Object.keys(candidate);
        if (keys.length !== expected.length) {
            return false;
        }
        for (let index = 0; index < expected.length; index += 1) {
            if (!Object.prototype.hasOwnProperty.call(candidate, expected[index])) {
                return false;
            }
        }
        return true;
    }

    function validHelperEpoch(value) {
        return typeof value === "string" && /^[0-9a-f]{32}$/.test(value);
    }
    function markHelperReady() {
        readinessWatchdog.stop();
        if (state.processReady) {
            return;
        }
        state.processReady = true;
        state.restartAttempts = 0;
    }

    function acceptHelperStderrLine(line) {
        if (!state.acceptingLines || helper === null || !helper.running) {
            return;
        }

        let candidate;
        try {
            candidate = JSON.parse(line);
        } catch (error) {
            if (typeof line === "string" && line.indexOf("\"event\":\"ready\"") !== -1) {
                warnBounded("invalid helper readiness");
            } else {
                forwardHelperDiagnostic(line);
            }
            return;
        }

        if (candidate === null || typeof candidate !== "object" || Array.isArray(candidate)
                || candidate.event !== helperReadyEvent) {
            forwardHelperDiagnostic(line);
            return;
        }
        if (!exactKeys(candidate, ["version", "event", "helperEpoch"]) || candidate.version !== 1 ||
                !validHelperEpoch(candidate.helperEpoch)) {
            warnBounded("invalid helper readiness");
            return;
        }

        const epochKey = "$" + candidate.helperEpoch;
        if (state.retiredHelperEpochs[epochKey] === true) {
            warnBounded("retired helper readiness");
            return;
        }
        if (state.activeHelperEpoch === "") {
            state.pendingReadyEpoch = candidate.helperEpoch;
            return;
        }
        if (state.activeHelperEpoch !== candidate.helperEpoch) {
            warnBounded("unexpected helper readiness");
            return;
        }
        markHelperReady();
    }
    function startHelperIfAllowed() {
        if (state.helperController !== null && !state.destroying && state.startAllowed && helperPath
                !== "") {
            state.helperController.helperPath = helperPath;
            state.helperController.shouldRun = true;
        }
    }

    function handleHelperStarted() {
        state.acceptingLines = true;
        state.processReady = false;
        state.pendingReadyEpoch = "";
        readinessWatchdog.restart();
    }

    function handleHelperReadinessTimeout() {
        if (state.destroying || state.processReady || helper === null || !helper.running) {
            return;
        }

        state.acceptingLines = false;
        retireActiveHelperEpoch();
        publishUnavailable();
        warnBounded("helper readiness timed out");
        helper.signal(9);
    }

    function acceptSnapshotLine(line) {
        // SplitParser emits an unterminated tail while Process is finishing. At
        // that point Process.running is already false, so the retired process
        // cannot promote a partial final record into live state.
        if (!state.acceptingLines || helper === null || !helper.running) {
            return;
        }
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

        if (!stageSnapshot(candidate)) {
            warnBounded("invalid snapshot schema");
            return;
        }
        const envelope = state.pendingEnvelope;
        state.pendingEnvelope = null;

        if (state.activeHelperEpoch === "") {
            if (state.retiredHelperEpochs["$" + envelope.helperEpoch] === true) {
                warnBounded("retired helper epoch");
                return;
            }
            state.activeHelperEpoch = envelope.helperEpoch;
            if (state.pendingReadyEpoch !== "") {
                const pendingEpoch = state.pendingReadyEpoch;
                state.pendingReadyEpoch = "";
                if (pendingEpoch !== state.activeHelperEpoch) {
                    warnBounded("unexpected helper readiness");
                } else {
                    markHelperReady();
                }
            }
        } else if (state.activeHelperEpoch !== envelope.helperEpoch) {
            warnBounded("unexpected helper epoch");
            return;
        }

        const normalized = envelope.snapshot;
        const serialized = JSON.stringify(normalized);
        if (serialized === state.serializedSnapshot) {
            return;
        }

        applySnapshot(normalized, serialized);
    }

    function recordIndexForName(records, name) {
        for (let index = 0; index < records.length; index += 1) {
            if (records[index].name === name) {
                return index;
            }
        }
        return -1;
    }

    function recordIndexForScreen(records, screen) {
        if (screen === null || screen === undefined || typeof screen.name !== "string"
                || screen.name.length === 0 || screen.name.length > 256) {
            return -1;
        }
        return recordIndexForName(records, screen.name);
    }

    function projectionFor(screen) {
        const index = recordIndexForScreen(state.records, screen);
        return index < 0 ? state.unavailableProjection : state.records[index].projection;
    }

    function outputTokenFor(screen) {
        const index = recordIndexForScreen(state.records, screen);
        return index < 0 ? null : state.records[index].outputToken;
    }

    function resolveTransient(sourceToken, sourceGeneration, revision) {
        for (let index = 0; index < state.records.length; index += 1) {
            const record = state.records[index];
            const retained = record.presentation;
            if (record.sourceToken === sourceToken && record.sourceGeneration === sourceGeneration
                    && record.revision === revision && retained !== null
                    && retained.sourceGeneration === sourceGeneration && retained.revision
                    === revision) {
                return retained.value;
            }
        }
        return null;
    }

    function desktopListsEqual(left, right) {
        if (left.length !== right.length) {
            return false;
        }
        for (let index = 0; index < left.length; index += 1) {
            if (left[index].id !== right[index].id || left[index].name !== right[index].name
                    || left[index].position !== right[index].position) {
                return false;
            }
        }
        return true;
    }

    function projectionForOutput(desktops, output) {
        for (let index = 0; index < desktops.length; index += 1) {
            const desktop = desktops[index];
            if (desktop.id === output.currentId) {
                return Object.freeze({
                                         "available": true,
                                         "currentId": desktop.id,
                                         "currentName": desktop.name,
                                         "currentPosition": desktop.position,
                                         "desktops": desktops
                                     });
            }
        }
        return state.unavailableProjection;
    }

    function presentationFor(projection) {
        if (!projection.available) {
            return null;
        }
        const boundedName = projection.currentName.slice(0, 256).trim();
        return Object.freeze({
                                 "iconName": "preferences-desktop-virtual-symbolic",
                                 "primary": boundedName === "" ? qsTr("Workspace") : boundedName,
                                 "detail": qsTr("Current desktop"),
                                 "value": (projection.currentPosition + 1) + " / "
                                          + projection.desktops.length
                             });
    }

    function nextOpaqueToken(kind) {
        state.nextOpaqueIdentity += 1;
        return "workspace-" + kind + "-" + state.nextOpaqueIdentity;
    }

    function retiredSourceIndexForName(retiredSources, name) {
        for (let index = 0; index < retiredSources.length; index += 1) {
            if (retiredSources[index].name === name) {
                return index;
            }
        }
        return -1;
    }

    function retainSource(retiredSources, record) {
        const next = [];
        for (let index = 0; index < retiredSources.length; index += 1) {
            if (retiredSources[index].name !== record.name) {
                next.push(retiredSources[index]);
            }
        }
        next.push(Object.freeze({
                                    "name": record.name,
                                    "sourceGeneration": record.sourceGeneration,
                                    "sourceToken": record.sourceToken
                                }));
        while (next.length > maximumRetiredOutputSources) {
            next.shift();
        }
        return next;
    }

    function applySnapshot(normalized, serialized) {
        const previousSnapshot = state.snapshot;
        const previousRecords = state.records;
        const sharedDesktopsUnchanged = desktopListsEqual(previousSnapshot.desktops,
                                                          normalized.desktops);
        const consumedPrevious = [];
        const nextRecords = [];
        const changes = [];
        const invalidations = [];
        let retiredSources = state.retiredSources.slice();

        for (let index = 0; index < normalized.outputs.length; index += 1) {
            const output = normalized.outputs[index];
            const previousIndex = recordIndexForName(previousRecords, output.name);
            if (previousIndex >= 0) {
                consumedPrevious[previousIndex] = true;
                const previous = previousRecords[previousIndex];
                const currentChanged = previous.projection.currentId !== output.currentId;
                const projectionChanged = currentChanged || !sharedDesktopsUnchanged;
                const confirmedTransient = output.showTransient && currentChanged;
                const projection = projectionChanged ? projectionForOutput(normalized.desktops,
                                                                           output) : previous.projection;
                let sourceGeneration = previous.sourceGeneration;
                let sourceToken = previous.sourceToken;
                let revision = previous.revision;
                let presentation = previous.presentation;
                if (projectionChanged) {
                    if (revision < maximumSourceVersion) {
                        revision += 1;
                    } else {
                        invalidations.push(Object.freeze({
                                                             "sourceGeneration":
                                                             previous.sourceGeneration,
                                                             "sourceToken": previous.sourceToken
                                                         }));
                        sourceGeneration = previous.sourceGeneration < maximumSourceVersion
                                ? previous.sourceGeneration + 1 : 1;
                        sourceToken = previous.sourceGeneration < maximumSourceVersion
                                ? previous.sourceToken : nextOpaqueToken("source");
                        revision = 1;
                        presentation = null;
                    }
                    if (!confirmedTransient && presentation !== null) {
                        invalidations.push(Object.freeze({
                                                             "sourceGeneration":
                                                             previous.sourceGeneration,
                                                             "sourceToken": previous.sourceToken
                                                         }));
                        presentation = null;
                    }
                }
                if (confirmedTransient) {
                    presentation = Object.freeze({
                                                     "revision": revision,
                                                     "sourceGeneration": sourceGeneration,
                                                     "value": presentationFor(projection)
                                                 });
                }
                const record = Object.freeze({
                                                 "name": output.name,
                                                 "outputToken": previous.outputToken,
                                                 "presentation": presentation,
                                                 "projection": projection,
                                                 "revision": revision,
                                                 "sourceGeneration": sourceGeneration,
                                                 "sourceToken": sourceToken
                                             });
                nextRecords.push(record);
                if (confirmedTransient) {
                    changes.push(record);
                }
                continue;
            }

            const retiredIndex = retiredSourceIndexForName(retiredSources, output.name);
            let sourceGeneration = 1;
            let sourceToken = null;
            if (retiredIndex >= 0) {
                const retired = retiredSources[retiredIndex];
                retiredSources.splice(retiredIndex, 1);
                if (retired.sourceGeneration < maximumSourceVersion) {
                    sourceGeneration = retired.sourceGeneration + 1;
                    sourceToken = retired.sourceToken;
                }
            }
            if (sourceToken === null) {
                sourceToken = nextOpaqueToken("source");
            }
            nextRecords.push(Object.freeze({
                                               "name": output.name,
                                               "outputToken": nextOpaqueToken("output"),
                                               "presentation": null,
                                               "projection": projectionForOutput(normalized.desktops,
                                                                                 output),
                                               "revision": 1,
                                               "sourceGeneration": sourceGeneration,
                                               "sourceToken": sourceToken
                                           }));
        }

        for (let index = 0; index < previousRecords.length; index += 1) {
            if (consumedPrevious[index] === true) {
                continue;
            }
            const removed = previousRecords[index];
            invalidations.push(Object.freeze({
                                                 "sourceGeneration": removed.sourceGeneration,
                                                 "sourceToken": removed.sourceToken
                                             }));
            retiredSources = retainSource(retiredSources, removed);
        }

        state.serializedSnapshot = serialized;
        state.snapshot = normalized;
        state.records = Object.freeze(nextRecords);
        state.retiredSources = Object.freeze(retiredSources);

        for (let index = 0; index < invalidations.length; index += 1) {
            const invalidation = invalidations[index];
            adapter.confirmedWorkspaceInvalidated(invalidation.sourceToken,
                                                  invalidation.sourceGeneration);
        }
        for (let index = 0; index < changes.length; index += 1) {
            const change = changes[index];
            adapter.confirmedWorkspaceChanged(change.sourceToken, change.sourceGeneration,
                                              change.revision, change.outputToken);
        }
    }

    function stageSnapshot(candidate) {
        state.pendingEnvelope = null;
        if (candidate === null || typeof candidate !== "object" || Array.isArray(candidate) ||
                !exactKeys(candidate, ["version", "helperEpoch", "desktops", "outputs"])
                || candidate.version !== 2 || !validHelperEpoch(candidate.helperEpoch) ||
                !Array.isArray(candidate.desktops) || !Array.isArray(candidate.outputs)) {
            return false;
        }

        if (candidate.desktops.length === 0 || candidate.outputs.length === 0) {
            if (candidate.desktops.length !== 0 || candidate.outputs.length !== 0) {
                return false;
            }
            state.pendingEnvelope = Object.freeze({
                                                      "helperEpoch": candidate.helperEpoch,
                                                      "snapshot": Object.freeze({
                                                                                    "desktops":
                                                                                    Object.freeze(
                                                                                        []),
                                                                                    "outputs":
                                                                                    Object.freeze(
                                                                                        [])
                                                                                })
                                                  });
            return true;
        }
        if (candidate.desktops.length > maximumDesktopCount || candidate.outputs.length
                > maximumOutputCount) {
            return false;
        }

        const normalizedDesktops = [];
        const ids = {};
        const positions = {};
        for (let index = 0; index < candidate.desktops.length; index += 1) {
            const desktop = candidate.desktops[index];
            if (desktop === null || typeof desktop !== "object" || Array.isArray(desktop) || !exactKeys(desktop,
                                                                                                        ["id", "name",
                                                                                                         "position"])
                    || typeof desktop.id !== "string" || desktop.id.length === 0
                    || desktop.id.length > 1024 || typeof desktop.name !== "string"
                    || desktop.name.length > 256 || !Number.isInteger(desktop.position)
                    || desktop.position < 0 || desktop.position >= candidate.desktops.length
                    || ids["$" + desktop.id] === true || positions["$" + desktop.position]
                    === true) {

                return false;
            }
            ids["$" + desktop.id] = true;
            positions["$" + desktop.position] = true;
            normalizedDesktops.push(Object.freeze({
                                                      "id": desktop.id,
                                                      "name": desktop.name,
                                                      "position": desktop.position
                                                  }));
        }
        normalizedDesktops.sort((left, right) => left.position - right.position);
        for (let index = 0; index < normalizedDesktops.length; index += 1) {
            if (normalizedDesktops[index].position !== index) {
                return false;
            }
        }
        const frozenDesktops = Object.freeze(normalizedDesktops);

        const normalizedOutputs = [];
        const names = {};
        let transientSeen = false;
        for (let index = 0; index < candidate.outputs.length; index += 1) {
            const output = candidate.outputs[index];
            if (output === null || typeof output !== "object" || Array.isArray(output) || !exactKeys(
                        output, ["name", "currentId", "showTransient"]) || typeof output.name
                    !== "string" || output.name.length === 0 || output.name.length > 256
                    || typeof output.currentId !== "string" || output.currentId.length === 0
                    || output.currentId.length > 1024 || typeof output.showTransient !== "boolean"
                    || names["$" + output.name] === true || ids["$" + output.currentId] !== true || (
                        output.showTransient && transientSeen)) {
                return false;
            }
            names["$" + output.name] = true;
            transientSeen = transientSeen || output.showTransient;
            normalizedOutputs.push(Object.freeze({
                                                     "name": output.name,
                                                     "currentId": output.currentId,
                                                     "showTransient": output.showTransient
                                                 }));
        }

        state.pendingEnvelope = Object.freeze({
                                                  "helperEpoch": candidate.helperEpoch,
                                                  "snapshot": Object.freeze({
                                                                                "desktops":
                                                                                frozenDesktops,
                                                                                "outputs":
                                                                                Object.freeze(
                                                                                    normalizedOutputs)
                                                                            })
                                              });
        return true;
    }

    function publishUnavailable() {
        const serialized = "{\"desktops\":[],\"outputs\":[]}";
        if (serialized === state.serializedSnapshot) {
            return;
        }
        applySnapshot(Object.freeze({
                                        "desktops": Object.freeze([]),
                                        "outputs": Object.freeze([])
                                    }), serialized);
    }

    function retireActiveHelperEpoch() {
        readinessWatchdog.stop();
        if (state.activeHelperEpoch !== "") {
            const retired = Object.assign({}, state.retiredHelperEpochs);
            const order = state.retiredHelperEpochOrder.slice();
            const key = "$" + state.activeHelperEpoch;
            retired[key] = true;
            order.push(key);
            if (order.length > maximumRetiredHelperEpochs) {
                delete retired[order.shift()];
            }
            state.retiredHelperEpochs = retired;
            state.retiredHelperEpochOrder = order;
        }
        state.activeHelperEpoch = "";
        state.pendingReadyEpoch = "";
        state.processReady = false;
    }

    function handleHelperExit() {
        readinessWatchdog.stop();
        state.acceptingLines = false;
        retireActiveHelperEpoch();
        publishUnavailable();
        state.startAllowed = false;

        if (!state.destroying && helperPath !== "" && state.restartAttempts < 3) {
            state.restartAttempts += 1;
            restartTimer.restart();
        } else {
            restartTimer.stop();
        }

        if (!state.destroying) {
            warnBounded("helper exited");
        }
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

        state.diagnosticCount += 1;
        console.warn("KWin virtual desktop helper: diagnostic received");
    }

    QtObject {
        id: state

        property bool acceptingLines: false
        property bool destroying: false
        property bool processReady: false
        property bool startAllowed: true
        property int diagnosticCount: 0
        property int restartAttempts: 0
        property double nextOpaqueIdentity: 0
        property string activeHelperEpoch: ""
        property string pendingReadyEpoch: ""
        property var helperController: null
        property var pendingEnvelope: null
        property var retiredHelperEpochs: ({})
        property var retiredHelperEpochOrder: []
        property var records: Object.freeze([])
        property var retiredSources: Object.freeze([])
        property string serializedSnapshot: "{\"desktops\":[],\"outputs\":[]}"
        property var snapshot: Object.freeze({
                                                 "desktops": Object.freeze([]),
                                                 "outputs": Object.freeze([])
                                             })
        property var unavailableProjection: Object.freeze({
                                                              "available": false,
                                                              "currentId": "",
                                                              "currentName": "",
                                                              "currentPosition": -1,
                                                              "desktops": Object.freeze([])
                                                          })
    }

    Timer {
        id: readinessWatchdog

        interval: adapter.helperReadinessTimeoutMs
        repeat: false
        onTriggered: adapter.handleHelperReadinessTimeout()
    }

    Timer {
        id: restartTimer

        interval: state.restartAttempts === 1 ? 250 : state.restartAttempts === 2 ? 500 : 1000
        repeat: false
        onTriggered: {
            if (!state.destroying && adapter.helperPath !== "") {
                state.startAllowed = true;
                adapter.startHelperIfAllowed();
            }
        }
    }

    Component {
        id: helperControllerComponent

        QtObject {
            id: controller

            required property var owner
            required property string helperPath
            property bool shouldRun: false
            property bool shuttingDown: false

            function finishTeardown() {
                gracefulShutdownTimer.stop();
                forcedShutdownTimer.stop();
                shouldRun = false;
                Qt.callLater(() => controller.destroy());
            }

            function beginShutdown() {
                if (shuttingDown) {
                    return;
                }
                shuttingDown = true;
                owner = null;
                if (!helperProcess.running) {
                    finishTeardown();
                    return;
                }

                helperProcess.write("{\"op\":\"shutdown\"}\n");
                helperProcess.stdinEnabled = false;
                gracefulShutdownTimer.start();
            }

            property Process helperProcess: Process {
                command: [controller.helperPath]
                stdinEnabled: true
                running: controller.shouldRun

                stdout: SplitParser {
                    onRead: data => {
                        if (controller.owner !== null)
                            controller.owner.acceptSnapshotLine(data);
                    }
                }

                stderr: SplitParser {
                    onRead: data => {
                        if (controller.owner !== null)
                            controller.owner.acceptHelperStderrLine(data);
                    }
                }

                onStarted: {
                    if (controller.owner !== null)
                    controller.owner.handleHelperStarted();
                }
                onExited: function (exitCode, exitStatus) {
                    const notifyOwner = controller.shouldRun && !controller.shuttingDown;
                    controller.shouldRun = false;
                    if (controller.shuttingDown) {
                        controller.finishTeardown();
                    } else if (notifyOwner && controller.owner !== null) {
                        controller.owner.handleHelperExit();
                    }
                }
                onRunningChanged: {
                    // Quickshell does not emit exited() when QProcess fails to start.
                    if (!running && controller.shouldRun && !controller.shuttingDown) {
                        controller.shouldRun = false;
                        if (controller.owner !== null)
                        controller.owner.handleHelperExit();
                    }
                }
            }

            property Timer gracefulShutdownTimer: Timer {
                interval: 250
                repeat: false
                onTriggered: {
                    if (!controller.helperProcess.running) {
                        controller.finishTeardown();
                        return;
                    }
                    controller.helperProcess.signal(15);
                    controller.forcedShutdownTimer.start();
                }
            }

            property Timer forcedShutdownTimer: Timer {
                interval: 5000
                repeat: false
                onTriggered: {
                    if (controller.helperProcess.running)
                    controller.helperProcess.signal(9);
                    else
                    controller.finishTeardown();
                }
            }
        }
    }

    Component.onCompleted: {
        const controller = helperControllerComponent.createObject(Quickshell, {
                                                                      "owner": adapter,
                                                                      "helperPath":
                                                                      adapter.helperPath
                                                                  });
        if (controller === null) {
            state.startAllowed = false;
            warnBounded("helper controller creation failed");
            return;
        }
        state.helperController = controller;
        startHelperIfAllowed();
    }

    Component.onDestruction: {
        state.destroying = true;
        state.acceptingLines = false;
        state.startAllowed = false;
        restartTimer.stop();
        readinessWatchdog.stop();
        retireActiveHelperEpoch();
        publishUnavailable();
        const controller = state.helperController;
        state.helperController = null;
        if (controller !== null)
        controller.beginShutdown();
    }
}

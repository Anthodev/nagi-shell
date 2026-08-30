pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: adapter

    required property string helperPath
    readonly property var helper: state.helperController === null ? null :
                                                                    state.helperController.helperProcess

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
    readonly property string transientSourceToken: "workspace-current"

    signal confirmedWorkspaceChanged(string sourceToken, int sourceGeneration, int revision)
    signal confirmedWorkspaceInvalidated(string sourceToken, int sourceGeneration)

    readonly property int maximumLineLength: 65536
    readonly property int maximumDiagnostics: 4
    readonly property int maximumRetiredHelperEpochs: 16
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

        const envelope = normalizeSnapshot(candidate);
        if (envelope === null) {
            warnBounded("invalid snapshot schema");
            return;
        }

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
    function resolveTransient(sourceToken, sourceGeneration, revision) {
        if (!available || sourceToken !== transientSourceToken || sourceGeneration
                !== state.sourceGeneration || revision !== state.revision || state.presentation
                === null) {
            return null;
        }
        return state.presentation;
    }

    function applySnapshot(normalized, serialized) {
        const previous = state.snapshot;
        const previousProjection = projectionFor(previous);
        const nextProjection = projectionFor(normalized);
        state.serializedSnapshot = serialized;
        state.snapshot = normalized;

        if (!normalized.available) {
            if (previous.available) {
                adapter.confirmedWorkspaceInvalidated(transientSourceToken, state.sourceGeneration);
            }
            state.presentation = null;
            state.revision = 0;
            return;
        }

        if (!previous.available) {
            state.sourceGeneration += 1;
            state.revision = 1;
            state.presentation = null;
            return;
        }
        if (projectionEquals(previousProjection, nextProjection)) {
            return;
        }

        state.revision += 1;
        if (normalized.showTransient) {
            state.presentation = presentationFor(nextProjection);
            adapter.confirmedWorkspaceChanged(transientSourceToken, state.sourceGeneration,
                                              state.revision);
        } else {
            state.presentation = null;
            adapter.confirmedWorkspaceInvalidated(transientSourceToken, state.sourceGeneration);
        }
    }

    function projectionFor(snapshot) {
        if (!snapshot.available) {
            return null;
        }
        for (let index = 0; index < snapshot.desktops.length; index += 1) {
            const desktop = snapshot.desktops[index];
            if (desktop.id === snapshot.currentId) {
                return {
                    "id": desktop.id,
                    "name": desktop.name,
                    "position": desktop.position,
                    "count": snapshot.desktops.length
                };
            }
        }
        return null;
    }

    function projectionEquals(left, right) {
        return left !== null && right !== null && left.id === right.id && left.name === right.name
                && left.position === right.position && left.count === right.count;
    }

    function presentationFor(projection) {
        if (projection === null) {
            return null;
        }
        const boundedName = projection.name.slice(0, 256).trim();
        return {
            "iconName": "preferences-desktop-virtual-symbolic",
            "primary": boundedName === "" ? qsTr("Workspace") : boundedName,
            "detail": qsTr("Current desktop"),
            "value": (projection.position + 1) + " / " + projection.count
        };
    }

    function normalizeSnapshot(candidate) {
        if (candidate === null || typeof candidate !== "object" || Array.isArray(candidate) ||
                !exactKeys(candidate, ["version", "helperEpoch", "available", "currentId",
                                       "showTransient", "desktops"]) || candidate.version !== 1 ||
                !validHelperEpoch(candidate.helperEpoch) || typeof candidate.available
                !== "boolean" || typeof candidate.showTransient !== "boolean" || !Array.isArray(
                    candidate.desktops)) {
            return null;
        }

        if (!candidate.available) {
            if (candidate.currentId !== null || candidate.desktops.length !== 0
                    || candidate.showTransient) {
                return null;
            }
            return {
                "helperEpoch": candidate.helperEpoch,
                "snapshot": {
                    "available": false,
                    "currentId": null,
                    "showTransient": false,
                    "desktops": []
                }
            };
        }

        if (typeof candidate.currentId !== "string" || candidate.currentId.length === 0
                || candidate.currentId.length > 1024 || candidate.desktops.length === 0
                || candidate.desktops.length > 256) {
            return null;
        }

        const normalizedDesktops = [];
        const ids = {};
        const positions = {};
        let currentFound = false;
        for (let index = 0; index < candidate.desktops.length; index += 1) {
            const desktop = candidate.desktops[index];
            if (desktop === null || typeof desktop !== "object" || Array.isArray(desktop) || !exactKeys(desktop,
                                                                                                        ["id", "name",
                                                                                                         "position"])
                    || typeof desktop.id !== "string" || desktop.id.length === 0
                    || desktop.id.length > 1024 || typeof desktop.name !== "string"
                    || desktop.name.length > 256 || !Number.isInteger(desktop.position)
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
            "helperEpoch": candidate.helperEpoch,
            "snapshot": {
                "available": true,
                "currentId": candidate.currentId,
                "showTransient": candidate.showTransient,
                "desktops": normalizedDesktops
            }
        };
    }

    function publishUnavailable() {
        const serialized
              = "{\"available\":false,\"currentId\":null,\"showTransient\":false,\"desktops\":[]}";
        if (serialized === state.serializedSnapshot) {
            return;
        }
        applySnapshot({
                          "available": false,
                          "currentId": null,
                          "showTransient": false,
                          "desktops": []
                      }, serialized);
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

        const boundedMessage = typeof message === "string" ? message.slice(0, 256) :
                                                             "invalid helper diagnostic";
        state.diagnosticCount += 1;
        console.warn("KWin virtual desktop helper: " + boundedMessage);
    }

    QtObject {
        id: state

        property bool acceptingLines: false
        property bool destroying: false
        property bool processReady: false
        property bool startAllowed: true
        property int diagnosticCount: 0
        property int restartAttempts: 0
        property int sourceGeneration: 0
        property int revision: 0
        property string activeHelperEpoch: ""
        property string pendingReadyEpoch: ""
        property var helperController: null
        property var retiredHelperEpochs: ({})
        property var retiredHelperEpochOrder: []
        property var presentation: null
        property string serializedSnapshot:
        "{\"available\":false,\"currentId\":null,\"showTransient\":false,\"desktops\":[]}"
        property var snapshot: ({
                                    "available": false,
                                    "currentId": null,
                                    "showTransient": false,
                                    "desktops": []
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
        state.presentation = null;
    }
}

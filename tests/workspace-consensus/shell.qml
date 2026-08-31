import Quickshell
import Quickshell.Io
import QtQuick
import "qml"

ShellRoot {
    id: test

    readonly property string helperPath: Quickshell.env("NAGI_WORKSPACE_HELPER")
    readonly property string controllerPath: Quickshell.env("NAGI_WORKSPACE_CONTROLLER")
    readonly property int expectedOutputs: Number(Quickshell.env("KWIN_TEST_OUTPUTS") || "1")
    readonly property string pluginName: "nagi-workspace-projection-test-controller"
    readonly property var unknownOutputToken: Object.freeze({})
    readonly property string currentRename: "Nagi Current Renamed"
    readonly property string nonCurrentRename: "Nagi Non-current Renamed"
    readonly property string retiredRename: "Nagi Retired Renamed"
    readonly property string replacementName: "Nagi Replacement"
    readonly property string replacementRename: "Nagi Replacement Renamed"

    property string stage: "await-initial"
    property int attempts: 0
    property int controllerScriptId: -1
    property int workspaceChangeCount: 0
    property int workspaceInvalidationCount: 0
    property int changesAtDivergence: 0
    property int changesAtSharedSwitch: 0
    property int invalidationsAtSharedSwitch: 0
    property int desktopCountBeforeRemoval: 0
    property int probeSerial: 0
    property string firstId: ""
    property string switchedId: ""
    property string replacementId: ""
    property var affectedScreen: null
    property var affectedSurfaceToken: null
    property var affectedOutputToken: null
    property var obsoleteSourceToken: null
    property int obsoleteSourceGeneration: 0
    property int obsoleteRevision: 0
    property var lastWorkspaceChange: null
    property var lastWorkspaceInvalidation: null
    property bool finishing: false

    function fail(message) {
        console.error("FAIL: " + message + " (stage=" + stage + ")");
        Qt.exit(1);
        throw new Error(message);
    }

    function require(condition, message) {
        if (!condition) {
            fail(message);
            return false;
        }
        return true;
    }

    function setStage(nextStage) {
        stage = nextStage;
        attempts = 0;
    }

    function awaitState(condition, message) {
        if (condition) {
            attempts = 0;
            return true;
        }
        attempts += 1;
        if (attempts > 1000) {
            fail(message);
        }
        return false;
    }

    function exactKeys(object, expected) {
        return object !== null && typeof object === "object" && !Array.isArray(object)
                && JSON.stringify(Object.keys(object).sort())
                === JSON.stringify(expected.slice().sort());
    }

    function registryRecordForScreen(screen) {
        for (let index = 0; index < host.registry.length; index += 1) {
            if (host.registry[index].screen === screen) {
                return host.registry[index];
            }
        }
        return null;
    }

    function projectionRecords() {
        const records = [];
        for (let index = 0; index < Quickshell.screens.length; index += 1) {
            const screen = Quickshell.screens[index];
            records.push({
                             "screen": screen,
                             "projection": adapter.projectionFor(screen),
                             "outputToken": adapter.outputTokenFor(screen),
                             "registry": registryRecordForScreen(screen)
                         });
        }
        return records;
    }

    function desktops() {
        if (Quickshell.screens.length === 0) {
            return [];
        }
        return adapter.projectionFor(Quickshell.screens[0]).desktops;
    }

    function desktopById(id) {
        const values = desktops();
        for (let index = 0; index < values.length; index += 1) {
            if (values[index].id === id) {
                return values[index];
            }
        }
        return null;
    }

    function desktopByName(name) {
        const values = desktops();
        for (let index = 0; index < values.length; index += 1) {
            if (values[index].name === name) {
                return values[index];
            }
        }
        return null;
    }

    function recordsNotCurrent(id) {
        const changed = [];
        const records = projectionRecords();
        for (let index = 0; index < records.length; index += 1) {
            if (records[index].projection.currentId !== id) {
                changed.push(records[index]);
            }
        }
        return changed;
    }

    function allOutputsCurrent(id) {
        const records = projectionRecords();
        if (records.length !== expectedOutputs) {
            return false;
        }
        for (let index = 0; index < records.length; index += 1) {
            if (!records[index].projection.available || records[index].projection.currentId !== id) {
                return false;
            }
        }
        return true;
    }

    function allOwners(ownerName) {
        if (host.registry.length !== expectedOutputs) {
            return false;
        }
        for (let index = 0; index < host.registry.length; index += 1) {
            if (coordinator.surfaceSnapshot(host.registry[index].token).ownerName !== ownerName) {
                return false;
            }
        }
        return true;
    }

    function onlySurfaceOwnsWorkspace(surfaceToken) {
        if (surfaceToken === null || surfaceToken === undefined
                || host.registry.length !== expectedOutputs) {
            return false;
        }
        for (let index = 0; index < host.registry.length; index += 1) {
            const record = host.registry[index];
            const expected = record.token === surfaceToken ? "workspace" : "idle";
            if (coordinator.surfaceSnapshot(record.token).ownerName !== expected
                    || record.surface.surfaceState.ownerName !== expected) {
                return false;
            }
        }
        return true;
    }

    function joinReady() {
        if (Quickshell.screens.length !== expectedOutputs || adapter.outputCount !== expectedOutputs
                || host.registry.length !== expectedOutputs
                || host.liveSurfaceCount !== expectedOutputs
                || coordinator.surfaceCount !== expectedOutputs) {
            return false;
        }
        const records = projectionRecords();
        for (let index = 0; index < records.length; index += 1) {
            const record = records[index];
            if (record.registry === null || record.registry.surface === null
                    || record.registry.surface.surfaceState.ownerName !== "idle"
                    || !record.projection.available || record.outputToken === null
                    || record.outputToken === undefined
                    || host.surfaceTokenForOutput(record.outputToken) !== record.registry.token
                    || record.registry.surface.workspaceProjection !== record.projection) {
                return false;
            }
        }
        return true;
    }

    // Equal helper/Quickshell counts plus one unique successful lookup for
    // every real ShellScreen proves the internal name join is a bijection
    // without exporting the helper's raw output names.
    function requireProductionJoin(label) {
        const records = projectionRecords();
        const screenNames = Object.create(null);
        for (let index = 0; index < records.length; index += 1) {
            const record = records[index];
            const screenName = record.screen.name;
            require(typeof screenName === "string" && screenName.length > 0
                    && screenNames["$" + screenName] !== true,
                    label + " exposes one unique live Quickshell screen name per output");
            screenNames["$" + screenName] = true;
            require(record.registry !== null && record.registry.screen === record.screen
                    && record.registry.surface !== null
                    && record.registry.surface.workspaceProjection === record.projection
                    && record.projection.available
                    && exactKeys(record.projection,
                                 ["available", "currentId", "currentName", "currentPosition",
                                  "desktops"]),
                    label + " binds the production host surface to the adapter projection");
            require(record.outputToken !== null && record.outputToken !== undefined
                    && record.outputToken !== screenName
                    && String(record.outputToken).indexOf(screenName) === -1
                    && record.projection.name === undefined
                    && record.projection.outputName === undefined
                    && host.surfaceTokenForOutput(record.outputToken) === record.registry.token,
                    label + " keeps raw output identity inside the adapter boundary");
            for (let peerIndex = index + 1; peerIndex < records.length; peerIndex += 1) {
                require(record.outputToken !== records[peerIndex].outputToken,
                        label + " assigns one unique opaque token per helper output");
            }
        }
        const values = desktops();
        for (let index = 0; index < values.length; index += 1) {
            require(exactKeys(values[index], ["id", "name", "position"])
                    && values[index].position === index,
                    label + " exposes the exact normalized desktop projection shape");
        }
        require(adapter.outputCount === Quickshell.screens.length
                && host.surfaceTokenForOutput(unknownOutputToken) === null,
                label + " forms a complete name join and rejects an unknown output token");
    }

    function recordForOutputToken(outputToken) {
        const records = projectionRecords();
        let matched = null;
        for (let index = 0; index < records.length; index += 1) {
            if (records[index].outputToken === outputToken) {
                if (matched !== null) {
                    return null;
                }
                matched = records[index];
            }
        }
        return matched;
    }

    function changeRouteReady(change, expectedCurrentId) {
        if (change === null) {
            return false;
        }
        const record = recordForOutputToken(change.outputToken);
        if (record === null || record.projection.currentId !== expectedCurrentId
                || host.surfaceTokenForOutput(change.outputToken) !== record.registry.token) {
            return false;
        }
        const snapshot = coordinator.surfaceSnapshot(record.registry.token);
        return snapshot.ownerName === "workspace"
                && snapshot.ownerSourceToken === change.sourceToken
                && snapshot.ownerSourceGeneration === change.sourceGeneration
                && snapshot.ownerSourceRevision === change.revision
                && record.registry.surface.surfaceState.ownerName === "workspace"
                && record.registry.surface.surfaceState.ownerSourceToken === change.sourceToken
                && record.registry.surface.surfaceState.ownerSourceGeneration
                === change.sourceGeneration
                && record.registry.surface.surfaceState.ownerSourceRevision === change.revision
                && onlySurfaceOwnsWorkspace(record.registry.token);
    }

    function probeFailClosed(outputToken, label) {
        const beforePending = coordinator.pendingTransientCount;
        const before = [];
        for (let index = 0; index < host.registry.length; index += 1) {
            const snapshot = coordinator.surfaceSnapshot(host.registry[index].token);
            before.push({
                            "epoch": snapshot.ownerEpoch,
                            "name": snapshot.ownerName,
                            "revision": snapshot.revision,
                            "sourceToken": snapshot.ownerSourceToken
                        });
        }
        probeSerial += 1;
        routingProbe.confirmedWorkspaceChanged("workspace-route-probe-" + probeSerial, 1, 1,
                                               outputToken);
        require(coordinator.pendingTransientCount === beforePending,
                label + " creates no pending feedback");
        for (let index = 0; index < host.registry.length; index += 1) {
            const after = coordinator.surfaceSnapshot(host.registry[index].token);
            require(after.ownerEpoch === before[index].epoch && after.ownerName
                    === before[index].name && after.revision === before[index].revision
                    && after.ownerSourceToken === before[index].sourceToken,
                    label + " cannot reroute onto any live surface");
        }
    }

    function finishProjectionChecks() {
        const staleScreen = affectedScreen === null ? Quickshell.screens[0] : affectedScreen;
        const staleOutputToken = adapter.outputTokenFor(staleScreen);
        require(staleOutputToken !== null
                && host.surfaceTokenForOutput(staleOutputToken) !== null,
                "stale-token probe starts from a live production mapping");
        adapter.publishUnavailable();
        require(adapter.outputCount === 0 && !adapter.projectionFor(staleScreen).available
                && host.surfaceTokenForOutput(staleOutputToken) === null,
                "helper unavailability retires the opaque output mapping fail closed");
        probeFailClosed(staleOutputToken, "retired opaque output token");
        finishing = true;
        poll.stop();
        setStage("unloading-controller");
        unloadController.running = true;
    }

    function run() {
        if (stage === "await-initial") {
            if (!awaitState(joinReady(), "helper outputs never joined the production surfaces")) {
                return;
            }
            requireProductionJoin(expectedOutputs + "-output recovery");
            const records = projectionRecords();
            firstId = records[0].projection.currentId;
            require(firstId !== "" && allOutputsCurrent(firstId) && allOwners("idle"),
                    "initial recovery exposes one output-local projection per idle surface");
            probeFailClosed(unknownOutputToken, "unknown opaque output token");
            setStage("loading-controller");
            loadController.running = true;
            return;
        }

        if (stage === "await-divergence") {
            const changed = recordsNotCurrent(firstId);
            if (!awaitState(changed.length > 0 && lastWorkspaceChange !== null
                            && changeRouteReady(lastWorkspaceChange,
                                                changed.length === 1
                                                ? changed[0].projection.currentId : ""),
                            "divergent switch never reached one production surface")) {
                return;
            }
            require(changed.length === 1,
                    "divergent switch changes exactly one real output projection");
            const record = changed[0];
            switchedId = record.projection.currentId;
            affectedScreen = record.screen;
            affectedSurfaceToken = record.registry.token;
            affectedOutputToken = record.outputToken;
            changesAtDivergence = workspaceChangeCount;
            require(switchedId !== "" && switchedId !== firstId
                    && lastWorkspaceChange.outputToken === affectedOutputToken
                    && adapter.resolveTransient(lastWorkspaceChange.sourceToken,
                                                lastWorkspaceChange.sourceGeneration,
                                                lastWorkspaceChange.revision) !== null,
                    "divergent helper switch resolves only through its real affected output");
            probeFailClosed(unknownOutputToken,
                            "unknown token during divergent workspace presentation");
            setStage("await-reconvergence");
            return;
        }

        if (stage === "await-reconvergence") {
            if (!awaitState(allOutputsCurrent(firstId)
                            && workspaceChangeCount > changesAtDivergence
                            && lastWorkspaceChange !== null
                            && changeRouteReady(lastWorkspaceChange, firstId),
                            "reconvergence never returned through the affected surface")) {
                return;
            }
            const record = recordForOutputToken(lastWorkspaceChange.outputToken);
            require(record !== null && record.screen === affectedScreen
                    && record.registry.token === affectedSurfaceToken,
                    "reconvergence preserves the exact affected production surface");
            setStage("await-shared-switch");
            return;
        }

        if (stage === "await-shared-switch") {
            const values = recordsNotCurrent(firstId);
            if (!awaitState(values.length === expectedOutputs && lastWorkspaceChange !== null
                            && workspaceChangeCount
                            > (expectedOutputs > 1 ? changesAtDivergence + 1 : 0)
                            && changeRouteReady(lastWorkspaceChange,
                                                values.length > 0
                                                ? values[0].projection.currentId : ""),
                            "shared switch never reached its initiating production surface")) {
                return;
            }
            switchedId = values[0].projection.currentId;
            require(switchedId !== "" && switchedId !== firstId
                    && allOutputsCurrent(switchedId),
                    "shared switch updates every output-local projection");
            const record = recordForOutputToken(lastWorkspaceChange.outputToken);
            require(record !== null && record.projection.currentId === switchedId,
                    "shared switch retains exactly one mapped initiating output");
            affectedScreen = record.screen;
            affectedSurfaceToken = record.registry.token;
            affectedOutputToken = record.outputToken;
            obsoleteSourceToken = lastWorkspaceChange.sourceToken;
            obsoleteSourceGeneration = lastWorkspaceChange.sourceGeneration;
            obsoleteRevision = lastWorkspaceChange.revision;
            require(adapter.resolveTransient(obsoleteSourceToken, obsoleteSourceGeneration,
                                             obsoleteRevision) !== null,
                    "confirmed shared switch resolves its exact retained tuple");
            changesAtSharedSwitch = workspaceChangeCount;
            invalidationsAtSharedSwitch = workspaceInvalidationCount;
            setStage("await-reorder");
            return;
        }

        if (stage === "await-reorder") {
            const values = desktops();
            const affectedRecord = registryRecordForScreen(affectedScreen);
            if (!awaitState(values.length >= 2 && values[0].id === switchedId
                            && workspaceInvalidationCount > invalidationsAtSharedSwitch
                            && coordinator.pendingTransientCount === 0 && allOwners("idle")
                            && affectedRecord !== null && affectedRecord.surface !== null
                            && affectedRecord.surface.surfaceState.ownerName === "idle",
                            "silent reorder never invalidated the retained workspace tuple")) {
                return;
            }
            const current = desktopById(switchedId);
            require(current !== null && current.name !== currentRename
                    && workspaceChangeCount === changesAtSharedSwitch
                    && workspaceInvalidationCount === invalidationsAtSharedSwitch + 1
                    && lastWorkspaceInvalidation !== null
                    && lastWorkspaceInvalidation.sourceToken === obsoleteSourceToken
                    && lastWorkspaceInvalidation.sourceGeneration === obsoleteSourceGeneration
                    && adapter.resolveTransient(obsoleteSourceToken, obsoleteSourceGeneration,
                                                obsoleteRevision) === null
                    && coordinator.pendingTransientCount === 0 && allOwners("idle")
                    && affectedRecord.surface.surfaceState.ownerName === "idle",
                    "silent structural projection invalidates visible stale presentation without feedback");
            setStage("await-current-rename");
            return;
        }

        if (stage === "await-current-rename") {
            const current = desktopById(switchedId);
            if (!awaitState(current !== null && current.name === currentRename,
                            "current desktop rename never reached every projection")) {
                return;
            }
            require(allOutputsCurrent(switchedId)
                    && workspaceChangeCount === changesAtSharedSwitch
                    && workspaceInvalidationCount === invalidationsAtSharedSwitch + 1,
                    "current rename stays silent after obsolete presentation invalidation");
            setStage("await-non-current-rename");
            return;
        }

        if (stage === "await-non-current-rename") {
            const original = desktopById(firstId);
            if (!awaitState(original !== null && original.name === nonCurrentRename,
                            "non-current desktop rename never reached every projection")) {
                return;
            }
            desktopCountBeforeRemoval = desktops().length;
            require(workspaceChangeCount === changesAtSharedSwitch
                    && workspaceInvalidationCount === invalidationsAtSharedSwitch + 1,
                    "non-current rename remains a feedback-free structural update");
            setStage("await-removal");
            return;
        }

        if (stage === "await-removal") {
            if (!awaitState(desktopById(firstId) === null
                            && desktops().length === desktopCountBeforeRemoval - 1,
                            "desktop removal never reached every projection")) {
                return;
            }
            require(desktopByName(retiredRename) === null && allOutputsCurrent(switchedId)
                    && workspaceChangeCount === changesAtSharedSwitch
                    && workspaceInvalidationCount === invalidationsAtSharedSwitch + 1,
                    "removal and retired rename publish no stale feedback");
            setStage("await-replacement");
            return;
        }

        if (stage === "await-replacement") {
            const replacement = desktopByName(replacementName);
            if (!awaitState(replacement !== null
                            && desktops().length === desktopCountBeforeRemoval,
                            "replacement desktop never reached every projection")) {
                return;
            }
            replacementId = replacement.id;
            require(allOutputsCurrent(switchedId)
                    && workspaceChangeCount === changesAtSharedSwitch
                    && workspaceInvalidationCount === invalidationsAtSharedSwitch + 1,
                    "replacement remains a feedback-free structural update");
            setStage("await-replacement-rename");
            return;
        }

        if (stage === "await-replacement-rename") {
            const replacement = desktopById(replacementId);
            if (!awaitState(replacement !== null && replacement.name === replacementRename,
                            "replacement rename never reached every projection")) {
                return;
            }
            require(allOutputsCurrent(switchedId)
                    && workspaceChangeCount === changesAtSharedSwitch
                    && workspaceInvalidationCount === invalidationsAtSharedSwitch + 1,
                    "replacement rename remains silent and output local");
            finishProjectionChecks();
        }
    }

    IslandStateCoordinator {
        id: coordinator
    }

    KWinVirtualDesktopAdapter {
        id: adapter

        helperPath: test.helperPath
        onConfirmedWorkspaceChanged: function (sourceToken, sourceGeneration, revision,
                                               outputToken) {
            test.workspaceChangeCount += 1;
            test.lastWorkspaceChange = {
                "sourceToken": sourceToken,
                "sourceGeneration": sourceGeneration,
                "revision": revision,
                "outputToken": outputToken
            };
        }
        onConfirmedWorkspaceInvalidated: function (sourceToken, sourceGeneration) {
            test.workspaceInvalidationCount += 1;
            test.lastWorkspaceInvalidation = {
                "sourceToken": sourceToken,
                "sourceGeneration": sourceGeneration
            };
        }
    }

    IslandSurfaceHost {
        id: host

        coordinator: coordinator
        virtualDesktops: adapter
        workspaceTransientSource: adapter
        reducedMotion: true
    }

    TransientCoordinatorBridge {
        coordinator: coordinator
        surfaceHost: host
        workspaceSource: adapter
    }

    QtObject {
        id: routingProbe

        signal confirmedWorkspaceChanged(var sourceToken, int sourceGeneration, int revision,
                                         var outputToken)
        signal confirmedWorkspaceInvalidated(var sourceToken, int sourceGeneration)
    }

    TransientCoordinatorBridge {
        coordinator: coordinator
        surfaceHost: host
        workspaceSource: routingProbe
    }

    Process {
        id: loadController

        command: ["busctl", "--user", "call", "org.kde.KWin", "/Scripting",
            "org.kde.kwin.Scripting", "loadScript", "ss", test.controllerPath, test.pluginName]
        stdout: StdioCollector {
            id: loadOutput
        }
        onExited: function (exitCode) {
            if (!test.require(exitCode === 0, "controller script loads")) {
                return;
            }
            const match = /^i\s+(-?\d+)/.exec(loadOutput.text.trim());
            if (!test.require(match !== null && Number(match[1]) >= 0,
                              "controller returns a valid KWin script ID")) {
                return;
            }
            test.controllerScriptId = Number(match[1]);
            runController.command = ["busctl", "--user", "call", "org.kde.KWin",
                                     "/Scripting/Script" + test.controllerScriptId,
                                     "org.kde.kwin.Script", "run"];
            runController.running = true;
        }
    }

    Process {
        id: runController

        onExited: function (exitCode) {
            if (!test.require(exitCode === 0, "controller script runs")) {
                return;
            }
            test.setStage(test.expectedOutputs > 1 ? "await-divergence" :
                                                     "await-shared-switch");
        }
    }

    Process {
        id: unloadController

        command: ["busctl", "--user", "call", "org.kde.KWin", "/Scripting",
            "org.kde.kwin.Scripting", "unloadScript", "s", test.pluginName]
        onExited: function (exitCode) {
            if (!test.require(test.finishing && exitCode === 0,
                              "controller script unloads after all projection checks")) {
                return;
            }
            console.warn("workspace production-routing virtual-KWin tests passed for "
                         + test.expectedOutputs + " outputs");
            Qt.exit(0);
        }
    }

    Timer {
        id: poll

        interval: 20
        repeat: true
        running: true
        onTriggered: test.run()
    }

    Timer {
        interval: 25000
        running: true
        onTriggered: test.fail("workspace production-routing virtual-KWin test timed out")
    }

    Component.onCompleted: {
        if (helperPath === "" || controllerPath === ""
                || expectedOutputs < 1 || expectedOutputs > 3) {
            fail("workspace projection test environment is incomplete");
        }
    }
}

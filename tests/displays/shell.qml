import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    readonly property int expectedOutputs: parseInt(Quickshell.env("NAGI_TEST_OUTPUTS") ?? "2")
    readonly property int soakCycleCount: 20
    readonly property var host: hostLoader.item
    readonly property var stateCoordinator: coordinator
    property string stage: "initial"
    property int attempts: 0
    property int cycle: 0
    property var victimScreen: null
    property var retiredToken: null
    property int retiredGeneration: 0
    property real retiredEpoch: 0
    property int retiredRevision: 0
    property var replacementToken: null
    property var reloadRecords: []
    property var shutdownRecords: []
    property var controlCenterRouteToken: null
    property var controlCenterRouteScreen: null
    property int controlCenterRehomeCount: 0
    property int coordinatorCreationCount: 0
    property int hostCreationCount: 0
    property int activeHostCount: 0
    property int observedRegistryCount: -1
    property bool reducedMotion: false
    property bool displaysPageEnabled: true

    property var workspaceRouteRecord: null
    readonly property string workspaceRouteSourceToken: "display-workspace-source"
    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function awaitState(condition, message) {
        if (condition) {
            attempts = 0;
            return true;
        }
        attempts += 1;
        if (attempts > 500) {
            require(false, message);
        }
        retry.restart();
        return false;
    }

    function advance() {
        Qt.callLater(test.run);
    }

    function registryRecordForScreen(screen) {
        if (host === null) {
            return null;
        }
        for (let index = 0; index < host.registry.length; index += 1) {
            if (host.registry[index].screen === screen) {
                return host.registry[index];
            }
        }
        return null;
    }

    function tokenForScreen(screen) {
        const record = registryRecordForScreen(screen);
        return record === null ? null : record.token;
    }

    function ownerCount(ownerName) {
        if (host === null) {
            return 0;
        }
        let count = 0;
        for (let index = 0; index < host.registry.length; index += 1) {
            if (coordinator.surfaceSnapshot(host.registry[index].token).ownerName === ownerName) {
                count += 1;
            }
        }
        return count;
    }

    function allOwners(ownerName) {
        return host !== null && ownerCount(ownerName) === host.registry.length;
    }

    function requireRegistry(expectedCount, label) {
        require(host !== null, label + " keeps one live surface host");
        require(activeHostCount === 1 && coordinatorCreationCount === 1,
                label + " keeps one host and one process-wide coordinator");
        require(host.registry.length === expectedCount && host.liveSurfaceCount === expectedCount
                && coordinator.surfaceCount === expectedCount,
                label + " keeps registry and coordinator counts exact");
        for (let index = 0; index < host.registry.length; index += 1) {
            const record = host.registry[index];
            const snapshot = coordinator.surfaceSnapshot(record.token);
            require(record.surface !== null && record.generation > 0
                    && snapshot.generation === record.generation
                    && snapshot.ownerName !== "none",
                    label + " keeps every registry row attached to its exact generation");
            const projection = fixtureVirtualDesktops.projectionFor(record.screen);
            const outputToken = fixtureVirtualDesktops.outputTokenFor(record.screen);
            require(record.surface.workspaceProjection === projection && projection.available
                    && projection.currentPosition
                    === fixtureVirtualDesktops.screenIndex(record.screen)
                    && host.surfaceTokenForOutput(outputToken) === record.token,
                    label + " binds each surface and opaque output token to the same live screen");
            for (let peerIndex = index + 1; peerIndex < host.registry.length; peerIndex += 1) {
                const peer = host.registry[peerIndex];
                require(peer.token !== record.token && peer.screen !== record.screen,
                        label + " keeps one unique surface token per connected output");
            }
        }
    }

    function captureRetired(screen) {
        const record = registryRecordForScreen(screen);
        require(record !== null, "cycle surface exists before lifecycle replacement");
        const snapshot = coordinator.surfaceSnapshot(record.token);
        victimScreen = screen;
        retiredToken = record.token;
        retiredGeneration = record.generation;
        retiredEpoch = snapshot.ownerEpoch;
        retiredRevision = snapshot.revision;
    }

    function requireRetiredRejected(label) {
        const snapshot = coordinator.surfaceSnapshot(retiredToken);
        require(snapshot.generation === 0 && snapshot.ownerName === "none"
                && snapshot.restorationDepth === 0,
                label + " removes the retired surface record completely");
        require(!coordinator.acknowledgeVisible(retiredToken, retiredGeneration, retiredEpoch,
                                                retiredRevision)
                && !coordinator.setHover(retiredToken, retiredGeneration, true)
                && !coordinator.detachSurface(retiredToken, retiredGeneration),
                label + " rejects stale acknowledgement, intent, and detach callbacks");
    }

    function requireReplacementIdle(label) {
        const record = registryRecordForScreen(victimScreen);
        require(record !== null && record.token !== retiredToken
                && record.generation > retiredGeneration,
                label + " creates a fresh token and strictly newer host generation");
        const snapshot = coordinator.surfaceSnapshot(record.token);
        require(snapshot.ownerName === "idle" && snapshot.restorationDepth === 0
                && snapshot.ownerSourceToken === null,
                label + " does not replay retired ownership onto the replacement");
        replacementToken = record.token;
    }

    function openControlCenterRoute(token) {
        const screen = host.screenForToken(token);
        require(screen !== null, "Control Center route starts from a live surface");
        controlCenterRouteToken = token;
        controlCenterRouteScreen = screen;
    }

    function rehomeControlCenterRoute(label) {
        const retiredRouteToken = controlCenterRouteToken;
        require(host.screenForToken(retiredRouteToken) === null,
                label + " observes that the initiating surface has left the registry");
        const replacement = host.routeSurfaceToken(retiredRouteToken);
        const replacementScreen = host.screenForToken(replacement);
        require(replacement !== null && replacement !== retiredRouteToken
                && replacementScreen !== null,
                label + " rehomes through the shared live-surface router");
        controlCenterRouteToken = replacement;
        controlCenterRouteScreen = replacementScreen;
        controlCenterRehomeCount += 1;
    }

    function captureReloadRecords() {
        const records = [];
        for (let index = 0; index < host.registry.length; index += 1) {
            const record = host.registry[index];
            const snapshot = coordinator.surfaceSnapshot(record.token);
            records.push({
                             "epoch": snapshot.ownerEpoch,
                             "generation": record.generation,
                             "revision": snapshot.revision,
                             "token": record.token
                         });
        }
        return records;
    }

    function requireReloadRecordsRetired(records, label) {
        for (let index = 0; index < records.length; index += 1) {
            const record = records[index];
            const snapshot = coordinator.surfaceSnapshot(record.token);
            require(snapshot.generation === 0 && snapshot.ownerName === "none"
                    && !coordinator.acknowledgeVisible(record.token, record.generation,
                                                      record.epoch, record.revision)
                    && !coordinator.detachSurface(record.token, record.generation),
                    label + " retires every old token and rejects its callbacks");
            if (host !== null) {
                for (let liveIndex = 0; liveIndex < host.registry.length; liveIndex += 1) {
                    require(host.registry[liveIndex].token !== record.token,
                            label + " never reuses a token after reload");
                }
            }
        }
    }

    function transientToken() {
        return "display-soak-" + cycle;
    }

    function startCycle() {
        requireRegistry(expectedOutputs, "cycle " + cycle + " start");
        require(allOwners("idle") && coordinator.pendingTransientCount === 0
                && !coordinator.modalPresent && coordinator.interactiveHostToken === null,
                "cycle starts from exact process-wide Idle state");
        const rows = host.activeDisplays();
        require(rows.length === expectedOutputs && host.enabledDisplayCount === expectedOutputs,
                "cycle starts with every connected display enabled");
        const victim = rows[cycle % rows.length];
        if (expectedOutputs > 1) {
            const fallback = rows[(cycle + 1) % rows.length];
            require(host.setFallback(fallback.screen),
                    "cycle selects a distinct live fallback before transfer");
        }
        const token = tokenForScreen(victim.screen);
        openControlCenterRoute(token);
        require(coordinator.openLauncher(token),
                "cycle opens one Interactive owner on the selected island");
        captureRetired(victim.screen);
        require(retiredEpoch > 0 && coordinator.interactiveHostToken === retiredToken
                && ownerCount("launcher") === 1,
                "cycle admits exactly one Interactive generation");
        if (expectedOutputs === 1) {
            require(!host.setEnabled(victim.screen, false)
                    && host.liveSurfaceCount === 1 && coordinator.surfaceCount === 1,
                    "single-output cycle rejects disabling its final island");
            require(coordinator.cancelInteractive(retiredEpoch),
                    "single-output cycle cancels its Interactive owner");
            stage = "interactive-cleanup";
            retry.restart();
            return;
        }
        require(host.setEnabled(victim.screen, false),
                "cycle disables an Interactive host through the transfer seam");
        stage = "interactive-disabled";
        retry.restart();
    }

    function run() {
        if (stage === "initial") {
            if (!awaitState(host !== null && activeHostCount === 1
                            && host.liveSurfaceCount === expectedOutputs
                            && coordinator.surfaceCount === expectedOutputs
                            && displaysPageLoader.item !== null,
                            "one live island did not settle on every connected output")) {
                return;
            }
            requireRegistry(expectedOutputs, "initial settlement");
            require(hostCreationCount === 1 && coordinatorCreationCount === 1,
                    "fixture creates one host and one process-wide coordinator");
            const rows = host.activeDisplays();
            require(rows.length === expectedOutputs && host.enabledDisplayCount === expectedOutputs,
                    "new installations enable every connected display");
            require(host.rememberedDisplays.length === 0,
                    "unreliable ShellScreen identities never create remembered rows");
            for (let index = 0; index < rows.length; index += 1) {
                require(rows[index].enabled && !rows[index].reliable,
                        "active display row is enabled and session-only");
            }
            require(displaysPageLoader.item.displayController === host,
                    "Displays page consumes the shared display controller");
            const pointerToken = host.routeSurfaceToken(null);
            require(pointerToken !== null && coordinator.openDashboard(null)
                    && coordinator.surfaceSnapshot(pointerToken).ownerName === "expanded",
                    "global action routes through the native pointer-screen bridge");
            require(coordinator.resetToIdle(pointerToken),
                    "pointer-routed dashboard returns to its initiating surface Idle");
            require(host.surfaceTokenForOutput(fixtureVirtualDesktops.staleOutputToken) === null,
                    "unknown opaque output identity has no live-surface fallback");
            workspaceRouteRecord = host.registry[host.registry.length - 1];
            const workspaceOutputToken = fixtureVirtualDesktops.outputTokenFor(
                                           workspaceRouteRecord.screen);
            fixtureWorkspaceSource.confirmedWorkspaceChanged(workspaceRouteSourceToken, 1, 1,
                                                              workspaceOutputToken);
            stage = "workspace-route-requested";
            retry.restart();
            return;
        }

        if (stage === "workspace-route-requested") {
            const routed = coordinator.surfaceSnapshot(workspaceRouteRecord.token);
            if (!awaitState(routed.ownerName === "workspace" && routed.presentationVisible
                            && ownerCount("workspace") === 1,
                            "workspace feedback did not settle on exactly its output surface")) {
                return;
            }
            for (let index = 0; index < host.registry.length; index += 1) {
                const record = host.registry[index];
                const snapshot = coordinator.surfaceSnapshot(record.token);
                require(record.token === workspaceRouteRecord.token
                        ? snapshot.ownerName === "workspace" : snapshot.ownerName === "idle",
                        "workspace output routing leaves every peer surface Idle");
            }
            fixtureWorkspaceSource.confirmedWorkspaceChanged(workspaceRouteSourceToken, 1, 2,
                                                              fixtureVirtualDesktops.staleOutputToken);
            require(coordinator.surfaceSnapshot(workspaceRouteRecord.token).ownerSourceRevision
                    === 1 && ownerCount("workspace") === 1
                    && coordinator.pendingTransientCount === 1,
                    "stale opaque output token is rejected without rerouting or coalescing");
            fixtureWorkspaceSource.confirmedWorkspaceInvalidated(workspaceRouteSourceToken, 1);
            stage = "workspace-route-cleared";
            retry.restart();
            return;
        }

        if (stage === "workspace-route-cleared") {
            if (!awaitState(coordinator.pendingTransientCount === 0 && allOwners("idle"),
                            "workspace invalidation did not restore every surface to Idle")) {
                return;
            }
            stage = "cycle-start";
            advance();
            return;
        }

        if (stage === "cycle-start") {
            startCycle();
            return;
        }

        if (stage === "interactive-disabled") {
            if (!awaitState(host.liveSurfaceCount === expectedOutputs - 1
                            && coordinator.surfaceCount === expectedOutputs - 1
                            && tokenForScreen(victimScreen) === null,
                            "disabled Interactive island did not destroy independently")) {
                return;
            }
            requireRegistry(expectedOutputs - 1, "Interactive transfer");
            require(host.surfaceTokenForOutput(
                        fixtureVirtualDesktops.outputTokenFor(victimScreen)) === null,
                    "disabled output identity cannot target a detached surface");
            requireRetiredRejected("Interactive transfer");
            const transferred = coordinator.surfaceSnapshot(coordinator.interactiveHostToken);
            require(coordinator.interactiveHostToken !== retiredToken
                    && transferred.ownerName === "launcher" && transferred.ownerEpoch
                    === retiredEpoch && transferred.revision === retiredRevision + 1
                    && ownerCount("launcher") === 1,
                    "Interactive transfer preserves one epoch on one replacement island");
            rehomeControlCenterRoute("Interactive-host loss");
            require(host.setEnabled(victimScreen, true),
                    "disabled Interactive island re-enables");
            stage = "interactive-reenabled";
            retry.restart();
            return;
        }

        if (stage === "interactive-reenabled") {
            if (!awaitState(host.liveSurfaceCount === expectedOutputs
                            && coordinator.surfaceCount === expectedOutputs
                            && tokenForScreen(victimScreen) !== null
                            && tokenForScreen(victimScreen) !== retiredToken,
                            "re-enabled Interactive island did not receive a fresh surface")) {
                return;
            }
            requireRegistry(expectedOutputs, "Interactive recreation");
            requireReplacementIdle("Interactive recreation");
            const transferred = coordinator.surfaceSnapshot(coordinator.interactiveHostToken);
            require(transferred.ownerName === "launcher" && transferred.ownerEpoch === retiredEpoch
                    && ownerCount("launcher") === 1
                    && coordinator.cancelInteractive(transferred.ownerEpoch),
                    "transferred Interactive task completes once after recreation");
            stage = "interactive-cleanup";
            retry.restart();
            return;
        }

        if (stage === "interactive-cleanup") {
            if (!awaitState(allOwners("idle") && coordinator.interactiveHostToken === null
                            && !host.contentTransitionRunning && !host.geometryAnimationRunning,
                            "Interactive cleanup did not return every island to Idle")) {
                return;
            }
            requireRegistry(expectedOutputs, "Interactive cleanup");
            require(coordinator.requestNotification(transientToken(), cycle + 1, 1, null),
                    "cycle broadcasts one normalized transient generation");
            stage = "transient-projected";
            retry.restart();
            return;
        }

        if (stage === "transient-projected") {
            if (!awaitState(coordinator.pendingTransientCount === 1
                            && ownerCount("notification") === expectedOutputs,
                            "broadcast transient did not project to every live island")) {
                return;
            }
            const rows = host.activeDisplays();
            const victim = rows[(cycle + 1) % rows.length];
            captureRetired(victim.screen);
            openControlCenterRoute(retiredToken);
            if (expectedOutputs === 1) {
                require(coordinator.invalidateTransient(transientToken(), cycle + 1),
                        "single-output transient invalidates exactly once");
                stage = "transient-cleanup";
                retry.restart();
                return;
            }
            require(host.setEnabled(victim.screen, false),
                    "cycle destroys one transient projection through the display seam");
            stage = "transient-disabled";
            retry.restart();
            return;
        }

        if (stage === "transient-disabled") {
            if (!awaitState(host.liveSurfaceCount === expectedOutputs - 1
                            && coordinator.surfaceCount === expectedOutputs - 1
                            && tokenForScreen(victimScreen) === null,
                            "transient projection did not detach with its island")) {
                return;
            }
            requireRegistry(expectedOutputs - 1, "transient projection loss");
            requireRetiredRejected("transient projection loss");
            require(coordinator.pendingTransientCount === 1
                    && ownerCount("notification") === expectedOutputs - 1,
                    "projection loss keeps one bounded event on remaining islands");
            rehomeControlCenterRoute("transient-projection loss");
            require(host.setEnabled(victimScreen, true),
                    "transient projection island re-enables");
            stage = "transient-reenabled";
            retry.restart();
            return;
        }

        if (stage === "transient-reenabled") {
            if (!awaitState(host.liveSurfaceCount === expectedOutputs
                            && coordinator.surfaceCount === expectedOutputs
                            && tokenForScreen(victimScreen) !== null
                            && tokenForScreen(victimScreen) !== retiredToken,
                            "transient projection replacement did not settle")) {
                return;
            }
            requireRegistry(expectedOutputs, "transient projection recreation");
            requireReplacementIdle("transient projection recreation");
            require(coordinator.pendingTransientCount === 1
                    && ownerCount("notification") === expectedOutputs - 1
                    && ownerCount("idle") === 1,
                    "replacement stays Idle without replaying the pre-existing transient");
            require(coordinator.invalidateTransient(transientToken(), cycle + 1),
                    "broadcast transient invalidates once after projection recreation");
            stage = "transient-cleanup";
            retry.restart();
            return;
        }

        if (stage === "transient-cleanup") {
            if (!awaitState(coordinator.pendingTransientCount === 0 && allOwners("idle"),
                            "transient cleanup did not restore exact Idle ownership")) {
                return;
            }
            requireRegistry(expectedOutputs, "transient cleanup");
            reducedMotion = true;
            const modalPredecessor = host.routeFallbackToken(null);
            openControlCenterRoute(modalPredecessor);
            require(coordinator.openLauncher(modalPredecessor),
                    "Modal rehome cycle starts with one Interactive predecessor");
            stage = "modal-predecessor";
            retry.restart();
            return;
        }

        if (stage === "modal-predecessor") {
            if (!awaitState(coordinator.interactiveHostToken === controlCenterRouteToken
                            && ownerCount("launcher") === 1,
                            "Modal predecessor did not settle on the fallback island")) {
                return;
            }
            require(coordinator.syncPolkitModal(true, true, cycle + 1)
                    && coordinator.modalHostToken !== null && ownerCount("polkitModal") === 1,
                    "cycle admits one process-wide Modal owner");
            reloadRecords = captureReloadRecords();
            displaysPageEnabled = false;
            hostLoader.active = false;
            stage = "host-unloaded";
            retry.restart();
            return;
        }

        if (stage === "host-unloaded") {
            if (!awaitState(host === null && activeHostCount === 0
                            && coordinator.surfaceCount === 0,
                            "host reload did not synchronously drain every surface record")) {
                return;
            }
            require(coordinatorCreationCount === 1 && coordinator.surfaceRouter === null
                    && coordinator.modalPresent && coordinator.modalHostToken === null
                    && coordinator.interactiveHostToken === null
                    && coordinator.pendingTransientCount === 0,
                    "unloaded host leaves one empty coordinator with no orphan owner or event");
            requireReloadRecordsRetired(reloadRecords, "host unload");
            hostLoader.active = true;
            stage = "host-reloaded";
            retry.restart();
            return;
        }

        if (stage === "host-reloaded") {
            if (!awaitState(host !== null && activeHostCount === 1
                            && host.liveSurfaceCount === expectedOutputs
                            && coordinator.surfaceCount === expectedOutputs
                            && coordinator.modalHostToken !== null
                            && ownerCount("polkitModal") === 1,
                            "host reload did not rehome Modal onto one fresh surface")) {
                return;
            }
            displaysPageEnabled = true;
            requireRegistry(expectedOutputs, "host reload");
            require(hostCreationCount === cycle + 2,
                    "reload creates exactly one replacement host per completed cycle");
            requireReloadRecordsRetired(reloadRecords, "host reload");
            rehomeControlCenterRoute("host reload");
            require(coordinator.syncPolkitModal(false, false, 0),
                    "Modal completion releases the reloaded host");
            stage = "modal-cleared";
            retry.restart();
            return;
        }

        if (stage === "modal-cleared") {
            if (!awaitState(!coordinator.modalPresent && coordinator.modalHostToken === null
                            && allOwners("idle") && !host.contentTransitionRunning,
                            "Modal cleanup did not restore fresh settled Idle surfaces")) {
                return;
            }
            requireRegistry(expectedOutputs, "Modal cleanup");
            const token = host.routeFallbackToken(null);
            require(coordinator.openLauncher(token),
                    "reduced-motion cleanup opens one final Interactive owner");
            stage = "reduced-interactive";
            retry.restart();
            return;
        }

        if (stage === "reduced-interactive") {
            if (!awaitState(coordinator.interactiveHostToken === host.surfaceToken
                            && ownerCount("launcher") === 1 && host.launcherLoaded
                            && !host.contentTransitionRunning,
                            "reduced-motion Interactive owner did not settle: token="
                            + (coordinator.interactiveHostToken === host.surfaceToken) + ", owners="
                            + ownerCount("launcher") + ", loaded=" + host.launcherLoaded + ", content="
                            + host.contentTransitionRunning)) {
                return;
            }
            const epoch = coordinator.surfaceSnapshot(host.surfaceToken).ownerEpoch;
            require(coordinator.cancelInteractive(epoch),
                    "reduced-motion Interactive owner cancels");
            const snapshot = coordinator.surfaceSnapshot(host.surfaceToken);
            require(snapshot.ownerName === "idle" && snapshot.restorationDepth === 0
                    && !host.contentTransitionRunning && !host.geometryAnimationRunning
                    && host.contentOutgoingItem === null && host.contentIncomingOpacity === 1
                    && host.geometryAnimationDuration === 0,
                    "Minimal motion synchronously clears overlap and geometry work: owner="
                    + snapshot.ownerName + ", depth=" + snapshot.restorationDepth + ", content="
                    + host.contentTransitionRunning + ", geometry=" + host.geometryAnimationRunning
                    + ", outgoing=" + (host.contentOutgoingItem !== null) + ", incomingOpacity="
                    + host.contentIncomingOpacity + ", duration=" + host.geometryAnimationDuration);
            reducedMotion = false;
            stage = "cycle-settled";
            advance();
            return;
        }

        if (stage === "cycle-settled") {
            if (!awaitState(allOwners("idle") && coordinator.interactiveHostToken === null
                            && coordinator.pendingTransientCount === 0 && !host.launcherLoaded
                            && !host.contentTransitionRunning && !host.geometryAnimationRunning,
                            "cycle did not return to exact settled state")) {
                return;
            }
            requireRegistry(expectedOutputs, "cycle " + cycle + " final settlement");
            cycle += 1;
            if (cycle < soakCycleCount) {
                stage = "cycle-start";
                advance();
                return;
            }
            shutdownRecords = captureReloadRecords();
            displaysPageEnabled = false;
            hostLoader.active = false;
            stage = "final-shutdown";
            retry.restart();
            return;
        }

        if (stage === "final-shutdown") {
            if (!awaitState(host === null && activeHostCount === 0
                            && coordinator.surfaceCount === 0,
                            "final shutdown did not drain registry and coordinator exactly")) {
                return;
            }
            requireReloadRecordsRetired(shutdownRecords, "final shutdown");
            require(coordinatorCreationCount === 1
                    && hostCreationCount === soakCycleCount + 1
                    && coordinator.surfaceRouter === null
                    && coordinator.pendingTransientCount === 0
                    && !coordinator.modalPresent && coordinator.modalHostToken === null
                    && coordinator.interactiveHostToken === null,
                    "final shutdown leaves one empty coordinator and no process-wide work");
            const expectedRehomes = soakCycleCount * (expectedOutputs === 1 ? 1 : 3);
            require(controlCenterRehomeCount === expectedRehomes,
                    "Control Center routing rehomes exactly once per surface-loss seam");
            console.warn("display orchestration " + expectedOutputs + "-output soak passed "
                         + soakCycleCount + " cycles with exact final cleanup");
            Qt.exit(0);
        }
    }

    IslandStateCoordinator {
        id: coordinator

        Component.onCompleted: test.coordinatorCreationCount += 1
    }

    QtObject {
        id: fixtureVirtualDesktops

        readonly property var staleOutputToken: ({})
        readonly property var outputTokens: Object.freeze([Object.freeze({}), Object.freeze({}),
                                                            Object.freeze({})])
        readonly property var desktops: Object.freeze([Object.freeze({
                                                               "id": "desktop-1",
                                                               "name": "Desktop 1",
                                                               "position": 0
                                                           }), Object.freeze({
                                                               "id": "desktop-2",
                                                               "name": "Desktop 2",
                                                               "position": 1
                                                           }), Object.freeze({
                                                               "id": "desktop-3",
                                                               "name": "Desktop 3",
                                                               "position": 2
                                                           })])
        readonly property var projections: Object.freeze([Object.freeze({
                                                                  "available": true,
                                                                  "currentId": "desktop-1",
                                                                  "currentName": "Desktop 1",
                                                                  "currentPosition": 0,
                                                                  "desktops":
                                                                  fixtureVirtualDesktops.desktops
                                                              }), Object.freeze({
                                                                  "available": true,
                                                                  "currentId": "desktop-2",
                                                                  "currentName": "Desktop 2",
                                                                  "currentPosition": 1,
                                                                  "desktops":
                                                                  fixtureVirtualDesktops.desktops
                                                              }), Object.freeze({
                                                                  "available": true,
                                                                  "currentId": "desktop-3",
                                                                  "currentName": "Desktop 3",
                                                                  "currentPosition": 2,
                                                                  "desktops":
                                                                  fixtureVirtualDesktops.desktops
                                                              })])
        readonly property var unavailableProjection: Object.freeze({
                                                                       "available": false,
                                                                       "currentId": "",
                                                                       "currentName": "",
                                                                       "currentPosition": -1,
                                                                       "desktops":
                                                                       Object.freeze([])
                                                                   })

        function screenIndex(screen) {
            for (let index = 0; index < Quickshell.screens.length; index += 1) {
                if (Quickshell.screens[index] === screen) {
                    return index;
                }
            }
            return -1;
        }

        function outputTokenFor(screen) {
            const index = screenIndex(screen);
            return index < 0 || index >= outputTokens.length ? null : outputTokens[index];
        }

        function projectionFor(screen) {
            const index = screenIndex(screen);
            return index < 0 || index >= projections.length ? unavailableProjection :
                                                               projections[index];
        }
    }

    QtObject {
        id: fixtureWorkspaceSource

        signal confirmedWorkspaceChanged(var sourceToken, int sourceGeneration, int revision,
                                         var outputToken)
        signal confirmedWorkspaceInvalidated(var sourceToken, int sourceGeneration)

        function resolveTransient(sourceToken, sourceGeneration, revision) {
            if (sourceToken !== test.workspaceRouteSourceToken || sourceGeneration !== 1
                    || revision !== 1) {
                return null;
            }
            return Object.freeze({
                                     "detail": "Current desktop",
                                     "iconName": "preferences-desktop-virtual-symbolic",
                                     "primary": "Desktop 3",
                                     "value": "3 / 3"
                                 });
        }
    }

    TransientCoordinatorBridge {
        coordinator: coordinator
        surfaceHost: test.host
        workspaceSource: fixtureWorkspaceSource
    }

    QtObject {
        id: fixtureApplicationModel

        readonly property bool initialized: false
        readonly property bool available: false
        readonly property bool pinMutationPending: false
        readonly property string pinFailure: ""
        readonly property var applications: []
        readonly property var pinnedApplications: []
        readonly property var recentApplications: []
        readonly property var pinIds: []
        readonly property var recencyIds: []
    }

    LazyLoader {
        id: hostLoader

        active: true

        IslandSurfaceHost {
            coordinator: test.stateCoordinator
            virtualDesktops: fixtureVirtualDesktops
            workspaceTransientSource: fixtureWorkspaceSource
            reducedMotion: test.reducedMotion
            applicationModel: fixtureApplicationModel

            Component.onCompleted: {
                test.hostCreationCount += 1;
                test.activeHostCount += 1;
            }
            Component.onDestruction: test.activeHostCount -= 1
        }
    }

    LazyLoader {
        id: displaysPageLoader

        active: test.displaysPageEnabled && test.host !== null

        DisplaysPage {
            visible: false
            displayController: test.host
        }
    }

    Connections {
        id: registryObserver

        target: test.host

        function onRegistryChanged() {
            if (registryObserver.target !== null) {
                test.observedRegistryCount = registryObserver.target.registry.length;
            }
        }
    }

    Timer {
        id: retry

        interval: 10
        onTriggered: test.run()
    }

    Timer {
        interval: 1
        running: true
        onTriggered: test.run()
    }
}

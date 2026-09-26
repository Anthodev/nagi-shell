import Quickshell
import QtQuick
import QtTest
import "qml"

ShellRoot {
    id: test

    property int step: 0
    property int retryAttempts: 0
    property int mountedRegionCount: 0
    property int hoverExpandedEpoch: 0
    property int focusSerialBeforeRestore: 0
    property real sessionEpoch: 0
    property real historyEpoch: 0
    property real trayEpoch: 0
    property real audioEpoch: 0
    property real weatherEpoch: 0
    property bool audioVerified: false
    property bool trayVerified: false
    property bool weatherVerified: false
    property var initialSurfaceToken: null
    property int initialSurfaceGeneration: 0
    property int compactTransientWidth: 0
    property int compactTransientHeight: 0
    property real modalRevisionBeforeReplacement: 0
    property int notificationRevisionProbeStage: 0
    property var notificationRevisionProbe: null
    readonly property int maximumRetryAttempts: 500
    property bool reducedCollapsePending: false
    property real reducedExpandedOpacityBefore: 0
    property int pendingReverseKind: 0
    property int workspaceFullProbeStage: 0
    readonly property int soakCycleCount: 100
    property int soakCycle: 0
    property bool soakInteractiveCancellationPending: false
    property var soakSurfaceTokens: []
    property var soakSurfaceGenerations: []
    property var soakExpectedGeometry: null
    property int soakSettingsGeneration: 0
    property real soakDevicePixelRatio: 0
    property real soakInteractiveEpoch: 0
    property var soakControlCenterToken: null
    property int soakControlCenterRehomeCount: 0
    property int testRegionImplicitWidth: 120
    property int testRegionImplicitHeight: 72
    readonly property int maximumGeometryDurationMs: 5000
    property string geometryDirection: ""
    property real geometryStartTimeMs: 0
    property int geometryStableSamples: 0
    property real geometryStartTopMargin: 0
    property real geometryStartWidth: 0
    property real geometryStartHeight: 0
    property real geometryLastWidth: 0
    property real geometryLastHeight: 0
    property real maximumCenteringError: 0
    property real maximumTopMarginDelta: 0
    property int motionResetStage: 0
    property int behaviorProbeStage: 0
    property bool coldPreparationObserved: false
    property real reversalWidth: 0
    property real reversalHeight: 0
    readonly property string polkitVisualState: Quickshell.env("NAGI_POLKIT_VISUAL_STATE") ?? ""
    property int railPointerCase: 0
    property point railActivationPoint: Qt.point(0, 0)
    property real railNaturalWidth: 0
    property real railNaturalHeight: 0
    property real railOwnerEpoch: 0
    readonly property var railDestinations: [{
            "button": "dashboardTray",
            "owner": "tray"
        }, {
            "button": "dashboardHistory",
            "owner": "history"
        }, {
            "button": "dashboardLauncher",
            "owner": "launcher"
        }]

    function advance() {
        Qt.callLater(test.runStep);
    }

    function awaitState(condition, message) {
        if (condition) {
            retryAttempts = 0;
            return true;
        }

        retryAttempts += 1;
        require(retryAttempts <= maximumRetryAttempts, message);
        retry.restart();
        return false;
    }

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function requireNaturalSourceGeometry(source, label) {
        require(source !== null && source.width > 0 && source.height > 0
                && Math.abs(source.width - source.implicitWidth) <= 0.5
                && Math.abs(source.height - source.implicitHeight) <= 0.5,
                label + " root keeps natural actual geometry: actual="
                + (source === null ? "null" : source.width + "x" + source.height) + " implicit="
                + (source === null ? "null" : source.implicitWidth + "x"
                                     + source.implicitHeight));
    }

    function requireWorkspacePresentationGeometry(source, label) {
        requireNaturalSourceGeometry(source, label);
        require(source.workspace && source.workspaceDisplayText === "02"
                && source.workspacePosition === 2 && source.workspaceCount === 4,
                label + " renders the two-digit position and four-desktop projection");
        require(source.workspaceBadgeItem !== null
                && source.workspaceBadgeItem.width === Theme.size.islandWorkspaceIndicatorWidth
                && source.workspaceBadgeItem.height === Theme.size.islandWorkspaceIndicatorHeight,
                label + " keeps the shared 28 by 22 workspace badge geometry");
        require(Math.abs(source.contentCenterX - source.width / 2) <= 1
                && Math.abs(source.workspaceIndicatorCenterX - source.width / 2) <= 1,
                label + " centers its badge and desktop dots in the compact source root");
    }
    function captureSoakRegistry() {
        const tokens = [];
        const generations = [];
        for (let index = 0; index < host.registry.length; index += 1) {
            tokens.push(host.registry[index].token);
            generations.push(host.registry[index].generation);
        }
        soakSurfaceTokens = tokens;
        soakSurfaceGenerations = generations;
    }

    function requireSoakRegistry(label) {
        require(host.registry.length === host.liveSurfaceCount
                && coordinatorCore.surfaceCount === host.liveSurfaceCount
                && host.liveSurfaceCount === Quickshell.screens.length,
                label + " keeps registry and coordinator counts exact");
        require(host.registry.length === soakSurfaceTokens.length,
                label + " keeps one surface per initial output");
        for (let index = 0; index < host.registry.length; index += 1) {
            const record = host.registry[index];
            const snapshot = coordinatorCore.surfaceSnapshot(record.token);
            require(record.token === soakSurfaceTokens[index]
                    && record.generation === soakSurfaceGenerations[index]
                    && snapshot.generation === record.generation
                    && snapshot.ownerName !== "none",
                    label + " preserves each live surface generation");
        }
    }

    function currentSurfaceScale() {
        const surface = host.fallbackSurface;
        if (surface === null || surface.contentItem === null
                || surface.contentItem.children.length === 0
                || surface.contentItem.children[0] === null) {
            return 0;
        }
        return surface.contentItem.children[0].Screen.devicePixelRatio;
    }

    function requireSoakGeometry(label) {
        const snapshot = UserConfig.snapshot;
        require(soakExpectedGeometry !== null && Object.isFrozen(snapshot)
                && Object.isFrozen(snapshot.island)
                && snapshot.generation === soakSettingsGeneration
                && snapshot.island.compactHeight === soakExpectedGeometry.compactHeight
                && snapshot.island.compactPadding === soakExpectedGeometry.compactPadding
                && snapshot.island.expandedWidthPercent === soakExpectedGeometry.expandedWidthPercent
                && snapshot.island.expandedHeightPercent
                === soakExpectedGeometry.expandedHeightPercent
                && Theme.size.islandIdleHeight === soakExpectedGeometry.compactHeight
                && Theme.size.islandCompactPadding === soakExpectedGeometry.compactPadding,
                label + " observes the validated published geometry");
    }

    function transferSoakInteractiveToLiveSurface() {
        const token = syntheticSoakSurfaceToken;
        const generation = 1000 + soakCycle;
        soakSyntheticRouter.routeToken = null;
        soakSyntheticRouter.fallbackToken = host.surfaceToken;
        coordinatorCore.surfaceRouter = soakSyntheticRouter;
        require(coordinatorCore.attachSurface(token, generation),
                "surface soak attaches one temporary Interactive source");
        require(coordinatorCore.openLauncher(token),
                "surface soak opens Interactive on the temporary source");
        const source = coordinatorCore.surfaceSnapshot(token);
        require(source.ownerName === "launcher" && source.ownerEpoch > 0
                && coordinatorCore.interactiveHostToken === token,
                "temporary Interactive source owns one fresh epoch");
        require(coordinatorCore.detachSurface(token, generation),
                "surface soak removes the temporary Interactive source");
        coordinatorCore.surfaceRouter = host;
        soakSyntheticRouter.fallbackToken = null;
        const targetToken = coordinatorCore.interactiveHostToken;
        const target = coordinatorCore.surfaceSnapshot(targetToken);
        require(targetToken !== null && host.registryRecordForToken(targetToken) !== null
                && target.ownerName === "launcher" && target.ownerEpoch === source.ownerEpoch,
                "Interactive owner transfers to one live surface without replay");
        require(!coordinatorCore.detachSurface(token, generation)
                && coordinatorCore.surfaceSnapshot(token).ownerName === "none",
                "retired Interactive generation cannot detach or remain projected");
        soakInteractiveEpoch = source.ownerEpoch;
        host.fallbackSurface.refreshSurfaceState();
    }

    function rehomeSoakModalToLiveSurface() {
        const token = syntheticSoakSurfaceToken;
        const generation = 2000 + soakCycle;
        fakePolkitController.available = true;
        fakePolkitController.terminal = false;
        fakePolkitController.responseRequired = true;
        fakePolkitController.responseVisible = true;
        fakePolkitController.submissionPending = false;
        fakePolkitController.cancellationPending = false;
        fakePolkitController.flowGeneration = generation;
        fakePolkitController.promptGeneration = generation;
        soakSyntheticRouter.routeToken = token;
        soakSyntheticRouter.fallbackToken = host.surfaceToken;
        coordinatorCore.surfaceRouter = soakSyntheticRouter;
        require(coordinatorCore.attachSurface(token, generation),
                "surface soak attaches one temporary Modal source");
        require(coordinatorCore.syncPolkitModal(true, true, generation),
                "surface soak opens Modal on the temporary source");
        require(coordinatorCore.modalHostToken === token
                && coordinatorCore.surfaceSnapshot(token).ownerName === "polkitModal",
                "temporary Modal source owns the active flow");
        require(coordinatorCore.detachSurface(token, generation),
                "surface soak removes the temporary Modal source");
        coordinatorCore.surfaceRouter = host;
        soakSyntheticRouter.routeToken = null;
        soakSyntheticRouter.fallbackToken = null;
        const targetToken = coordinatorCore.modalHostToken;
        require(targetToken !== null && host.registryRecordForToken(targetToken) !== null
                && coordinatorCore.surfaceSnapshot(targetToken).ownerName === "polkitModal",
                "Modal owner rehomes to one live surface with the same active flow");
        require(!coordinatorCore.detachSurface(token, generation)
                && coordinatorCore.surfaceSnapshot(token).ownerName === "none",
                "retired Modal generation cannot detach or remain projected");
        host.fallbackSurface.refreshSurfaceState();

        soakControlCenterToken = null;
        host.controlCenterRequested(token);
        require(soakControlCenterToken !== null
                && host.registryRecordForToken(soakControlCenterToken) !== null
                && host.screenForToken(soakControlCenterToken) !== null,
                "Control Center request from a retired token rehomes to a live output");
    }


    function startSurfaceSoakCycle() {
        const previous = UserConfig.snapshot;
        const candidate = UserConfig.mutableSnapshot(UserConfig.defaultSnapshot(0));
        const compactHeight = [44, 48, 46][soakCycle % 3];
        const compactPadding = [16, 32, 24][soakCycle % 3];
        const expandedWidthPercent = [0.6, 1, 0.8][soakCycle % 3];
        const expandedHeightPercent = [0.8, 0.6, 1][soakCycle % 3];
        require(!Object.isFrozen(candidate) && !Object.isFrozen(candidate.island),
                "surface soak mutates only an explicit mutable settings snapshot");
        candidate.appearance.motion = "minimal";
        candidate.island.compactHeight = compactHeight;
        candidate.island.compactPadding = compactPadding;
        candidate.island.expandedWidthPercent = expandedWidthPercent;
        candidate.island.expandedHeightPercent = expandedHeightPercent;
        require(previous.island.compactHeight !== compactHeight
                && previous.island.compactPadding !== compactPadding
                && previous.island.expandedWidthPercent !== expandedWidthPercent
                && previous.island.expandedHeightPercent !== expandedHeightPercent,
                "every surface soak cycle changes all four geometry inputs");
        host.reducedMotion = true;
        const normalized = UserConfig.validateCandidate(candidate);
        require(normalized !== null && UserConfig.publish(normalized),
                "surface soak geometry candidate validates and publishes");
        soakExpectedGeometry = Object.freeze({
                                                   "compactHeight": compactHeight,
                                                   "compactPadding": compactPadding,
                                                   "expandedWidthPercent": expandedWidthPercent,
                                                   "expandedHeightPercent": expandedHeightPercent
                                               });
        soakSettingsGeneration = UserConfig.snapshot.generation;
        require(soakSettingsGeneration > previous.generation,
                "surface soak publishes a fresh settings generation");
        requireSoakGeometry("surface soak cycle " + soakCycle);
        const measuredScale = currentSurfaceScale();
        require(Number.isFinite(measuredScale) && measuredScale > 0,
                "surface soak observes the live output scale");
        if (soakDevicePixelRatio === 0) {
            soakDevicePixelRatio = measuredScale;
        } else {
            require(Math.abs(soakDevicePixelRatio - measuredScale) < 0.001,
                    "surface scale remains stable across one isolated run");
        }
        soakInteractiveCancellationPending = false;
        step = 36;
        advance();
    }

    function findObject(root, name) {
        if (root === null || root === undefined) {
            return null;
        }
        if (root.objectName === name) {
            return root;
        }
        if (root.presentationSource !== undefined && root.presentationSource !== null) {
            const sourceMatch = findObject(root.presentationSource, name);
            if (sourceMatch !== null) {
                return sourceMatch;
            }
        }
        const children = root.children ?? [];
        let childCount = 0;
        try {
            childCount = children.length;
        } catch (error) {
            return null;
        }
        for (let index = 0; index < childCount; index += 1) {
            const match = findObject(children[index], name);
            if (match !== null) {
                return match;
            }
        }
        return null;
    }
    function findPresentationForSource(root, source) {
        if (root === null || root === undefined || source === null || source === undefined) {
            return null;
        }
        if (root.presentationSource !== undefined && root.presentationSource === source) {
            return root;
        }
        const children = root.children ?? [];
        for (let index = 0; index < children.length; index += 1) {
            const match = findPresentationForSource(children[index], source);
            if (match !== null) {
                return match;
            }
        }
        return null;
    }

    function surfaceMatches(reference) {
        return host.fallbackSurface !== null
                && Math.abs(host.surfacePreferredWidth - reference.implicitWidth) <= 1
                && Math.abs(host.surfacePreferredHeight - reference.implicitHeight) <= 1
                && Math.abs(host.renderedPanelWidth - reference.implicitWidth) <= 1
                && Math.abs(host.renderedPanelHeight - reference.implicitHeight) <= 1;
    }

    function requireSurfaceMatches(reference, label) {
        console.warn(label + " panel geometry: " + host.renderedPanelWidth + "x"
                     + host.renderedPanelHeight + " (natural " + reference.implicitWidth + "x"
                     + reference.implicitHeight + ")");
        require(surfaceMatches(reference),
                label + " rendered panel geometry must equal the view envelope");
    }

    function requireContentContinuity(label) {
        const outgoing = host.contentOutgoingItem;
        const incoming = host.contentIncomingItem;
        const panel = findObject(host.fallbackSurface.contentItem, "surfaceBackground");
        require(panel !== null && panel.clip
                && Math.abs(panel.width - host.renderedPanelWidth) <= 0.5
                && Math.abs(panel.height - host.renderedPanelHeight) <= 0.5
                && (outgoing === null || outgoing.parent === panel)
                && (incoming === null || incoming.parent === panel),
                label + " confines every retained and incoming presentation to the current rendered panel");
        require(host.fallbackSurface.activeVisualKeyCount
                <= host.fallbackSurface.visualKeys().length,
                label + " bounds displayed faces by the registered visual keys");
        require(host.contentRenderedOpacityTotal >= 0.999,
                label + " never samples an all-transparent rendered frame: opacity="
                + host.contentRenderedOpacityTotal + ", retained=" + host.retainedPresentationCount
                + ", from=" + host.contentTransitionFromKind + ", to="
                + host.contentTransitionToKind + ", outgoingOpacity=" + host.contentOutgoingOpacity
                + ", incomingOpacity=" + host.contentIncomingOpacity + ", outgoing="
                + (outgoing !== null) + ", incoming=" + (incoming !== null));
        if (host.contentTransitionRunning) {
            require(outgoing !== null,
                    label + " retains an outgoing presentation until the transition completes");
            if (outgoing !== incoming && host.contentOutgoingOpacity > 0.0001) {
                require(host.contentOutgoingRendered && !host.contentOutgoingWorkActive
                        && !host.contentOutgoingEnabled
                        && host.contentOutgoingAccessibleIgnored,
                        label + " freezes the rendered predecessor while disabling its work and input: "
                        + host.contentOutgoingRendered + "/" + host.contentOutgoingWorkActive + "/"
                        + host.contentOutgoingEnabled + "/" + host.contentOutgoingAccessibleIgnored
                        + ", from=" + host.contentTransitionFromKind + ", to="
                        + host.contentTransitionToKind + ", retained="
                        + host.retainedPresentationCount);
            }
            if (host.contentTransitionDestinationReady) {
                require(incoming !== null && host.contentIncomingOpacity >= 0
                        && host.contentIncomingOpacity <= 1 && host.contentOutgoingOpacity >= 0
                        && host.contentOutgoingOpacity <= 1,
                        label + " presents a bounded incoming/outgoing blend");
            } else {
                require(incoming === null && host.contentIncomingOpacity === 0
                        && host.fallbackSurface.morphProgress === 0,
                        label + " freezes the predecessor while preparing its destination");
            }
        } else {
            require(host.contentTransitionDestinationReady && outgoing === null
                    && incoming !== null && host.contentOutgoingOpacity === 0
                    && host.contentIncomingOpacity === 1
                    && host.retainedPresentationCount === 0,
                    label + " performs guarded cleanup only at the committed endpoint");
        }
    }

    function requireOutgoingTransition(fromKind, toKind, label) {
        const outgoing = host.contentOutgoingItem;
        const incoming = host.contentIncomingItem;
        require(host.contentTransitionRunning && host.contentTransitionFromKind === fromKind
                && host.contentTransitionToKind === toKind && outgoing !== null
                && outgoing.sourceItem !== null && outgoing.visible
                && host.contentOutgoingOpacity > 0 && host.contentOutgoingRendered
                && !outgoing.live && !host.contentOutgoingWorkActive
                && !host.contentOutgoingEnabled && host.contentOutgoingAccessibleIgnored,
                label + " retains rendered whole-face pixels without outgoing work or input: kind="
                + host.contentTransitionFromKind + ">" + host.contentTransitionToKind
                + ", opacity=" + host.contentOutgoingOpacity
                + ", source=" + (outgoing === null ? null : outgoing.sourceItem)
                + ", incoming=" + incoming);
        requireContentContinuity(label);
    }
    function awaitOutgoingTransition(fromKind, toKind, label) {
        if (!awaitState(host.contentTransitionRunning
                        && host.contentTransitionFromKind === fromKind
                        && host.contentTransitionToKind === toKind
                        && host.contentOutgoingItem !== null,
                        label + " was not admitted for its current owner epoch")) {
            return false;
        }
        requireOutgoingTransition(fromKind, toKind, label);
        return true;
    }



    function requireShadowGutterContract(label) {
        const surface = host.fallbackSurface;
        require(host.windowGutterLeft === Theme.elevation.shadowGutterLeft
                && host.windowGutterRight === Theme.elevation.shadowGutterRight
                && host.windowGutterTop === Theme.elevation.shadowGutterTop
                && host.windowGutterBottom === Theme.elevation.shadowGutterBottom,
                label + " derives the visual gutters from the shadow bounds");
        require(Math.abs(surface.implicitWidth - (surface.envelopePanelWidth
                                                   + host.windowGutterLeft + host.windowGutterRight)) <= 1
                && Math.abs(surface.implicitHeight - (surface.envelopePanelHeight
                                                    + host.windowGutterTop + host.windowGutterBottom)) <= 1,
                label + " keeps the window envelope independent of the animated panel");
        require(Math.abs(host.panelMappedTopLeft.x - surface.panelOriginX) <= 0.5
                && Math.abs(host.panelMappedTopLeft.y - host.windowGutterTop) <= 0.5
                && Math.abs(host.panelMappedBottomRight.x - host.panelMappedTopLeft.x
                            - host.renderedPanelWidth) <= 0.5
                && Math.abs(host.panelMappedBottomRight.y - host.panelMappedTopLeft.y
                            - host.renderedPanelHeight) <= 0.5,
                label + " maps the panel, mask, and blur to the same visible bounds");
        require(surface.mask !== null
                && surface.requestedKwinBlurRegionCount === (host.blurRequested ? 1 : 0)
                && surface.shadowLayerCount === 1 && surface.renderedShadowOpacity > 0,
                label + " keeps one bounded input region, blur request, and shadow layer");
        require(host.surfaceTopMargin + host.panelMappedTopLeft.y === surface.edgeInset
                && Math.abs(host.surfaceLeftMargin + host.panelMappedTopLeft.x
                            + host.renderedPanelWidth / 2 - host.surfaceScreenWidth / 2) <= 1,
                label + " leaves the visible panel top-pinned and centered");
    }
    function requireMorphSettled(label) {
        const surface = host.fallbackSurface;
        require(surface !== null && !surface.geometryAnimationRunning
                && !host.contentTransitionRunning && host.retainedPresentationCount === 0
                && Math.abs(surface.renderedPanelWidth - surface.safeLogicalSize(
                                surface.preferredWidth, host.surfaceScreenWidth,
                                surface.largeContent ? UserConfig.snapshot.island.expandedWidthPercent : 1,
                                host.windowGutterLeft + host.windowGutterRight)) <= 1
                && Math.abs(surface.renderedPanelHeight - surface.safeLogicalSize(
                                surface.preferredHeight, host.surfaceScreenHeight,
                                surface.largeContent ? UserConfig.snapshot.island.expandedHeightPercent : 1,
                                host.windowGutterTop + host.windowGutterBottom)) <= 1,
                label + " releases outgoing faces and settles at the bounded natural viewport");
        requireContentContinuity(label);
        requireShadowGutterContract(label);
    }

    function startGeometrySampling(direction, transition) {
        geometryDirection = direction;
        geometryStartTimeMs = Date.now();
        geometryStableSamples = 0;
        geometryStartTopMargin = host.surfaceTopMargin;
        geometryStartWidth = host.fallbackSurface.renderedPanelWidth;
        geometryStartHeight = host.fallbackSurface.renderedPanelHeight;
        geometryLastWidth = host.surfaceWidth;
        geometryLastHeight = host.surfaceHeight;
        maximumCenteringError = 0;
        maximumTopMarginDelta = 0;
        require(transition(), direction + " geometry transition was rejected");
    }

    function sampleGeometry() {
        const surface = host.fallbackSurface;
        if (surface === null) return;
        require(Date.now() - geometryStartTimeMs <= maximumGeometryDurationMs,
                geometryDirection + " did not settle before the deadline");
        requireContentContinuity(geometryDirection);
        require(host.surfaceWidth === geometryLastWidth && host.surfaceHeight === geometryLastHeight,
                geometryDirection + " preserves one output-bounded window while the panel morphs");
        maximumCenteringError = Math.max(maximumCenteringError,
                                         Math.abs(host.surfaceLeftMargin + host.panelMappedTopLeft.x
                                                  + surface.renderedPanelWidth / 2
                                                  - host.surfaceScreenWidth / 2));
        maximumTopMarginDelta = Math.max(maximumTopMarginDelta,
                                         Math.abs(host.surfaceTopMargin - geometryStartTopMargin));
        if (surface.geometryAnimationRunning || host.contentTransitionRunning
                || !host.contentTransitionDestinationReady || !coordinator.presentationVisible) {
            geometryStableSamples = 0;
            return;
        }
        geometryStableSamples += 1;
        if (geometryStableSamples < 2) return;
        require(maximumCenteringError <= 1 && maximumTopMarginDelta <= 1,
                geometryDirection + " keeps the panel centered and top-pinned");
        require(Math.abs(surface.renderedPanelWidth - geometryStartWidth) > 1
                && Math.abs(surface.renderedPanelHeight - geometryStartHeight) > 1,
                geometryDirection + " changes visible width and height");
        requireMorphSettled(geometryDirection);
        const completedDirection = geometryDirection;
        geometryDirection = "";
        step = completedDirection === "expanding" ? 1 : 5;
        advance();
    }

    function runMorphBehaviorStep() {
        const surface = host.fallbackSurface;
        require(surface !== null, "motion checks keep one live surface");
        if (behaviorProbeStage === 0) {
            requireMorphSettled("motion behavior baseline");
            host.reducedMotion = false;
            coldPreparationObserved = false;
            behaviorProbeStage = 1;
            require(coordinatorCore.setHover(host.surfaceToken, host.surfaceGeneration, true),
                    "hover starts a cold Expanded reveal");
            surface.refreshSurfaceState();
            retry.restart();
            return false;
        }
        if (behaviorProbeStage === 1) {
            if (!awaitState(coordinator.ownerName === "expanded"
                            && host.contentTransitionDestinationReady
                            && surface.geometryAnimationRunning,
                            "cold Expanded destination did not start moving after preparation")) {
                return false;
            }
            require(coldPreparationObserved,
                    "cold Expanded presentation remains behind Idle until texture preparation");
            testRegionImplicitWidth = 176;
            testRegionImplicitHeight = 84;
            behaviorProbeStage = 2;
            retry.restart();
            return false;
        }
        if (behaviorProbeStage === 2) {
            require(host.contentTransitionRunning,
                    "first natural-size drift happens during the same active reveal");
            testRegionImplicitWidth = 224;
            testRegionImplicitHeight = 96;
            behaviorProbeStage = 3;
            retry.restart();
            return false;
        }
        if (behaviorProbeStage === 3) {
            const expectedWidth = surface.safeLogicalSize(surface.preferredWidth,
                host.surfaceScreenWidth, UserConfig.snapshot.island.expandedWidthPercent,
                host.windowGutterLeft + host.windowGutterRight);
            const expectedHeight = surface.safeLogicalSize(surface.preferredHeight,
                host.surfaceScreenHeight, UserConfig.snapshot.island.expandedHeightPercent,
                host.windowGutterTop + host.windowGutterBottom);
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible
                            && !surface.geometryAnimationRunning
                            && !host.contentTransitionRunning
                            && Math.abs(surface.renderedPanelWidth - expectedWidth) <= 1
                            && Math.abs(surface.renderedPanelHeight - expectedHeight) <= 1,
                            "active content drift did not converge to its latest natural viewport")) {
                return false;
            }
            requireMorphSettled("active natural-size drift");
            require(!host.launcherLoaded && coordinator.openLauncher(host.surfaceToken),
                    "Launcher interrupts the settled Expanded owner");
            surface.refreshSurfaceState();
            behaviorProbeStage = 4;
            retry.restart();
            return false;
        }
        if (behaviorProbeStage === 4) {
            if (!awaitState(coordinator.ownerName === "launcher"
                            && host.contentTransitionDestinationReady
                            && surface.geometryAnimationRunning,
                            "cold Launcher did not enter its prepared geometry trajectory")) {
                return false;
            }
            reversalWidth = surface.renderedPanelWidth;
            reversalHeight = surface.renderedPanelHeight;
            require(coordinator.cancelInteractive(coordinator.ownerEpoch),
                    "rapid Launcher cancellation restores Expanded");
            surface.refreshSurfaceState();
            require(Math.abs(surface.renderedPanelWidth - reversalWidth) <= 1
                    && Math.abs(surface.renderedPanelHeight - reversalHeight) <= 1,
                    "reversal retains the rendered geometry instead of jumping to an old endpoint");
            behaviorProbeStage = 5;
            retry.restart();
            return false;
        }
        if (behaviorProbeStage === 5) {
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible
                            && !surface.geometryAnimationRunning
                            && !host.contentTransitionRunning && !host.launcherLoaded,
                            "rapid reversal did not restore and release Launcher")) {
                return false;
            }
            requireMorphSettled("ready Launcher reversal");
            testRegionImplicitWidth = 260;
            testRegionImplicitHeight = 120;
            behaviorProbeStage = 6;
            retry.restart();
            return false;
        }
        if (behaviorProbeStage === 6) {
            if (!awaitState(surface.geometryAnimationRunning,
                            "natural-size update did not begin a geometry trajectory")) {
                return false;
            }
            const smoothMorphWidth = surface.renderedPanelWidth;
            const smoothMorphHeight = surface.renderedPanelHeight;
            const fastCandidate = UserConfig.mutableSnapshot(UserConfig.snapshot);
            fastCandidate.appearance.motion = "fast";
            const fastNormalized = UserConfig.validateCandidate(fastCandidate);
            require(fastNormalized !== null && UserConfig.publish(fastNormalized)
                    && Theme.motion.morphScale === 1 && Theme.motion.scale === 1,
                    "live Fast switch pins the general interface scale at its historical speed");
            require(Math.abs(surface.renderedPanelWidth - smoothMorphWidth) <= 1
                    && Math.abs(surface.renderedPanelHeight - smoothMorphHeight) <= 1
                    && surface.geometryAnimationRunning,
                    "switching Smooth to Fast mid-trajectory keeps rendered geometry moving");
            const candidate = UserConfig.mutableSnapshot(UserConfig.snapshot);
            candidate.island.expandedWidthPercent = 0.6;
            candidate.island.expandedHeightPercent = 0.6;
            const normalized = UserConfig.validateCandidate(candidate);
            require(normalized !== null && UserConfig.publish(normalized),
                    "live bounds shrink publishes valid geometry limits");
            surface.interruptMorphForScreenBounds();
            behaviorProbeStage = 7;
            retry.restart();
            return false;
        }
        if (behaviorProbeStage === 7) {
            const expectedWidth = surface.safeLogicalSize(surface.preferredWidth,
                host.surfaceScreenWidth, 0.6, host.windowGutterLeft + host.windowGutterRight);
            const expectedHeight = surface.safeLogicalSize(surface.preferredHeight,
                host.surfaceScreenHeight, 0.6, host.windowGutterTop + host.windowGutterBottom);
            if (!awaitState(!surface.geometryAnimationRunning
                            && Math.abs(surface.renderedPanelWidth - expectedWidth) <= 1
                            && Math.abs(surface.renderedPanelHeight - expectedHeight) <= 1,
                            "live bounds interruption did not settle inside its new cap")) {
                return false;
            }
            requireMorphSettled("live screen-bound shrink");
            testRegionImplicitWidth = 120;
            testRegionImplicitHeight = 72;
            require(UserConfig.publish(UserConfig.defaultSnapshot(0))
                    && Theme.motion.morphScale === 1.35,
                    "motion checks restore the default natural bounds and Smooth response");
            host.reducedMotion = true;
            require(host.cancelDashboard(), "motion checks return to Idle");
            behaviorProbeStage = 8;
            retry.restart();
            return false;
        }
        if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible
                        && !surface.geometryAnimationRunning && !host.contentTransitionRunning,
                        "motion checks did not release the Expanded presentation")) {
            return false;
        }
        requireMorphSettled("motion behavior cleanup");
        return true;
    }

    function configurePolkitVisualState() {
        const supported = ["hidden-multiple", "single", "visible", "pending", "failure",
                           "cancellation"];
        require(supported.indexOf(polkitVisualState) >= 0,
                "unknown Polkit visual state: " + polkitVisualState);
        fakePolkitController.available = true;
        fakePolkitController.terminal = false;
        fakePolkitController.responseRequired = true;
        fakePolkitController.responseVisible = polkitVisualState === "visible";
        fakePolkitController.submissionPending = polkitVisualState === "pending";
        fakePolkitController.cancellationPending = polkitVisualState === "cancellation";
        fakePolkitController.supplementaryMessage = polkitVisualState === "failure"
                ? "Authentication failed. Check the response and try again." : "";
        fakePolkitController.supplementaryIsError = polkitVisualState === "failure";
        fakePolkitController.identities = polkitVisualState === "hidden-multiple"
                ? [modalIdentity, alternateModalIdentity] : [modalIdentity];
        fakePolkitController.selectedIdentity = modalIdentity;
    }

    function runPolkitVisualStep() {
        if (step === 0) {
            if (!awaitState(host.surfaceToken !== null && coordinator.presentationVisible,
                            "visual surface did not acknowledge Idle")) {
                return;
            }
            configurePolkitVisualState();
            require(coordinator.syncPolkitModal(true, true, 1),
                    "visual Modal snapshot enters");
            step = 1;
            advance();
            return;
        }
        if (!awaitState(coordinator.ownerName === "polkitModal"
                        && coordinator.presentationVisible && host.polkitLoaded,
                        "visual Polkit state did not render")) {
            return;
        }
        console.warn("holding Polkit visual state " + polkitVisualState);
    }

    function runStep() {
        if (polkitVisualState !== "") {
            runPolkitVisualStep();
            return;
        }
        if (step === 0) {
            if (!awaitState(host.surfaceToken !== null && coordinator.presentationVisible
                            && host.loadedDashboardRegionCount === 0,
                            "actual surface and unloaded Idle dashboard did not settle within five seconds")) {
                return;
            }
            require(coordinator.ownerName === "idle", "actual surface acknowledges Idle");
            require(!host.surfaceFocusable, "Idle never takes keyboard focus");
            require(host.gamingPerformanceBadgeVisible,
                    "actual Idle PanelWindow renders the static Gaming Performance badge");
            require(host.menuParentWindow !== null,
                    "actual surface exposes its Quickshell proxy for native platform menus");
            require(host.backgroundRadius === Theme.radius.outer
                    && defaultPanelReference.radius === Theme.radius.md,
                    "surface keeps the outer radius override while standard panels default to md");
            initialSurfaceToken = host.surfaceToken;
            initialSurfaceGeneration = host.surfaceGeneration;
            require(host.fallbackSurface.workspaceProjection
                    === fakeVirtualDesktops.projectionFor(host.fallbackSurface.screen)
                    && host.fallbackSurface.workspaceProjection.available
                    && host.fallbackSurface.workspaceProjection.currentPosition === 1,
                    "actual surface binds Idle to its own output-local workspace projection");
            require(mountedRegionCount === 0,
                    "Idle performs no hidden dashboard projection work");
            startGeometrySampling("expanding", function () {
                return coordinator.setHover(host.surfaceGeneration, true);
            });
            return;
        } else if (step === 1) {
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible
                            && host.loadedDashboardRegionCount === 8,
                            "eight-region hover dashboard did not become visible within five seconds")) {
                return;
            }
            require(coordinator.focusTarget === coordinator.focusNone && !host.surfaceFocusable,
                    "hover expansion never steals keyboard focus");
            require(host.surfaceToken === initialSurfaceToken && host.surfaceGeneration
                    === initialSurfaceGeneration, "expansion preserves the one live surface");
            const expectedWidth = Theme.spacing.xl * 3 + Theme.spacing.lg + Theme.spacing.md
                                  + Theme.size.iconSizeMd + testRegionImplicitWidth * 3;
            const expectedHeight = Theme.spacing.xl * 4 + Theme.spacing.md + Theme.spacing.lg
                                   + testRegionImplicitHeight * 5;
            require(Math.abs(host.surfacePreferredWidth - expectedWidth) <= 1
                    && Math.abs(host.surfacePreferredHeight - expectedHeight) <= 1
                    && host.renderedPanelWidth <= expectedWidth + 1
                    && host.renderedPanelHeight <= expectedHeight + 1,
                    "expanded preferred geometry follows the eight-region relational composition");
            requireMorphSettled("expanded dashboard");
            requireShadowGutterContract("expanded dashboard");
            require(host.surfaceWidth > host.renderedPanelWidth
                    && host.surfaceHeight > host.renderedPanelHeight,
                    "hover dashboard morphs inside the fixed output-bounded host");
            hoverExpandedEpoch = coordinator.ownerEpoch;
            const background = findObject(host.fallbackSurface.contentItem, "surfaceBackground");
            const revisionBeforePromotion = coordinator.revision;
            const focusSerialBeforePromotion = coordinator.focusRequestSerial;
            require(background !== null, "hover-expanded surface exposes its background");
            inputDriver.click(background);
            require(coordinator.explicitExpandedIntent
                    && coordinator.ownerEpoch === hoverExpandedEpoch
                    && coordinator.revision === revisionBeforePromotion
                    && coordinator.focusRequestSerial === focusSerialBeforePromotion + 1,
                    "one background tap promotes hover expansion without replacing its owner");
        } else if (step === 2) {
            if (!awaitState(host.surfaceFocusable && host.dashboardFocused,
                            "deliberate expansion did not receive focus within five seconds")) {
                return;
            }
            require(coordinator.ownerEpoch === hoverExpandedEpoch,
                    "deliberate intent updates the visible dashboard in place");
            require(coordinator.focusTarget === coordinator.focusExpandedDashboard,
                    "coordinator targets dashboard focus only after deliberate intent");
            const explicitBackground = findObject(host.fallbackSurface.contentItem,
                                                  "surfaceBackground");
            const explicitOwnerEpoch = coordinator.ownerEpoch;
            const explicitRevision = coordinator.revision;
            const explicitFocusSerial = coordinator.focusRequestSerial;
            require(explicitBackground !== null,
                    "explicit Expanded keeps the shared background mounted");
            inputDriver.click(explicitBackground);
            require(coordinator.explicitExpandedIntent
                    && coordinator.ownerEpoch === explicitOwnerEpoch
                    && coordinator.revision === explicitRevision
                    && coordinator.focusRequestSerial === explicitFocusSerial,
                    "explicit Expanded background taps are inert and request no duplicate focus");
            require(!host.launcherLoaded,
                    "the first Launcher transition starts from a genuinely cold lazy loader");
            require(coordinator.openLauncher(host.surfaceToken),
                    "higher-priority interaction interrupts Expanded");
        } else if (step === 3) {
            if (!awaitState(coordinator.ownerName === "launcher"
                            && coordinator.presentationVisible && host.surfaceFocusable
                            && host.launcherFocused && host.launcherResultCount === 1
                            && !host.launcherResultScrollVisible && surfaceMatches(launcherReference)
                            && !host.contentTransitionRunning
                            && host.contentOutgoingItem === null
                            && host.loadedDashboardRegionCount === 0,
                            "launcher state: owner=" + coordinator.ownerName + " visible="
                            + coordinator.presentationVisible + " focusable="
                            + host.surfaceFocusable + " focused=" + host.launcherFocused
                            + " regions=" + host.loadedDashboardRegionCount + " target="
                            + coordinator.focusTarget + " serial="
                            + coordinator.focusRequestSerial)) {
                return;
            }
            require(host.launcherSelectedId === "fixture.desktop"
                    && host.surfaceToken === initialSurfaceToken,
                    "launcher selection did not remain on the original surface");
            requireSurfaceMatches(launcherReference, "launcher");
            const expectedLauncherWidth = Theme.spacing.xxl * 15 + Theme.spacing.lg * 2;
            require(launcherReference.implicitWidth === expectedLauncherWidth
                    && Math.abs(host.surfacePreferredWidth - expectedLauncherWidth) <= 1
                    && Math.abs(host.renderedPanelWidth - expectedLauncherWidth) <= 1,
                    "launcher visible panel is exactly the 480 px lane plus frame padding");
            require(!host.launcherResultScrollVisible,
                    "one launcher result must not create a phantom scrollbar");
            focusSerialBeforeRestore = coordinator.focusRequestSerial;
            require(coordinator.cancelInteractive(coordinator.ownerEpoch),
                    "interrupted interaction cancels through the coordinator");
            require(Math.abs(host.surfacePreferredWidth - launcherReference.implicitWidth) > 1,
                    "outer preferred geometry switches immediately instead of staging after exit");
        } else if (step === 4) {
            if (host.contentTransitionRunning && host.contentOutgoingItem !== null
                    && host.contentTransitionDestinationReady
                    && host.contentTransitionFromKind === coordinatorCore.ownerLauncher
                    && host.contentTransitionToKind === coordinatorCore.ownerExpanded) {
                requireOutgoingTransition(coordinatorCore.ownerLauncher,
                                          coordinatorCore.ownerExpanded,
                                          "Launcher reverse transition");
            }
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible
                            && host.surfaceFocusable && host.dashboardFocused
                            && !host.contentTransitionRunning && host.contentOutgoingItem === null
                            && !host.launcherLoaded && host.loadedDashboardRegionCount === 8
                            && Math.abs(host.renderedPanelWidth
                                        - host.surfacePreferredWidth) <= 1
                            && Math.abs(host.renderedPanelHeight
                                        - host.surfacePreferredHeight) <= 1,
                            "dashboard did not restore at settled visible geometry with focus")) {
                return;
            }
            require(host.contentIncomingItem !== null && host.contentIncomingOpacity === 1,
                    "restored dashboard releases its outgoing Launcher face");
            require(coordinator.focusRequestSerial === focusSerialBeforeRestore + 1,
                    "restored deliberate dashboard receives one fresh focus request");
            startGeometrySampling("collapsing", function () {
                return host.cancelDashboard();
            });
            return;
        } else if (step === 5) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible &&
                            !host.surfaceFocusable,
                            "dashboard cancellation did not restore Idle")) {
                return;
            }
            require(!coordinator.hoverIntent && !coordinator.explicitExpandedIntent,
                    "cancellation clears both baseline intents");
            const reducedCandidate = UserConfig.mutableSnapshot(UserConfig.snapshot);
            reducedCandidate.appearance.motion = "reduced";
            const reduced = UserConfig.validateCandidate(reducedCandidate);
            require(reduced !== null && UserConfig.publish(reduced)
                    && Theme.motion.scale === 0.5 && Theme.motion.morphScale === 0.5,
                    "Reduced motion halves the geometry time scale without changing ownership");
            host.reducedMotion = false;
            require(host.requestDeliberateExpansion(),
                    "host exposes deliberate keyboard expansion under Reduced motion");
        } else if (step === 6) {
            if (!reducedCollapsePending) {
                if (!awaitState(coordinator.ownerName === "expanded"
                                && host.contentTransitionRunning
                                && host.contentTransitionDestinationReady
                                && host.geometryAnimationRunning
                                && host.contentOpacityForKind(coordinatorCore.ownerExpanded) > 0.05,
                                "Reduced dashboard did not reveal visible Expanded pixels during geometry")) {
                    return;
                }
                requireContentContinuity("Reduced dashboard entry");
                require(Theme.motion.scale > 0 && host.geometryAnimationRunning,
                        "Reduced motion preserves an actual geometry transition");
                const mountedExpanded = host.fallbackSurface.visualLayerForKind(
                                            coordinatorCore.ownerExpanded);
                require(mountedExpanded !== null && mountedExpanded.sourceItem !== null
                        && host.loadedDashboardRegionCount === 8,
                        "Reduced destination mounted its complete dashboard before reversal");
                reducedExpandedOpacityBefore = host.contentOpacityForKind(
                                                   coordinatorCore.ownerExpanded);
                require(host.cancelDashboard(), "Close remains functional with Reduced motion");
                reducedCollapsePending = true;
                retry.restart();
                return;
            }
            const expandedPresentation = host.fallbackSurface.visualLayerForKind(
                                             coordinatorCore.ownerExpanded);
            if (!awaitState(host.contentTransitionFromKind === coordinatorCore.ownerExpanded
                            && host.contentTransitionToKind === coordinatorCore.ownerIdle,
                            "Reduced reverse request was not admitted after coordinator ownership changed")) {
                return;
            }
            const retainedVisuals = [];
            for (const kind of host.fallbackSurface.visualKeys()) {
                const alpha = host.contentOpacityForKind(kind);
                if (alpha > 0.00001)
                    retainedVisuals.push(kind + ":" + alpha.toFixed(3));
            }
            require(host.contentOutgoingItem === expandedPresentation
                    && host.contentOpacityForKind(coordinatorCore.ownerExpanded) > 0
                    && expandedPresentation.sourceItem !== null && expandedPresentation.visible
                    && host.loadedDashboardRegionCount === 8,
                    "Reduced reversal keeps the already visible Expanded whole face mounted: "
                    + "owner=" + coordinator.ownerName + "/" + coordinator.ownerEpoch
                    + " surface=" + host.fallbackSurface.ownerKind + "/"
                    + host.fallbackSurface.ownerEpoch
                    + " running=" + host.contentTransitionRunning
                    + " from/to=" + host.contentTransitionFromKind + "/"
                    + host.contentTransitionToKind
                    + " alpha=" + reducedExpandedOpacityBefore.toFixed(3) + ">"
                    + host.contentOpacityForKind(coordinatorCore.ownerExpanded).toFixed(3)
                    + " contributors=" + retainedVisuals.join(",")
                    + " faces=" + host.retainedPresentationCount + "/"
                    + host.fallbackSurface.activeVisualKeyCount
                    + " outgoingIsExpanded=" + (host.contentOutgoingItem === expandedPresentation)
                    + " source=" + (expandedPresentation.sourceItem !== null)
                    + " visible=" + expandedPresentation.visible
                    + " live=" + expandedPresentation.live
                    + " enabled=" + expandedPresentation.enabled
                    + " ignored=" + expandedPresentation.Accessible.ignored
                    + " dashboardRegions=" + host.loadedDashboardRegionCount);
            requireOutgoingTransition(coordinatorCore.ownerExpanded, coordinatorCore.ownerIdle,
                                      "Reduced dashboard collapse");
        } else if (step === 7) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible
                            && !host.contentTransitionRunning
                            && host.contentOutgoingItem === null,
                            "Reduced collapse did not restore settled Idle")) {
                return;
            }
            requireMorphSettled("Reduced dashboard collapse");
            const minimalCandidate = UserConfig.mutableSnapshot(UserConfig.snapshot);
            minimalCandidate.appearance.motion = "minimal";
            const minimal = UserConfig.validateCandidate(minimalCandidate);
            require(minimal !== null && UserConfig.publish(minimal)
                    && Theme.motion.scale === 0 && Theme.motion.morphScale === 0,
                    "Minimal motion disables ongoing geometry work");
            host.reducedMotion = true;
            require(host.requestDeliberateExpansion(),
                    "session entry can originate from a Minimal dashboard");
        } else if (step === 8) {
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible
                            && !host.contentTransitionRunning && host.contentOutgoingItem === null
                            && !host.geometryAnimationRunning,
                            "Minimal dashboard did not settle synchronously")) {
                return;
            }
            require(!host.geometryAnimationRunning,
                    "Minimal dashboard settles content and geometry synchronously");
            requireMorphSettled("Minimal dashboard entry");
            require(coordinator.openSession(host.surfaceToken),
                    "visible dashboard session entry is admitted");
            sessionEpoch = coordinator.ownerEpoch;
        } else if (step === 9) {
            if (!awaitState(coordinator.ownerName === "session" && coordinator.presentationVisible
                            && host.surfaceFocusable && host.sessionFocused
                            && surfaceMatches(sessionReference),
                            "session focus state: owner=" + coordinator.ownerName + " visible="
                            + coordinator.presentationVisible + " focusable="
                            + host.surfaceFocusable + " focused=" + host.sessionFocused
                            + " target=" + coordinator.focusTarget + " serial="
                            + coordinator.focusRequestSerial)) {
                return;
            }
            require(coordinator.focusTarget === coordinator.focusSessionActions,
                    "session presentation receives the action-grid focus target");
            require(host.surfaceToken === initialSurfaceToken,
                    "session interaction preserves the one live surface");
            requireSurfaceMatches(sessionReference, "session");
            require(!coordinator.cancelInteractive(sessionEpoch - 1),
                    "stale session cancellation cannot close the current owner");
            require(coordinator.cancelInteractive(sessionEpoch),
                    "session cancellation accepts the current owner epoch");
        } else if (step === 10) {
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible
                            && host.dashboardFocused && !host.contentTransitionRunning
                            && host.contentOutgoingItem === null && host.contentIncomingItem !== null
                            && host.contentIncomingOpacity === 1
                            && !host.geometryAnimationRunning && !host.sessionLoaded,
                            "session cancellation did not synchronously restore the deliberate dashboard")) {
                return;
            }
            requireMorphSettled("Minimal Session exit");
            const fullCandidate = UserConfig.mutableSnapshot(UserConfig.snapshot);
            fullCandidate.appearance.motion = "full";
            const full = UserConfig.validateCandidate(fullCandidate);
            require(full !== null && UserConfig.publish(full) && Theme.motion.scale === 1
                    && Theme.motion.morphScale === 1.35,
                    "Smooth motion restores the normal interface response");
            host.reducedMotion = false;
            require(coordinator.openHistory(host.surfaceToken),
                    "visible dashboard history entry is admitted");
            historyEpoch = coordinator.ownerEpoch;
        } else if (step === 11) {
            if (pendingReverseKind === coordinatorCore.ownerHistory) {
                if (!awaitOutgoingTransition(coordinatorCore.ownerHistory,
                                             coordinatorCore.ownerExpanded,
                                             "History reverse transition")) return;
                pendingReverseKind = coordinatorCore.ownerNone;
            } else {
                if (!awaitState(coordinator.ownerName === "history"
                                && coordinator.presentationVisible && host.surfaceFocusable
                                && host.historyFocused && host.historyRowCount === 2
                                && surfaceMatches(historyReference)
                                && !host.contentTransitionRunning
                                && host.contentOutgoingItem === null,
                                "history geometry/focus did not settle: panel="
                                + host.renderedPanelWidth + "x" + host.renderedPanelHeight
                                + " preferred=" + host.surfacePreferredWidth + "x"
                                + host.surfacePreferredHeight + " natural="
                                + historyReference.implicitWidth + "x"
                                + historyReference.implicitHeight + " focused="
                                + host.historyFocused + " rows=" + host.historyRowCount)) return;
                require(coordinator.focusTarget === coordinator.focusNotificationHistory,
                        "history presentation receives the list focus target");
                requireSurfaceMatches(historyReference, "history");
                require(!coordinator.cancelInteractive(historyEpoch - 1),
                        "stale history Back cannot close the current owner");
                require(coordinator.cancelInteractive(historyEpoch),
                        "history Back accepts the current owner epoch");
                pendingReverseKind = coordinatorCore.ownerHistory;
                retry.restart();
                return;
            }
        } else if (step === 12) {
            if (pendingReverseKind !== coordinatorCore.ownerNone) {
                const kind = pendingReverseKind;
                if (!awaitOutgoingTransition(kind, coordinatorCore.ownerExpanded,
                                             "Interactive reverse transition")) return;
                if (kind === coordinatorCore.ownerTray) {
                    const trayControl = findObject(host.contentOutgoingItem, "trayItemButton");
                    require(trayControl !== null,
                            "retained Tray exposes its representative control");
                    inputDriver.click(trayControl);
                    require(fakeTrayAdapter.activationCount === 0,
                            "disabled outgoing Tray cannot dispatch pointer activation");
                    trayVerified = true;
                } else if (kind === coordinatorCore.ownerAudio) {
                    const audioControl = findObject(host.contentOutgoingItem,
                                                    "audioOutputDropdown");
                    require(audioControl !== null,
                            "retained Audio exposes its representative dropdown");
                    inputDriver.click(audioControl);
                    require(fakeAudioAdapter.selectionCount === 0,
                            "disabled outgoing Audio cannot dispatch pointer selection");
                    audioVerified = true;
                } else {
                    require(kind === coordinatorCore.ownerWeather,
                            "only admitted Interactive owners enter the reversal check");
                    weatherVerified = true;
                }
                pendingReverseKind = coordinatorCore.ownerNone;
                step = 11;
            } else if (!trayVerified && coordinator.ownerName === "tray") {
                if (!awaitState(coordinator.presentationVisible && host.surfaceFocusable
                                && host.trayLoaded && host.trayFocused
                                && surfaceMatches(trayReference)
                                && !host.contentTransitionRunning
                                && host.contentOutgoingItem === null,
                                "tray view did not settle at its envelope and receive focus")) {
                    return;
                }
                require(coordinator.focusTarget === coordinator.focusTray,
                        "tray presentation receives the item focus target");
                require(host.surfacePreferredWidth >= Theme.size.islandSubviewMinimumWidth
                        && host.renderedPanelWidth >= Theme.size.islandSubviewMinimumWidth - 1,
                        "sparse Tray keeps the shared interactive width floor");
                const beforeExit = coordinatorCore.surfaceSnapshot(host.surfaceToken);
                const focusableBeforeExit = host.surfaceFocusable;
                const focusedBeforeExit = host.trayFocused;
                const hoverAccepted = coordinator.setHover(host.surfaceGeneration, false);
                const afterExit = coordinatorCore.surfaceSnapshot(host.surfaceToken);
                require(hoverAccepted && coordinator.ownerName === "tray"
                        && host.surfaceFocusable && host.trayFocused,
                        "pointer exit cannot reset an active interactive subview: "
                        + "accepted=" + hoverAccepted
                        + " owner=" + beforeExit.ownerName + "/" + beforeExit.ownerEpoch
                        + ">" + afterExit.ownerName + "/" + afterExit.ownerEpoch
                        + " focusTarget=" + beforeExit.focusTarget + ">" + afterExit.focusTarget
                        + " focusSerial=" + beforeExit.focusRequestSerial + ">"
                        + afterExit.focusRequestSerial
                        + " visible=" + beforeExit.presentationVisible + ">"
                        + afterExit.presentationVisible
                        + " focusable=" + focusableBeforeExit + ">" + host.surfaceFocusable
                        + " itemFocus=" + focusedBeforeExit + ">" + host.trayFocused
                        + " handoff=" + host.fallbackSurface.focusHandoffPending
                        + " focusedEpoch=" + host.fallbackSurface.focusedOwnerEpoch
                        + " appliedSerial=" + host.fallbackSurface.appliedFocusRequestSerial
                        + " windowActive=" + (host.fallbackSurface.backingWindow !== null
                                              && host.fallbackSurface.backingWindow.active));
                requireSurfaceMatches(trayReference, "tray");
                require(coordinator.cancelInteractive(trayEpoch),
                        "tray Back accepts the current owner epoch");
                pendingReverseKind = coordinatorCore.ownerTray;
                retry.restart();
                return;
            } else if (!audioVerified && coordinator.ownerName === "audio") {
                if (!awaitState(coordinator.presentationVisible && host.surfaceFocusable
                                && host.audioLoaded && host.audioFocused
                                && !host.contentTransitionRunning
                                && host.contentOutgoingItem === null
                                && !host.geometryAnimationRunning
                                && Math.abs(host.surfacePreferredWidth
                                            - audioWidthReference.implicitWidth) <= 1
                                && Math.abs(host.renderedPanelWidth
                                            - audioWidthReference.implicitWidth) <= 1,
                                "audio view did not settle, focus, and drive the preferred viewport")) {
                    return;
                }
                const audioFrame = findObject(host.interactiveContent, "audioSubviewFrame");
                require(audioFrame !== null && audioFrame.preferredViewportWidth === 572
                        && audioFrame.preferredViewportHeight === 360
                        && audioFrame.resolvedViewportWidth === 572
                        && audioFrame.resolvedViewportHeight <= 360
                        && Math.abs(host.surfacePreferredHeight
                                    - host.interactiveContent.implicitHeight) <= 1
                        && Math.abs(host.renderedPanelHeight
                                    - host.interactiveContent.implicitHeight) <= 1,
                        "Audio preserves its wide preferred viewport within screen bounds");
                requireShadowGutterContract("Audio subview");
                require(host.surfacePreferredWidth >= Theme.size.islandSubviewMinimumWidth,
                        "Audio keeps the shared interactive width floor");
                require(coordinator.focusTarget === coordinator.focusAudio,
                        "audio presentation receives the dropdown focus target");
                const presetSelect = findObject(host.interactiveContent,
                                                "audioEasyEffectsOutputPreset");
                require(presetSelect !== null && presetSelect.control !== null,
                        "actual Audio surface exposes its preset select list");
                const audioPanelWidth = host.renderedPanelWidth;
                const audioPanelHeight = host.renderedPanelHeight;
                presetSelect.openPopup(presetSelect.candidates.indexOf("Cinema"));
                const presetPopup = findObject(host.interactiveContent,
                                               "audioEasyEffectsOutputPresetPopup");
                require(presetPopup !== null && presetPopup.visible && presetPopup.height > 0
                        && presetPopup.height <= Theme.size.controlHeightMd * 5
                        + Theme.spacing.xs * 2 + 0.5
                        && Math.abs(host.renderedPanelWidth - audioPanelWidth) <= 1
                        && Math.abs(host.renderedPanelHeight - audioPanelHeight) <= 1,
                        "preset disclosure stays within five rows without resizing the viewport");
                presetSelect.closePopup();
                require(coordinator.cancelInteractive(audioEpoch),
                        "audio Back accepts the current owner epoch");
                pendingReverseKind = coordinatorCore.ownerAudio;
                retry.restart();
                return;
            } else if (!weatherVerified && coordinator.ownerName === "weather") {
                if (!awaitState(coordinator.presentationVisible && host.surfaceFocusable
                                && host.weatherLoaded && host.weatherFocused
                                && !host.contentTransitionRunning
                                && host.contentOutgoingItem === null
                                && !host.geometryAnimationRunning
                                && host.renderedPanelWidth > 0 && host.renderedPanelHeight > 0,
                                "Weather view did not settle: loaded=" + host.weatherLoaded
                                + " focused=" + host.weatherFocused + " panel="
                                + host.renderedPanelWidth + "x" + host.renderedPanelHeight
                                + " unbounded=" + weatherReference.implicitWidth + "x"
                                + weatherReference.implicitHeight)) {
                    return;
                }
                require(coordinator.focusTarget === coordinator.focusWeather,
                        "Weather presentation receives its dedicated focus target");
                require(fakeWeatherAdapter.hourly.length === 12
                        && fakeWeatherAdapter.daily.length === 5,
                        "Weather renders the bounded shared 12-hour and five-day models");
                const weatherFrame = findObject(host.interactiveContent, "weatherSubviewFrame");
                require(weatherFrame !== null && weatherFrame.preferredViewportWidth === 576
                        && weatherFrame.preferredViewportHeight === 360
                        && weatherFrame.resolvedViewportWidth <= 576
                        && weatherFrame.resolvedViewportHeight <= 360
                        && Math.abs(host.surfacePreferredWidth
                                    - host.interactiveContent.implicitWidth) <= 1
                        && Math.abs(host.surfacePreferredHeight
                                    - host.interactiveContent.implicitHeight) <= 1
                        && Math.abs(host.renderedPanelWidth
                                    - host.interactiveContent.implicitWidth) <= 1
                        && Math.abs(host.renderedPanelHeight
                                    - host.interactiveContent.implicitHeight) <= 1
                        && host.renderedPanelWidth <= weatherReference.implicitWidth
                        && host.renderedPanelHeight <= weatherReference.implicitHeight,
                        "Weather resolves its 576 by 360 preferred viewport within screen bounds");
                requireShadowGutterContract("Weather subview");
                require(coordinator.cancelInteractive(weatherEpoch),
                        "Weather Back accepts the current owner epoch");
                pendingReverseKind = coordinatorCore.ownerWeather;
                retry.restart();
                return;
            } else {
                if (!awaitState(coordinator.ownerName === "expanded"
                                && coordinator.presentationVisible && host.dashboardFocused
                                && !host.contentTransitionRunning
                                && host.contentOutgoingItem === null,
                                "interactive Back did not settle the deliberate dashboard")) {
                    return;
                }
                require(host.contentIncomingItem !== null && host.contentIncomingOpacity === 1,
                        "restored dashboard has no hidden recurring transition work");
                if (!trayVerified) {
                    require(!host.historyLoaded,
                            "History unloads only after its reverse exit completes");
                    require(coordinator.openTray(host.surfaceToken),
                            "visible dashboard tray entry is admitted");
                    trayEpoch = coordinator.ownerEpoch;
                    step = 11;
                } else if (!audioVerified) {
                    require(!host.trayLoaded,
                            "Tray unloads only after its reverse exit completes");
                    require(coordinator.openAudio(host.surfaceToken),
                            "visible dashboard audio entry is admitted");
                    audioEpoch = coordinator.ownerEpoch;
                    step = 11;
                } else if (!weatherVerified) {
                    require(!host.audioLoaded,
                            "Audio unloads only after its reverse exit completes");
                    require(coordinator.openWeather(host.surfaceToken),
                            "compact Weather route is admitted on the initiating surface");
                    weatherEpoch = coordinator.ownerEpoch;
                    step = 11;
                } else {
                    require(!host.weatherLoaded,
                            "Weather unloads only after its reverse exit completes");
                    require(host.cancelDashboard(), "restored dashboard remains cancellable");
                }
            }
        } else if (step === 13) {
            if (workspaceFullProbeStage === 0) {
                if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible
                                && !host.contentTransitionRunning
                                && host.contentOutgoingItem === null,
                                "final dashboard cancellation did not restore Idle")) {
                    return;
                }
                host.reducedMotion = false;
                require(coordinator.requestWorkspace("surface-workspace-full", 3, 1,
                                                     host.surfaceToken),
                        "Full workspace transient enters");
                workspaceFullProbeStage = 1;
                retry.restart();
                return;
            }
            if (workspaceFullProbeStage === 1) {
                if (!awaitState(coordinator.ownerName === "workspace"
                                && host.contentTransitionRunning
                                && host.contentOutgoingItem !== null
                                && host.contentIncomingItem !== null
                                && host.contentOutgoingItem.sourceItem !== null
                                && host.contentIncomingItem.sourceItem !== null
                                && host.contentIncomingItem.sourceItem.workspace,
                                "Full workspace transient did not mount both retained source roots")) {
                    return;
                }
                const idleSource = host.contentOutgoingItem.sourceItem;
                const workspaceSource = host.contentIncomingItem.sourceItem;
                require(idleSource.width > 0 && idleSource.height > 0
                        && Math.abs(idleSource.width - idleSource.implicitWidth) <= 0.5
                        && Math.abs(idleSource.height - idleSource.implicitHeight) <= 0.5
                        && workspaceSource.width > 0 && workspaceSource.height > 0
                        && Math.abs(workspaceSource.width - workspaceSource.implicitWidth) <= 0.5
                        && Math.abs(workspaceSource.height - workspaceSource.implicitHeight) <= 0.5,
                        "Full retained Idle and workspace roots keep natural actual geometry: idle actual="
                        + idleSource.width + "x" + idleSource.height + " implicit="
                        + idleSource.implicitWidth + "x" + idleSource.implicitHeight
                        + ", workspace actual=" + workspaceSource.width + "x"
                        + workspaceSource.height + " implicit=" + workspaceSource.implicitWidth + "x"
                        + workspaceSource.implicitHeight);
                requireWorkspacePresentationGeometry(workspaceSource,
                                                     "Full workspace transient");
                workspaceFullProbeStage = 2;
                retry.restart();
                return;
            }
            if (workspaceFullProbeStage === 2) {
                if (!awaitState(coordinator.ownerName === "workspace"
                                && coordinator.presentationVisible && host.transientCommitted
                                && !host.contentTransitionRunning
                                && host.contentOutgoingItem === null,
                                "Full workspace transient did not settle and commit")) {
                    return;
                }
                requireWorkspacePresentationGeometry(host.contentIncomingItem.sourceItem,
                                                     "settled Full workspace transient");
                require(coordinator.invalidateTransient("surface-workspace-full", 3),
                        "Full workspace source invalidates");
                workspaceFullProbeStage = 3;
                retry.restart();
                return;
            }
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible
                            && !host.contentTransitionRunning
                            && host.contentOutgoingItem === null,
                            "Full workspace invalidation did not restore Idle")) {
                return;
            }
            require(coordinator.requestVolume("surface-volume", 1, 1, host.surfaceToken),
                    "actual surface accepts a compact value transient");
            require(!coordinator.presentationVisible,
                    "visible hold waits for compact entry completion");
        } else if (step === 14) {
            if (!awaitState(coordinator.ownerName === "volume" && coordinator.presentationVisible
                            && host.transientCommitted && !host.contentTransitionRunning
                            && host.contentOutgoingItem === null,
                            "compact value transient did not settle and commit visibly")) {
                return;
            }
            requireMorphSettled("compact value transient");
            require(host.transientPrimaryText === "Built-in Audio" && host.transientDetailText
                    === "Output volume", "compact transient resolves the exact normalized payload");
            require(host.surfacePreferredWidth
                    >= Theme.size.islandTransientCompactMinimumWidth
                    && host.surfacePreferredWidth <= Theme.size.islandTransientCompactWidth
                    && host.surfacePreferredHeight === Theme.size.islandTransientCompactHeight,
                    "compact transient uses the shared OSD geometry bounds");
            require(!host.surfaceFocusable && host.contentIncomingItem !== null
                    && host.contentIncomingOpacity === 1,
                    "settled transient owns one opaque visual and never steals focus");
            compactTransientWidth = host.surfacePreferredWidth;
            compactTransientHeight = host.surfacePreferredHeight;
            require(coordinator.requestNotification("surface-notification", 2, 1, host.surfaceToken),
                    "notification preempts the compact transient");
            require(!coordinator.presentationVisible,
                    "notification hold waits for its taller entry completion");
        } else if (step === 15) {
            const surface = host.fallbackSurface;
            require(surface !== null, "notification revision keeps one live surface");
            if (notificationRevisionProbeStage === 0) {
                if (!awaitState(coordinator.ownerName === "notification"
                                && surface.geometryAnimationRunning
                                && host.transientDetailText === "Review requested",
                                "notification entry did not begin its visible geometry change")) {
                    return;
                }
                notificationRevisionProbe = Object.freeze({
                                                               "epoch": surface.ownerEpoch,
                                                               "revision": surface.ownerRevision
                                                           });
                require(coordinator.requestNotification("surface-notification", 2, 2,
                                                        host.surfaceToken),
                        "newer notification revision replaces the visible event in place");
                surface.refreshSurfaceState();
                require(surface.ownerEpoch === notificationRevisionProbe.epoch
                        && surface.ownerRevision === notificationRevisionProbe.revision + 1,
                        "the same transient owner updates its revision without replacing ownership");
                notificationRevisionProbeStage = 1;
                retry.restart();
                return;
            }
            if (!awaitState(!surface.geometryAnimationRunning
                            && !host.contentTransitionRunning
                            && host.contentOutgoingItem === null
                            && coordinator.presentationVisible && host.transientCommitted
                            && host.transientDetailText === "Updated review",
                            "replacement notification did not settle with its current payload")) {
                return;
            }
            requireMorphSettled("notification revision replacement");
            require(host.transientPrimaryText === "Messages"
                    && surface.ownerEpoch === notificationRevisionProbe.epoch,
                    "notification revision keeps ownership and replaces stale text");
            require(host.surfacePreferredWidth > compactTransientWidth
                    && host.surfacePreferredHeight > compactTransientHeight
                    && host.surfacePreferredHeight
                       > Theme.size.islandTransientNotificationHeight,
                    "replacement notification body grows the existing island");
            notificationRevisionProbeStage = 0;
            notificationRevisionProbe = null;
            require(coordinator.invalidateTransient("surface-notification", 2),
                    "notification source invalidation releases current ownership");
        } else if (step === 16) {
            if (!awaitState(coordinator.ownerName === "volume" && coordinator.presentationVisible
                            && host.transientPrimaryText === "Built-in Audio"
                            && !host.contentTransitionRunning
                            && host.contentOutgoingItem === null,
                            "fresh compact predecessor did not restore visibly")) {
                return;
            }
            require(coordinator.invalidateTransient("surface-volume", 1),
                    "restored compact source invalidates cleanly");
        } else if (step === 17) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible
                            && !host.contentTransitionRunning
                            && host.contentOutgoingItem === null,
                            "transient invalidation did not restore settled Idle")) {
                return;
            }
            const transientMinimalCandidate = UserConfig.mutableSnapshot(UserConfig.snapshot);
            transientMinimalCandidate.appearance.motion = "minimal";
            const transientMinimal = UserConfig.validateCandidate(transientMinimalCandidate);
            require(transientMinimal !== null && UserConfig.publish(transientMinimal)
                    && Theme.motion.scale === 0,
                    "transient Minimal probe publishes synchronous motion");
            host.reducedMotion = true;
            require(coordinator.requestWorkspace("surface-workspace", 3, 1, host.surfaceToken),
                    "Minimal workspace transient enters");
        } else if (step === 18) {
            if (!awaitState(coordinator.ownerName === "workspace"
                            && coordinator.presentationVisible && host.transientCommitted
                            && !host.contentTransitionRunning
                            && host.contentOutgoingItem === null,
                            "Minimal transient did not settle and commit")) {
                return;
            }
            require(host.transientPrimaryText === "Development" && host.transientDetailText
                    === "Desktop 2 of 4", "Minimal motion preserves transient state meaning");
            require(host.surfacePreferredWidth <= Theme.size.islandTransientCompactWidth,
                    "workspace transient stays within the compact surface width bound");
            require(!host.geometryAnimationRunning
                    && host.contentIncomingItem !== null && host.contentIncomingOpacity === 1,
                    "Minimal motion synchronously settles transient geometry and content");
            requireMorphSettled("Minimal workspace transient");
            requireWorkspacePresentationGeometry(host.contentIncomingItem.sourceItem,
                                                 "Minimal workspace transient");
            require(coordinator.invalidateTransient("surface-workspace", 3),
                    "Minimal source invalidates");
        } else if (step === 19) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible
                            && !host.contentTransitionRunning
                            && host.contentOutgoingItem === null,
                            "final transient cleanup did not restore settled Idle")) {
                return;
            }
            require(mountedRegionCount === 0 && host.loadedDashboardRegionCount === 0,
                    "settled Idle unloads dashboard regions after Interactive interruptions");
            require(!coordinator.setHover(host.surfaceGeneration + 1, true),
                    "stale surface intent cannot reopen the dashboard");
            host.reducedMotion = true;
            require(host.requestDeliberateExpansion(),
                    "Modal predecessor opens through deliberate surface intent");
        } else if (step === 20) {
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible
                            && host.dashboardFocused,
                            "Modal predecessor did not become focused")) {
                return;
            }
            require(coordinator.syncPolkitModal(true, true, 1),
                    "controlled Modal snapshot enters");
        } else if (step === 21) {
            if (!awaitState(coordinator.ownerName === "polkitModal"
                            && coordinator.presentationVisible && host.surfaceFocusable
                            && host.polkitLoaded && host.polkitFocused
                            && Math.abs(host.renderedPanelWidth
                                        - host.surfacePreferredWidth) <= 1
                            && Math.abs(host.renderedPanelHeight
                                        - host.surfacePreferredHeight) <= 1
                            && !host.contentTransitionRunning,
                            "Polkit presentation did not settle, acknowledge, and focus")) {
                return;
            }
            require(host.surfacePreferredWidth > 0 && host.surfacePreferredHeight > 0
                    && Math.abs(host.renderedPanelWidth
                                - host.surfacePreferredWidth) <= 1
                    && Math.abs(host.renderedPanelHeight
                                - host.surfacePreferredHeight) <= 1
                   ,
                    "Polkit panel geometry actual=" + host.renderedPanelWidth + "x"
                    + host.renderedPanelHeight + " preferred=" + host.surfacePreferredWidth + "x"
                    + host.surfacePreferredHeight + " duration="
                    + " running=" + host.geometryAnimationRunning);
            requireMorphSettled("Minimal Polkit presentation");
            require(host.polkitIdentityCount === 2 && host.polkitResponseFieldVisible,
                    "normalized identities and the live prompt reach the Modal view");
            require(!coordinator.openLauncher(host.surfaceToken)
                    && !coordinator.openSession(host.surfaceToken),
                    "Modal rejects lower-priority Interactive requests");
            fakePolkitController.promptGeneration += 1;
        } else if (step === 22) {
            if (!awaitState(host.polkitResponseFocused,
                            "new prompt generation did not focus the response field")) {
                return;
            }
            fakePolkitController.available = false;
        } else if (step === 23) {
            if (!awaitState(!host.polkitLoaded && !host.polkitResponseFieldVisible,
                            "unavailable controller did not destroy the credential view")) {
                return;
            }
            fakePolkitController.available = true;
        } else if (step === 24) {
            if (!awaitState(host.polkitLoaded && coordinator.presentationVisible
                            && host.surfaceFocusable,
                            "restored controller did not recreate the current Modal view")) {
                return;
            }
            modalRevisionBeforeReplacement = coordinator.revision;
            fakePolkitController.flowGeneration = 2;
            fakePolkitController.promptGeneration += 1;
            require(coordinator.syncPolkitModal(true, true, 2),
                    "serialized flow replacement updates Modal in place");
            require(!coordinator.presentationVisible,
                    "flow replacement waits for its matching presentation acknowledgement");
        } else if (step === 25) {
            if (!awaitState(coordinator.ownerName === "polkitModal"
                            && coordinator.presentationVisible && host.polkitLoaded
                            && host.polkitResponseFocused,
                            "replacement flow did not acknowledge and refocus")) {
                return;
            }
            require(coordinator.revision === modalRevisionBeforeReplacement + 1,
                    "flow replacement increments one Modal revision without a second frame");
            const modalFullCandidate = UserConfig.mutableSnapshot(UserConfig.snapshot);
            modalFullCandidate.appearance.motion = "full";
            const modalFull = UserConfig.validateCandidate(modalFullCandidate);
            require(modalFull !== null && UserConfig.publish(modalFull),
                    "Modal exit restores configured Full motion");
            host.reducedMotion = false;
            require(coordinator.syncPolkitModal(false, false, 0),
                    "terminal absent snapshot releases Modal");
            const sensitiveFace = host.fallbackSurface.visualLayerForKind(
                                      coordinatorCore.ownerPolkitModal);
            require(sensitiveFace.sourceItem === null && !sensitiveFace.visible
                    && (host.contentOutgoingItem === null
                        || host.contentOutgoingItem.sourceItem === null),
                    "leaving Modal immediately invalidates the sensitive face and its source");
            require(fakePolkitController.submitCount === 0,
                    "Modal exit cannot dispatch an unauthorised response");
        } else if (step === 26) {
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible
                            && host.dashboardFocused && !host.polkitLoaded
                            && !host.contentTransitionRunning
                            && host.contentOutgoingItem === null,
                            "Modal completion state owner=" + coordinator.ownerName + " visible="
                            + coordinator.presentationVisible + " focused=" + host.dashboardFocused
                            + " polkitLoaded=" + host.polkitLoaded + " target="
                            + coordinator.focusTarget + " serial="
                            + coordinator.focusRequestSerial)) {
                return;
            }
            require(host.cancelDashboard(), "restored predecessor remains cancellable");
        } else if (step === 27) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible
                            && !host.surfaceFocusable,
                            "final Modal predecessor cleanup did not restore Idle")) {
                return;
            }
            require(coordinator.setHover(host.surfaceGeneration, true),
                    "Expanded menu scenario enters through pointer hover");
        } else if (step === 28) {
            if (!awaitState(coordinator.ownerName === "expanded"
                            && coordinator.presentationVisible,
                            "hover-expanded menu scenario did not settle")) {
                return;
            }
            require(host.menuParentWindow.beginShellMenu()
                    && host.menuParentWindow.reportHover(false)
                    && coordinator.ownerName === "expanded" && coordinator.hoverIntent,
                    "opening a shell-owned menu suppresses its synthetic hover exit");
            require(host.menuParentWindow.completeShellMenuAction(),
                    "selecting the Expanded tray menu action resets to Idle");
        } else if (step === 29) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible
                            && !host.surfaceFocusable,
                            "Expanded tray menu selection did not settle at Idle")) {
                return;
            }
            require(coordinator.openTray(host.surfaceToken),
                    "focus-loss scenario opens a shell-focused tray");
        } else if (step === 30) {
            if (!awaitState(coordinator.ownerName === "tray" && coordinator.presentationVisible
                            && host.trayFocused,
                            "focus-loss tray did not become focused")) {
                return;
            }
            require(!host.menuParentWindow.handleWindowActivation(true),
                    "focus acquisition records ownership without resetting");
            require(host.menuParentWindow.handleWindowActivation(false),
                    "reliable external focus loss resets non-modal ownership");
        } else if (step === 31) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible
                            && !host.surfaceFocusable && !host.trayLoaded,
                            "external focus loss did not settle at Idle")) {
                return;
            }
            require(coordinator.openLauncher(host.surfaceToken),
                    "external launch scenario opens Launcher");
        } else if (step === 32) {
            if (!awaitState(coordinator.ownerName === "launcher"
                            && coordinator.presentationVisible && host.launcherFocused,
                            "external launch scenario did not focus Launcher")) {
                return;
            }
            require(host.menuParentWindow.interactiveContent.launchSelected(),
                    "selected application dispatches through Launcher");
            fakeApplicationModel.launchAccepted(1, "fixture.desktop");
        } else if (step === 33) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible
                            && !host.surfaceFocusable && !host.launcherLoaded,
                            "accepted application launch did not settle at Idle")) {
                return;
            }
            const surfaceGeneration = host.surfaceGeneration;
            const schemes = ["nagi-dark", "nagi-oled", "nagi-light", "system", "custom"];
            for (let index = 0; index < schemes.length; index += 1) {
                const candidate = UserConfig.mutableSnapshot(UserConfig.snapshot);
                candidate.appearance.scheme = schemes[index];
                candidate.appearance.accentMode = "nagi";
                candidate.appearance.customSurface = "#101010";
                candidate.appearance.customText = "#F0F0F0";
                candidate.appearance.customAccent = "#8090FF";
                const normalized = UserConfig.validateCandidate(candidate);
                require(normalized !== null, "surface scheme candidate is valid");
                UserConfig.publish(normalized);
                require(Theme.snapshot.scheme === schemes[index],
                        "scheme " + schemes[index] + " reaches the live surface Theme");
            }
            Theme.wallpaperPalette = Object.freeze({
                                                       "accent": "#D06BFF"
                                                   });
            const accentModes = ["nagi", "system", "wallpaper", "custom"];
            for (let index = 0; index < accentModes.length; index += 1) {
                const candidate = UserConfig.mutableSnapshot(UserConfig.snapshot);
                candidate.appearance.accentMode = accentModes[index];
                candidate.appearance.customAccent = "#8090FF";
                const normalized = UserConfig.validateCandidate(candidate);
                require(normalized !== null, "surface accent candidate is valid");
                UserConfig.publish(normalized);
                require(Theme.snapshot.mode === accentModes[index],
                        "accent mode " + accentModes[index] + " reaches the live Theme");
            }
            const extreme = UserConfig.mutableSnapshot(UserConfig.snapshot);
            extreme.appearance.scheme = "custom";
            extreme.appearance.accentMode = "custom";
            extreme.appearance.customSurface = "#F4F6F8";
            extreme.appearance.customText = "#151A21";
            extreme.appearance.customAccent = "#003B82";
            extreme.appearance.surfaceOpacity = 0.85;
            extreme.appearance.borderIntensity = 1;
            extreme.appearance.blurEnabled = true;
            extreme.appearance.motion = "minimal";
            extreme.appearance.outerRadius = 32;
            extreme.island.compactHeight = 48;
            extreme.island.compactPadding = 32;
            extreme.island.expandedWidthPercent = 0.6;
            extreme.island.expandedHeightPercent = 0.6;
            extreme.island.showWorkspace = false;
            extreme.island.showWeather = false;
            extreme.media.compactVisible = false;
            const normalizedExtreme = UserConfig.validateCandidate(extreme);
            require(normalizedExtreme !== null, "combined live appearance extreme is valid");
            UserConfig.publish(normalizedExtreme);
            require(host.surfaceGeneration === surfaceGeneration && host.backgroundRadius === 32
                    && host.blurRequested && Theme.snapshot.contrast.textOnSurface >= 4.5
                    && Theme.snapshot.contrast.textSecondaryOnSurface >= 4.5
                    && Theme.snapshot.contrast.textMutedOnSurface >= 4.5
                    && Theme.snapshot.contrast.statusOnSurface >= 4.5
                    && Theme.snapshot.contrast.dangerOnFills >= 4.5,
                    "live customization updates one surface with complete readable roles and no service recreation");
            require(coordinator.setHover(host.surfaceGeneration, false),
                    "custom geometry clears stale hover intent before explicit expansion");
            require(host.requestDeliberateExpansion(),
                    "custom geometry expands through the existing coordinator path");
        } else if (step === 34) {
            if (!awaitState(coordinator.ownerName === "expanded"
                            && coordinator.presentationVisible && host.dashboardFocused
                            && !host.contentTransitionRunning
                            && host.contentOutgoingItem === null,
                            "custom geometry dashboard did not settle")) {
                return;
            }
            const customizedSurface = host.fallbackSurface;
            require(host.renderedPanelWidth <= customizedSurface.stablePanelMaximumWidth + 1
                    && host.renderedPanelHeight <= customizedSurface.stablePanelMaximumHeight + 1
                    && Math.abs(host.dashboardViewportWidth - host.renderedPanelWidth) <= 1
                    && Math.abs(host.dashboardViewportHeight - host.renderedPanelHeight) <= 1
                    && (host.dashboardNaturalWidth <= host.dashboardViewportWidth + 0.5
                        || host.dashboardHorizontalOverflow)
                    && (host.dashboardNaturalHeight <= host.dashboardViewportHeight + 0.5
                        || host.dashboardVerticalOverflow)
                   
                    && !host.geometryAnimationRunning,
                    "60% visible-panel cap keeps the natural dashboard reachable through overflow: panel="
                    + host.renderedPanelWidth + "x" + host.renderedPanelHeight + ", max="
                    + customizedSurface.stablePanelMaximumWidth + "x"
                    + customizedSurface.stablePanelMaximumHeight + ", viewport="
                    + host.dashboardViewportWidth + "x" + host.dashboardViewportHeight + ", natural="
                    + host.dashboardNaturalWidth + "x" + host.dashboardNaturalHeight + ", overflow="
                    + host.dashboardHorizontalOverflow + "/" + host.dashboardVerticalOverflow
                    + ", running=" + host.geometryAnimationRunning);
            requireMorphSettled("customized Minimal dashboard");
            require(host.cancelDashboard(), "customized dashboard remains cancellable");
            require(coordinator.setHover(host.surfaceGeneration, false),
                    "customized dashboard clears hover restoration before reset");
            Theme.wallpaperPalette = null;
            UserConfig.publish(UserConfig.defaultSnapshot(0));
        } else if (step === 35) {
            if (behaviorProbeStage === 0) {
                if (motionResetStage === 0) {
                    host.fallbackSurface.hoverInputEnabled = false;
                    require(coordinatorCore.setHover(host.surfaceToken,
                                                     host.surfaceGeneration, false),
                            "motion baseline clears pointer hover");
                    host.reducedMotion = true;
                    require(coordinatorCore.resetToIdle(host.surfaceToken),
                            "motion baseline clears live pointer and interaction intent");
                    host.fallbackSurface.refreshSurfaceState();
                    motionResetStage = 1;
                }
                if (!awaitState(coordinator.ownerName === "idle"
                                && coordinator.presentationVisible
                                && !host.contentTransitionRunning && !host.geometryAnimationRunning,
                                "customization reset did not restore settled Idle")) {
                    return;
                }
                require(host.surfaceGeneration === initialSurfaceGeneration
                        && host.backgroundRadius === Theme.radius.outer && !host.blurRequested,
                        "reset preserves the one surface and versioned appearance");
            }
            if (!runMorphBehaviorStep()) return;
            captureSoakRegistry();
            requireSoakRegistry("surface soak baseline");
            require(soakCycleCount === 100,
                    "surface soak retains the exact one-hundred-cycle contract");
            startSurfaceSoakCycle();
            return;
        } else if (step === 36) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible
                            && !host.contentTransitionRunning
                            && host.contentOutgoingItem === null
                            && Math.abs(host.renderedPanelWidth
                                        - host.surfacePreferredWidth) <= 1
                            && Math.abs(host.renderedPanelHeight
                                        - host.surfacePreferredHeight) <= 1,
                            "surface soak compact panel geometry did not settle synchronously")) {
                return;
            }
            requireSoakRegistry("surface soak compact cycle " + soakCycle);
            requireSoakGeometry("surface soak compact cycle " + soakCycle);
            require(host.surfacePreferredHeight >= soakExpectedGeometry.compactHeight
                    && host.surfacePreferredHeight <= 48
                    && !host.geometryAnimationRunning
                    && Math.abs(currentSurfaceScale() - soakDevicePixelRatio) < 0.001,
                    "Minimal motion applies compact geometry at the observed output scale");
            require(host.requestDeliberateExpansion(),
                    "surface soak expands through the existing coordinator seam");
        } else if (step === 37) {
            if (!awaitState(coordinator.ownerName === "expanded"
                            && coordinator.presentationVisible && host.dashboardFocused
                            && !host.contentTransitionRunning
                            && host.contentOutgoingItem === null
                            && Math.abs(host.renderedPanelWidth
                                        - Math.min(host.surfacePreferredWidth,
                                                   host.fallbackSurface.stablePanelMaximumWidth)) <= 1
                            && Math.abs(host.renderedPanelHeight
                                        - Math.min(host.surfacePreferredHeight,
                                                   host.fallbackSurface.stablePanelMaximumHeight)) <= 1,
                            "surface soak expanded panel geometry did not settle synchronously: owner="
                            + coordinator.ownerName + " visible=" + coordinator.presentationVisible
                            + " focused=" + host.dashboardFocused + " content="
                            + host.contentTransitionRunning + "/" + host.contentOutgoingItem
                            + " panel=" + host.renderedPanelWidth + "x" + host.renderedPanelHeight
                            + " preferred=" + host.surfacePreferredWidth + "x"
                            + host.surfacePreferredHeight)) {
                return;
            }
            requireSoakRegistry("surface soak expanded cycle " + soakCycle);
            requireSoakGeometry("surface soak expanded cycle " + soakCycle);
            require(!host.geometryAnimationRunning
                    && host.renderedPanelWidth
                    <= host.fallbackSurface.stablePanelMaximumWidth + 1
                    && host.renderedPanelHeight
                    <= host.fallbackSurface.stablePanelMaximumHeight + 1,
                    "Minimal motion applies bounded visible geometry without recurring animation");
            requireMorphSettled("surface soak expanded cycle " + soakCycle);
            transferSoakInteractiveToLiveSurface();
        } else if (step === 38) {
            if (!soakInteractiveCancellationPending) {
                if (!awaitState(coordinator.ownerName === "launcher"
                                && coordinator.presentationVisible && host.launcherLoaded,
                                "surface soak transferred Interactive generation did not settle")) {
                    return;
                }
                const ownerEpoch = coordinator.ownerEpoch;
                require(ownerEpoch === soakInteractiveEpoch
                        && coordinator.cancelInteractive(ownerEpoch),
                        "surface soak cancels the transferred Interactive generation");
                soakInteractiveCancellationPending = true;
                retry.restart();
                return;
            }
            if (!awaitState(coordinator.ownerName === "expanded"
                            && coordinatorCore.interactiveHostToken === null
                            && !host.contentTransitionRunning && host.contentOutgoingItem === null
                            && host.contentIncomingItem !== null && host.contentIncomingOpacity === 1
                            && !host.geometryAnimationRunning && !host.launcherLoaded,
                            "Minimal motion did not clear Interactive transition work")) {
                return;
            }
            const completedEpoch = soakInteractiveEpoch;
            require(host.cancelDashboard() && coordinator.ownerName === "idle"
                    && !host.geometryAnimationRunning,
                    "Minimal motion synchronously collapses the dashboard");
            require(!coordinator.cancelInteractive(completedEpoch),
                    "completed Interactive generation cannot replay");
            require(coordinator.requestWorkspace("surface-workspace", 3000 + soakCycle,
                                                 soakCycle + 1, host.surfaceToken),
                    "surface soak projects one fresh normalized transient generation");
        } else if (step === 39) {
            if (!awaitState(coordinator.ownerName === "workspace"
                            && coordinator.presentationVisible && host.transientCommitted
                            && !host.contentTransitionRunning
                            && host.contentOutgoingItem === null,
                            "surface soak transient did not settle and commit")) {
                return;
            }
            require(!host.geometryAnimationRunning
                    && host.contentIncomingItem !== null && host.contentIncomingOpacity === 1,
                    "Minimal motion keeps transient projection free of recurring work");
            require(coordinator.invalidateTransient("surface-workspace", 3000 + soakCycle)
                    && !coordinator.invalidateTransient("surface-workspace", 3000 + soakCycle),
                    "surface soak invalidates each transient generation exactly once");
            rehomeSoakModalToLiveSurface();
            requireSoakRegistry("surface soak Modal rehome cycle " + soakCycle);
        } else if (step === 40) {
            if (!awaitState(coordinator.ownerName === "polkitModal"
                            && coordinator.presentationVisible && host.surfaceFocusable
                            && host.polkitLoaded && host.polkitFocused
                            && coordinatorCore.modalHostToken === host.surfaceToken,
                            "surface soak rehomed Modal did not settle")) {
                return;
            }
            require(!host.geometryAnimationRunning
                    && soakControlCenterRehomeCount === soakCycle + 1
                    && !coordinator.openLauncher(host.surfaceToken)
                    && !coordinator.openSession(host.surfaceToken),
                    "Modal rehome stays synchronous and rejects lower-priority work");
            require(coordinator.syncPolkitModal(false, false, 0),
                    "surface soak releases the rehomed Modal generation");
        } else if (step === 41) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible
                            && coordinatorCore.pendingTransientCount === 0
                            && coordinatorCore.interactiveHostToken === null
                            && coordinatorCore.modalHostToken === null
                            && !coordinatorCore.modalPresent && !host.polkitLoaded
                            && !host.contentTransitionRunning && host.contentOutgoingItem === null
                            && !host.geometryAnimationRunning,
                            "surface soak cycle cleanup did not settle")) {
                return;
            }
            requireSoakGeometry("surface soak cleanup cycle " + soakCycle);
            requireSoakRegistry("surface soak cleanup cycle " + soakCycle);
            require(coordinatorCore.surfaceSnapshot(syntheticSoakSurfaceToken).ownerName === "none",
                    "surface soak cycle leaves no temporary surface record");
            soakCycle += 1;
            if (soakCycle < soakCycleCount) {
                startSurfaceSoakCycle();
                return;
            }
            fakePolkitController.responseVisible = false;
            require(UserConfig.publish(UserConfig.defaultSnapshot(0)),
                    "surface soak restores default settings");
            host.reducedMotion = false;
        } else if (step === 42) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible
                            && coordinatorCore.pendingTransientCount === 0
                            && !host.contentTransitionRunning && host.contentOutgoingItem === null
                            && !host.geometryAnimationRunning
                            && Math.abs(host.renderedPanelWidth
                                        - host.surfacePreferredWidth) <= 1
                            && Math.abs(host.renderedPanelHeight
                                        - host.surfacePreferredHeight) <= 1,
                            "surface soak final panel cleanup did not settle")) {
                return;
            }
            const defaults = UserConfig.defaultSnapshot(0);
            requireSoakRegistry("surface soak final cleanup");
            require(soakCycleCount === 100 && soakCycle === soakCycleCount
                    && soakControlCenterRehomeCount === soakCycleCount
                    && UserConfig.snapshot.island.compactHeight === defaults.island.compactHeight
                    && UserConfig.snapshot.island.compactPadding === defaults.island.compactPadding
                    && UserConfig.snapshot.island.expandedWidthPercent
                    === defaults.island.expandedWidthPercent
                    && UserConfig.snapshot.island.expandedHeightPercent
                    === defaults.island.expandedHeightPercent
                    && coordinatorCore.interactiveHostToken === null
                    && coordinatorCore.modalHostToken === null
                    && !coordinatorCore.modalPresent
                    && coordinatorCore.surfaceSnapshot(
                        syntheticSoakSurfaceToken).ownerName === "none"
                    && coordinatorCore.surfaceCount === host.liveSurfaceCount
                    && host.loadedDashboardRegionCount === 0
                    && mountedRegionCount === 0
                    && coordinatorCore.surfaceRouter === host
                    && soakSyntheticRouter.routeToken === null
                    && soakSyntheticRouter.fallbackToken === null
                    && host.registryRecordForToken(soakControlCenterToken) !== null,
                    "one hundred soak cycles leave default geometry and no orphan surface or owner");
            host.dashboardNavigationContent = null;
            host.fallbackSurface.hoverInputEnabled = true;
            testRegionImplicitWidth = 320;
        } else if (step === 43) {
            // The previous pointer can already have re-entered Expanded. Both
            // Idle and hover-Expanded accept the same deliberate focus request.
            require(host.requestDeliberateExpansion(),
                    "rail pointer scenario expands the existing surface");
        } else if (step === 44) {
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible
                            && host.dashboardFocused && !host.contentTransitionRunning
                            && !host.geometryAnimationRunning,
                            "real navigation rail did not settle")) return;
            const entry = railDestinations[railPointerCase];
            const button = findObject(host.fallbackSurface.contentItem, entry.button);
            const natural = entry.owner === "tray" ? trayReference : entry.owner === "history"
                                                    ? historyReference : launcherReference;
            require(button !== null && button.enabled && button.visible,
                    "the real " + entry.button + " accepts pointer input");
            const click = button.mapToItem(host.fallbackSurface.contentItem, button.width / 2,
                                           button.height / 2);
            railActivationPoint = click;
            railNaturalWidth = natural.implicitWidth;
            railNaturalHeight = natural.implicitHeight;
            const finalLeft = host.surfaceWidth / 2 - railNaturalWidth / 2;
            require(click.x > finalLeft + railNaturalWidth
                    && click.x < host.panelMappedBottomRight.x
                    && click.y > host.panelMappedTopLeft.y
                    && click.y < host.panelMappedBottomRight.y,
                    entry.owner + " rail click begins outside its smaller natural destination: "
                    + "click=" + click.x + "," + click.y + " panel="
                    + host.renderedPanelWidth + "x" + host.renderedPanelHeight + " natural="
                    + railNaturalWidth + "x" + railNaturalHeight);
            inputDriver.click(button);
            railOwnerEpoch = coordinator.ownerEpoch;
        } else if (step === 45) {
            const entry = railDestinations[railPointerCase];
            if (!awaitState(coordinator.ownerName === entry.owner
                            && coordinator.presentationVisible && host.surfaceFocusable
                            && !host.contentTransitionRunning && !host.geometryAnimationRunning,
                            entry.owner + " pointer-origin transition did not settle")) return;
            require(coordinator.ownerEpoch === railOwnerEpoch
                    && host.surfacePreferredWidth <= railNaturalWidth + 1
                    && host.renderedPanelWidth > railNaturalWidth + 1
                    && railActivationPoint.x < host.panelMappedBottomRight.x - Theme.radius.outer
                    && host.renderedPanelWidth <= host.fallbackSurface.stablePanelMaximumWidth + 1
                    && host.renderedPanelHeight <= host.fallbackSurface.stablePanelMaximumHeight + 1
                    && host.contentOutgoingItem === null && host.retainedPresentationCount === 0,
                    entry.owner + " keeps the clicked point inside its visible bounded panel, "
                    + "without enlarging the natural viewport or retaining Expanded");
            requireShadowGutterContract(entry.owner + " protected input mask");
            const surface = host.fallbackSurface;
            const source = host.interactiveContent;
            const paintedFace = findPresentationForSource(surface.contentItem, source);
            require(source !== null && paintedFace !== null,
                    entry.owner + " retains its real interactive source and rendered face");
            const paintedOrigin = paintedFace.mapToItem(surface.contentItem, 0, 0);
            const inputOrigin = source.mapToItem(surface.contentItem, 0, 0);
            require(Math.abs(paintedOrigin.x - inputOrigin.x) <= 1
                    && Math.abs(paintedOrigin.y - inputOrigin.y) <= 1,
                    entry.owner + " hit targets coincide with the visible centered natural face "
                    + "while the panel is held wider");
            if (railPointerCase === 0) {
                require(host.fallbackSurface.reportHover(false),
                        "deliberate pointer exit reports through the surface hover seam");
                require(host.fallbackSurface.renderedPanelWidth > railNaturalWidth + 1,
                        "pointer exit releases the floor through the existing spring, not a snap");
                require(coordinator.ownerName === entry.owner,
                        "pointer exit alone does not masquerade as window deactivation");
                host.fallbackSurface.handleWindowActivation(true);
                require(host.fallbackSurface.handleWindowActivation(false),
                        "genuine external focus transfer dismisses the active interaction");
                railPointerCase += 1;
                step = 43;
                advance();
                return;
            }
            if (entry.owner === "launcher") {
                const search = source.searchFieldItem;
                const back = findObject(source, "subviewBackButton");
                require(search !== null && back !== null,
                        "Launcher exposes a real search field and a separate focus target");
                back.forceActiveFocus(Qt.TabFocusReason);
                const localSearch = search.mapToItem(source, search.width / 2,
                                                     search.height / 2);
                const visibleSearch = paintedFace.mapToItem(surface.contentItem, localSearch);
                inputDriver.mouseClick(surface.contentItem, visibleSearch.x, visibleSearch.y,
                                       Qt.LeftButton);
                require(host.launcherFocused && coordinator.ownerEpoch === railOwnerEpoch,
                        "clicking the painted Launcher search field reaches its live input "
                        + "while the panel is wider than its natural face");
                inputDriver.mouseMove(surface.contentItem, visibleSearch.x + 6, visibleSearch.y);
                require(host.geometryAnimationRunning,
                        "pointer entering Launcher starts the natural-size spring convergence");
                back.forceActiveFocus(Qt.TabFocusReason);
                const convergingSearch = paintedFace.mapToItem(surface.contentItem, localSearch);
                const liveSearch = search.mapToItem(surface.contentItem, search.width / 2,
                                                    search.height / 2);
                require(Math.abs(convergingSearch.x - liveSearch.x) <= 1
                        && Math.abs(convergingSearch.y - liveSearch.y) <= 1,
                        "input follows the painted search field throughout floor release");
                inputDriver.mouseClick(surface.contentItem, convergingSearch.x,
                                       convergingSearch.y, Qt.LeftButton);
                require(host.launcherFocused && coordinator.ownerEpoch === railOwnerEpoch,
                        "search remains clickable at its painted position while width converges");
            }
            if (entry.owner !== "launcher") {
                const background = findObject(surface.contentItem, "surfaceBackground");
                inputDriver.mouseMove(background, background.width / 2,
                                      Math.min(background.height / 2, railNaturalHeight / 2));
            }
        } else if (step === 46) {
            if (!awaitState(!host.geometryAnimationRunning && !host.contentTransitionRunning
                            && Math.abs(host.renderedPanelWidth - railNaturalWidth) <= 1
                            && Math.abs(host.renderedPanelHeight - railNaturalHeight) <= 1,
                            "moving into " + railDestinations[railPointerCase].owner
                            + " releases only the temporary visible-panel floor")) return;
            require(coordinator.ownerName === railDestinations[railPointerCase].owner
                    && coordinator.ownerEpoch === railOwnerEpoch && host.surfaceFocusable
                    && host.retainedPresentationCount === 0 && host.contentOutgoingItem === null,
                    "natural-size release keeps the focused destination and does not revive Expanded");
            requireShadowGutterContract("released rail input mask");
            require(coordinator.cancelInteractive(railOwnerEpoch),
                    "rail scenario cancels its current focused owner");
        } else if (step === 47) {
            if (!awaitState(coordinator.ownerName === "expanded" && !host.contentTransitionRunning
                            && !host.geometryAnimationRunning,
                            "rail scenario restores the dashboard for the next action")) return;
            railPointerCase += 1;
            if (railPointerCase < railDestinations.length) {
                step = 43;
                advance();
                return;
            }
            const keyboard = findObject(host.fallbackSurface.contentItem, "dashboardTray");
            require(keyboard !== null, "keyboard path targets the real Tray rail button");
            keyboard.forceActiveFocus(Qt.TabFocusReason);
            inputDriver.keyClick(Qt.Key_Space);
        } else if (step === 48) {
            if (!awaitState(coordinator.ownerName === "tray" && coordinator.presentationVisible
                            && host.trayFocused && !host.contentTransitionRunning
                            && !host.geometryAnimationRunning,
                            "keyboard rail activation did not settle")) return;
            requireMorphSettled("keyboard Tray activation remains natural sized");
            require(host.renderedPanelWidth <= trayReference.implicitWidth + 1
                    && host.renderedPanelHeight <= trayReference.implicitHeight + 1,
                    "a hovering cursor cannot create a floor for keyboard activation");
            console.warn("actual rail pointer floor and keyboard activation passed");
            Qt.exit(0);
            return;
        }

        step += 1;
        advance();
    }

    component TestRegion: Item {
        implicitWidth: test.testRegionImplicitWidth
        implicitHeight: test.testRegionImplicitHeight
        activeFocusOnTab: true
        Component.onCompleted: test.mountedRegionCount += 1
        Component.onDestruction: test.mountedRegionCount -= 1
    }

    component TestClockRegion: TestRegion {
        implicitWidth: Math.max(1, test.testRegionImplicitWidth / 2)
    }

    Component {
        id: mediaRegion
        TestRegion {}
    }

    Component {
        id: clockRegion
        TestClockRegion {}
    }

    Component {
        id: statusRegion
        TestRegion {}
    }

    Component {
        id: quickControlsRegion
        TestRegion {}
    }

    Component {
        id: audioRegion
        TestRegion {}
    }

    Component {
        id: notificationsRegion
        TestRegion {}
    }

    Component {
        id: navigationRegion
        TestRegion {}
    }

    ListModel {
        id: fakeHistoryModel

        ListElement {
            firstAdmissionSequence: "2"
            state: "expired"
            appName: "Mail"
            summary: "Build finished"
            body: "The controlled verification run completed."
        }

        ListElement {
            firstAdmissionSequence: "1"
            state: "live"
            appName: "Messages"
            summary: "Review requested"
            body: "Please check the latest changes."
        }
    }

    QtObject {
        id: fakeNotificationService

        readonly property var historyModel: fakeHistoryModel
        readonly property bool serverOwned: true

        function dismiss(recordKey) {
            const index = historyIndex(recordKey);
            if (index < 0) {
                return false;
            }
            fakeHistoryModel.remove(index);
            return true;
        }

        function historyIndex(recordKey) {
            const key = String(recordKey);
            for (let index = 0; index < fakeHistoryModel.count; index += 1) {
                if (String(fakeHistoryModel.get(index).firstAdmissionSequence) === key) {
                    return index;
                }
            }
            return -1;
        }
    }

    QtObject {
        id: syntheticSoakSurfaceToken
    }

    QtObject {
        id: soakSyntheticRouter

        property var routeToken: null
        property var fallbackToken: null

        function routeSurfaceToken(excludedToken) {
            if (routeToken !== null && routeToken !== excludedToken) {
                return routeToken;
            }
            if (fallbackToken !== null && fallbackToken !== excludedToken) {
                return fallbackToken;
            }
            return host.routeSurfaceToken(excludedToken);
        }
    }

    QtObject {
        id: modalIdentity

        readonly property string id: "unix-user:1000"
        readonly property string string: "unix-user:developer"
        readonly property string displayName: "Developer"
        readonly property bool isGroup: false
    }

    QtObject {
        id: alternateModalIdentity

        readonly property string id: "unix-user:0"
        readonly property string string: "unix-user:root"
        readonly property string displayName: "Administrator"
        readonly property bool isGroup: false
    }

    TestCase {
        id: inputDriver

        name: "Retained exit input driver"
        when: false

        function click(item) {
            mouseClick(item, item.width / 2, item.height / 2, Qt.LeftButton);
        }
    }
    QtObject {

        id: fakePolkitController

        property bool available: true
        property bool terminal: false
        property bool responseRequired: true
        property bool responseVisible: false
        property bool submissionPending: false
        property bool cancellationPending: false
        property int flowGeneration: 1
        property int promptGeneration: 1
        property int failureGeneration: 0
        property string message: "Authentication is required to change system settings."
        property string actionId: "org.example.settings.modify"
        property string inputPrompt: "Password"
        property string supplementaryMessage: ""
        property bool supplementaryIsError: false
        property string iconName: "object-locked-symbolic"
        property var identities: [modalIdentity, alternateModalIdentity]
        property var selectedIdentity: modalIdentity
        property int submitCount: 0

        function cancel() {
            cancellationPending = true;
        }
        function selectIdentity(identity) {
            selectedIdentity = identity;
        }
        function submitResponse(response, generation) {
            submitCount += 1;
            submissionPending = true;
            responseRequired = false;
        }
    }

    QtObject {
        id: fakeSessionService

        readonly property bool backendReady: true
        readonly property bool pending: false
        readonly property string pendingAction: "none"
        readonly property string failure: "none"

        signal operationFinished(int requestId, string action, string outcome)

        function clearFailure() {
        }
        function requestAction(action) {
            return 0;
        }
    }

    QtObject {
        id: fakeGamingPerformance

        readonly property bool active: true
        readonly property bool available: true

        function resolveTransient(sourceToken, sourceGeneration, sourceRevision) {
            if (sourceToken !== "gaming-performance") {
                return null;
            }
            return {
                "kind": "gamingPerformance",
                "icon": "gamingPerformance",
                "primary": "Gaming performance active",
                "detail": "",
                "generation": sourceGeneration,
                "revision": sourceRevision
            };
        }
    }

    QtObject {
        id: fakeClock

        readonly property string text: "10:42"
        readonly property bool showIdleDate: false
        readonly property string dateText: ""
    }

    QtObject {
        id: fakeVirtualDesktops

        readonly property var outputToken: ({})
        readonly property var projection: Object.freeze({
                                                           "available": true,
                                                           "currentId": "second",
                                                           "currentName": "Desktop 2",
                                                           "currentPosition": 1,
                                                           "desktops": Object.freeze([{
                                                                   "id": "first",
                                                                   "name": "Desktop 1",
                                                                   "position": 0
                                                               }, {
                                                                   "id": "second",
                                                                   "name": "Desktop 2",
                                                                   "position": 1
                                                               }, {
                                                                   "id": "third",
                                                                   "name": "Desktop 3",
                                                                   "position": 2
                                                               }, {
                                                                   "id": "fourth",
                                                                   "name": "Desktop 4",
                                                                   "position": 3
                                                               }])
                                                       })

        function outputTokenFor(screen) {
            return screen === null || screen === undefined ? null : outputToken;
        }

        function projectionFor(screen) {
            return screen === null || screen === undefined ? null : projection;
        }
    }

    QtObject {
        id: fakeMedia

        readonly property bool available: true
        readonly property string artist: "Nagi"
        readonly property string title: "Continuity"
    }
    QtObject {
        id: fakeTransientSource

        function resolveTransient(sourceToken, sourceGeneration, sourceRevision) {
            if (sourceToken === "surface-volume" && sourceGeneration === 1 && sourceRevision
                    === 1) {
                return {
                    "detail": "Output volume",
                    "iconName": "audio-volume-high-symbolic",
                    "primary": "Built-in Audio",
                    "progress": 0.64,
                    "value": "64%"
                };
            }
            if (sourceToken === "surface-notification" && sourceGeneration === 2 && sourceRevision
                    === 1) {
                return {
                    "appIconName": Quickshell.shellPath("assets/icons/nagi/notification.svg"),
                    "body": "A bounded plain-text notification body that grows the island.",
                    "detail": "Review requested",
                    "iconName": "preferences-desktop-notification-symbolic",
                    "primary": "Messages",
                    "value": ""
                };
            }
            if (sourceToken === "surface-notification" && sourceGeneration === 2 && sourceRevision
                    === 2) {
                return {
                    "appIconName": Quickshell.shellPath("assets/icons/nagi/notification.svg"),
                    "body": "The replacement keeps the same event identity.\nIts taller body changes the endpoint.\nRelated bindings must settle together.\nNo ordinary drift segment may follow.",
                    "detail": "Updated review",
                    "iconName": "preferences-desktop-notification-symbolic",
                    "primary": "Messages",
                    "value": ""
                };
            }
            const fullWorkspace = sourceToken === "surface-workspace-full"
                                  && sourceGeneration === 3 && sourceRevision === 1;
            const soakGeneration = sourceGeneration - 3000;
            if ((fullWorkspace || sourceToken === "surface-workspace")
                    && (fullWorkspace || (sourceGeneration === 3 && sourceRevision === 1)
                        || (Number.isInteger(soakGeneration) && soakGeneration >= 0
                            && soakGeneration < test.soakCycleCount
                            && sourceRevision === soakGeneration + 1))) {
                return {
                    "detail": "Desktop 2 of 4",
                    "iconName": "preferences-desktop-virtual-symbolic",
                    "primary": "Development",
                    "value": "2 / 4"
                };
            }
            return null;
        }
    }

    QtObject {
        id: fakeApplicationModel

        readonly property bool initialized: true
        readonly property bool available: true
        readonly property bool pinMutationPending: false
        readonly property string pinFailure: "none"
        readonly property var pinIds: []
        readonly property var recencyIds: ["fixture.desktop"]
        readonly property var applications: [{
                "id": "fixture.desktop",
                "name": "Fixture Application",
                "keywords": ["fixture"],
                "icon": "",
                "nameOrder": 0,
                "idOrder": 0
            }]
        readonly property var pinnedApplications: []
        readonly property var recentApplications: applications

        signal launchAccepted(int requestId, string desktopFileId)
        signal launchRejected(int requestId, string category)
        signal pinCommitted(string desktopFileId)
        signal pinRemoved(string desktopFileId)
        signal pinReordered(string desktopFileId)
        signal pinMutationFailed(string category)

        function captureDiscoveryGeneration() {
        }
        function dispatchLaunch(desktopFileId) {
            return 1;
        }
        function movePin(desktopFileId, newIndex) {
            return false;
        }
        function pin(desktopFileId) {
            return true;
        }
        function unpin(desktopFileId) {
            return false;
        }
        function eligible(desktopFileId) {
            return desktopFileId === "com.github.wwmm.easyeffects.desktop";
        }
    }
    QtObject {
        id: fakeEasyEffectsStatus

        property bool ready: true
        property bool refreshing: false
        property bool loadPending: false
        property bool interested: ownerEpoch > 0
        property real ownerEpoch: 0
        property string loadPipeline: ""
        property string loadState: "none"
        property string outputState: "lastLoaded"
        property string outputName: "Studio"
        property string inputState: "lastLoaded"
        property string inputName: "Voice"
        property var outputPresets: ["Cinema", "Studio"]
        property string outputPresetsState: "ready"
        property var inputPresets: ["Voice"]
        property string inputPresetsState: "ready"

        function activate(epoch) {
            ownerEpoch = epoch;
            return true;
        }
        function deactivate(epoch) {
            if (ownerEpoch !== epoch) {
                return false;
            }
            ownerEpoch = 0;
            return true;
        }
        function refresh(epoch) {
            return ownerEpoch === epoch;
        }
        function validPresetName(name) {
            return typeof name === "string" && name.length > 0 && name.length <= 100
                    && !/[:/\\\n\r]/u.test(name);
        }
        function loadPreset(epoch, pipeline, name) {
            const candidates = pipeline === "output" ? outputPresets :
                               pipeline === "input" ? inputPresets : [];
            return ownerEpoch === epoch && candidates.indexOf(name) !== -1;
        }
    }
    QtObject {
        id: fakeTrayAdapter
        property int activationCount: 0
        signal menuActionTriggered(int token)

        function activate(token) {
            activationCount += 1;
            return "accepted";
        }

        function secondaryActivate(token) {
            return "accepted";
        }

        function openMenu(token, window, x, y) {
            return "dispatched";
        }

        function cancelMenuTracking() {
        }

        readonly property var items: [{
                "token": 1,
                "label": "Fixture tray item",
                "tooltip": "Fixture tray item",
                "iconSource": "",
                "status": "active",
                "hasMenu": false,
                "onlyMenu": false
            }]
    }

    QtObject {
        id: fakeAudioAdapter
        property int selectionCount: 0

        readonly property bool available: true
        readonly property bool pendingOutputSelection: false
        readonly property bool pendingInputSelection: false
        readonly property string failure: "none"
        readonly property bool outputEasyEffectsInternalDefault: false
        readonly property bool inputEasyEffectsInternalDefault: false
        readonly property var outputCandidates: [{
                "endpointKey": "output",
                "label": "Fixture output",
                "isDefault": true
            }]
        readonly property var inputCandidates: [{
                "endpointKey": "input",
                "label": "Fixture input",
                "isDefault": true
            }]

        function requestOutputSelection(endpointKey) {
            selectionCount += 1;
            return endpointKey === "output";
        }

        function requestInputSelection(endpointKey) {
            selectionCount += 1;
            return endpointKey === "input";
        }
    }

    QtObject {
        id: fakeWeatherAdapter

        readonly property real temperatureC: current.temperature
        readonly property string condition: current.condition
        readonly property string dayPhase: current.dayPhase
        readonly property bool stale: false
        readonly property string failure: "none"
        readonly property real lastUpdatedAgeMs: 600000
        readonly property bool manualRefreshAvailable: true
        readonly property bool refreshInFlight: false
        readonly property var current: ({
                                            "temperature": 18,
                                            "temperatureUnit": "celsius",
                                            "feelsLike": 17,
                                            "feelsLikeCalculated": true,
                                            "humidity": 62,
                                            "wind": 12,
                                            "windUnit": "kmh",
                                            "condition": "partlyCloudy",
                                            "dayPhase": "day"
                                        })
        readonly property var hourly: {
            const values = [];
            for (let index = 1; index <= 12; index += 1) {
                values.push({
                                "forecastEpoch": Date.now() + index * 3600000,
                                "temperature": 18 + index / 10,
                                "temperatureUnit": "celsius",
                                "condition": "partlyCloudy",
                                "dayPhase": "day"
                            });
            }
            return values;
        }
        readonly property var daily: {
            const values = [];
            for (let index = 0; index < 5; index += 1) {
                values.push({
                                "dateEpoch": Date.now() + index * 86400000,
                                "minimumTemperature": 10 + index,
                                "maximumTemperature": 20 + index,
                                "temperatureUnit": "celsius",
                                "condition": "clear",
                                "dayPhase": "day"
                            });
            }
            return values;
        }
        readonly property var model: ({
                                          "location": "Fixture City",
                                          "current": current,
                                          "hourly": hourly,
                                          "daily": daily
                                      })

        function manualRefresh() {
            return true;
        }
    }

    Item {
        visible: false

        AudioSelectionView {
            id: audioWidthReference

            active: false
            adapter: fakeAudioAdapter
            applicationModel: fakeApplicationModel
            easyEffectsStatus: fakeEasyEffectsStatus
            ownerEpoch: 0
            reducedMotion: true
        }

        WeatherView {
            id: weatherReference

            active: true
            adapter: fakeWeatherAdapter
            ownerEpoch: 0
            reducedMotion: true
        }

        LauncherView {
            id: launcherReference

            active: false
            applicationModel: fakeApplicationModel
            ownerEpoch: 0
            reducedMotion: true
        }

        NotificationHistoryView {
            id: historyReference

            active: false
            ownerEpoch: 0
            reducedMotion: true
            service: fakeNotificationService
        }

        SessionView {
            id: sessionReference

            active: false
            ownerEpoch: 0
            reducedMotion: true
            service: fakeSessionService
        }

        TrayView {
            id: trayReference

            active: false
            adapter: fakeTrayAdapter
            ownerEpoch: 0
            reducedMotion: true
        }

        IslandPanel {
            id: defaultPanelReference
        }
    }

    IslandStateCoordinator {
        id: coordinatorCore
    }

    QtObject {
        id: coordinator

        readonly property var snapshot: coordinatorCore.surfaceSnapshot(host.surfaceToken)
        readonly property string ownerName: snapshot.ownerName
        readonly property bool presentationVisible: snapshot.presentationVisible
        readonly property real ownerEpoch: snapshot.ownerEpoch
        readonly property real revision: snapshot.revision
        readonly property int focusTarget: snapshot.focusTarget
        readonly property real focusRequestSerial: snapshot.focusRequestSerial
        readonly property bool hoverIntent: snapshot.hoverIntent
        readonly property bool explicitExpandedIntent: snapshot.explicitExpandedIntent
        readonly property int focusNone: coordinatorCore.focusNone
        readonly property int focusExpandedDashboard: coordinatorCore.focusExpandedDashboard
        readonly property int focusLauncherSearch: coordinatorCore.focusLauncherSearch
        readonly property int focusSessionActions: coordinatorCore.focusSessionActions
        readonly property int focusNotificationHistory: coordinatorCore.focusNotificationHistory
        readonly property int focusTray: coordinatorCore.focusTray
        readonly property int focusAudio: coordinatorCore.focusAudio
        readonly property int focusWeather: coordinatorCore.focusWeather

        function refreshFallback(result) {
            if (host.fallbackSurface !== null) {
                host.fallbackSurface.refreshSurfaceState();
            }
            return result;
        }

        function cancelInteractive(epoch) {
            return refreshFallback(coordinatorCore.cancelInteractive(epoch));
        }
        function invalidateTransient(token, generation) {
            return refreshFallback(coordinatorCore.invalidateTransient(token, generation));
        }
        function openAudio(token) {
            return coordinatorCore.openAudio(token);
        }
        function openWeather(token) {
            return coordinatorCore.openWeather(token);
        }
        function openHistory(token) {
            return coordinatorCore.openHistory(token);
        }
        function openLauncher(token) {
            return coordinatorCore.openLauncher(token);
        }
        function openSession(token) {
            return coordinatorCore.openSession(token);
        }
        function openTray(token) {
            return coordinatorCore.openTray(token);
        }
        function requestNotification(token, generation, sourceRevision, initiatingToken) {
            return coordinatorCore.requestNotification(token, generation, sourceRevision,
                                                       initiatingToken);
        }
        function requestVolume(token, generation, sourceRevision, initiatingToken) {
            return coordinatorCore.requestVolume(token, generation, sourceRevision,
                                                 initiatingToken);
        }
        function requestWorkspace(token, generation, sourceRevision, initiatingToken) {
            return coordinatorCore.requestWorkspace(token, generation, sourceRevision,
                                                    initiatingToken);
        }
        function setExplicitExpanded(generation, value) {
            const accepted = coordinatorCore.setExplicitExpanded(host.surfaceToken, generation,
                                                                 value);
            host.fallbackSurface.refreshSurfaceState();
            return accepted;
        }
        function setHover(generation, value) {
            const accepted = coordinatorCore.setHover(host.surfaceToken, generation, value);
            host.fallbackSurface.refreshSurfaceState();
            return accepted;
        }
        function syncPolkitModal(active, flowPresent, flowGeneration) {
            return refreshFallback(coordinatorCore.syncPolkitModal(active, flowPresent,
                                                                   flowGeneration));
        }
    }

    IslandSurfaceHost {
        id: host

        coordinator: coordinatorCore
        virtualDesktops: fakeVirtualDesktops
        dashboardMediaContent: mediaRegion
        dashboardClockContent: clockRegion
        dashboardStatusContent: statusRegion
        dashboardQuickControlsContent: quickControlsRegion
        dashboardAudioContent: audioRegion
        dashboardNotificationsContent: notificationsRegion
        dashboardNavigationContent: navigationRegion
        sessionService: fakeSessionService
        trayAdapter: fakeTrayAdapter
        audioAdapter: fakeAudioAdapter
        weather: fakeWeatherAdapter
        gamingPerformance: fakeGamingPerformance
        clock: fakeClock
        media: fakeMedia
        polkitController: fakePolkitController
        notificationService: fakeNotificationService
        applicationModel: fakeApplicationModel
        easyEffectsStatusService: fakeEasyEffectsStatus
        workspaceTransientSource: fakeTransientSource
        brightnessTransientSource: fakeTransientSource
        volumeTransientSource: fakeTransientSource
        notificationTransientSource: fakeTransientSource
        onControlCenterRequested: function (initiatingToken) {
            if (initiatingToken !== syntheticSoakSurfaceToken) {
                return;
            }
            const initiatingScreen = host.screenForToken(initiatingToken);
            const routedToken = initiatingScreen === null ? host.routeSurfaceToken(
                                                                initiatingToken) : initiatingToken;
            test.soakControlCenterToken = routedToken;
            test.soakControlCenterRehomeCount += 1;
        }
    }

    FrameAnimation {
        running: test.geometryDirection !== "" || (test.step === 35
                                                     && test.behaviorProbeStage === 1)
        onTriggered: {
            if (test.geometryDirection !== "") Qt.callLater(test.sampleGeometry);
            if (test.step === 35 && test.behaviorProbeStage === 1
                    && host.contentTransitionRunning
                    && !host.contentTransitionDestinationReady
                    && !host.geometryAnimationRunning && host.contentOutgoingOpacity > 0)
                test.coldPreparationObserved = true;
        }
    }

    Timer {
        id: retry

        interval: 10
        onTriggered: test.runStep()
    }

    Component.onCompleted: advance()
}

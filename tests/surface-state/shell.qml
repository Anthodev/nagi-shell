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
    property var notificationRevisionSegment: null
    property real launcherExitAnchorX: 0
    property real launcherExitMappedX: 0
    property bool launcherExitTransformObserved: false
    readonly property int maximumRetryAttempts: 500
    readonly property int soakCycleCount: 100
    property int soakCycle: 0
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
    property int geometrySampleCount: 0
    property real geometryStartTimeMs: 0
    property int geometryStableSamples: 0
    property int widthStartSample: -1
    property int heightStartSample: -1
    property real geometryScreenWidth: 0
    property real geometryStartTopMargin: 0
    property real geometryStartWidth: 0
    property real geometryStartHeight: 0
    property real geometryLastWidth: 0
    property real geometryLastHeight: 0
    property real geometryTargetWidth: 0
    property real geometryTargetHeight: 0
    property real maximumCenteringError: 0
    property real maximumTopMarginDelta: 0
    property bool geometryMonotonic: true
    property var geometrySegmentSnapshot: null
    property int motionProbeStage: 0
    property bool motionEntryRequested: false
    property int motionEntryBaselineSequence: 0
    property int motionResetStage: 0
    property bool motionProbeSampling: false
    property var motionObservedSegment: null
    property var motionFrozenSegment: null
    property bool motionChainExpectedActive: false
    property bool motionChainGapObserved: false
    property bool motionFollowUpObserved: false
    readonly property string polkitVisualState: Quickshell.env("NAGI_POLKIT_VISUAL_STATE") ?? ""

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
    function surfaceMatches(reference) {
        return Math.abs(host.surfacePreferredWidth - reference.implicitWidth) <= 1
                && Math.abs(host.surfacePreferredHeight - reference.implicitHeight) <= 1
                && Math.abs(host.surfaceWidth - reference.implicitWidth) <= 1
                && Math.abs(host.surfaceHeight - reference.implicitHeight) <= 1;
    }

    function requireSurfaceMatches(reference, label) {
        console.warn(label + " geometry: " + host.surfaceWidth + "x" + host.surfaceHeight
                     + " (natural " + reference.implicitWidth + "x" + reference.implicitHeight
                     + ")");
        require(surfaceMatches(reference),
                label + " PanelWindow geometry must equal the view's natural implicit size");
    }

    function currentMorphSegment() {
        const surface = host.fallbackSurface;
        require(surface !== null, "the live surface exists for morph inspection");
        return Object.freeze({
                                 "sequence": surface.morphSequence,
                                 "fromWidth": surface.morphSegmentFromWidth,
                                 "fromHeight": surface.morphSegmentFromHeight,
                                 "toWidth": surface.morphSegmentToWidth,
                                 "toHeight": surface.morphSegmentToHeight
                             });
    }

    function requireMorphSegmentUnchanged(segment, label) {
        const surface = host.fallbackSurface;
        require(surface !== null && segment !== null
                && surface.morphSequence === segment.sequence
                && Math.abs(surface.morphSegmentFromWidth - segment.fromWidth) < 0.001
                && Math.abs(surface.morphSegmentFromHeight - segment.fromHeight) < 0.001
                && Math.abs(surface.morphSegmentToWidth - segment.toWidth) < 0.001
                && Math.abs(surface.morphSegmentToHeight - segment.toHeight) < 0.001,
                label + " keeps one immutable geometry segment");
    }

    function requireCoupledMorphSample(label) {
        const surface = host.fallbackSurface;
        require(surface !== null && surface.morphProgress >= 0 && surface.morphProgress <= 1,
                label + " keeps normalized morph progress");
        const widthDelta = surface.morphSegmentToWidth - surface.morphSegmentFromWidth;
        const heightDelta = surface.morphSegmentToHeight - surface.morphSegmentFromHeight;
        if (Math.abs(widthDelta) <= 1 || Math.abs(heightDelta) <= 1) {
            return;
        }

        const widthProgress = (surface.implicitWidth - surface.morphSegmentFromWidth) / widthDelta;
        const heightProgress = (surface.implicitHeight - surface.morphSegmentFromHeight)
                             / heightDelta;
        require(Math.abs(widthProgress - heightProgress) <= 0.05
                && Math.abs(widthProgress - surface.morphProgress) <= 0.05
                && Math.abs(heightProgress - surface.morphProgress) <= 0.05,
                label + " drives width and height from the same progress");
    }

    function requireMorphSettled(label) {
        const surface = host.fallbackSurface;
        require(surface !== null && !surface.geometryAnimationRunning
                && surface.morphProgress === 1 && !surface.morphFollowUpPending
                && Math.abs(surface.implicitWidth - surface.morphSegmentToWidth) < 0.001
                && Math.abs(surface.implicitHeight - surface.morphSegmentToHeight) < 0.001
                && surface.interactiveExitOffset === 0,
                label + " settles at the exact endpoint without pending work or transforms");
    }

    function sampleMotionProbeFrame() {
        const surface = host.fallbackSurface;
        if (surface === null || !surface.geometryAnimationRunning) {
            return;
        }
        if (motionObservedSegment === null
                || motionObservedSegment.sequence !== surface.morphSequence) {
            motionObservedSegment = currentMorphSegment();
        } else {
            requireMorphSegmentUnchanged(motionObservedSegment, "sampled morph");
        }
        requireCoupledMorphSample("sampled morph");
    }

    function startGeometrySampling(direction, transition) {
        geometryDirection = direction;
        geometrySampleCount = 0;
        geometryStartTimeMs = Date.now();
        geometryStableSamples = 0;
        widthStartSample = -1;
        heightStartSample = -1;
        geometryScreenWidth = host.surfaceScreenWidth;
        geometryStartTopMargin = host.surfaceTopMargin;
        geometryStartWidth = host.surfaceWidth;
        geometryStartHeight = host.surfaceHeight;
        geometryLastWidth = geometryStartWidth;
        geometryLastHeight = geometryStartHeight;
        maximumCenteringError = 0;
        maximumTopMarginDelta = 0;
        geometryMonotonic = true;
        require(transition(), direction + " geometry transition was rejected");
        geometrySegmentSnapshot = null;
        geometryTargetWidth = host.surfacePreferredWidth;
        geometryTargetHeight = host.surfacePreferredHeight;
    }

    function sampleGeometry() {
        geometrySampleCount += 1;
        if (geometrySegmentSnapshot === null) {
            if (!host.fallbackSurface.geometryAnimationRunning) {
                return;
            }
            geometrySegmentSnapshot = currentMorphSegment();
        }
        // Headless compositors can render frames faster than wall-clock animation time.
        require(Date.now() - geometryStartTimeMs <= maximumGeometryDurationMs,
                geometryDirection + " geometry morph timed out");

        requireMorphSegmentUnchanged(geometrySegmentSnapshot, geometryDirection);
        requireCoupledMorphSample(geometryDirection);
        const width = host.surfaceWidth;
        const height = host.surfaceHeight;
        const expectedLeftMargin = (geometryScreenWidth - width) / 2;
        maximumCenteringError = Math.max(maximumCenteringError,
                                         Math.abs(host.surfaceLeftMargin
                                                  - expectedLeftMargin));
        maximumTopMarginDelta = Math.max(maximumTopMarginDelta,
                                         Math.abs(host.surfaceTopMargin
                                                  - geometryStartTopMargin));

        const expanding = geometryDirection === "expanding";
        geometryMonotonic = geometryMonotonic
                && (expanding ? width >= geometryLastWidth && height >= geometryLastHeight
                              : width <= geometryLastWidth && height <= geometryLastHeight);
        if (widthStartSample < 0 && width !== geometryStartWidth) {
            widthStartSample = geometrySampleCount;
        }
        if (heightStartSample < 0 && height !== geometryStartHeight) {
            heightStartSample = geometrySampleCount;
        }
        geometryLastWidth = width;
        geometryLastHeight = height;

        const atTarget = Math.abs(width - geometryTargetWidth) <= 1
                && Math.abs(height - geometryTargetHeight) <= 1;
        geometryStableSamples = atTarget ? geometryStableSamples + 1 : 0;
        if (geometryStableSamples < 3) {
            return;
        }

        console.warn(geometryDirection + " geometry: " + geometryStartWidth + "x"
                     + geometryStartHeight + " -> " + width + "x" + height
                     + ", max centering error " + maximumCenteringError
                     + "px, max top-margin delta " + maximumTopMarginDelta + "px, starts "
                     + widthStartSample + "/" + heightStartSample);
        require(maximumCenteringError <= 1,
                geometryDirection + " must request horizontal centering within one pixel");
        require(maximumTopMarginDelta <= 1,
                geometryDirection + " must preserve the top margin within one pixel");
        require(geometryMonotonic,
                geometryDirection + " width and height must remain monotonic");
        require(widthStartSample >= 0 && heightStartSample >= 0
                && Math.abs(widthStartSample - heightStartSample) <= 1,
                geometryDirection + " width and height must start together");
        require(Math.abs(width - geometryTargetWidth) <= 1
                && Math.abs(height - geometryTargetHeight) <= 1,
                geometryDirection + " must reach its preferred end geometry");
        requireMorphSettled(geometryDirection);

        const completedDirection = geometryDirection;
        geometryDirection = "";
        step = completedDirection === "expanding" ? 1 : 5;
        advance();
    }

    function runMorphContractStep() {
        const surface = host.fallbackSurface;
        require(surface !== null, "motion contract keeps one live surface");

        if (motionProbeStage === 0) {
            if (!motionEntryRequested) {
                if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible
                                && !surface.geometryAnimationRunning,
                                "motion probe baseline did not settle at Idle")) {
                    return false;
                }
                host.reducedMotion = false;
                testRegionImplicitWidth = 120;
                testRegionImplicitHeight = 72;
                requireMorphSettled("motion probe baseline");
                motionEntryBaselineSequence = surface.morphSequence;
                require(coordinator.setHover(host.surfaceGeneration, true),
                        "motion probe enters Expanded through hover");
                surface.refreshSurfaceState();
                motionEntryRequested = true;
                retry.restart();
                return false;
            }
            if (!awaitState(surface.geometryAnimationRunning
                            && surface.morphSequence > motionEntryBaselineSequence
                            && surface.morphSequence <= motionEntryBaselineSequence + 2,
                            "hover entry did not capture one coupled geometry segment: running="
                            + surface.geometryAnimationRunning + " sequence="
                            + surface.morphSequence + " baseline=" + motionEntryBaselineSequence
                            + " owner=" + coordinator.ownerName + " duration="
                            + surface.geometryAnimationDuration + " size=" + surface.implicitWidth
                            + "x" + surface.implicitHeight)) {
                return false;
            }
            motionFrozenSegment = currentMorphSegment();
            motionObservedSegment = null;
            motionProbeSampling = true;
            motionProbeStage = 1;
            retry.restart();
            return false;
        }

        if (motionProbeStage === 1) {
            if (!awaitState(surface.geometryAnimationRunning && surface.morphProgress > 0.05
                            && surface.morphProgress < 0.85,
                            "motion probe did not reach a running expansion sample")) {
                return false;
            }
            requireMorphSegmentUnchanged(motionFrozenSegment, "preferred-size drift baseline");
            requireCoupledMorphSample("preferred-size drift baseline");
            testRegionImplicitWidth = 152;
            testRegionImplicitHeight = 84;
            motionProbeStage = 2;
            retry.restart();
            return false;
        }

        if (motionProbeStage === 2) {
            if (!awaitState(surface.geometryAnimationRunning && surface.morphFollowUpPending,
                            "preferred-size drift did not queue one follow-up")) {
                return false;
            }
            requireMorphSegmentUnchanged(motionFrozenSegment, "first preferred-size drift");
            testRegionImplicitWidth = 168;
            testRegionImplicitHeight = 96;
            require(surface.morphFollowUpPending,
                    "multiple preferred-size drifts coalesce into the pending follow-up");
            requireMorphSegmentUnchanged(motionFrozenSegment, "multiple preferred-size drifts");
            testRegionImplicitWidth = 120;
            testRegionImplicitHeight = 72;
            motionProbeStage = 3;
            retry.restart();
            return false;
        }

        if (motionProbeStage === 3) {
            if (!awaitState(surface.geometryAnimationRunning && !surface.morphFollowUpPending,
                            "drifting back to the frozen endpoint did not clear the follow-up")) {
                return false;
            }
            requireMorphSegmentUnchanged(motionFrozenSegment, "preferred-size drift-back");
            motionChainGapObserved = false;
            motionFollowUpObserved = false;
            motionChainExpectedActive = true;
            testRegionImplicitWidth = 176;
            testRegionImplicitHeight = 104;
            motionProbeStage = 4;
            retry.restart();
            return false;
        }

        if (motionProbeStage === 4) {
            if (surface.morphSequence === motionFrozenSegment.sequence) {
                requireMorphSegmentUnchanged(motionFrozenSegment, "queued follow-up");
            }
            if (!awaitState(motionFollowUpObserved && !motionChainGapObserved
                            && surface.geometryAnimationRunning
                            && surface.morphSequence === motionFrozenSegment.sequence + 1
                            && surface.morphProgress > 0.05 && surface.morphProgress < 0.85,
                            "one immediate chained segment did not start without a running gap")) {
                return false;
            }
            require(Math.abs(surface.morphSegmentFromWidth - motionFrozenSegment.toWidth) < 0.001
                    && Math.abs(surface.morphSegmentFromHeight
                                - motionFrozenSegment.toHeight) < 0.001
                    && !surface.morphFollowUpPending,
                    "the single follow-up starts at the exact frozen endpoint");
            requireCoupledMorphSample("single preferred-size follow-up");

            const followUpWidth = surface.implicitWidth;
            const followUpHeight = surface.implicitHeight;
            const followUpSequence = surface.morphSequence;
            require(coordinator.openLauncher(host.surfaceToken),
                    "owner interruption replaces the running follow-up with Launcher");
            surface.refreshSurfaceState();
            require(coordinator.ownerName === "launcher" && surface.geometryAnimationRunning
                    && surface.morphSequence === followUpSequence + 1
                    && Math.abs(surface.morphSegmentFromWidth - followUpWidth) <= 1
                    && Math.abs(surface.morphSegmentFromHeight - followUpHeight) <= 1,
                    "owner replacement samples the current interpolated geometry once: owner="
                    + coordinator.ownerName + " running=" + surface.geometryAnimationRunning
                    + " sequence=" + surface.morphSequence + "/" + (followUpSequence + 1)
                    + " width=" + surface.morphSegmentFromWidth + "/" + followUpWidth
                    + " height=" + surface.morphSegmentFromHeight + "/" + followUpHeight);

            const launcherEpoch = coordinator.ownerEpoch;
            const launcherWidth = surface.implicitWidth;
            const launcherHeight = surface.implicitHeight;
            const launcherSequence = surface.morphSequence;
            require(coordinator.cancelInteractive(launcherEpoch),
                    "rapid Launcher cancellation restores its Expanded predecessor");
            require(coordinator.ownerName === "expanded" && surface.geometryAnimationRunning
                    && surface.morphSequence === launcherSequence + 1
                    && Math.abs(surface.morphSegmentFromWidth - launcherWidth) <= 1
                    && Math.abs(surface.morphSegmentFromHeight - launcherHeight) <= 1,
                    "same-epoch predecessor restore interrupts from current geometry");
            require(host.interactiveExitRunning && host.launcherLoaded
                    && !host.interactiveExitLoaderEnabled && host.interactiveExitLoaderZ > 0,
                    "rapid restore retains an inert outgoing Loader above its replacement: exit="
                    + host.interactiveExitRunning + " loaded=" + host.launcherLoaded
                    + " enabled=" + host.interactiveExitLoaderEnabled + " z="
                    + host.interactiveExitLoaderZ);
            motionProbeStage = 5;
            retry.restart();
            return false;
        }

        if (motionProbeStage === 5) {
            if (surface.geometryAnimationRunning) {
                requireCoupledMorphSample("restored Expanded interruption");
            }
            if (!awaitState(coordinator.ownerName === "expanded"
                            && coordinator.presentationVisible && host.dashboardFocused
                            && !surface.geometryAnimationRunning && !host.interactiveExitRunning
                            && !host.launcherLoaded,
                            "interrupted predecessor did not settle, focus, and acknowledge")) {
                return false;
            }
            requireMorphSettled("interrupted Expanded predecessor");
            require(surface.hostSurfaceGeneration === initialSurfaceGeneration
                    && surface.surfaceState.ownerEpoch === coordinator.ownerEpoch
                    && surface.surfaceState.revision === coordinator.revision
                    && surface.surfaceState.presentationVisible,
                    "settled interruption preserves the exact surface and acknowledgement tuple");
            testRegionImplicitWidth = 520;
            testRegionImplicitHeight = 320;
            motionProbeStage = 6;
            retry.restart();
            return false;
        }

        if (motionProbeStage === 6) {
            if (!awaitState(surface.geometryAnimationRunning && surface.morphProgress > 0.05
                            && surface.morphProgress < 0.85,
                            "large preferred geometry did not begin one coupled segment")) {
                return false;
            }
            requireCoupledMorphSample("pre-shrink geometry");
            const candidate = UserConfig.mutableSnapshot(UserConfig.snapshot);
            candidate.island.expandedWidthPercent = 0.6;
            candidate.island.expandedHeightPercent = 0.6;
            const normalized = UserConfig.validateCandidate(candidate);
            require(normalized !== null && UserConfig.publish(normalized),
                    "screen-shrink probe publishes valid tighter geometry bounds");
            motionProbeStage = 7;
            retry.restart();
            return false;
        }

        if (motionProbeStage === 7) {
            if (!awaitState(surface.geometryAnimationRunning && surface.morphFollowUpPending,
                            "tighter live bounds did not supersede the running endpoint")) {
                return false;
            }
            const shrinkStartWidth = surface.implicitWidth;
            const shrinkStartHeight = surface.implicitHeight;
            const shrinkSequence = surface.morphSequence;
            const expectedWidth = surface.safeLogicalSize(surface.preferredWidth,
                                                          host.surfaceScreenWidth, 0.6);
            const expectedHeight = surface.safeLogicalSize(surface.preferredHeight,
                                                           host.surfaceScreenHeight, 0.6);
            surface.interruptMorphForScreenBounds();
            require(surface.geometryAnimationRunning && surface.morphSequence
                    === shrinkSequence + 1
                    && Math.abs(surface.morphSegmentFromWidth - shrinkStartWidth) <= 1
                    && Math.abs(surface.morphSegmentFromHeight - shrinkStartHeight) <= 1
                    && Math.abs(surface.morphSegmentToWidth - expectedWidth) < 0.001
                    && Math.abs(surface.morphSegmentToHeight - expectedHeight) < 0.001,
                    "screen-bound shrink interrupts from current geometry to the new safe bound");
            requireCoupledMorphSample("screen-bound interruption");

            host.reducedMotion = true;
            requireMorphSettled("minimal-motion interruption");
            require(surface.geometryAnimationDuration === 0
                    && surface.morphSegmentFromWidth === expectedWidth
                    && surface.morphSegmentFromHeight === expectedHeight
                    && surface.morphSegmentToWidth === expectedWidth
                    && surface.morphSegmentToHeight === expectedHeight,
                    "Minimal motion synchronously snaps both axes and clears the segment");

            testRegionImplicitWidth = 120;
            testRegionImplicitHeight = 72;
            require(UserConfig.publish(UserConfig.defaultSnapshot(0)),
                    "motion probe restores default geometry settings");
            require(host.cancelDashboard(),
                    "motion probe returns the hover-expanded surface to Idle");
            motionProbeStage = 8;
            retry.restart();
            return false;
        }

        if (motionProbeStage === 8) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible
                            && !surface.geometryAnimationRunning && !host.interactiveExitRunning
                            && host.surfaceWidth === host.surfacePreferredWidth
                            && host.surfaceHeight === host.surfacePreferredHeight,
                            "motion probe cleanup did not settle at exact Idle geometry")) {
                return false;
            }
            requireMorphSettled("motion probe cleanup");
            host.reducedMotion = false;
            motionProbeSampling = false;
            motionObservedSegment = null;
            motionChainExpectedActive = false;
            motionProbeStage = 9;
            return true;
        }

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
                            && host.loadedDashboardRegionCount === 6,
                            "actual surface and pre-warmed dashboard did not settle within five seconds")) {
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
            require(mountedRegionCount === host.liveSurfaceCount * 6,
                    "all dashboard regions mount before expansion starts");
            startGeometrySampling("expanding", function () {
                return coordinator.setHover(host.surfaceGeneration, true);
            });
            return;
        } else if (step === 1) {
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible
                            && host.loadedDashboardRegionCount === 6,
                            "hover dashboard did not become visible within five seconds")) {
                return;
            }
            require(coordinator.focusTarget === coordinator.focusNone && !host.surfaceFocusable,
                    "hover expansion never steals keyboard focus");
            require(host.surfaceToken === initialSurfaceToken && host.surfaceGeneration
                    === initialSurfaceGeneration, "expansion preserves the one live surface");
            const expectedWidth = Theme.spacing.xl * 2 + 120 + Theme.spacing.lg + 120
                                  + Theme.spacing.lg + 120;
            require(host.backgroundCoversSurface,
                    "expanded background geometry equals the surface geometry");
            const expectedHeight = Theme.spacing.xl * 2
                                   + Math.max(testRegionImplicitHeight, testRegionImplicitHeight)
                                   + testRegionImplicitHeight * 3 + Theme.spacing.lg * 3;
            require(host.surfacePreferredWidth === expectedWidth
                    && host.surfacePreferredHeight === expectedHeight && host.surfaceWidth
                    <= expectedWidth && host.surfaceHeight <= expectedHeight,
                    "expanded geometry derives from mounted row content");
            require(host.geometryAnimationDuration === Theme.motion.durationExpansion
                    && host.geometryAnimationDuration >= 170
                    && host.geometryAnimationDuration <= 210,
                    "expanded geometry uses the responsive 170–210 ms interpolation");
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
            require(coordinator.openLauncher(host.surfaceToken),
                    "higher-priority interaction interrupts Expanded");
        } else if (step === 3) {
            if (!awaitState(coordinator.ownerName === "launcher"
                            && coordinator.presentationVisible && host.surfaceFocusable
                            && host.launcherFocused && host.launcherResultCount === 1
                            && !host.launcherResultScrollVisible && surfaceMatches(launcherReference)
                            && host.loadedDashboardRegionCount === 6,
                            "launcher state: owner=" + coordinator.ownerName + " visible="
                            + coordinator.presentationVisible + " focusable="
                            + host.surfaceFocusable + " focused=" + host.launcherFocused
                            + " regions=" + host.loadedDashboardRegionCount + " target="
                            + coordinator.focusTarget
                            + " serial=" + coordinator.focusRequestSerial)) {
                return;
            }
            require(host.launcherSelectedId === "fixture.desktop"
                    && host.surfaceToken === initialSurfaceToken,
                    "launcher selection did not remain on the original surface");
            requireSurfaceMatches(launcherReference, "launcher");
            const expectedLauncherWidth = Theme.spacing.xxl * 15 + Theme.spacing.lg * 2;
            require(launcherReference.implicitWidth === expectedLauncherWidth
                    && Math.abs(host.surfacePreferredWidth - expectedLauncherWidth) <= 1
                    && Math.abs(host.surfaceWidth - expectedLauncherWidth) <= 1,
                    "launcher surface width is exactly the 480 px lane plus frame padding");
            require(!host.launcherResultScrollVisible,
                    "one launcher result must not create a phantom scrollbar");
            focusSerialBeforeRestore = coordinator.focusRequestSerial;
            require(coordinator.cancelInteractive(coordinator.ownerEpoch),
                    "interrupted interaction cancels through the coordinator");
            require(host.interactiveExitRunning && host.launcherLoaded && host.surfaceFocusable
                    && host.interactiveExitLoaderZ > 0,
                    "reverse exit retains focus and layers Launcher above the restored dashboard");
            require(!host.interactiveExitLoaderEnabled,
                    "outgoing Launcher is disabled as soon as ownership returns");
            launcherExitAnchorX = host.interactiveExitLoaderX;
            launcherExitMappedX = host.interactiveExitMappedX;
            require(host.interactiveExitDuration === Theme.motion.durationNormal
                    && host.interactiveExitDuration === 120
                    && host.geometryAnimationDuration === Theme.motion.durationExpansion
                    && host.geometryAnimationDuration === 190,
                    "internal exit uses 120 ms while outer geometry uses 190 ms");
            require(Math.abs(host.surfacePreferredWidth - launcherReference.implicitWidth) > 1,
                    "outer preferred geometry switches immediately instead of staging after exit");
        } else if (step === 4) {
            if (host.interactiveExitRunning && host.interactiveExitOffset > 0) {
                require(host.interactiveExitLoaderX === launcherExitAnchorX,
                        "anchored outgoing Loader geometry remains unchanged during exit");
                if (host.interactiveExitMappedX > launcherExitMappedX) {
                    require(host.interactiveExitMappedX - launcherExitMappedX > 0,
                            "outgoing Loader transform moves in the expected positive direction");
                    launcherExitTransformObserved = true;
                }
            }
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible
                            && host.surfaceFocusable && host.dashboardFocused
                            && !host.interactiveExitRunning && !host.launcherLoaded
                            && host.loadedDashboardRegionCount === 6
                            && host.surfaceWidth === host.surfacePreferredWidth
                            && host.surfaceHeight === host.surfacePreferredHeight,
                            "dashboard did not restore at settled geometry with focus")) {
                return;
            }
            require(launcherExitTransformObserved && host.interactiveExitOffset === 0,
                    "exit transform is observed mid-animation and reset on completion");
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
            host.reducedMotion = true;
            require(host.requestDeliberateExpansion(),
                    "host exposes deliberate keyboard expansion");
        } else if (step === 6) {
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible
                            && host.surfaceFocusable && host.surfacePreferredWidth
                            > Theme.size.islandIdleWidth && host.surfacePreferredHeight
                            > Theme.size.islandIdleHeight,
                            "reduced-motion dashboard did not become usable")) {
                return;
            }
            require(host.geometryAnimationDuration === 0,
                    "reduced motion removes geometry interpolation");
            require(host.cancelDashboard(), "Close remains functional with reduced motion");
        } else if (step === 7) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible,
                            "reduced-motion collapse did not restore Idle")) {
                return;
            }
            require(host.requestDeliberateExpansion(),
                    "session entry can originate from a deliberate dashboard");
        } else if (step === 8) {
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible,
                            "dashboard did not reopen for session entry")) {
                return;
            }
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
            require(!host.interactiveExitRunning && !host.geometryAnimationRunning
                    && !host.sessionLoaded && host.interactiveExitDuration === 0
                    && host.geometryAnimationDuration === 0 && host.interactiveExitOffset === 0,
                    "reduced motion synchronously finishes exit, resets its transform, and skips geometry work");
        } else if (step === 10) {
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible
                            && host.dashboardFocused,
                            "session cancellation did not restore the deliberate dashboard")) {
                return;
            }
            host.reducedMotion = false;
            require(coordinator.openHistory(host.surfaceToken),
                    "visible dashboard history entry is admitted");
            historyEpoch = coordinator.ownerEpoch;
        } else if (step === 11) {
            if (!awaitState(coordinator.ownerName === "history" && coordinator.presentationVisible
                            && host.surfaceFocusable && host.historyFocused && host.historyRowCount
                            === 2 && surfaceMatches(historyReference),
                            "history geometry/focus did not settle: surface=" + host.surfaceWidth
                            + "x" + host.surfaceHeight + " preferred=" + host.surfacePreferredWidth
                            + "x" + host.surfacePreferredHeight + " natural="
                            + historyReference.implicitWidth + "x" + historyReference.implicitHeight
                            + " focused=" + host.historyFocused + " rows=" + host.historyRowCount)) {
                return;
            }
            require(coordinator.focusTarget === coordinator.focusNotificationHistory,
                    "history presentation receives the list focus target");
            requireSurfaceMatches(historyReference, "history");
            require(!coordinator.cancelInteractive(historyEpoch - 1),
                    "stale history Back cannot close the current owner");
            require(coordinator.cancelInteractive(historyEpoch),
                    "history Back accepts the current owner epoch");
            require(host.interactiveExitRunning && host.historyLoaded && host.surfaceFocusable
                    && host.interactiveExitLoaderZ > 0,
                    "reverse exit retains focus while History fades above the dashboard");
            require(!host.interactiveExitLoaderEnabled,
                    "outgoing History is disabled immediately while retained for its fade");
        } else if (step === 12) {
            if (!trayVerified && coordinator.ownerName === "tray") {
                if (!awaitState(coordinator.presentationVisible && host.surfaceFocusable
                                && host.trayLoaded && host.trayFocused
                                && surfaceMatches(trayReference),
                                "tray view did not load at its natural size and receive focus")) {
                    return;
                }
                require(coordinator.focusTarget === coordinator.focusTray,
                        "tray presentation receives the item focus target");
                require(host.surfacePreferredWidth >= Theme.size.islandSubviewMinimumWidth
                        && host.surfaceWidth >= Theme.size.islandSubviewMinimumWidth - 1,
                        "sparse Tray keeps the shared interactive width floor");
                require(coordinator.setHover(host.surfaceGeneration, false)
                        && coordinator.ownerName === "tray" && host.surfaceFocusable,
                        "pointer exit cannot reset an active interactive subview");
                requireSurfaceMatches(trayReference, "tray");
                require(coordinator.cancelInteractive(trayEpoch),
                        "tray Back accepts the current owner epoch");
                require(host.interactiveExitRunning && host.trayLoaded && host.surfaceFocusable
                        && host.interactiveExitLoaderZ > 0,
                        "generic reverse exit keeps focus and layers Tray above its replacement");
                require(!host.interactiveExitLoaderEnabled,
                        "outgoing Tray is disabled immediately while retained for its fade");
                const trayControl = findObject(host.interactiveExitItem, "trayItemButton");
                require(trayControl !== null, "retained Tray exposes its representative control");
                inputDriver.click(trayControl);
                require(fakeTrayAdapter.activationCount === 0,
                        "disabled outgoing Tray cannot dispatch pointer activation");
                trayVerified = true;
                step = 11;
            } else if (!audioVerified && coordinator.ownerName === "audio") {
                if (!awaitState(coordinator.presentationVisible && host.surfaceFocusable
                                && host.audioLoaded && host.audioFocused
                                && Math.abs(host.surfacePreferredWidth
                                            - audioWidthReference.implicitWidth) <= 1
                                && Math.abs(host.surfaceWidth - audioWidthReference.implicitWidth)
                                <= 1,
                                "audio view did not load, focus, and drive the exact surface width")) {
                    return;
                }
                require(host.backgroundCoversSurface,
                        "interactive subview background geometry equals the surface geometry");
                require(Math.abs(host.surfacePreferredWidth - audioWidthReference.implicitWidth)
                        <= 1 && Math.abs(host.surfaceWidth - audioWidthReference.implicitWidth) <= 1,
                        "audio surface width equals the audio view implicit width");
                require(host.surfacePreferredWidth >= Theme.size.islandSubviewMinimumWidth,
                        "Audio keeps the shared interactive width floor");
                require(coordinator.focusTarget === coordinator.focusAudio,
                        "audio presentation receives the dropdown focus target");
                const presetSelect = findObject(host.interactiveContent,
                                                "audioEasyEffectsOutputPreset");
                require(presetSelect !== null && presetSelect.control !== null
                        && presetSelect.popup !== null,
                        "actual Audio surface exposes its preset select list");
                inputDriver.click(presetSelect.control);
                require(presetSelect.popup.visible && presetSelect.popup.height > 0
                        && presetSelect.popup.height <= Theme.size.controlHeightMd * 5
                        + Theme.spacing.xs * 2 + 0.5,
                        "actual preset select list opens and remains bounded to five rows");
                presetSelect.closePopup();
                require(coordinator.cancelInteractive(audioEpoch),
                        "audio Back accepts the current owner epoch");
                require(host.interactiveExitRunning && host.audioLoaded && host.surfaceFocusable
                        && host.interactiveExitLoaderZ > 0,
                        "generic reverse exit keeps focus and layers Audio above its replacement");
                require(!host.interactiveExitLoaderEnabled,
                        "outgoing Audio is disabled immediately while retained for its fade");
                const audioControl = findObject(host.interactiveExitItem, "audioOutputDropdown");
                require(audioControl !== null,
                        "retained Audio exposes its representative dropdown");
                inputDriver.click(audioControl);
                require(fakeAudioAdapter.selectionCount === 0,
                        "disabled outgoing Audio cannot dispatch pointer selection");
                audioVerified = true;
                step = 11;
            } else if (!weatherVerified && coordinator.ownerName === "weather") {
                if (!awaitState(coordinator.presentationVisible && host.surfaceFocusable
                                && host.weatherLoaded && host.weatherFocused
                                && host.surfaceWidth > 0 && host.surfaceHeight > 0,
                                "Weather view did not settle: loaded=" + host.weatherLoaded
                                + " focused=" + host.weatherFocused + " surface="
                                + host.surfaceWidth + "x" + host.surfaceHeight + " natural="
                                + weatherReference.implicitWidth + "x"
                                + weatherReference.implicitHeight)) {
                    return;
                }
                require(coordinator.focusTarget === coordinator.focusWeather,
                        "Weather presentation receives its dedicated focus target");
                require(fakeWeatherAdapter.hourly.length === 12
                        && fakeWeatherAdapter.daily.length === 5,
                        "Weather renders the bounded shared 12-hour and five-day models");
                require(host.surfaceWidth <= weatherReference.implicitWidth
                        && host.surfaceHeight <= weatherReference.implicitHeight
                        && host.backgroundCoversSurface,
                        "Weather natural content is screen-bounded and clipped by SubviewFrame");
                require(coordinator.cancelInteractive(weatherEpoch),
                        "Weather Back accepts the current owner epoch");
                require(host.interactiveExitRunning && host.weatherLoaded && host.surfaceFocusable
                        && host.interactiveExitLoaderZ > 0,
                        "generic reverse exit keeps focus and layers Weather above its replacement");
                require(!host.interactiveExitLoaderEnabled,
                        "outgoing Weather disables actions immediately");
                weatherVerified = true;
                step = 11;
            } else {
                if (!awaitState(coordinator.ownerName === "expanded"
                                && coordinator.presentationVisible && host.dashboardFocused
                                && !host.interactiveExitRunning,
                                "interactive Back did not settle the deliberate dashboard")) {
                    return;
                }
                require(!host.interactiveExitRunning,
                        "restored dashboard has no hidden recurring exit work");
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
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible,
                            "final dashboard cancellation did not restore Idle")) {
                return;
            }
            host.reducedMotion = false;
            require(coordinator.requestVolume("surface-volume", 1, 1, host.surfaceToken),
                    "actual surface accepts a compact value transient");
            require(!coordinator.presentationVisible,
                    "visible hold waits for compact entry completion");
        } else if (step === 14) {
            if (!awaitState(coordinator.ownerName === "volume" && coordinator.presentationVisible
                            && host.transientCommitted,
                            "compact value transient did not commit visibly")) {
                return;
            }
            require(host.backgroundCoversSurface,
                    "transient background geometry equals the surface geometry");
            require(host.transientPrimaryText === "Built-in Audio" && host.transientDetailText
                    === "Output volume", "compact transient resolves the exact normalized payload");
            require(host.surfacePreferredWidth
                    >= Theme.size.islandTransientCompactMinimumWidth
                    && host.surfacePreferredWidth <= Theme.size.islandTransientCompactWidth
                    && host.surfacePreferredHeight === Theme.size.islandTransientCompactHeight,
                    "compact transient uses the shared OSD geometry bounds");
            require(!host.transientEntryAnimationRunning && !host.surfaceFocusable,
                    "settled transient suspends animation and never steals focus");
            compactTransientWidth = host.surfacePreferredWidth;
            compactTransientHeight = host.surfacePreferredHeight;
            require(coordinator.requestNotification("surface-notification", 2, 1, host.surfaceToken),
                    "notification preempts the compact transient");
            require(!coordinator.presentationVisible,
                    "notification hold waits for its taller entry completion");
        } else if (step === 15) {
            const surface = host.fallbackSurface;
            require(surface !== null, "notification revision probe keeps one live surface");
            if (notificationRevisionProbeStage === 0) {
                if (!awaitState(coordinator.ownerName === "notification"
                                && surface.geometryAnimationRunning
                                && surface.morphProgress > 0.05 && surface.morphProgress < 0.85
                                && !surface.morphFollowUpPending
                                && host.transientDetailText === "Review requested"
                                && Math.abs(surface.morphSegmentToHeight
                                            - host.surfacePreferredHeight) < 0.001,
                                "notification entry did not expose one stable running segment")) {
                    return;
                }
                const oldSegment = currentMorphSegment();
                notificationRevisionProbe = Object.freeze({
                                                               "epoch": surface.ownerEpoch,
                                                               "revision": surface.ownerRevision,
                                                               "sequence": surface.morphSequence,
                                                               "width": surface.implicitWidth,
                                                               "height": surface.implicitHeight,
                                                               "oldTargetWidth": oldSegment.toWidth,
                                                               "oldTargetHeight": oldSegment.toHeight
                                                           });
                require(coordinator.requestNotification("surface-notification", 2, 2,
                                                        host.surfaceToken),
                        "newer notification revision replaces the visible event in place");
                surface.refreshSurfaceState();
                require(surface.ownerEpoch === notificationRevisionProbe.epoch
                        && surface.ownerRevision === notificationRevisionProbe.revision + 1
                        && surface.morphSequence === notificationRevisionProbe.sequence
                        && !surface.morphFollowUpPending,
                        "same-epoch revision waits for one coalesced semantic interruption");
                requireMorphSegmentUnchanged(oldSegment, "queued notification replacement");
                notificationRevisionProbeStage = 1;
                retry.restart();
                return;
            }
            if (notificationRevisionProbeStage === 1) {
                if (!awaitState(surface.geometryAnimationRunning
                                && surface.morphSequence
                                === notificationRevisionProbe.sequence + 1
                                && surface.ownerEpoch === notificationRevisionProbe.epoch
                                && surface.ownerRevision
                                === notificationRevisionProbe.revision + 1,
                                "notification revision did not start exactly one new segment")) {
                    return;
                }
                require(Math.abs(surface.morphSegmentFromWidth
                                 - notificationRevisionProbe.width) <= 1
                        && Math.abs(surface.morphSegmentFromHeight
                                    - notificationRevisionProbe.height) <= 1
                        && Math.abs(surface.morphSegmentToWidth
                                    - host.surfacePreferredWidth) < 0.001
                        && Math.abs(surface.morphSegmentToHeight
                                    - host.surfacePreferredHeight) < 0.001
                        && !surface.morphFollowUpPending,
                        "revision interruption samples the current pose and freezes its new endpoint: from="
                        + surface.morphSegmentFromWidth + "x" + surface.morphSegmentFromHeight
                        + " observed=" + notificationRevisionProbe.width + "x"
                        + notificationRevisionProbe.height + " to=" + surface.morphSegmentToWidth
                        + "x" + surface.morphSegmentToHeight + " preferred="
                        + host.surfacePreferredWidth + "x" + host.surfacePreferredHeight
                        + " oldTarget=" + notificationRevisionProbe.oldTargetWidth + "x"
                        + notificationRevisionProbe.oldTargetHeight + " pending="
                        + surface.morphFollowUpPending);
                notificationRevisionSegment = currentMorphSegment();
                notificationRevisionProbeStage = 2;
                retry.restart();
                return;
            }
            if (surface.geometryAnimationRunning) {
                requireMorphSegmentUnchanged(notificationRevisionSegment,
                                             "running notification replacement");
            }
            if (!awaitState(!surface.geometryAnimationRunning && coordinator.presentationVisible
                            && host.transientCommitted,
                            "replacement notification did not settle and acknowledge")) {
                return;
            }
            requireMorphSegmentUnchanged(notificationRevisionSegment,
                                         "settled notification replacement");
            requireMorphSettled("notification revision replacement");
            require(surface.morphSequence === notificationRevisionProbe.sequence + 1
                    && !surface.morphFollowUpPending,
                    "one semantic revision produces one sequence with no ordinary drift follow-up");
            require(host.transientPrimaryText === "Messages" && host.transientDetailText
                    === "Updated review",
                    "notification revision replaces content without stale text");
            require(host.surfacePreferredWidth > compactTransientWidth
                    && host.surfacePreferredHeight > compactTransientHeight
                    && host.surfacePreferredHeight
                    > Theme.size.islandTransientNotificationHeight,
                    "replacement notification body grows the existing island");
            notificationRevisionProbeStage = 0;
            notificationRevisionProbe = null;
            notificationRevisionSegment = null;
            require(coordinator.invalidateTransient("surface-notification", 2),
                    "notification source invalidation releases current ownership");
        } else if (step === 16) {
            if (!awaitState(coordinator.ownerName === "volume" && coordinator.presentationVisible
                            && host.transientPrimaryText === "Built-in Audio",
                            "fresh compact predecessor did not restore visibly")) {
                return;
            }
            require(coordinator.invalidateTransient("surface-volume", 1),
                    "restored compact source invalidates cleanly");
        } else if (step === 17) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible,
                            "transient invalidation did not restore Idle")) {
                return;
            }
            host.reducedMotion = true;
            require(coordinator.requestWorkspace("surface-workspace", 3, 1, host.surfaceToken),
                    "reduced-motion workspace transient enters");
        } else if (step === 18) {
            if (!awaitState(coordinator.ownerName === "workspace"
                            && coordinator.presentationVisible && host.transientCommitted,
                            "reduced-motion transient did not commit")) {
                return;
            }
            require(host.transientPrimaryText === "Development" && host.transientDetailText
                    === "Desktop 2 of 4", "reduced motion preserves transient state meaning");
            require(host.surfacePreferredWidth <= Theme.size.islandTransientCompactWidth,
                    "workspace transient stays within the compact surface width bound");
            require(host.geometryAnimationDuration === 0 && !host.transientEntryAnimationRunning,
                    "reduced motion removes geometry and entry animation work");
            require(coordinator.invalidateTransient("surface-workspace", 3),
                    "reduced-motion source invalidates");
        } else if (step === 19) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible,
                            "final transient cleanup did not restore Idle")) {
                return;
            }
            require(mountedRegionCount === host.liveSurfaceCount * 6,
                    "dashboard regions stay mounted across Interactive interruptions");
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
                            && Math.abs(host.surfaceWidth - host.surfacePreferredWidth) <= 1
                            && Math.abs(host.surfaceHeight - host.surfacePreferredHeight) <= 1,
                            "Polkit presentation did not load, acknowledge, and focus")) {
                return;
            }
            require(host.surfacePreferredWidth > 0 && host.surfacePreferredHeight > 0
                    && host.surfaceWidth <= host.surfacePreferredWidth + 1
                    && host.surfaceHeight <= host.surfacePreferredHeight + 1
                    && host.geometryAnimationDuration === 0,
                    "Polkit geometry actual=" + host.surfaceWidth + "x" + host.surfaceHeight
                    + " preferred=" + host.surfacePreferredWidth + "x"
                    + host.surfacePreferredHeight + " duration="
                    + host.geometryAnimationDuration);
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
            host.reducedMotion = false;
            require(coordinator.syncPolkitModal(false, false, 0),
                    "terminal absent snapshot releases Modal");
            require(host.interactiveExitRunning && host.polkitLoaded
                    && !host.interactiveExitLoaderEnabled,
                    "outgoing Polkit remains visual but becomes disabled immediately");
            const authenticateControl = findObject(host.interactiveExitItem,
                                                   "polkitAuthenticateButton");
            require(authenticateControl !== null,
                    "retained Polkit exposes its representative authentication control");
            inputDriver.click(authenticateControl);
            require(fakePolkitController.submitCount === 0,
                    "disabled outgoing Polkit cannot dispatch a response");
        } else if (step === 26) {
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible
                            && host.dashboardFocused && !host.polkitLoaded,
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
                            && coordinator.presentationVisible && host.dashboardFocused,
                            "custom geometry dashboard did not settle")) {
                return;
            }
            require(host.surfaceWidth <= host.surfaceScreenWidth * 0.6
                    && host.surfaceHeight <= host.surfaceScreenHeight * 0.6
                    && host.geometryAnimationDuration === 0 && host.backgroundCoversSurface,
                    "custom expanded bounds remain screen-safe and Minimal motion settles");
            require(host.cancelDashboard(), "customized dashboard remains cancellable");
            require(coordinator.setHover(host.surfaceGeneration, false),
                    "customized dashboard clears hover restoration before reset");
            Theme.wallpaperPalette = null;
            UserConfig.publish(UserConfig.defaultSnapshot(0));
        } else if (step === 35) {
            if (motionProbeStage === 0 && !motionEntryRequested) {
                if (motionResetStage === 0) {
                    host.fallbackSurface.hoverInputEnabled = false;
                    require(!host.fallbackSurface.hoverInputEnabled,
                            "motion contract suspends live pointer input");
                    require(coordinatorCore.setHover(host.surfaceToken,
                                                     host.surfaceGeneration, false),
                            "motion contract clears pointer hover before its Idle baseline");
                    host.reducedMotion = true;
                    require(coordinatorCore.resetToIdle(host.surfaceToken),
                            "motion contract resets live pointer intent before its Idle baseline");
                    host.fallbackSurface.refreshSurfaceState();
                    host.fallbackSurface.queuePresentationAcknowledgement();
                    require(!coordinatorCore.surfaceSnapshot(host.surfaceToken).hoverIntent,
                            "motion reset publishes cleared hover intent immediately");
                    motionResetStage = 1;
                }
                host.fallbackSurface.refreshSurfaceState();
                if (!awaitState(coordinator.ownerName === "idle"
                                && coordinator.presentationVisible,
                                "reset customization did not restore Idle: owner="
                                + coordinator.ownerName + " visible="
                                + coordinator.presentationVisible + " hover="
                                + coordinator.hoverIntent + " explicit="
                                + coordinator.explicitExpandedIntent + " input="
                                + host.fallbackSurface.hoverInputEnabled + " pointer="
                                + host.fallbackSurface.pointerHovered)) {
                    return;
                }
                require(host.surfaceGeneration === initialSurfaceGeneration
                        && host.backgroundRadius === Theme.radius.outer && !host.blurRequested,
                        "reset restores versioned appearance without recreating the live surface");
            }
            if (!runMorphContractStep()) {
                return;
            }
            captureSoakRegistry();
            requireSoakRegistry("surface soak baseline");
            startSurfaceSoakCycle();
            return;
        } else if (step === 36) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible
                            && host.surfaceWidth === host.surfacePreferredWidth
                            && host.surfaceHeight === host.surfacePreferredHeight,
                            "surface soak compact geometry did not settle synchronously")) {
                return;
            }
            requireSoakRegistry("surface soak compact cycle " + soakCycle);
            requireSoakGeometry("surface soak compact cycle " + soakCycle);
            require(host.surfacePreferredHeight >= soakExpectedGeometry.compactHeight
                    && host.surfacePreferredHeight <= 48 && host.geometryAnimationDuration === 0
                    && !host.geometryAnimationRunning
                    && Math.abs(currentSurfaceScale() - soakDevicePixelRatio) < 0.001,
                    "Minimal motion applies compact geometry at the observed output scale");
            require(host.requestDeliberateExpansion(),
                    "surface soak expands through the existing coordinator seam");
        } else if (step === 37) {
            if (!awaitState(coordinator.ownerName === "expanded"
                            && coordinator.presentationVisible && host.dashboardFocused
                            && host.surfaceWidth === host.surfacePreferredWidth
                            && host.surfaceHeight === host.surfacePreferredHeight,
                            "surface soak expanded geometry did not settle synchronously")) {
                return;
            }
            requireSoakRegistry("surface soak expanded cycle " + soakCycle);
            requireSoakGeometry("surface soak expanded cycle " + soakCycle);
            require(host.geometryAnimationDuration === 0 && !host.geometryAnimationRunning
                    && host.surfaceWidth <= host.surfaceScreenWidth
                    * soakExpectedGeometry.expandedWidthPercent
                    && host.surfaceHeight <= host.surfaceScreenHeight
                    * soakExpectedGeometry.expandedHeightPercent,
                    "Minimal motion applies bounded expanded geometry without recurring animation");
            transferSoakInteractiveToLiveSurface();
        } else if (step === 38) {
            if (!awaitState(coordinator.ownerName === "launcher"
                            && coordinator.presentationVisible && host.launcherLoaded,
                            "surface soak transferred Interactive generation did not settle")) {
                return;
            }
            const ownerEpoch = coordinator.ownerEpoch;
            require(ownerEpoch === soakInteractiveEpoch
                    && coordinator.cancelInteractive(ownerEpoch),
                    "surface soak cancels the transferred Interactive generation");
            require(coordinator.ownerName === "expanded"
                    && coordinatorCore.interactiveHostToken === null
                    && !host.interactiveExitRunning && !host.geometryAnimationRunning
                    && !host.launcherLoaded && host.interactiveExitDuration === 0
                    && host.geometryAnimationDuration === 0 && host.interactiveExitOffset === 0,
                    "Minimal motion synchronously clears Interactive exit work");
            require(host.cancelDashboard() && coordinator.ownerName === "idle"
                    && !host.geometryAnimationRunning,
                    "Minimal motion synchronously collapses the dashboard");
            require(!coordinator.cancelInteractive(ownerEpoch),
                    "completed Interactive generation cannot replay");
            require(coordinator.requestWorkspace("surface-workspace", 3000 + soakCycle,
                                                 soakCycle + 1, host.surfaceToken),
                    "surface soak projects one fresh normalized transient generation");
        } else if (step === 39) {
            if (!awaitState(coordinator.ownerName === "workspace"
                            && coordinator.presentationVisible && host.transientCommitted,
                            "surface soak transient did not commit")) {
                return;
            }
            require(host.geometryAnimationDuration === 0
                    && !host.geometryAnimationRunning && !host.transientEntryAnimationRunning,
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
            require(host.geometryAnimationDuration === 0 && !host.geometryAnimationRunning
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
                            && !host.interactiveExitRunning && !host.geometryAnimationRunning,
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
                            && !host.interactiveExitRunning && !host.geometryAnimationRunning
                            && host.surfaceWidth === host.surfacePreferredWidth
                            && host.surfaceHeight === host.surfacePreferredHeight,
                            "surface soak final cleanup did not settle")) {
                return;
            }
            const defaults = UserConfig.defaultSnapshot(0);
            requireSoakRegistry("surface soak final cleanup");
            require(soakCycle === soakCycleCount
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
                    && host.loadedDashboardRegionCount === 6
                    && mountedRegionCount === host.liveSurfaceCount * 6
                    && coordinatorCore.surfaceRouter === host
                    && soakSyntheticRouter.routeToken === null
                    && soakSyntheticRouter.fallbackToken === null
                    && host.registryRecordForToken(soakControlCenterToken) !== null,
                    "surface soak leaves default geometry and no orphan surface or owner");
            console.warn("actual island surface soak passed " + soakCycleCount
                         + " cycles at DPR " + soakDevicePixelRatio
                         + " with exact final registry/coordinator counts");
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
    }

    Component {
        id: mediaRegion
        TestRegion {}
    }

    Component {
        id: clockRegion
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
            const soakGeneration = sourceGeneration - 3000;
            if (sourceToken === "surface-workspace"
                    && ((sourceGeneration === 3 && sourceRevision === 1)
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
        dashboardMediaContent: mediaRegion
        dashboardClockContent: clockRegion
        dashboardQuickControlsContent: quickControlsRegion
        dashboardAudioContent: audioRegion
        dashboardNotificationsContent: notificationsRegion
        dashboardNavigationContent: navigationRegion
        sessionService: fakeSessionService
        trayAdapter: fakeTrayAdapter
        audioAdapter: fakeAudioAdapter
        weather: fakeWeatherAdapter
        gamingPerformance: fakeGamingPerformance
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

    Connections {
        target: host.fallbackSurface
        ignoreUnknownSignals: true

        function onGeometryAnimationRunningChanged() {
            if (test.motionChainExpectedActive && !target.geometryAnimationRunning) {
                test.motionChainGapObserved = true;
            }
        }

        function onMorphSequenceChanged() {
            if (test.motionChainExpectedActive && test.motionFrozenSegment !== null
                    && target.morphSequence === test.motionFrozenSegment.sequence + 1) {
                test.motionFollowUpObserved = true;
                test.motionChainExpectedActive = false;
            }
        }
    }

    FrameAnimation {
        running: test.geometryDirection !== "" || test.motionProbeSampling
        onTriggered: {
            if (test.geometryDirection !== "") {
                Qt.callLater(test.sampleGeometry);
            }
            if (test.motionProbeSampling) {
                Qt.callLater(test.sampleMotionProbeFrame);
            }
        }
    }
    Timer {
        id: retry

        interval: 10
        onTriggered: test.runStep()
    }

    Component.onCompleted: advance()
}

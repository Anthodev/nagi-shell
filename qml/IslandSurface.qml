import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Window

PanelWindow {
    id: surface

    required property var coordinator
    required property var hostSurfaceToken
    required property int hostSurfaceGeneration
    required property var surfaceHost

    // Normalized idle data sources. Null keeps the matching block collapsed,
    // so harnesses can mount the surface without the full adapter set.
    property var virtualDesktops: null
    property var clock: null
    property var weather: null
    property var media: null
    property var gamingPerformance: null
    property bool reducedMotion: false
    property var sessionService: null
    property var polkitController: null
    property var notificationService: null
    property var applicationModel: null
    property var trayAdapter: null
    property var audioAdapter: null
    property var easyEffectsStatusService: null
    // Each source resolves only its own normalized payload for an exact opaque
    // token, source generation, and backend-confirmed revision.
    property var workspaceTransientSource: null
    property var brightnessTransientSource: null
    property var volumeTransientSource: null
    property var notificationTransientSource: null

    // Downstream dashboard features provide real visual components through
    // these slots. Null content is removed instead of replaced by inert UI.
    property Component dashboardMediaContent: null
    property Component dashboardClockContent: null
    property Component dashboardQuickControlsContent: null
    property Component dashboardAudioContent: null
    property Component dashboardNotificationsContent: null
    property Component dashboardNavigationContent: null

    property var surfaceState: ({
                                    "focusRequestSerial": 0,
                                    "focusTarget": coordinator.focusNone,
                                    "ownerEpoch": 0,
                                    "ownerKind": coordinator.ownerNone,
                                    "ownerName": "none",
                                    "ownerSourceGeneration": 0,
                                    "ownerSourceRevision": 0,
                                    "ownerSourceToken": null,
                                    "presentationVisible": false,
                                    "revision": 0
                                })

    function refreshSurfaceState() {
        surfaceState = coordinator.surfaceSnapshot(hostSurfaceToken);
    }
    readonly property int ownerKind: surfaceState.ownerKind
    readonly property real ownerEpoch: surfaceState.ownerEpoch
    readonly property real ownerRevision: surfaceState.revision
    readonly property int focusTarget: surfaceState.focusTarget
    readonly property real focusRequestSerial: surfaceState.focusRequestSerial
    readonly property bool expanded: ownerKind === coordinator.ownerExpanded
    readonly property bool launcher: ownerKind === coordinator.ownerLauncher
    readonly property bool session: ownerKind === coordinator.ownerSession
    readonly property bool history: ownerKind === coordinator.ownerHistory
    readonly property bool tray: ownerKind === coordinator.ownerTray
    readonly property bool audio: ownerKind === coordinator.ownerAudio
    readonly property bool weatherDetails: ownerKind === coordinator.ownerWeather
    readonly property bool polkitControllerReady: polkitController !== null && polkitController
                                                  !== undefined && polkitController.available
                                                  === true
                                                  && typeof polkitController.selectIdentity
                                                  === "function"
                                                  && typeof polkitController.submitResponse
                                                  === "function" && typeof polkitController.cancel
                                                  === "function"
    readonly property bool polkit: ownerKind === coordinator.ownerPolkitModal
                                   && polkitControllerReady
    readonly property bool transientOwner: ownerKind === coordinator.ownerWorkspace || ownerKind
                                           === coordinator.ownerBrightness || ownerKind
                                           === coordinator.ownerVolume || ownerKind
                                           === coordinator.ownerGamingPerformance || ownerKind
                                           === coordinator.ownerNotification
    readonly property bool notificationTransient: ownerKind === coordinator.ownerNotification
    readonly property bool largeContent: expanded || launcher || history || tray || audio
                                         || weatherDetails || session || polkit
    readonly property bool interactiveOwner: launcher || history || tray || audio || weatherDetails
                                             || session || polkit
    property int previousOwnerKind: -1
    property int exitingOwnerKind: -1
    property var exitingLoader: null
    property real interactiveExitOffset: 0
    property bool focusPendingAfterExit: false
    readonly property bool interactiveExitRunning: interactiveExitAnimation.running
                                                   || exitingOwnerKind >= 0
    readonly property real interactiveExitLoaderX: exitingLoader === null ? 0 : exitingLoader.x
    readonly property real interactiveExitMappedX: interactiveExitOffset * 0 + (exitingLoader
                                                                                === null ? 0 :
                                                                                           exitingLoader.mapToItem(
                                                                                               surface.contentItem,
                                                                                               0, 0).x)
    readonly property bool interactiveExitLoaderEnabled: exitingLoader !== null
                                                         && exitingLoader.enabled
    readonly property var interactiveExitItem: exitingLoader === null ? null : exitingLoader.item
    readonly property int transientPreferredWidth: notificationTransient
                                                   ? Theme.size.islandTransientNotificationWidth :
                                                     transientLoader.item === null
                                                     ? Theme.size.islandTransientCompactWidth :
                                                       Math.min(Theme.size.islandTransientCompactWidth,
                                                                transientLoader.item.implicitWidth)
    readonly property Item interactiveContent: launcher ? launcherLoader.item : history
                                                          ? historyLoader.item : tray
                                                            ? trayLoader.item : audio
                                                              ? audioLoader.item : weatherDetails
                                                                ? weatherLoader.item : session
                                                                  ? sessionLoader.item : polkit
                                                                    ? polkitLoader.item : null
    readonly property real interactivePreferredWidth: interactiveContent === null
                                                      ? Theme.size.islandIdleWidth :
                                                        interactiveContent.implicitWidth
    readonly property real interactivePreferredHeight: interactiveContent === null
                                                       ? Theme.size.islandIdleHeight :
                                                         interactiveContent.implicitHeight
    readonly property int edgeInset: Theme.spacing.sm
    readonly property int horizontalSlack: screen === null ? edgeInset * 2 : Math.max(edgeInset * 2,
                                                                                      screen.width
                                                                                      - width)
    readonly property real settledPreferredWidth: expanded ? expandedContent.implicitWidth :
                                                             largeContent
                                                             ? interactivePreferredWidth :
                                                               transientOwner
                                                               ? transientPreferredWidth : Math.max(
                                                                     Theme.size.islandIdleWidth,
                                                                     idleContentWidth)
    readonly property real settledPreferredHeight: expanded ? expandedContent.implicitHeight :
                                                              largeContent
                                                              ? interactivePreferredHeight :
                                                                transientOwner
                                                                ? transientLoader.item === null ? (
                                                                                                      notificationTransient
                                                                                                      ? Theme.size.islandTransientNotificationHeight :
                                                                                                        Theme.size.islandTransientCompactHeight) :
                                                                                                  transientLoader.item.implicitHeight :
                                                                                                  Theme.size.islandIdleHeight
    readonly property real preferredWidth: settledPreferredWidth
    readonly property real preferredHeight: settledPreferredHeight
    readonly property int interactiveExitDuration: reducedMotion ? 0 : Theme.motion.durationNormal
    readonly property int idleContentWidth: idleContent.visible ? idleContent.implicitWidth :
                                                                  Theme.size.islandIdleWidth
    readonly property bool gamingPerformanceBadgeVisible: idleContent.visible
                                                          && idleContent.gamingPerformanceBlock.visible
    readonly property bool transientCommitted: transientLoader.item !== null
                                               && transientLoader.item.committed
    readonly property bool transientEntryAnimationRunning: transientLoader.item !== null
                                                           && transientLoader.item.entryAnimationRunning
    readonly property string transientPrimaryText: transientLoader.item === null ? "" :
                                                                                   transientLoader.item.primaryText
    readonly property string transientDetailText: transientLoader.item === null ? "" :
                                                                                  transientLoader.item.detailText
    readonly property int geometryAnimationDuration: reducedMotion ? 0 :
                                                                     Theme.motion.durationExpansion
    readonly property bool geometryAnimationRunning: geometryHeightAnimation.running
                                                     || geometryWidthAnimation.running
    readonly property point backgroundMappedTopLeft: surfaceBackground.mapToItem(surface.contentItem,
                                                                                 0, 0)
    readonly property point backgroundMappedBottomRight: surfaceBackground.mapToItem(
                                                             surface.contentItem,
                                                             surfaceBackground.width,
                                                             surfaceBackground.height)
    readonly property bool backgroundCoversSurface: backgroundMappedTopLeft.x === 0
                                                    && backgroundMappedTopLeft.y === 0
                                                    && backgroundMappedBottomRight.x
                                                    === surface.width
                                                    && backgroundMappedBottomRight.y
                                                    === surface.height
    readonly property real backgroundRadius: surfaceBackground.radius
    readonly property bool blurRequested: Theme.snapshot.blurEnabled
    readonly property bool dashboardFocused: expandedContent.activeFocus
    readonly property int loadedDashboardRegionCount: expandedContent.loadedRegionCount
    readonly property bool launcherLoaded: launcherLoader.item !== null
    readonly property bool launcherFocused: launcherLoader.item !== null
                                            && launcherLoader.item.searchFocused
    readonly property int launcherResultCount: launcherLoader.item === null ? 0 :
                                                                              launcherLoader.item.resultCount
    readonly property bool launcherResultScrollVisible: launcherLoader.item !== null
                                                        && launcherLoader.item.resultScrollBarActive
    readonly property string launcherSelectedId: launcherLoader.item === null ? "" :
                                                                                launcherLoader.item.selectedId
    readonly property bool sessionFocused: sessionLoader.item !== null
                                           && sessionLoader.item.activeFocus
    readonly property bool historyLoaded: historyLoader.item !== null
    readonly property bool trayLoaded: trayLoader.item !== null
    readonly property bool sessionLoaded: sessionLoader.item !== null
    readonly property bool trayFocused: trayLoader.item !== null && trayLoader.item.activeFocus
    readonly property bool audioLoaded: audioLoader.item !== null
    readonly property bool audioFocused: audioLoader.item !== null && audioLoader.item.activeFocus
    readonly property bool weatherLoaded: weatherLoader.item !== null
    readonly property bool weatherFocused: weatherLoader.item !== null
                                           && weatherLoader.item.activeFocus
    readonly property bool polkitLoaded: polkitLoader.item !== null
    readonly property bool polkitFocused: polkitLoader.item !== null
                                          && polkitLoader.item.activeFocus
    readonly property bool polkitResponseFocused: polkitLoader.item !== null
                                                  && polkitLoader.item.responseFocused
    readonly property int polkitIdentityCount: polkitLoader.item === null ? 0 :
                                                                            polkitLoader.item.identityCount

    readonly property bool polkitResponseFieldVisible: polkitLoader.item !== null
                                                       && polkitLoader.item.responseFieldVisible
    readonly property bool historyFocused: historyLoader.item !== null
                                           && historyLoader.item.historyFocused
    readonly property int historyRowCount: historyLoader.item === null ? 0 :
                                                                         historyLoader.item.rowCount

    readonly property bool historyEmptyStateVisible: historyLoader.item !== null
                                                     && historyLoader.item.emptyStateVisible

    property real focusedOwnerEpoch: 0
    property real appliedFocusRequestSerial: 0
    property int sessionRequestId: 0
    property real sessionRequestOwnerEpoch: 0
    property int launcherRequestId: 0
    property real launcherRequestOwnerEpoch: 0
    readonly property var backingWindow: surface.contentItem.Window.window
    property bool shellWindowWasActive: false
    property bool shellMenuOpen: false

    function isInteractiveKind(kind) {
        return kind === coordinator.ownerLauncher || kind === coordinator.ownerHistory || kind
                === coordinator.ownerTray || kind === coordinator.ownerAudio || kind
                === coordinator.ownerWeather || kind === coordinator.ownerSession || kind
                === coordinator.ownerPolkitModal;
    }

    function loaderForKind(kind) {
        if (kind === coordinator.ownerLauncher) {
            return launcherLoader;
        }
        if (kind === coordinator.ownerHistory) {
            return historyLoader;
        }
        if (kind === coordinator.ownerTray) {
            return trayLoader;
        }
        if (kind === coordinator.ownerAudio) {
            return audioLoader;
        }
        if (kind === coordinator.ownerWeather) {
            return weatherLoader;
        }
        if (kind === coordinator.ownerSession) {
            return sessionLoader;
        }
        if (kind === coordinator.ownerPolkitModal) {
            return polkitLoader;
        }
        return null;
    }

    function completeInteractiveExit() {
        interactiveExitAnimation.stop();
        const loader = exitingLoader;
        interactiveExitOffset = 0;
        if (loader !== null) {
            loader.opacity = 1;
        }
        exitingOwnerKind = -1;
        exitingLoader = null;
        if (focusPendingAfterExit) {
            focusPendingAfterExit = false;
            queueOwnerFocus();
        }
        queuePresentationAcknowledgement();
    }

    function beginInteractiveExit(kind) {
        if (!isInteractiveKind(kind)) {
            return;
        }
        if (exitingOwnerKind >= 0) {
            completeInteractiveExit();
        }

        const loader = loaderForKind(kind);
        if (loader === null || loader.item === null) {
            return;
        }
        exitingOwnerKind = kind;
        exitingLoader = loader;
        interactiveExitOffset = 0;
        loader.opacity = 1;
        if (reducedMotion) {
            completeInteractiveExit();
            return;
        }
        interactiveExitAnimation.restart();
    }

    function sourceForTransient(kind) {
        if (kind === coordinator.ownerWorkspace) {
            return workspaceTransientSource;
        }
        if (kind === coordinator.ownerBrightness) {
            return brightnessTransientSource;
        }
        if (kind === coordinator.ownerVolume) {
            return volumeTransientSource;
        }
        if (kind === coordinator.ownerGamingPerformance) {
            return gamingPerformance;
        }
        if (kind === coordinator.ownerNotification) {
            return notificationTransientSource;
        }
        return null;
    }

    function resolveTransientPresentation() {
        if (!transientOwner) {
            return null;
        }
        const source = sourceForTransient(ownerKind);
        if (source === null || source === undefined || typeof source.resolveTransient
                !== "function") {
            return null;
        }
        const resolved = source.resolveTransient(surfaceState.ownerSourceToken,
                                                 surfaceState.ownerSourceGeneration,
                                                 surfaceState.ownerSourceRevision);
        return resolved !== null && typeof resolved === "object" && !Array.isArray(resolved)
                ? resolved : null;
    }

    readonly property var transientPresentation: resolveTransientPresentation()

    function acknowledgePresentation(generation, epoch, contentRevision) {
        if (generation <= 0 || hostSurfaceGeneration !== generation || ownerEpoch !== epoch
                || ownerRevision !== contentRevision) {
            return;
        }

        const idleVisible = ownerKind === coordinator.ownerIdle && idleContent.visible;
        const dashboardVisible = ownerKind === coordinator.ownerExpanded && expandedContent.visible;
        const historyVisible = ownerKind === coordinator.ownerHistory && historyLoader.item
              !== null && historyLoader.item.visible;
        const launcherVisible = ownerKind === coordinator.ownerLauncher && launcherLoader.item
              !== null && launcherLoader.item.visible;
        const sessionVisible = ownerKind === coordinator.ownerSession && sessionLoader.item
              !== null && sessionLoader.item.visible;
        const trayVisible = ownerKind === coordinator.ownerTray && trayLoader.item !== null
              && trayLoader.item.visible;
        const audioVisible = ownerKind === coordinator.ownerAudio && audioLoader.item !== null
              && audioLoader.item.visible;
        const weatherVisible = ownerKind === coordinator.ownerWeather && weatherLoader.item
              !== null && weatherLoader.item.visible;
        const polkitVisible = polkit && polkitLoader.item !== null && polkitLoader.item.visible;
        const transientVisible = transientOwner && transientLoader.item !== null
              && transientLoader.item.visible && transientLoader.item.committed;
        if (!idleVisible && !dashboardVisible && !launcherVisible && !historyVisible &&
                !trayVisible && !audioVisible && !weatherVisible && !sessionVisible &&
                !polkitVisible && !transientVisible) {
            return;
        }

        coordinator.acknowledgeVisible(hostSurfaceToken, generation, epoch, contentRevision);
    }

    function cancelDashboard() {
        if (hostSurfaceGeneration <= 0) {
            return false;
        }

        // Explicit close/cancel also suppresses the current hover sample. The
        // HoverHandler will report true again only after a real pointer exit
        // and re-entry, so Close is never an inert control.
        const explicitAccepted = coordinator.setExplicitExpanded(hostSurfaceToken,
                                                                 hostSurfaceGeneration, false);
        const hoverAccepted = coordinator.setHover(hostSurfaceToken, hostSurfaceGeneration, false);
        refreshSurfaceState();
        return explicitAccepted && hoverAccepted;
    }

    function trackLauncherRequest(requestId, epoch) {
        if (!launcher || epoch !== ownerEpoch || requestId <= 0 || launcherRequestId !== 0) {
            return;
        }
        launcherRequestId = requestId;
        launcherRequestOwnerEpoch = epoch;
    }

    function trackSessionRequest(requestId, epoch) {
        if (!session || epoch !== ownerEpoch || requestId <= 0 || sessionRequestId !== 0) {
            return;
        }
        sessionRequestId = requestId;
        sessionRequestOwnerEpoch = epoch;
    }

    function queueOwnerFocus() {
        if (interactiveExitRunning) {
            focusPendingAfterExit = true;
            return;
        }
        const generation = hostSurfaceGeneration;
        const epoch = ownerEpoch;
        const serial = focusRequestSerial;
        Qt.callLater(function () {
            if (surface === null) {
                return;
            }
            if (generation !== surface.hostSurfaceGeneration || epoch !== surface.ownerEpoch
                    || serial !== surface.focusRequestSerial) {
                return;
            }
            if (surface.interactiveExitRunning) {
                surface.focusPendingAfterExit = true;
                return;
            }
            let target = null;
            if (surface.focusTarget === surface.coordinator.focusExpandedDashboard
                    && surface.expanded) {
                target = expandedContent;
            } else if (surface.focusTarget === surface.coordinator.focusLauncherSearch
                       && surface.launcher && launcherLoader.item !== null) {
                target = launcherLoader.item;
            } else if (surface.focusTarget === surface.coordinator.focusNotificationHistory
                       && surface.history && historyLoader.item !== null) {
                target = historyLoader.item;
            } else if (surface.focusTarget === surface.coordinator.focusSessionActions
                       && surface.session && sessionLoader.item !== null) {
                target = sessionLoader.item;
            } else if (surface.focusTarget === surface.coordinator.focusTray && surface.tray
                       && trayLoader.item !== null) {
                target = trayLoader.item;
            } else if (surface.focusTarget === surface.coordinator.focusAudio && surface.audio
                       && audioLoader.item !== null) {
                target = audioLoader.item;
            } else if (surface.focusTarget === surface.coordinator.focusWeather
                       && surface.weatherDetails && weatherLoader.item !== null) {
                target = weatherLoader.item;
            } else if (surface.focusTarget === surface.coordinator.focusPolkitModal
                       && surface.polkit && polkitLoader.item !== null) {
                target = polkitLoader.item;
            }
            if (target === null) {
                return;
            }

            surface.focusedOwnerEpoch = epoch;
            surface.appliedFocusRequestSerial = serial;
            target.focusInitialControl();
        });
    }

    function queuePresentationAcknowledgement() {
        const generation = hostSurfaceGeneration;
        const epoch = ownerEpoch;
        const contentRevision = ownerRevision;
        Qt.callLater(function () {
            if (surface !== null) {
                surface.acknowledgePresentation(generation, epoch, contentRevision);
            }
        });
    }

    function reportHover(hovered) {
        if (shellMenuOpen && !hovered) {
            return true;
        }
        const accepted = coordinator.setHover(hostSurfaceToken, hostSurfaceGeneration, hovered);
        refreshSurfaceState();
        return accepted;
    }

    function requestDeliberateExpansion() {
        const accepted = coordinator.setExplicitExpanded(hostSurfaceToken, hostSurfaceGeneration,
                                                         true);
        refreshSurfaceState();
        return accepted;
    }

    function beginShellMenu() {
        shellMenuOpen = true;
        return true;
    }

    function cancelShellMenu() {
        shellMenuOpen = false;
        if (trayAdapter !== null && typeof trayAdapter.cancelMenuTracking === "function") {
            trayAdapter.cancelMenuTracking();
        }
    }

    function finishShellMenuOpen(result) {
        if (result !== "dispatched") {
            cancelShellMenu();
            return false;
        }
        return true;
    }

    function completeShellMenuAction() {
        cancelShellMenu();
        return coordinator.resetToIdle(hostSurfaceToken);
    }

    function handleWindowActivation(active) {
        if (active) {
            if (shellMenuOpen) {
                cancelShellMenu();
            }
            shellWindowWasActive = true;
            return false;
        }
        if (shellMenuOpen) {
            shellWindowWasActive = false;
            return false;
        }
        if (!shellWindowWasActive) {
            return false;
        }
        shellWindowWasActive = false;
        return coordinator.resetToIdle(hostSurfaceToken);
    }

    function safeLogicalSize(preferredSize, screenSize, maximumFraction) {
        if (screenSize <= 0) {
            return preferredSize;
        }
        const fraction = maximumFraction ?? 1;
        const available = Math.max(1, screenSize * fraction - edgeInset * 2);
        return Math.min(preferredSize, available);
    }
    function syncDashboardReveal() {
        dashboardReveal.stop();
        if (!expanded) {
            expandedContent.opacity = 0;
            dashboardRevealOffset.y = 0;
            return;
        }
        if (reducedMotion) {
            expandedContent.opacity = 1;
            dashboardRevealOffset.y = 0;
            return;
        }

        expandedContent.opacity = 0;
        dashboardRevealOffset.y = -Theme.spacing.xs;
        dashboardReveal.restart();
    }

    onExpandedChanged: syncDashboardReveal()
    onBackingWindowChanged: {
        shellWindowWasActive = false;
        if (backingWindow !== null) {
            handleWindowActivation(backingWindow.active);
        }
    }
    onReducedMotionChanged: {
        syncDashboardReveal();
        if (reducedMotion && exitingOwnerKind >= 0) {
            completeInteractiveExit();
        }
    }

    Component.onCompleted: {
        refreshSurfaceState();
        previousOwnerKind = ownerKind;
        syncDashboardReveal();
        queuePresentationAcknowledgement();
        if (backingWindow !== null) {
            handleWindowActivation(backingWindow.active);
        }
    }
    onOwnerKindChanged: {
        const outgoingKind = previousOwnerKind;
        previousOwnerKind = ownerKind;
        if (outgoingKind !== ownerKind) {
            beginInteractiveExit(outgoingKind);
        }
    }
    onHostSurfaceGenerationChanged: {
        queuePresentationAcknowledgement();
        if (hostSurfaceGeneration > 0 && hoverHandler.hovered) {
            reportHover(true);
        }
    }
    onHostSurfaceTokenChanged: refreshSurfaceState()

    Connections {
        target: surface.backingWindow
        ignoreUnknownSignals: true

        function onActiveChanged() {
            surface.handleWindowActivation(target.active);
        }
    }

    Connections {
        target: surface.coordinator

        function onStateSerialChanged() {
            Qt.callLater(surface.refreshSurfaceState);
        }
    }

    onFocusRequestSerialChanged: queueOwnerFocus()
    onOwnerEpochChanged: {
        focusedOwnerEpoch = 0;
        queuePresentationAcknowledgement();
    }
    onOwnerRevisionChanged: queuePresentationAcknowledgement()

    Connections {
        target: surface.applicationModel
        ignoreUnknownSignals: true

        function onLaunchAccepted(requestId, desktopFileId) {
            if (requestId !== surface.launcherRequestId) {
                return;
            }
            surface.launcherRequestId = 0;
            surface.launcherRequestOwnerEpoch = 0;
            surface.coordinator.resetToIdle(surface.hostSurfaceToken);
        }

        function onLaunchRejected(requestId, category) {
            if (requestId === surface.launcherRequestId) {
                surface.launcherRequestId = 0;
                surface.launcherRequestOwnerEpoch = 0;
            }
        }
    }

    Connections {
        target: surface.sessionService
        ignoreUnknownSignals: true

        function onOperationFinished(requestId, action, outcome) {
            if (requestId !== surface.sessionRequestId) {
                return;
            }
            const epoch = surface.sessionRequestOwnerEpoch;
            surface.sessionRequestId = 0;
            surface.sessionRequestOwnerEpoch = 0;
            if (outcome === "accepted") {
                surface.coordinator.completeInteractive(epoch);
            }
        }
    }

    // Leave screen unassigned at creation so Qt selects the startup primary/default output.
    // Explicit top/left anchoring requests a width-derived margin on every
    // layer-shell commit instead of relying on an unanchored compositor edge.
    anchors.top: true
    anchors.left: true
    color: "transparent"
    exclusiveZone: 0
    BackgroundEffect.blurRegion: Theme.snapshot.blurEnabled ? backgroundBlurRegion : null
    focusable: !interactiveExitRunning && focusedOwnerEpoch === ownerEpoch
               && appliedFocusRequestSerial === focusRequestSerial && ((expanded && focusTarget
                                                                        === coordinator.focusExpandedDashboard)
                                                                       || (launcher && focusTarget
                                                                           === coordinator.focusLauncherSearch)
                                                                       || (history && focusTarget
                                                                           === coordinator.focusNotificationHistory)
                                                                       || (tray && focusTarget
                                                                           === coordinator.focusTray)
                                                                       || (audio && focusTarget
                                                                           === coordinator.focusAudio)
                                                                       || (weatherDetails
                                                                           && focusTarget
                                                                           === coordinator.focusWeather)
                                                                       || (session && focusTarget
                                                                           === coordinator.focusSessionActions)
                                                                       || (polkit && focusTarget
                                                                           === coordinator.focusPolkitModal))
    implicitHeight: safeLogicalSize(preferredHeight, screen === null ? 0 : screen.height,
                                    largeContent ? UserConfig.snapshot.island.expandedHeightPercent :
                                                   1)
    implicitWidth: safeLogicalSize(preferredWidth, screen === null ? 0 : screen.width, largeContent
                                   ? UserConfig.snapshot.island.expandedWidthPercent : 1)

    Behavior on implicitHeight {
        enabled: !surface.reducedMotion

        NumberAnimation {
            id: geometryHeightAnimation

            duration: Theme.motion.durationExpansion
            easing.type: Theme.motion.easingExpansion
        }
    }

    Behavior on implicitWidth {
        enabled: !surface.reducedMotion

        NumberAnimation {
            id: geometryWidthAnimation

            duration: Theme.motion.durationExpansion
            easing.type: Theme.motion.easingExpansion
        }
    }

    margins.top: edgeInset
    margins.left: Math.round(horizontalSlack / 2)

    // Keep the fill out of the resize-time effect texture. The direct rectangle
    // tracks the PanelWindow every frame; only the one-pixel silhouette feeds
    // the shadow effect, and that work is suspended during the geometry morph.
    Rectangle {
        id: shadowOutline

        anchors.fill: parent
        radius: Theme.radius.outer
        color: "transparent"
        border.color: Theme.color.surfaceOpaque
        border.width: Theme.size.hairlineWidth
        opacity: Theme.opacity.surface
        visible: surface.visible && !surface.geometryAnimationRunning

        layer.enabled: visible
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            blurMax: Theme.elevation.shadowRadius
            shadowBlur: 1
            shadowColor: Theme.elevation.shadowColor
            shadowEnabled: true
            shadowHorizontalOffset: 0
            shadowOpacity: Theme.opacity.shadow
            shadowVerticalOffset: Theme.elevation.shadowVerticalOffset
        }
    }

    Region {
        id: backgroundBlurRegion

        item: surfaceBackground
    }

    IslandPanel {
        id: surfaceBackground

        objectName: "surfaceBackground"
        anchors.fill: parent
        radius: Theme.radius.outer
        color: Theme.color.surfaceOpaque
        opacity: Theme.opacity.surface
        border.color: Qt.rgba(Theme.color.surfaceBorder.r, Theme.color.surfaceBorder.g,
                              Theme.color.surfaceBorder.b, Theme.opacity.border)
        border.width: Theme.opacity.border > 0 ? Theme.size.hairlineWidth : 0
    }

    Loader {
        id: transientLoader

        anchors.fill: parent
        active: surface.transientOwner && surface.transientPresentation !== null
        visible: active

        sourceComponent: Component {
            TransientView {
                active: transientLoader.visible
                kind: surface.surfaceState.ownerName
                ownerEpoch: surface.ownerEpoch
                ownerRevision: surface.ownerRevision
                presentation: surface.transientPresentation
                reducedMotion: surface.reducedMotion
                surfaceGeneration: surface.hostSurfaceGeneration
                onVisiblyCommitted: (generation, epoch, contentRevision)
                                    => surface.acknowledgePresentation(generation, epoch,
                                                                       contentRevision)
            }
        }
        onLoaded: item.beginEntry()
    }

    IdleIsland {
        id: idleContent

        anchors.centerIn: parent
        visible: surface.ownerKind === surface.coordinator.ownerIdle
        virtualDesktops: surface.virtualDesktops
        clock: surface.clock
        gamingPerformance: surface.gamingPerformance
        weather: surface.weather
        media: surface.media
        reducedMotion: surface.reducedMotion
        showWorkspace: UserConfig.snapshot.island.showWorkspace
        showWeather: UserConfig.snapshot.island.showWeather
        showMedia: UserConfig.snapshot.media.compactVisible
        onWeatherRequested: surface.coordinator.openWeather(surface.hostSurfaceToken)
    }

    ExpandedDashboard {
        id: expandedContent

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: implicitWidth
        height: implicitHeight
        visible: surface.expanded
        transform: Translate {
            id: dashboardRevealOffset
        }
        mediaContent: surface.dashboardMediaContent
        clockContent: surface.dashboardClockContent
        quickControlsContent: surface.dashboardQuickControlsContent
        audioContent: surface.dashboardAudioContent
        notificationsContent: surface.dashboardNotificationsContent
        navigationContent: surface.dashboardNavigationContent
        onCloseRequested: surface.cancelDashboard()
    }

    SequentialAnimation {
        id: dashboardReveal

        PauseAnimation {
            duration: Theme.motion.durationFast
        }

        ParallelAnimation {
            NumberAnimation {
                target: expandedContent
                property: "opacity"
                from: 0
                to: 1
                duration: Theme.motion.durationNormal
                easing.type: Theme.motion.easingExpansion
            }

            NumberAnimation {
                target: dashboardRevealOffset
                property: "y"
                from: -Theme.spacing.xs
                to: 0
                duration: Theme.motion.durationNormal
                easing.type: Theme.motion.easingExpansion
            }
        }
    }

    ParallelAnimation {
        id: interactiveExitAnimation

        NumberAnimation {
            target: surface
            property: "interactiveExitOffset"
            from: 0
            to: Theme.spacing.xl
            duration: surface.interactiveExitDuration
            easing.type: Theme.motion.easingStandard
        }
        NumberAnimation {
            target: surface.exitingLoader
            property: "opacity"
            to: 0
            duration: surface.interactiveExitDuration
            easing.type: Theme.motion.easingStandard
        }
        onFinished: surface.completeInteractiveExit()
    }

    Loader {
        id: launcherLoader

        anchors.fill: parent
        active: (surface.launcher || surface.exitingOwnerKind
                 === surface.coordinator.ownerLauncher) && surface.applicationModel !== null
        visible: active
        enabled: surface.launcher
        transform: Translate {
            x: launcherLoader === surface.exitingLoader ? surface.interactiveExitOffset : 0
        }

        sourceComponent: Component {
            LauncherView {
                active: launcherLoader.visible
                reducedMotion: surface.reducedMotion
                applicationModel: surface.applicationModel
                ownerEpoch: surface.ownerEpoch
                onCancelled: epoch => surface.coordinator.cancelInteractive(epoch)
                onLaunchDispatched: (requestId, epoch) => surface.trackLauncherRequest(requestId,
                                                                                       epoch)
            }
        }

        onLoaded: {
            surface.queuePresentationAcknowledgement();
            surface.queueOwnerFocus();
        }
    }

    Loader {
        id: historyLoader

        anchors.fill: parent
        active: (surface.history || surface.exitingOwnerKind === surface.coordinator.ownerHistory)
                && surface.notificationService !== null
        visible: active
        enabled: surface.history
        transform: Translate {
            x: historyLoader === surface.exitingLoader ? surface.interactiveExitOffset : 0
        }

        sourceComponent: Component {
            NotificationHistoryView {
                active: historyLoader.visible
                reducedMotion: surface.reducedMotion
                ownerEpoch: surface.ownerEpoch
                service: surface.notificationService
                onCancelled: epoch => surface.coordinator.cancelInteractive(epoch)
            }
        }

        onLoaded: {
            surface.queuePresentationAcknowledgement();
            surface.queueOwnerFocus();
        }
    }

    Loader {
        id: trayLoader

        anchors.fill: parent
        active: (surface.tray || surface.exitingOwnerKind === surface.coordinator.ownerTray)
                && surface.trayAdapter !== null
        visible: active
        enabled: surface.tray
        transform: Translate {
            x: trayLoader === surface.exitingLoader ? surface.interactiveExitOffset : 0
        }

        sourceComponent: Component {
            TrayView {
                active: trayLoader.visible
                adapter: surface.trayAdapter
                menuParentWindow: surface
                ownerEpoch: surface.ownerEpoch
                reducedMotion: surface.reducedMotion
                onCancelled: epoch => surface.coordinator.cancelInteractive(epoch)
                onShellMenuOpening: surface.beginShellMenu()
                onShellMenuOpenResult: result => surface.finishShellMenuOpen(result)
                onExternalActionDispatched: surface.completeShellMenuAction()
            }
        }

        onLoaded: {
            surface.queuePresentationAcknowledgement();
            surface.queueOwnerFocus();
        }
    }

    Loader {
        id: audioLoader

        anchors.fill: parent
        active: (surface.audio || surface.exitingOwnerKind === surface.coordinator.ownerAudio)
                && surface.audioAdapter !== null
        visible: active
        enabled: surface.audio
        transform: Translate {
            x: audioLoader === surface.exitingLoader ? surface.interactiveExitOffset : 0
        }

        sourceComponent: Component {
            AudioSelectionView {
                active: audioLoader.visible
                adapter: surface.audioAdapter
                applicationModel: surface.applicationModel
                easyEffectsStatus: surface.easyEffectsStatusService
                maximumAvailableWidth: surface.screen === null ? Number.POSITIVE_INFINITY : Math.max(
                                                                     0, surface.screen.width
                                                                     - surface.edgeInset * 2)
                ownerEpoch: surface.ownerEpoch
                reducedMotion: surface.reducedMotion
                onCancelled: epoch => surface.coordinator.cancelInteractive(epoch)
            }
        }

        onLoaded: {
            surface.queuePresentationAcknowledgement();
            surface.queueOwnerFocus();
        }
    }

    Loader {
        id: weatherLoader

        anchors.fill: parent
        active: (surface.weatherDetails || surface.exitingOwnerKind
                 === surface.coordinator.ownerWeather) && surface.weather !== null
        visible: active
        enabled: surface.weatherDetails
        transform: Translate {
            x: weatherLoader === surface.exitingLoader ? surface.interactiveExitOffset : 0
        }

        sourceComponent: Component {
            WeatherView {
                active: weatherLoader.visible
                adapter: surface.weather
                ownerEpoch: surface.ownerEpoch
                reducedMotion: surface.reducedMotion
                onCancelled: epoch => surface.coordinator.cancelInteractive(epoch)
            }
        }

        onLoaded: {
            surface.queuePresentationAcknowledgement();
            surface.queueOwnerFocus();
        }
    }

    Loader {
        id: polkitLoader

        anchors.fill: parent
        active: surface.polkit || surface.exitingOwnerKind === surface.coordinator.ownerPolkitModal
        visible: active
        enabled: surface.polkit
        transform: Translate {
            x: polkitLoader === surface.exitingLoader ? surface.interactiveExitOffset : 0
        }

        sourceComponent: Component {
            PolkitView {
                active: polkitLoader.visible
                reducedMotion: surface.reducedMotion
                controller: surface.polkitController
                ownerEpoch: surface.ownerEpoch
                ownerRevision: surface.ownerRevision
            }
        }

        onLoaded: {
            surface.queuePresentationAcknowledgement();
            surface.queueOwnerFocus();
        }
    }

    Loader {
        id: sessionLoader

        anchors.fill: parent
        active: (surface.session || surface.exitingOwnerKind === surface.coordinator.ownerSession)
                && surface.sessionService !== null
        visible: active
        enabled: surface.session
        transform: Translate {
            x: sessionLoader === surface.exitingLoader ? surface.interactiveExitOffset : 0
        }

        sourceComponent: Component {
            SessionView {
                active: sessionLoader.visible
                reducedMotion: surface.reducedMotion
                ownerEpoch: surface.ownerEpoch
                service: surface.sessionService
                onActionDispatched: (requestId, epoch) => surface.trackSessionRequest(requestId,
                                                                                      epoch)
                onCancelled: epoch => surface.coordinator.cancelInteractive(epoch)
            }
        }

        onLoaded: {
            surface.queuePresentationAcknowledgement();
            surface.queueOwnerFocus();
        }
    }

    HoverHandler {
        id: hoverHandler

        onHoveredChanged: surface.reportHover(hovered)
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        enabled: surface.expanded && !surface.coordinator.explicitExpandedIntent
        onTapped: surface.requestDeliberateExpansion()
    }
}

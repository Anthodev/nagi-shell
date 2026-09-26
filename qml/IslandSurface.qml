import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Window

PanelWindow {
    id: surface
    readonly property string nagiTypographyScope: "expanded"

    required property var coordinator
    required property var hostSurfaceToken
    required property int hostSurfaceGeneration
    required property var surfaceHost

    // Normalized idle data sources. Null keeps the matching block collapsed,
    // so harnesses can mount the surface without the full adapter set.
    property var virtualDesktops: null
    readonly property var workspaceProjection: virtualDesktops !== null && virtualDesktops
                                               !== undefined
                                               && typeof virtualDesktops.projectionFor
                                               === "function" ? virtualDesktops.projectionFor(
                                                                    screen) : null
    property var clock: null
    property var weather: null
    property var media: null
    property var gamingPerformance: null
    property bool reducedMotion: false
    property bool hoverInputEnabled: true
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
    property Component dashboardStatusContent: null
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
        const snapshot = coordinator.surfaceSnapshot(hostSurfaceToken);
        const leavingSensitiveOwner = contentTransition.initialized
              && contentTransition.currentKind === coordinator.ownerPolkitModal
              && snapshot.ownerKind !== coordinator.ownerPolkitModal;
        if (contentTransition.initialized && (snapshot.ownerKind !== contentTransition.currentKind
                                              || snapshot.ownerEpoch
                                              !== contentTransition.currentEpoch))
            freezeDisplayedFaces();
        surfaceState = snapshot;
        // Authentication pixels must disappear on ownership loss, not after
        // the coalesced ordinary-owner reconciliation callback.
        if (leavingSensitiveOwner)
            contentTransition.handleIdentityChanged();
        else
            contentTransition.queueIdentityReconciliation();
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
    readonly property bool transientOwner: isTransientKind(ownerKind)
    readonly property bool notificationTransient: ownerKind === coordinator.ownerNotification
    readonly property bool largeContent: expanded || launcher || history || tray || audio
                                         || weatherDetails || session || polkit
    readonly property bool interactiveOwner: isInteractiveKind(ownerKind)

    property bool focusHandoffPending: false
    property int layoutRevision: 0
    // The rail's pointer press is surface-local; these values never size a
    // destination face or its readiness stamp, only the visible panel target.
    property bool navigationPointerProtected: false
    property int navigationPointerKind: coordinator.ownerNone
    property real navigationPointerEpoch: 0
    property int navigationPointerGeneration: 0
    property point navigationPointerPosition: Qt.point(0, 0)
    // Ignore a stale HoverHandler sample until a new move follows the click.
    property bool navigationPointerMoved: false
    readonly property point hoveredPointerPosition: hoverHandler.point.scenePosition
    onHoveredPointerPositionChanged: {
        if (navigationPointerProtected && hoverHandler.hovered && (Math.abs(
                                                                       hoveredPointerPosition.x
                                                                       - navigationPointerPosition.x)
                                                                   > 2 || Math.abs(
                                                                       hoveredPointerPosition.y
                                                                       - navigationPointerPosition.y)
                                                                   > 2)) {
            navigationPointerMoved = true;
            maybeReleaseNavigationPointer(true);
        }
    }

    readonly property int windowGutterLeft: Theme.elevation.shadowGutterLeft
    readonly property int windowGutterRight: Theme.elevation.shadowGutterRight
    readonly property int windowGutterTop: Theme.elevation.shadowGutterTop
    readonly property int windowGutterBottom: Theme.elevation.shadowGutterBottom
    readonly property real edgeInset: Math.max(Theme.spacing.sm, windowGutterTop)
    readonly property real stablePanelMaximumWidth: visiblePanelBound(screen === null ? 0 :
                                                                                        screen.width,
                                                                      UserConfig.snapshot.island.expandedWidthPercent,
                                                                      windowGutterLeft
                                                                      + windowGutterRight)
    readonly property real stablePanelMaximumHeight: visiblePanelBound(screen === null ? 0 :
                                                                                         screen.height,
                                                                       UserConfig.snapshot.island.expandedHeightPercent,
                                                                       windowGutterTop
                                                                       + windowGutterBottom)
    readonly property real maximumInteractiveViewportWidth: Math.max(0, stablePanelMaximumWidth
                                                                     - Theme.spacing.lg * 2)
    readonly property real maximumInteractiveViewportHeight: Math.max(0, stablePanelMaximumHeight
                                                                      - Theme.size.controlHeightMd
                                                                      - Theme.spacing.lg * 2
                                                                      - Theme.spacing.md)

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
    readonly property bool dashboardWorkActive: expanded
    readonly property bool dashboardReady: expandedContent.ready
    readonly property real dashboardNaturalWidth: expandedContent.naturalWidth
    readonly property real dashboardNaturalHeight: expandedContent.naturalHeight
    readonly property real dashboardViewportWidth: expandedContent.width
    readonly property real dashboardViewportHeight: expandedContent.height
    readonly property bool dashboardHorizontalOverflow: expandedContent.horizontalOverflow
    readonly property bool dashboardVerticalOverflow: expandedContent.verticalOverflow
    readonly property real settledPreferredWidth: expanded ? expandedContent.naturalWidth :
                                                             largeContent
                                                             ? interactivePreferredWidth :
                                                               transientOwner
                                                               ? transientPreferredWidth : Math.max(
                                                                     Theme.size.islandIdleWidth,
                                                                     idleContentWidth)
    readonly property real settledPreferredHeight: expanded ? expandedContent.naturalHeight :
                                                              largeContent
                                                              ? interactivePreferredHeight :
                                                                transientOwner
                                                                ? transientLoader.item === null
                                                                  ? notificationTransient
                                                                    ? Theme.size.islandTransientNotificationHeight :
                                                                      Theme.size.islandTransientCompactHeight :
                                                                      transientLoader.item.implicitHeight :
                                                                      Theme.size.islandIdleHeight
    readonly property real preferredWidth: settledPreferredWidth
    readonly property real preferredHeight: settledPreferredHeight
    readonly property int idleContentWidth: idleContent.implicitWidth > 0
                                            ? idleContent.implicitWidth : Theme.size.islandIdleWidth
    readonly property bool gamingPerformanceBadgeVisible: idleContent.visible
                                                          && idleContent.gamingPerformanceBlock.visible
    readonly property bool transientCommitted: transientLoader.item !== null
                                               && transientLoader.item.committed
    readonly property string transientPrimaryText: transientLoader.item === null ? "" :
                                                                                   transientLoader.item.primaryText
    readonly property string transientDetailText: transientLoader.item === null ? "" :
                                                                                  transientLoader.item.detailText

    readonly property bool geometryAnimationRunning: momentumGeometry.running
    readonly property bool pointerHovered: hoverHandler.hovered
    readonly property real morphProgress: contentTransition.fraction()
    readonly property real renderedPanelWidth: morphState.currentWidth()
    readonly property real renderedPanelHeight: morphState.currentHeight()
    readonly property point panelMappedTopLeft: Qt.point(surfaceBackground.x, surfaceBackground.y)
    readonly property point panelMappedBottomRight: Qt.point(surfaceBackground.x
                                                             + surfaceBackground.width,
                                                             surfaceBackground.y
                                                             + surfaceBackground.height)
    readonly property real backgroundRadius: surfaceBackground.radius
    readonly property bool blurRequested: Theme.snapshot.blurEnabled
    readonly property real renderedShadowOpacity: shadowOutline.visible ? Theme.opacity.shadow : 0
    readonly property int shadowLayerCount: shadowOutline.layer.enabled
                                            && shadowOutline.layer.effect !== null ? 1 : 0
    readonly property int requestedKwinBlurRegionCount: surface.BackgroundEffect.blurRegion
                                                        === null ? 0 : 1
    readonly property bool contentTransitionRunning: contentTransition.active
    readonly property bool contentTransitionDestinationReady: contentTransition.destinationReady
    readonly property int contentTransitionFromKind: contentTransition.fromKind
    readonly property int contentTransitionToKind: contentTransition.toKind
    readonly property var contentOutgoingItem: contentTransition.outgoingItem
    readonly property var contentIncomingItem: contentTransition.incomingItem
    readonly property real contentOutgoingOpacity: contentTransition.outgoingOpacity()
    readonly property real contentIncomingOpacity: contentTransition.incomingOpacity()
    readonly property bool contentOutgoingEnabled: contentOutgoingItem !== null
                                                   && contentOutgoingItem.enabled
    readonly property bool contentOutgoingAccessibleIgnored: contentOutgoingItem === null
                                                             || contentOutgoingItem.Accessible.ignored
    readonly property bool contentOutgoingRendered: contentTransition.retainedRendered()
    readonly property bool contentOutgoingWorkActive: contentTransition.retainedWorkActive()
    readonly property int retainedPresentationCount: contentTransition.retainedKeys.length
    readonly property int activeVisualKeyCount: contentTransition.displayedKeys.length
    readonly property real contentRenderedOpacityTotal: contentTransition.totalOpacity()

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

    function isTransientKind(kind) {
        return kind === coordinator.ownerWorkspace || kind === coordinator.ownerBrightness || kind
                === coordinator.ownerVolume || kind === coordinator.ownerGamingPerformance || kind
                === coordinator.ownerNotification;
    }

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

    function visualKey(kind) {
        return isTransientKind(kind) ? coordinator.ownerWorkspace : kind;
    }

    function visualKeys() {
        return [coordinator.ownerIdle, coordinator.ownerExpanded, coordinator.ownerWorkspace,
                coordinator.ownerLauncher, coordinator.ownerHistory, coordinator.ownerTray,
                coordinator.ownerAudio, coordinator.ownerWeather, coordinator.ownerSession,
                coordinator.ownerPolkitModal];
    }

    function visualLayerForKind(kind) {
        const key = visualKey(kind);
        if (key === coordinator.ownerIdle) {
            return idlePresentation;
        }
        if (key === coordinator.ownerExpanded) {
            return expandedPresentation;
        }
        if (key === coordinator.ownerWorkspace) {
            return transientPresentationLayer;
        }
        if (key === coordinator.ownerLauncher) {
            return launcherPresentation;
        }
        if (key === coordinator.ownerHistory) {
            return historyPresentation;
        }
        if (key === coordinator.ownerTray) {
            return trayPresentation;
        }
        if (key === coordinator.ownerAudio) {
            return audioPresentation;
        }
        if (key === coordinator.ownerWeather) {
            return weatherPresentation;
        }
        if (key === coordinator.ownerSession) {
            return sessionPresentation;
        }
        if (key === coordinator.ownerPolkitModal) {
            return polkitPresentation;
        }
        return null;
    }

    function visualLayerReady(kind) {
        if (kind === coordinator.ownerIdle) {
            return true;
        }
        if (kind === coordinator.ownerExpanded) {
            return expandedContent.ready;
        }
        const loader = isTransientKind(kind) ? transientLoader : loaderForKind(kind);
        return loader !== null && loader.item !== null;
    }

    function presentationWorkActive(kind) {
        const key = visualKey(kind);
        if (key !== visualKey(ownerKind)) {
            return false;
        }
        if (key === coordinator.ownerIdle) {
            return idleContent.workActive;
        }
        if (key === coordinator.ownerExpanded) {
            return expandedContent.active;
        }
        const loader = key === coordinator.ownerWorkspace ? transientLoader : loaderForKind(key);
        return loader !== null && loader.item !== null && loader.item.active === true;
    }

    function freezeDisplayedFaces() {
        for (let n = 0; n < contentTransition.displayedKeys.length; ++n) {
            const layer = visualLayerForKind(contentTransition.displayedKeys[n]);
            if (layer !== null && layer.sourceItem !== null)
                layer.freezeViewport(!contentTransition.active);
        }
    }

    function contentOpacityForKind(kind) {
        return contentTransition.opacityForKind(kind);
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
                || ownerRevision !== contentRevision || !contentTransition.revealedForCurrent()) {
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
        const generation = hostSurfaceGeneration;
        const epoch = ownerEpoch;
        const serial = focusRequestSerial;
        const transactionSerial = contentTransition.requestSerial;
        Qt.callLater(function () {
            if (surface === null) {
                return;
            }
            if (generation !== surface.hostSurfaceGeneration || epoch !== surface.ownerEpoch
                    || serial !== surface.focusRequestSerial || transactionSerial
                    !== contentTransition.requestSerial || !contentTransition.revealedForCurrent(
                        )) {
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
            surface.focusHandoffPending = false;
            target.focusInitialControl();
        });
    }

    function queuePresentationAcknowledgement() {
        const generation = hostSurfaceGeneration;
        const epoch = ownerEpoch;
        const contentRevision = ownerRevision;
        const transactionSerial = contentTransition.requestSerial;
        Qt.callLater(function () {
            if (surface !== null) {
                if (transactionSerial === contentTransition.requestSerial)
                    surface.acknowledgePresentation(generation, epoch, contentRevision);
            }
        });
    }

    function reportHover(hovered) {
        if (shellMenuOpen && !hovered) {
            return true;
        }
        if (!hovered)
            clearNavigationPointer(true);
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
        clearNavigationPointer(false);
        shellWindowWasActive = false;
        return coordinator.resetToIdle(hostSurfaceToken);
    }
    function navigationKind(name) {
        return name === "tray" ? coordinator.ownerTray : name === "history"
                                 ? coordinator.ownerHistory : name === "launcher"
                                   ? coordinator.ownerLauncher : coordinator.ownerNone;
    }

    function roundedPanelContains(point, width, height, inset) {
        const x = point.x - (windowGutterLeft + envelopePanelWidth / 2 - width / 2);
        const y = point.y - windowGutterTop;
        if (x < inset || y < inset || x > width - inset || y > height - inset)
            return false;
        const radius = Math.min(Theme.radius.outer, width / 2, height / 2);
        const dx = Math.max(radius - x, x - (width - radius), 0);
        const dy = Math.max(radius - y, y - (height - radius), 0);
        const innerRadius = Math.max(0, radius - inset);
        return dx * dx + dy * dy <= innerRadius * innerRadius;
    }
    function pointerInsideNatural(width, height) {
        return roundedPanelContains(navigationPointerPosition, width, height, Math.max(2,
                                                                                       morphState.physicalPixel));
    }

    // The natural target is still independently prepared and screen-capped.
    function protectedTargetWidth(width, height) {
        if (!navigationPointerProtected || navigationPointerKind !== ownerKind
                || navigationPointerGeneration !== hostSurfaceGeneration || pointerInsideNatural(
                    width, height))
            return width;
        const center = windowGutterLeft + envelopePanelWidth / 2;
        return Math.min(stablePanelMaximumWidth, Math.max(width, 2 * (Math.abs(
                                                                          navigationPointerPosition.x
                                                                          - center)
                                                                      + Theme.radius.outer
                                                                      + Math.max(2,
                                                                                 morphState.physicalPixel))));
    }

    function protectedTargetHeight(width, height) {
        if (!navigationPointerProtected || navigationPointerKind !== ownerKind
                || navigationPointerGeneration !== hostSurfaceGeneration || pointerInsideNatural(
                    width, height))
            return height;
        return Math.min(stablePanelMaximumHeight, Math.max(height, navigationPointerPosition.y
                                                           - windowGutterTop + Theme.radius.outer
                                                           + Math.max(2,
                                                                      morphState.physicalPixel)));
    }

    function beginNavigationPointer(name, point) {
        const kind = navigationKind(name);
        if (kind === coordinator.ownerNone || ownerKind !== coordinator.ownerExpanded
                || hostSurfaceGeneration <= 0 || screen === null || screen.width <= 0
                || screen.height <= 0 || !Number.isFinite(point.x) || !Number.isFinite(point.y) || !roundedPanelContains(
                    point, renderedPanelWidth, renderedPanelHeight, 0))
            return false;
        navigationPointerPosition = Qt.point(point.x, point.y);
        navigationPointerKind = kind;
        navigationPointerGeneration = hostSurfaceGeneration;
        navigationPointerEpoch = 0;
        navigationPointerMoved = false;
        navigationPointerProtected = true;
        return true;
    }

    function finishNavigationPointer(name, accepted) {
        if (!navigationPointerProtected || navigationPointerKind !== navigationKind(name))
            return;
        const snapshot = coordinator.surfaceSnapshot(hostSurfaceToken);
        if (!accepted || snapshot.generation !== navigationPointerGeneration || snapshot.ownerKind
                !== navigationPointerKind) {
            clearNavigationPointer(false);
            return;
        }
        navigationPointerEpoch = snapshot.ownerEpoch;
    }

    function clearNavigationPointer(reconcile) {
        if (!navigationPointerProtected)
            return;
        navigationPointerProtected = false;
        navigationPointerKind = coordinator.ownerNone;
        navigationPointerEpoch = 0;
        navigationPointerMoved = false;
        navigationPointerGeneration = 0;
        if (reconcile && morphState.initialized) {
            if (Theme.motion.morphScale <= 0 && !contentTransition.active)
                morphState.settleAt(morphState.canonicalWidth, morphState.canonicalHeight);
            else if (!contentTransition.preparing && (!contentTransition.active
                                                      || contentTransition.toKind === ownerKind))
                morphState.retarget();
        }
    }

    function maybeReleaseNavigationPointer(reconcile) {
        if (!navigationPointerMoved || !navigationPointerProtected || navigationPointerKind
                !== ownerKind || navigationPointerGeneration !== hostSurfaceGeneration || (
                    navigationPointerEpoch > 0 && navigationPointerEpoch !== ownerEpoch) || (
                    contentTransition.active && !contentTransition.destinationReady))
            return;
        const width = contentTransition.active ? contentTransition.preparedTargetWidth :
                                                 morphState.canonicalWidth;
        const height = contentTransition.active ? contentTransition.preparedTargetHeight :
                                                  morphState.canonicalHeight;
        if (roundedPanelContains(hoveredPointerPosition, width, height, Math.max(2,
                                                                                 morphState.physicalPixel)))
            clearNavigationPointer(reconcile);
    }

    function visiblePanelBound(screenSize, maximumFraction, totalGutter) {
        if (screenSize <= 0) {
            return Number.POSITIVE_INFINITY;
        }
        const fraction = maximumFraction ?? 1;
        return Math.max(1, screenSize * fraction - edgeInset * 2 - totalGutter);
    }

    function safeLogicalSize(preferredSize, screenSize, maximumFraction, totalGutter) {
        return Math.min(preferredSize, visiblePanelBound(screenSize, maximumFraction, totalGutter));
    }

    QtObject {
        id: contentTransition
        property bool initialized: false
        property bool active: false
        property bool preparing: false
        property bool destinationReady: true
        property bool commitQueued: false
        property bool identityReconcileQueued: false
        property int requestSerial: 0
        property int currentSurfaceGeneration: 0
        property int currentKind: surface.coordinator.ownerNone
        property real currentEpoch: 0
        property real currentRevision: 0
        property int fromKind: surface.coordinator.ownerNone
        property int toKind: surface.coordinator.ownerNone
        property real toEpoch: 0
        property real toRevision: 0
        property int toSurfaceGeneration: 0
        property var displayedKeys: []
        property var retainedKeys: []
        property var baseWeights: ({})
        property var readyStamps: ({})
        property var outgoingItem: null
        property var incomingItem: null
        property real distance: 0
        property real preparedTargetWidth: 0
        property real preparedTargetHeight: 0
        property real fallbackProgress: 0
        property bool fallbackActive: false
        property bool sensitiveInvalidated: false
        property bool handoffArmed: false
        property real innerBase: 0
        property real innerHoldProgress: 0
        property real pendingInnerBase: 0

        function key(kind) {
            return surface.visualKey(kind);
        }
        function initialize() {
            if (initialized)
                return;
            currentSurfaceGeneration = surface.hostSurfaceGeneration;
            currentKind = surface.ownerKind;
            currentEpoch = surface.ownerEpoch;
            currentRevision = surface.ownerRevision;
            fromKind = toKind = currentKind;
            toEpoch = currentEpoch;
            toRevision = currentRevision;
            toSurfaceGeneration = currentSurfaceGeneration;
            displayedKeys = [key(currentKind)];
            incomingItem = surface.visualLayerForKind(currentKind);
            destinationReady = surface.visualLayerReady(currentKind);
            initialized = true;
            markReady(currentKind);
        }
        function revealedForCurrent() {
            return initialized && !active && !preparing && destinationReady
                    && currentSurfaceGeneration === surface.hostSurfaceGeneration && currentKind
                    === surface.ownerKind && currentEpoch === surface.ownerEpoch && currentRevision
                    === surface.ownerRevision && incomingItem !== null && incomingItem.sourceItem
                    !== null;
        }
        function queueIdentityReconciliation() {
            if (identityReconcileQueued)
                return;
            identityReconcileQueued = true;
            Qt.callLater(function () {
                if (!contentTransition.identityReconcileQueued)
                    return;
                contentTransition.identityReconcileQueued = false;
                contentTransition.handleIdentityChanged();
            });
        }
        function sameTransientReplacement() {
            const source = transientLoader.item;
            return surface.isTransientKind(toKind) && source !== null && source.replacementActive
                    === true;
        }
        function geometryFraction() {
            if (distance <= morphState.physicalPixel)
                return 0;
            const remaining = Math.max(Math.abs(morphState.currentWidth()
                                                - momentumGeometry.widthTarget), Math.abs(
                                           morphState.currentHeight()
                                           - momentumGeometry.heightTarget));
            return Math.max(0, Math.min(1, 1 - remaining / distance));
        }
        function fraction() {
            if (!active)
                return 1;
            const source = transientLoader.item;
            if (preparing || !handoffArmed)
                return source !== null && source.replacementActive ? innerHoldProgress : 0;
            if (source !== null && source.replacementActive && !surface.isTransientKind(toKind))
                return innerHoldProgress;
            if (fallbackActive)
                return sameTransientReplacement() ? innerBase + (1 - innerBase) * fallbackProgress :
                                                    fallbackProgress;
            const u = geometryFraction();
            return sameTransientReplacement() ? innerBase + (1 - innerBase) * u : u;
        }
        function opacityForKind(kind) {
            const visual = key(kind);
            if (!initialized)
                return visual === key(surface.ownerKind) ? 1 : 0;
            if (!active)
                return visual === key(currentKind) ? 1 : 0;
            const u = handoffArmed && destinationReady && !preparing ? fallbackActive
                                                                       ? fallbackProgress :
                                                                         geometryFraction() : 0;
            let sum = 0;
            let value = 0;
            for (let n = 0; n < displayedKeys.length; ++n) {
                const k = displayedKeys[n];
                const amount = (baseWeights[k] || 0) * (1 - u) + (k === key(toKind) ? u : 0);
                sum += amount;
                if (k === visual)
                    value = amount;
            }
            return sum > 0.000001 ? value / sum : visual === key(toKind) ? 1 : 0;
        }
        function zForKind(kind) {
            if (!active)
                return key(kind) === key(currentKind) ? 1 : 0;
            const index = displayedKeys.indexOf(key(kind));
            return index < 0 ? 0 : displayedKeys.length - index + 1;
        }
        function retainsKind(kind) {
            return displayedKeys.indexOf(key(kind)) >= 0;
        }
        function layerVisible(kind) {
            if (key(kind) === surface.coordinator.ownerPolkitModal)
                return surface.polkit && !sensitiveInvalidated;
            return key(surface.ownerKind) === key(kind) || retainsKind(kind);
        }
        function outgoingOpacity() {
            return active && fromKind !== toKind ? opacityForKind(fromKind) : 0;
        }
        function incomingOpacity() {
            return active ? destinationReady ? opacityForKind(toKind) : 0 : incomingItem === null
                                               ? 0 : 1;
        }
        function totalOpacity() {
            let sum = 0;
            for (let n = 0; n < displayedKeys.length; ++n)
                sum += opacityForKind(displayedKeys[n]);
            return Math.min(1, sum);
        }
        function retainedRendered() {
            if (!active || retainedKeys.length === 0)
                return false;
            for (let n = 0; n < retainedKeys.length; ++n) {
                const k = retainedKeys[n];
                const layer = surface.visualLayerForKind(k);
                if (opacityForKind(k) > 0.0001 && (layer === null || layer.sourceItem === null ||
                                                   !layer.visible))
                    return false;
            }
            return true;
        }
        function retainedWorkActive() {
            for (let n = 0; n < retainedKeys.length; ++n)
                if (retainedKeys[n] !== key(surface.ownerKind) && surface.presentationWorkActive(
                            retainedKeys[n]))
                    return true;
            return false;
        }
        function stampFor(kind) {
            const layer = surface.visualLayerForKind(kind);
            if (layer === null || layer.sourceItem === null)
                return null;
            const transient = surface.isTransientKind(kind);
            return {
                source: layer.sourceItem,
                generation: surface.hostSurfaceGeneration,
                width: layer.width,
                height: layer.height,
                naturalWidth: layer.naturalWidth,
                naturalHeight: layer.naturalHeight,
                layout: surface.layoutRevision,
                kind: transient ? surface.surfaceState.ownerName : "",
                epoch: transient ? surface.ownerEpoch : 0,
                revision: transient ? surface.ownerRevision : 0,
                token: transient ? surface.surfaceState.ownerSourceToken : null,
                sourceGeneration: transient ? surface.surfaceState.ownerSourceGeneration : 0,
                sourceRevision: transient ? surface.surfaceState.ownerSourceRevision : 0
            };
        }
        function isReady(kind) {
            const stamp = readyStamps[key(kind)];
            const now = stampFor(kind);
            return stamp !== undefined && now !== null && stamp.source === now.source
                    && stamp.generation === now.generation && stamp.width === now.width
                    && stamp.height === now.height && Math.abs(stamp.naturalWidth
                                                               - now.naturalWidth)
                    <= morphState.physicalPixel && Math.abs(stamp.naturalHeight
                                                            - now.naturalHeight)
                    <= morphState.physicalPixel && stamp.layout === now.layout && stamp.kind
                    === now.kind && stamp.epoch === now.epoch && stamp.revision === now.revision
                    && stamp.token === now.token && stamp.sourceGeneration === now.sourceGeneration
                    && stamp.sourceRevision === now.sourceRevision;
        }
        function markReady(kind) {
            const stamp = stampFor(kind);
            if (stamp === null)
                return;
            const next = Object.assign({}, readyStamps);
            next[key(kind)] = stamp;
            readyStamps = next;
        }
        function forgetReady(kind) {
            if (readyStamps[key(kind)] === undefined)
                return;
            const next = Object.assign({}, readyStamps);
            delete next[key(kind)];
            readyStamps = next;
        }
        function captureBlend() {
            const next = {};
            for (let n = 0; n < displayedKeys.length; ++n)
                next[displayedKeys[n]] = opacityForKind(displayedKeys[n]);
            baseWeights = next;
        }
        function cancelPendingCommit() {
            destinationFramePrime.stop();
            destinationCommit.stop();
            commitQueued = false;
        }
        function request(generation, kind, epoch, revision) {
            if (!initialized)
                initialize();
            if (generation === currentSurfaceGeneration && kind === currentKind && epoch
                    === currentEpoch) {
                currentRevision = revision;
                toRevision = revision;
                if (!active)
                    surface.queuePresentationAcknowledgement();
                return;
            }
            const oldDestination = toKind;
            const transientView = transientLoader.item;
            const priorInnerPair = transientView !== null && transientView.replacementActive;
            innerHoldProgress = priorInnerPair ? transientView.boundedTransitionProgress : 0;
            pendingInnerBase = priorInnerPair && transientView.displayedOutgoingKind
                    === surface.surfaceState.ownerName && transientView.displayedOutgoingEpoch
                    === epoch ? 1 - innerHoldProgress : 0;
            // The captured outer transient key can still contain both inner
            // layers. Do not clear its old payload merely because ownership
            // changed: live sampling must not erase its remaining contribution.
            if (currentKind === surface.coordinator.ownerPolkitModal && kind !== currentKind) {
                displayedKeys = [];
                retainedKeys = [];
                baseWeights = ({});
                readyStamps = ({});
            }
            captureBlend();
            cancelPendingCommit();
            requestSerial += 1;
            if (kind === surface.coordinator.ownerPolkitModal)
                sensitiveInvalidated = false;
            const destination = key(kind);
            const kept = displayedKeys.filter(k => (baseWeights[k] || 0) > 0);
            if (kept.indexOf(destination) < 0)
                kept.push(destination);
            // Only keys from the fixed registry are ever mounted. A physical
            // overshoot may return after opacity hits zero, so keep every
            // contributor with a nonzero captured base until the next request
            // or final settlement, not until its instantaneous opacity is zero.
            displayedKeys = kept;
            retainedKeys = kept.filter(k => k !== destination && (baseWeights[k] || 0) > 0);
            const stamps = {};
            for (let n = 0; n < kept.length; ++n)
                if (readyStamps[kept[n]] !== undefined)
                    stamps[kept[n]] = readyStamps[kept[n]];
            readyStamps = stamps;
            fromKind = retainedKeys.indexOf(key(oldDestination)) >= 0 ? oldDestination :
                                                                        retainedKeys.length > 0
                                                                        ? retainedKeys[0] : kind;
            toKind = kind;
            currentSurfaceGeneration = toSurfaceGeneration = generation;
            currentKind = kind;
            currentEpoch = toEpoch = epoch;
            currentRevision = toRevision = revision;
            outgoingItem = retainedKeys.length > 0 ? surface.visualLayerForKind(fromKind) : null;
            incomingItem = null;
            destinationReady = false;
            preparing = active = true;
            fallbackFade.stop();
            fallbackActive = handoffArmed = false;
            fallbackProgress = 0;
            tryCommitDestination();
        }
        function tryCommitDestination() {
            if (!active || !preparing || commitQueued || !surface.visualLayerReady(toKind))
                return;
            const layer = surface.visualLayerForKind(toKind);
            if (layer === null || layer.sourceItem === null || layer.naturalWidth <= 0
                    || layer.naturalHeight <= 0)
                return;
            if (surface.reducedMotion || isReady(toKind)) {
                commitQueued = true;
                commitDestination(requestSerial);
                return;
            }
            commitQueued = true;
            layer.scheduleUpdate();
            destinationFramePrime.serial = requestSerial;
            destinationFramePrime.frameCount = 0;
            destinationFramePrime.restart();
        }
        function beginDestinationCommit(serial) {
            if (!active || !preparing || serial !== requestSerial)
                return;
            const layer = surface.visualLayerForKind(toKind);
            if (layer === null || layer.sourceItem === null) {
                commitQueued = false;
                return;
            }
            destinationCommit.serial = serial;
            destinationCommit.expectedWidth = layer.naturalWidth;
            destinationCommit.expectedHeight = layer.naturalHeight;
            destinationCommit.stabilityAttempts = 0;
            destinationCommit.stableTicks = 0;
            destinationCommit.restart();
        }
        function commitDestination(serial, expectedWidth, expectedHeight) {
            if (!active || !preparing || serial !== requestSerial)
                return;
            commitQueued = false;
            if (toSurfaceGeneration !== surface.hostSurfaceGeneration || toKind
                    !== surface.ownerKind || toEpoch !== surface.ownerEpoch ||
                    !surface.visualLayerReady(toKind))
                return;
            const item = surface.visualLayerForKind(toKind);
            if (item === null || item.sourceItem === null || item.naturalWidth <= 0 || item.naturalHeight
                    <= 0)
                return;
            if (!surface.reducedMotion && typeof expectedWidth === "number"
                    && destinationCommit.stabilityAttempts < 12) {
                const changed = morphState.targetsDiffer(expectedWidth, expectedHeight,
                                                         item.naturalWidth, item.naturalHeight);
                if (changed || destinationCommit.stableTicks < 1) {
                    commitQueued = true;
                    if (changed) {
                        destinationCommit.expectedWidth = item.naturalWidth;
                        destinationCommit.expectedHeight = item.naturalHeight;
                        destinationCommit.stableTicks = 0;
                    } else
                        destinationCommit.stableTicks += 1;
                    destinationCommit.stabilityAttempts += 1;
                    destinationCommit.restart();
                    return;
                }
            }
            const source = item.sourceItem;
            toRevision = currentRevision = surface.ownerRevision;
            const reusable = isReady(toKind);
            if (surface.isTransientKind(toKind) && typeof source.prepareTransition === "function"
                    && !source.prepareTransition(toSurfaceGeneration, toEpoch, toRevision))
                return;
            innerBase = pendingInnerBase;
            item.freezeViewport(!reusable);
            preparedTargetWidth = surface.safeLogicalSize(item.width, surface.screen === null ? 0 :
                                                                                                surface.screen.width,
                                                          surface.largeContent
                                                          ? UserConfig.snapshot.island.expandedWidthPercent :
                                                            1, surface.windowGutterLeft
                                                          + surface.windowGutterRight);
            preparedTargetHeight = surface.safeLogicalSize(item.height, surface.screen === null ? 0 :
                                                                                                  surface.screen.height,
                                                           surface.largeContent
                                                           ? UserConfig.snapshot.island.expandedHeightPercent :
                                                             1, surface.windowGutterTop
                                                           + surface.windowGutterBottom);
            incomingItem = item;
            destinationReady = true;
            preparing = false;
            surface.maybeReleaseNavigationPointer(false);
            markReady(toKind);
            if (surface.reducedMotion) {
                settleSynchronously();
                return;
            }
            morphState.retarget();
        }
        function beginGeometryHandoff(nextWidth, nextHeight) {
            const inner = sameTransientReplacement() ? fraction() : 0;
            captureBlend();
            fallbackFade.stop();
            const startWidth = morphState.currentWidth();
            const startHeight = morphState.currentHeight();
            distance = Math.max(Math.abs(nextWidth - startWidth), Math.abs(nextHeight
                                                                           - startHeight));
            innerBase = inner;
            fallbackProgress = 0;
            fallbackActive = false;
            handoffArmed = true;
        }
        function onGeometrySettled() {
            if (!active || preparing)
                return;
            if (surface.reducedMotion) {
                finish();
                return;
            }
            if (distance <= morphState.physicalPixel) {
                startFallback();
                return;
            }
            finish();
        }
        function startFallback() {
            if (!active || preparing || fallbackActive)
                return;
            const remainder = sameTransientReplacement() ? 1 - fraction() : 1 - opacityForKind(
                                                               toKind);
            if (remainder <= 0.0001) {
                fallbackActive = true;
                fallbackProgress = 1;
                onFallbackFinished();
                return;
            }
            captureBlend();
            fallbackProgress = 0;
            fallbackActive = true;
            fallbackFade.from = fallbackProgress;
            fallbackFade.duration = Math.max(1, Math.round(Theme.motion.morphDurationFast
                                                           * remainder));
            fallbackFade.restart();
        }
        function onFallbackFinished() {
            if (!active || !fallbackActive || momentumGeometry.running)
                return;
            fallbackProgress = 1;
            finish();
        }
        function finish() {
            if (!active || preparing || momentumGeometry.running || toKind !== surface.ownerKind
                    || toEpoch !== surface.ownerEpoch || toRevision !== surface.ownerRevision
                    || toSurfaceGeneration !== surface.hostSurfaceGeneration)
                return;
            fallbackFade.stop();
            const item = surface.visualLayerForKind(toKind);
            const source = item === null ? null : item.sourceItem;
            if (surface.isTransientKind(toKind) && source !== null
                    && typeof source.finishTransition === "function")
                source.finishTransition(toSurfaceGeneration, toEpoch, toRevision);
            active = false;
            preparing = false;
            fallbackActive = false;
            handoffArmed = false;
            displayedKeys = [key(toKind)];
            retainedKeys = [];
            baseWeights = ({});
            readyStamps = ({});
            outgoingItem = null;
            incomingItem = item;
            if (item !== null)
                item.releaseViewport();
            fromKind = toKind;
            // Layout can change while a prepared face is revealed. Once its
            // retained viewport is released, converge to the latest bounded
            // natural size instead of leaving the prepared target in place.
            const naturalWidth = morphState.canonicalWidth;
            const naturalHeight = morphState.canonicalHeight;
            if (morphState.targetsDiffer(momentumGeometry.widthTarget, momentumGeometry.heightTarget,
                                         surface.protectedTargetWidth(naturalWidth, naturalHeight),
                                         surface.protectedTargetHeight(naturalWidth,
                                                                       naturalHeight)))
                morphState.queueCanonicalReconcile();
            surface.queuePresentationAcknowledgement();
            surface.queueOwnerFocus();
        }
        function settleSynchronously() {
            if (!active)
                return;
            cancelPendingCommit();
            fallbackFade.stop();
            toKind = currentKind;
            toEpoch = currentEpoch;
            toRevision = currentRevision;
            if (!surface.visualLayerReady(toKind)) {
                preparing = true;
                tryCommitDestination();
                return;
            }
            if (preparing) {
                commitQueued = true;
                commitDestination(requestSerial);
            }
            if (!destinationReady)
                return;
            morphState.settleAt(surface.protectedTargetWidth(preparedTargetWidth,
                                                             preparedTargetHeight),
                                surface.protectedTargetHeight(preparedTargetWidth,
                                                              preparedTargetHeight));
            finish();
        }
        function cancelStale() {
            requestSerial += 1;
            cancelPendingCommit();
            fallbackFade.stop();
            sensitiveFramePrime.stop();
            readyStamps = ({});
            active = preparing = false;
            displayedKeys = [key(surface.ownerKind)];
            handoffArmed = false;
            retainedKeys = [];
            currentKind = toKind = surface.ownerKind;
            currentEpoch = toEpoch = surface.ownerEpoch;
            currentRevision = toRevision = surface.ownerRevision;
            currentSurfaceGeneration = toSurfaceGeneration = surface.hostSurfaceGeneration;
            outgoingItem = null;
            incomingItem = surface.visualLayerForKind(currentKind);
            destinationReady = surface.visualLayerReady(currentKind);
            sensitiveInvalidated = false;
        }
        function invalidateSensitive(force) {
            if (!initialized || currentKind !== surface.coordinator.ownerPolkitModal || (force
                                                                                         !== true
                                                                                         && polkitPresentation.sourceItem
                                                                                         === null))
                return;
            forgetReady(surface.coordinator.ownerPolkitModal);
            sensitiveInvalidated = true;
            sensitiveFramePrime.stop();
            const serial = requestSerial;
            const generation = surface.hostSurfaceGeneration;
            const epoch = surface.ownerEpoch;
            const revision = surface.ownerRevision;
            if (surface.reducedMotion) {
                sensitiveInvalidated = false;
                if (surface.polkit && polkitPresentation.sourceItem !== null) {
                    polkitPresentation.scheduleUpdate();
                    markReady(surface.coordinator.ownerPolkitModal);
                    surface.queuePresentationAcknowledgement();
                    surface.queueOwnerFocus();
                }
                return;
            }
            Qt.callLater(function () {
                if (serial !== contentTransition.requestSerial || generation
                        !== surface.hostSurfaceGeneration || epoch !== surface.ownerEpoch
                        || revision !== surface.ownerRevision)
                    return;
                contentTransition.sensitiveInvalidated = false;
                if (!surface.polkit || polkitPresentation.sourceItem === null)
                    return;
                polkitPresentation.scheduleUpdate();
                if (surface.reducedMotion) {
                    contentTransition.markReady(surface.coordinator.ownerPolkitModal);
                    surface.queuePresentationAcknowledgement();
                    surface.queueOwnerFocus();
                    return;
                }
                if (!contentTransition.active) {
                    sensitiveFramePrime.serial = serial;
                    sensitiveFramePrime.generation = generation;
                    sensitiveFramePrime.epoch = epoch;
                    sensitiveFramePrime.revision = revision;
                    sensitiveFramePrime.frameCount = 0;
                    sensitiveFramePrime.waitingFrames = 0;
                    sensitiveFramePrime.restart();
                }
            });
        }
        function handleIdentityChanged() {
            if (!initialized)
                return;
            if (surface.hostSurfaceGeneration !== currentSurfaceGeneration) {
                cancelStale();
                morphState.forceScreenBoundInterrupt();
                return;
            }
            if (surface.ownerKind !== currentKind || surface.ownerEpoch !== currentEpoch) {
                request(surface.hostSurfaceGeneration, surface.ownerKind, surface.ownerEpoch,
                        surface.ownerRevision);
                return;
            }
            if (surface.ownerRevision !== currentRevision) {
                currentRevision = toRevision = surface.ownerRevision;
                if (currentKind === surface.coordinator.ownerPolkitModal)
                    invalidateSensitive(true);
                else if (!active)
                    surface.queuePresentationAcknowledgement();
            }
        }
    }
    GeometryMotion {
        id: momentumGeometry
        onSettled: contentTransition.onGeometrySettled()
        onTargetWillChange: (nextWidth, nextHeight) => {
            if (contentTransition.active && !contentTransition.preparing)
                contentTransition.beginGeometryHandoff(nextWidth, nextHeight);
        }
    }

    QtObject {
        id: morphState
        readonly property real canonicalWidth: surface.safeLogicalSize(surface.preferredWidth,
                                                                       surface.screen === null ? 0 :
                                                                                                 surface.screen.width,
                                                                       surface.largeContent
                                                                       ? UserConfig.snapshot.island.expandedWidthPercent :
                                                                         1, surface.windowGutterLeft
                                                                       + surface.windowGutterRight)
        readonly property real canonicalHeight: surface.safeLogicalSize(surface.preferredHeight,
                                                                        surface.screen === null ? 0 :
                                                                                                  surface.screen.height,
                                                                        surface.largeContent
                                                                        ? UserConfig.snapshot.island.expandedHeightPercent :
                                                                          1, surface.windowGutterTop
                                                                        + surface.windowGutterBottom)
        readonly property real physicalPixel: surface.contentItem === null ? 1 : 1 / Math.max(1,
                                                                                              surface.contentItem.Screen.devicePixelRatio)
        readonly property size currentScreenBounds: Qt.size(surface.screen === null ? 0 :
                                                                                      surface.screen.width,
                                                            surface.screen === null ? 0 :
                                                                                      surface.screen.height)
        readonly property real morphScale: Theme.motion.morphScale
        property bool initialized: false
        property bool reconcileQueued: false

        function currentWidth() {
            return momentumGeometry.initialized ? momentumGeometry.renderedWidth : canonicalWidth;
        }
        function currentHeight() {
            return momentumGeometry.initialized ? momentumGeometry.renderedHeight : canonicalHeight;
        }
        function maxWidth() {
            return surface.screen === null || surface.screen.width <= 0 ? Math.max(1, currentWidth(),
                                                                                   canonicalWidth) :
                                                                          surface.visiblePanelBound(
                                                                              surface.screen.width,
                                                                              1, surface.windowGutterLeft
                                                                              + surface.windowGutterRight);
        }
        function maxHeight() {
            return surface.screen === null || surface.screen.height <= 0 ? Math.max(1, currentHeight(),
                                                                                    canonicalHeight) :
                                                                           surface.visiblePanelBound(
                                                                               surface.screen.height,
                                                                               1, surface.windowGutterTop
                                                                               + surface.windowGutterBottom);
        }
        function targetsDiffer(w1, h1, w2, h2) {
            return Math.abs(w1 - w2) > physicalPixel || Math.abs(h1 - h2) > physicalPixel;
        }
        function initialize() {
            if (initialized)
                return;
            momentumGeometry.initialize(canonicalWidth, canonicalHeight, maxWidth(), maxHeight(),
                                        physicalPixel);
            momentumGeometry.setMotionScale(morphScale);
            initialized = true;
        }
        function retarget() {
            if (!initialized || contentTransition.preparing)
                return;
            momentumGeometry.setBounds(maxWidth(), maxHeight(), physicalPixel);
            const naturalWidth = contentTransition.active ? contentTransition.preparedTargetWidth :
                                                            canonicalWidth;
            const naturalHeight = contentTransition.active ? contentTransition.preparedTargetHeight :
                                                             canonicalHeight;
            const width = surface.protectedTargetWidth(naturalWidth, naturalHeight);
            const height = surface.protectedTargetHeight(naturalWidth, naturalHeight);
            const different = targetsDiffer(momentumGeometry.widthTarget,
                                            momentumGeometry.heightTarget, width, height);
            momentumGeometry.requestTarget(width, height);
            if (!different && contentTransition.active) {
                contentTransition.beginGeometryHandoff(width, height);
                if (!momentumGeometry.running)
                    contentTransition.onGeometrySettled();
            }
        }
        function settleAt(width, height) {
            if (!initialized)
                return;
            momentumGeometry.setBounds(maxWidth(), maxHeight(), physicalPixel);
            momentumGeometry.snap(width, height);
        }
        function settleSynchronously() {
            settleAt(surface.protectedTargetWidth(canonicalWidth, canonicalHeight),
                     surface.protectedTargetHeight(canonicalWidth, canonicalHeight));
            contentTransition.settleSynchronously();
        }
        function forceScreenBoundInterrupt() {
            if (!initialized)
                return;
            if (surface.screen === null || surface.screen.width <= 0 || surface.screen.height <= 0)
                surface.clearNavigationPointer(false);
            surface.layoutRevision += 1;
            contentTransition.cancelPendingCommit();
            momentumGeometry.setBounds(maxWidth(), maxHeight(), physicalPixel);
            if (surface.reducedMotion)
                contentTransition.settleSynchronously();
            else if (contentTransition.active && contentTransition.preparing)
                contentTransition.tryCommitDestination();
            else if (contentTransition.active) {
                const item = surface.visualLayerForKind(contentTransition.toKind);
                if (item !== null && item.sourceItem !== null) {
                    item.releaseViewport();
                    item.freezeViewport(true);
                    contentTransition.preparedTargetWidth = surface.safeLogicalSize(item.width,
                                                                                    surface.screen
                                                                                    === null ? 0 :
                                                                                               surface.screen.width,
                                                                                    surface.largeContent
                                                                                    ? UserConfig.snapshot.island.expandedWidthPercent :
                                                                                      1, surface.windowGutterLeft
                                                                                    + surface.windowGutterRight);
                    contentTransition.preparedTargetHeight = surface.safeLogicalSize(item.height,
                                                                                     surface.screen
                                                                                     === null ? 0 :
                                                                                                surface.screen.height,
                                                                                     surface.largeContent
                                                                                     ? UserConfig.snapshot.island.expandedHeightPercent :
                                                                                       1, surface.windowGutterTop
                                                                                     + surface.windowGutterBottom);
                    retarget();
                }
            }
        }
        function queueCanonicalReconcile() {
            if (reconcileQueued)
                return;
            reconcileQueued = true;
            Qt.callLater(function () {
                if (!morphState.reconcileQueued)
                    return;
                morphState.reconcileQueued = false;
                if (surface.reducedMotion)
                    settleAt(surface.protectedTargetWidth(canonicalWidth, canonicalHeight),
                             surface.protectedTargetHeight(canonicalWidth, canonicalHeight));
                else if (!contentTransition.preparing && !contentTransition.active)
                    retarget();
            });
        }
        onCanonicalWidthChanged: {
            if (initialized && !contentTransition.preparing && !contentTransition.active)
                queueCanonicalReconcile();
        }
        onCanonicalHeightChanged: {
            if (initialized && !contentTransition.preparing && !contentTransition.active)
                queueCanonicalReconcile();
        }
        onCurrentScreenBoundsChanged: forceScreenBoundInterrupt()
        onMorphScaleChanged: {
            momentumGeometry.setMotionScale(morphScale);
            if (initialized && morphScale <= 0)
                settleSynchronously();
        }
        onPhysicalPixelChanged: {
            if (initialized)
                momentumGeometry.setBounds(maxWidth(), maxHeight(), physicalPixel);
        }
    }

    function interruptMorphForScreenBounds() {
        morphState.forceScreenBoundInterrupt();
    }

    FrameAnimation {
        id: sensitiveFramePrime
        running: false
        property int serial: -1
        property int generation: 0
        property real epoch: 0
        property real revision: 0
        property int frameCount: 0
        property int waitingFrames: 0
        onTriggered: {
            if (serial !== contentTransition.requestSerial || !surface.polkit || generation
                    !== surface.hostSurfaceGeneration || epoch !== surface.ownerEpoch || revision
                    !== surface.ownerRevision) {
                stop();
                return;
            }
            if (polkitPresentation.sourceItem === null) {
                frameCount = 0;
                waitingFrames += 1;
                if (waitingFrames >= 12)
                    stop();
                return;
            }
            frameCount += 1;
            if (frameCount < 2)
                return;
            stop();
            contentTransition.markReady(surface.coordinator.ownerPolkitModal);
            surface.queuePresentationAcknowledgement();
            surface.queueOwnerFocus();
        }
    }

    FrameAnimation {
        id: destinationFramePrime

        property int serial: -1
        property int frameCount: 0

        running: false
        onTriggered: {
            if (!contentTransition.active || !contentTransition.preparing || serial
                    !== contentTransition.requestSerial) {
                stop();
                return;
            }

            const layer = surface.visualLayerForKind(contentTransition.toKind);
            if (layer === null || layer.sourceItem === null) {
                stop();
                contentTransition.commitQueued = false;
                return;
            }

            frameCount += 1;
            if (frameCount < 2) {
                return;
            }

            stop();
            contentTransition.beginDestinationCommit(serial);
        }
    }

    Timer {
        id: destinationCommit

        property int serial: -1
        property int stabilityAttempts: 0
        property int stableTicks: 0
        property real expectedWidth: 0
        property real expectedHeight: 0

        interval: 1
        repeat: false
        onTriggered: contentTransition.commitDestination(serial, expectedWidth, expectedHeight)
    }

    NumberAnimation {
        id: fallbackFade
        target: contentTransition
        property: "fallbackProgress"
        from: 0
        to: 1
        easing.type: Easing.Linear
        onFinished: contentTransition.onFallbackFinished()
    }

    onScreenChanged: {
        clearNavigationPointer(false);
        morphState.forceScreenBoundInterrupt();
    }
    onBackingWindowChanged: {
        shellWindowWasActive = false;
        if (backingWindow === null)
            clearNavigationPointer(false);
        if (backingWindow !== null) {
            handleWindowActivation(backingWindow.active);
        }
    }
    onReducedMotionChanged: {
        if (reducedMotion) {
            sensitiveFramePrime.stop();
            if (contentTransition.sensitiveInvalidated)
                contentTransition.invalidateSensitive(true);
            else if (polkit && polkitPresentation.sourceItem !== null) {
                contentTransition.markReady(coordinator.ownerPolkitModal);
                queuePresentationAcknowledgement();
                queueOwnerFocus();
            }
            contentTransition.settleSynchronously();
            if (!contentTransition.active) {
                morphState.settleSynchronously();
            }
        }
    }

    Component.onCompleted: {
        refreshSurfaceState();
        morphState.initialize();
        contentTransition.initialize();
        queuePresentationAcknowledgement();
        if (backingWindow !== null) {
            handleWindowActivation(backingWindow.active);
        }
    }
    onOwnerKindChanged: {
        if (navigationPointerProtected && (ownerKind !== navigationPointerKind && (ownerKind
                                                                                   !== coordinator.ownerExpanded
                                                                                   || navigationPointerEpoch
                                                                                   > 0)))
            clearNavigationPointer(false);
        focusHandoffPending = focusTarget !== coordinator.focusNone;
        contentTransition.queueIdentityReconciliation();
    }
    onHostSurfaceGenerationChanged: {
        clearNavigationPointer(false);
        contentTransition.handleIdentityChanged();
        queuePresentationAcknowledgement();
        if (hoverInputEnabled && hostSurfaceGeneration > 0 && hoverHandler.hovered) {
            reportHover(true);
        }
    }
    onHostSurfaceTokenChanged: {
        clearNavigationPointer(false);
        refreshSurfaceState();
    }

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

    onFocusTargetChanged: focusHandoffPending = focusTarget !== coordinator.focusNone
    onFocusRequestSerialChanged: {
        // The coordinator can publish a newer focus serial in an unrelated
        // snapshot. Keep the window's keyboard claim until that exact serial
        // reaches the already mounted destination.
        focusHandoffPending = focusTarget !== coordinator.focusNone;
        queueOwnerFocus();
    }
    onOwnerEpochChanged: {
        if (navigationPointerProtected && navigationPointerEpoch > 0 && ownerEpoch
                !== navigationPointerEpoch)
            clearNavigationPointer(false);
        focusedOwnerEpoch = 0;
        focusHandoffPending = focusTarget !== coordinator.focusNone;
        contentTransition.queueIdentityReconciliation();
        if (!transientOwner) {
            queuePresentationAcknowledgement();
        }
    }
    onOwnerRevisionChanged: {
        contentTransition.queueIdentityReconciliation();
        if (!transientOwner) {
            queuePresentationAcknowledgement();
        }
    }

    Connections {
        target: surface.polkitController
        ignoreUnknownSignals: true
        function onFlowGenerationChanged() {
            contentTransition.invalidateSensitive();
        }
        function onPromptGenerationChanged() {
            contentTransition.invalidateSensitive();
        }
        function onResponseRequiredChanged() {
            if (!surface.polkitController.responseRequired)
                contentTransition.invalidateSensitive();
        }
        function onTerminalChanged() {
            if (surface.polkitController.terminal)
                contentTransition.invalidateSensitive();
        }
    }

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
    // The host owns one output-bounded envelope; only its masked child morphs.
    readonly property real envelopePanelWidth: screen === null || screen.width <= 0
                                               ? renderedPanelWidth : visiblePanelBound(screen.width,
                                                                                        1, windowGutterLeft
                                                                                        + windowGutterRight)
    readonly property real envelopePanelHeight: screen === null || screen.height <= 0
                                                ? renderedPanelHeight : visiblePanelBound(
                                                      screen.height, 1, windowGutterTop
                                                      + windowGutterBottom)
    readonly property real panelOriginX: windowGutterLeft + (envelopePanelWidth
                                                             - renderedPanelWidth) / 2
    // The window buffer includes fixed visual-only shadow gutters; visible panel
    // geometry remains the canonical morph coordinate space.
    anchors.top: true
    anchors.left: true
    color: "transparent"
    exclusiveZone: 0
    mask: panelInputRegion
    BackgroundEffect.blurRegion: Theme.snapshot.blurEnabled ? backgroundBlurRegion : null
    focusable: focusHandoffPending || (focusedOwnerEpoch === ownerEpoch
                                       && appliedFocusRequestSerial === focusRequestSerial && ((
                                                                                                   expanded
                                                                                                   && focusTarget
                                                                                                   === coordinator.focusExpandedDashboard)
                                                                                               || (launcher
                                                                                                   && focusTarget
                                                                                                   === coordinator.focusLauncherSearch)
                                                                                               || (history
                                                                                                   && focusTarget
                                                                                                   === coordinator.focusNotificationHistory)
                                                                                               || (tray
                                                                                                   && focusTarget
                                                                                                   === coordinator.focusTray)
                                                                                               || (audio
                                                                                                   && focusTarget
                                                                                                   === coordinator.focusAudio)
                                                                                               || (weatherDetails
                                                                                                   && focusTarget
                                                                                                   === coordinator.focusWeather)
                                                                                               || (session
                                                                                                   && focusTarget
                                                                                                   === coordinator.focusSessionActions)
                                                                                               || (polkit
                                                                                                   && focusTarget
                                                                                                   === coordinator.focusPolkitModal)))
    implicitHeight: windowGutterTop + envelopePanelHeight + windowGutterBottom
    implicitWidth: windowGutterLeft + envelopePanelWidth + windowGutterRight

    margins.top: edgeInset - windowGutterTop
    margins.left: screen === null ? edgeInset - windowGutterLeft : Math.round((screen.width
                                                                               - envelopePanelWidth)
                                                                              / 2) - windowGutterLeft

    Rectangle {
        id: shadowOutline

        x: surface.panelOriginX
        y: surface.windowGutterTop
        width: surface.renderedPanelWidth
        height: surface.renderedPanelHeight
        radius: Theme.radius.outer
        color: "transparent"
        border.color: Theme.color.surfaceOpaque
        border.width: Theme.size.hairlineWidth
        opacity: Theme.opacity.surface
        visible: surface.visible

        layer.enabled: visible
        layer.effect: MultiEffect {
            id: shadowEffect

            autoPaddingEnabled: false
            paddingRect: Qt.rect(-surface.windowGutterLeft, -surface.windowGutterTop,
                                 surface.windowGutterLeft + surface.windowGutterRight,
                                 surface.windowGutterTop + surface.windowGutterBottom)
            blurMax: Theme.elevation.shadowRadius
            shadowBlur: 1
            shadowColor: Theme.elevation.shadowColor
            shadowEnabled: true
            shadowHorizontalOffset: Theme.elevation.shadowHorizontalOffset
            shadowOpacity: surface.renderedShadowOpacity
            shadowVerticalOffset: Theme.elevation.shadowVerticalOffset
        }
    }

    Region {
        id: panelInputRegion

        item: surfaceBackground
        radius: Theme.radius.outer
    }

    Region {
        id: backgroundBlurRegion

        item: surfaceBackground
    }

    IslandPanel {
        id: surfaceBackground

        objectName: "surfaceBackground"
        x: surface.panelOriginX
        y: surface.windowGutterTop
        width: surface.renderedPanelWidth
        height: surface.renderedPanelHeight
        clip: true
        radius: Theme.radius.outer
        color: Theme.color.surfaceOpaque
        opacity: Theme.opacity.surface
        border.color: Qt.rgba(Theme.color.surfaceBorder.r, Theme.color.surfaceBorder.g,
                              Theme.color.surfaceBorder.b, Theme.opacity.border)
        border.width: Theme.opacity.border > 0 ? Theme.size.hairlineWidth : 0
    }

    component RetainedPresentation: ShaderEffectSource {
        id: retainedPresentation
        required property var transition
        required property int layerKind
        required property bool workActive
        property Item presentationSource: null
        property real naturalWidth: presentationSource === null ? 0 : presentationSource.width
        property real naturalHeight: presentationSource === null ? 0 : presentationSource.height
        property real viewportWidth: 0
        property real viewportHeight: 0
        property bool viewportHeld: false
        readonly property bool fixedViewport: viewportHeld && transition.displayedKeys.indexOf(
                                                  layerKind) >= 0 && viewportWidth > 0
                                              && viewportHeight > 0
        sourceRect: Qt.rect(0, 0, fixedViewport ? viewportWidth : naturalWidth, fixedViewport
                            ? viewportHeight : naturalHeight)
        property bool releasingTexture: false
        readonly property bool held: transition.layerVisible(layerKind)
        sourceItem: held && presentationSource !== null ? presentationSource : null
        live: sourceItem === null ? releasingTexture : workActive
        hideSource: sourceItem !== null
        recursive: false
        mipmap: false
        visible: held && sourceItem !== null
        enabled: false
        Accessible.ignored: true
        opacity: transition.opacityForKind(layerKind)
        z: transition.zForKind(layerKind)
        // Both faces stay at their own fixed screen-capped natural viewport.
        // The current panel is merely their clipping aperture; no face scales
        // or tracks the panel's height during the morph.
        x: (surface.renderedPanelWidth - width) / 2
        y: 0
        width: sourceItem === null ? 0 : fixedViewport ? viewportWidth : naturalWidth
        height: sourceItem === null ? 0 : fixedViewport ? viewportHeight : naturalHeight
        onSourceItemChanged: {
            if (sourceItem === null) {
                transition.forgetReady(layerKind);
                viewportWidth = 0;
                viewportHeight = 0;
                viewportHeld = false;
                releasingTexture = true;
                releaseTextureTimer.restart();
            } else {
                releasingTexture = false;
                releaseTextureTimer.stop();
                if (transition.initialized && !transition.active && layerKind
                        === transition.currentKind) {
                    if (layerKind !== surface.coordinator.ownerPolkitModal)
                        transition.markReady(layerKind);
                    else if (surface.reducedMotion) {
                        scheduleUpdate();
                        transition.markReady(layerKind);
                        surface.queuePresentationAcknowledgement();
                        surface.queueOwnerFocus();
                    } else if (sensitiveFramePrime.serial === transition.requestSerial
                               && sensitiveFramePrime.revision === surface.ownerRevision &&
                               !sensitiveFramePrime.running) {
                        sensitiveFramePrime.frameCount = 0;
                        sensitiveFramePrime.waitingFrames = 0;
                        sensitiveFramePrime.restart();
                    }
                }
                transition.tryCommitDestination();
            }
        }
        onNaturalWidthChanged: transition.tryCommitDestination()
        onNaturalHeightChanged: transition.tryCommitDestination()
        Timer {
            id: releaseTextureTimer
            interval: 0
            repeat: false
            onTriggered: retainedPresentation.releasingTexture = false
        }
        function freezeViewport(rebase) {
            if (naturalWidth <= 0 || naturalHeight <= 0)
                return;
            if (rebase === true || viewportWidth <= 0 || viewportHeight <= 0) {
                viewportWidth = naturalWidth;
                viewportHeight = naturalHeight;
            }
            viewportHeld = true;
        }
        function releaseViewport() {
            viewportHeld = false;
        }
    }

    Loader {
        id: transientLoader

        parent: surfaceBackground
        anchors.centerIn: parent
        width: item === null ? 0 : item.implicitWidth
        height: item === null ? 0 : item.implicitHeight
        active: ((surface.transientOwner && surface.transientPresentation !== null)
                 || contentTransition.retainsKind(surface.coordinator.ownerWorkspace))
        visible: active
        enabled: surface.transientOwner && contentTransition.revealedForCurrent()
        Accessible.ignored: !enabled

        sourceComponent: Component {
            TransientView {
                active: surface.transientOwner || contentTransition.retainsKind(
                            surface.coordinator.ownerWorkspace)
                kind: surface.transientOwner ? surface.surfaceState.ownerName : ""
                ownerEpoch: surface.ownerEpoch
                ownerRevision: surface.ownerRevision
                presentation: surface.transientPresentation ?? ({})
                surfaceGeneration: surface.hostSurfaceGeneration
                transitionManaged: contentTransition.active && contentTransition.retainsKind(
                                       surface.coordinator.ownerWorkspace)
                transitionProgress: surface.morphProgress
                onVisiblyCommitted: (generation, epoch, contentRevision)
                                    => surface.acknowledgePresentation(generation, epoch,
                                                                       contentRevision)
            }
        }
        onLoaded: contentTransition.tryCommitDestination()
    }

    RetainedPresentation {
        id: transientPresentationLayer

        parent: surfaceBackground
        transition: contentTransition
        layerKind: surface.coordinator.ownerWorkspace
        workActive: surface.transientOwner
        presentationSource: transientLoader.item
    }

    IdleIsland {
        id: idleContent

        parent: surfaceBackground
        anchors.centerIn: parent
        width: implicitWidth
        height: implicitHeight
        visible: contentTransition.layerVisible(surface.coordinator.ownerIdle)
        enabled: surface.ownerKind === surface.coordinator.ownerIdle
                 && contentTransition.revealedForCurrent()
        Accessible.ignored: !enabled
        workActive: surface.ownerKind === surface.coordinator.ownerIdle
        retainPresentation: contentTransition.retainsKind(surface.coordinator.ownerIdle)
        virtualDesktops: surface.workspaceProjection
        clock: surface.clock
        gamingPerformance: surface.gamingPerformance
        weather: surface.weather
        media: surface.media
        reducedMotion: surface.reducedMotion
        showWorkspace: UserConfig.snapshot.island.showWorkspace
        showWeather: UserConfig.snapshot.island.showWeather
        showMedia: UserConfig.snapshot.island.showMedia && UserConfig.snapshot.media.compactVisible
        onWeatherRequested: surface.coordinator.openWeather(surface.hostSurfaceToken)
    }

    RetainedPresentation {
        id: idlePresentation

        parent: surfaceBackground
        transition: contentTransition
        layerKind: surface.coordinator.ownerIdle
        workActive: idleContent.workActive
        presentationSource: idleContent
    }

    ExpandedDashboard {
        id: expandedContent

        parent: surfaceBackground
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: boundedWidth
        height: boundedHeight
        visible: contentTransition.layerVisible(surface.coordinator.ownerExpanded)
        enabled: surface.expanded && contentTransition.revealedForCurrent()
        Accessible.ignored: !enabled
        active: surface.expanded
        gamingPerformance: surface.gamingPerformance
        gamingIndicatorEnabled: UserConfig.snapshot.island.gamingIndicator
        retainPresentation: contentTransition.retainsKind(surface.coordinator.ownerExpanded)
        maximumViewportWidth: surface.stablePanelMaximumWidth
        maximumViewportHeight: surface.stablePanelMaximumHeight
        mediaContent: surface.dashboardMediaContent
        clockContent: surface.dashboardClockContent
        statusContent: surface.dashboardStatusContent
        quickControlsContent: surface.dashboardQuickControlsContent
        audioContent: surface.dashboardAudioContent
        notificationsContent: surface.dashboardNotificationsContent
        navigationContent: surface.dashboardNavigationContent
        onReadyChanged: contentTransition.tryCommitDestination()
        onLoadedRegionCountChanged: surface.layoutRevision += 1
        onCloseRequested: surface.cancelDashboard()
    }

    RetainedPresentation {
        id: expandedPresentation

        parent: surfaceBackground
        transition: contentTransition
        layerKind: surface.coordinator.ownerExpanded
        workActive: expandedContent.active
        presentationSource: expandedContent
    }

    Loader {
        id: launcherLoader

        parent: surfaceBackground
        anchors.horizontalCenter: parent.horizontalCenter
        width: item === null ? 0 : item.implicitWidth
        height: item === null ? 0 : item.implicitHeight
        active: (surface.launcher || contentTransition.retainsKind(
                     surface.coordinator.ownerLauncher)) && surface.applicationModel !== null
        visible: active
        enabled: surface.launcher && contentTransition.revealedForCurrent()
        Accessible.ignored: !enabled

        sourceComponent: Component {
            LauncherView {
                active: surface.launcher
                reducedMotion: surface.reducedMotion
                applicationModel: surface.applicationModel
                maximumViewportWidth: surface.maximumInteractiveViewportWidth
                maximumViewportHeight: surface.maximumInteractiveViewportHeight
                ownerEpoch: surface.ownerEpoch
                onCancelled: epoch => surface.coordinator.cancelInteractive(epoch)
                onLaunchDispatched: (requestId, epoch) => surface.trackLauncherRequest(requestId,
                                                                                       epoch)
            }
        }
        onLoaded: {
            surface.queuePresentationAcknowledgement();
            surface.queueOwnerFocus();
            contentTransition.tryCommitDestination();
        }
    }

    RetainedPresentation {
        id: launcherPresentation
        parent: surfaceBackground
        transition: contentTransition
        layerKind: surface.coordinator.ownerLauncher
        workActive: surface.launcher
        presentationSource: launcherLoader.item
    }

    Loader {
        id: historyLoader

        parent: surfaceBackground
        anchors.horizontalCenter: parent.horizontalCenter
        width: item === null ? 0 : item.implicitWidth
        height: item === null ? 0 : item.implicitHeight
        active: (surface.history || contentTransition.retainsKind(
                     surface.coordinator.ownerHistory)) && surface.notificationService !== null
        visible: active
        enabled: surface.history && contentTransition.revealedForCurrent()
        Accessible.ignored: !enabled

        sourceComponent: Component {
            NotificationHistoryView {
                active: surface.history
                reducedMotion: surface.reducedMotion
                maximumViewportWidth: surface.maximumInteractiveViewportWidth
                maximumViewportHeight: surface.maximumInteractiveViewportHeight
                ownerEpoch: surface.ownerEpoch
                service: surface.notificationService
                onCancelled: epoch => surface.coordinator.cancelInteractive(epoch)
            }
        }
        onLoaded: {
            surface.queuePresentationAcknowledgement();
            surface.queueOwnerFocus();
            contentTransition.tryCommitDestination();
        }
    }

    RetainedPresentation {
        id: historyPresentation
        parent: surfaceBackground
        transition: contentTransition
        layerKind: surface.coordinator.ownerHistory
        workActive: surface.history
        presentationSource: historyLoader.item
    }

    Loader {
        id: trayLoader

        parent: surfaceBackground
        anchors.horizontalCenter: parent.horizontalCenter
        width: item === null ? 0 : item.implicitWidth
        height: item === null ? 0 : item.implicitHeight
        active: (surface.tray || contentTransition.retainsKind(surface.coordinator.ownerTray))
                && surface.trayAdapter !== null
        visible: active
        enabled: surface.tray && contentTransition.revealedForCurrent()
        Accessible.ignored: !enabled

        sourceComponent: Component {
            TrayView {
                active: surface.tray
                adapter: surface.trayAdapter
                menuParentWindow: surface
                maximumViewportWidth: surface.maximumInteractiveViewportWidth
                maximumViewportHeight: surface.maximumInteractiveViewportHeight
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
            contentTransition.tryCommitDestination();
        }
    }

    RetainedPresentation {
        id: trayPresentation
        parent: surfaceBackground
        transition: contentTransition
        layerKind: surface.coordinator.ownerTray
        workActive: surface.tray
        presentationSource: trayLoader.item
    }

    Loader {
        id: audioLoader

        parent: surfaceBackground
        width: item === null ? 0 : item.implicitWidth
        height: item === null ? 0 : item.implicitHeight
        active: (surface.audio || contentTransition.retainsKind(surface.coordinator.ownerAudio))
                && surface.audioAdapter !== null
        visible: active
        enabled: surface.audio && contentTransition.revealedForCurrent()
        Accessible.ignored: !enabled

        sourceComponent: Component {
            AudioSelectionView {
                active: surface.audio
                adapter: surface.audioAdapter
                applicationModel: surface.applicationModel
                easyEffectsStatus: surface.easyEffectsStatusService
                maximumViewportWidth: surface.maximumInteractiveViewportWidth
                maximumViewportHeight: surface.maximumInteractiveViewportHeight
                ownerEpoch: surface.ownerEpoch
                reducedMotion: surface.reducedMotion
                onCancelled: epoch => surface.coordinator.cancelInteractive(epoch)
            }
        }
        onLoaded: {
            surface.queuePresentationAcknowledgement();
            surface.queueOwnerFocus();
            contentTransition.tryCommitDestination();
        }
    }

    RetainedPresentation {
        id: audioPresentation
        parent: surfaceBackground
        transition: contentTransition
        layerKind: surface.coordinator.ownerAudio
        workActive: surface.audio
        presentationSource: audioLoader.item
    }

    Loader {
        id: weatherLoader

        parent: surfaceBackground
        width: item === null ? 0 : item.implicitWidth
        height: item === null ? 0 : item.implicitHeight
        active: (surface.weatherDetails || contentTransition.retainsKind(
                     surface.coordinator.ownerWeather)) && surface.weather !== null
        visible: active
        enabled: surface.weatherDetails && contentTransition.revealedForCurrent()
        Accessible.ignored: !enabled

        sourceComponent: Component {
            WeatherView {
                active: surface.weatherDetails
                adapter: surface.weather
                maximumViewportWidth: surface.maximumInteractiveViewportWidth
                maximumViewportHeight: surface.maximumInteractiveViewportHeight
                ownerEpoch: surface.ownerEpoch
                reducedMotion: surface.reducedMotion
                onCancelled: epoch => surface.coordinator.cancelInteractive(epoch)
            }
        }
        onLoaded: {
            surface.queuePresentationAcknowledgement();
            surface.queueOwnerFocus();
            contentTransition.tryCommitDestination();
        }
    }

    RetainedPresentation {
        id: weatherPresentation
        parent: surfaceBackground
        transition: contentTransition
        layerKind: surface.coordinator.ownerWeather
        workActive: surface.weatherDetails
        presentationSource: weatherLoader.item
    }

    Loader {
        id: polkitLoader

        parent: surfaceBackground
        width: item === null ? 0 : item.implicitWidth
        height: item === null ? 0 : item.implicitHeight
        active: surface.polkit || (surface.polkitControllerReady && contentTransition.retainsKind(
                                       surface.coordinator.ownerPolkitModal))
        visible: active
        enabled: surface.polkit && contentTransition.revealedForCurrent()
        Accessible.ignored: !enabled

        sourceComponent: Component {
            PolkitView {
                active: surface.polkit
                controller: surface.polkitController
                maximumViewportWidth: surface.maximumInteractiveViewportWidth
                maximumViewportHeight: surface.maximumInteractiveViewportHeight
                ownerEpoch: surface.ownerEpoch
                ownerRevision: surface.ownerRevision
            }
        }
        onLoaded: {
            surface.queuePresentationAcknowledgement();
            surface.queueOwnerFocus();
            contentTransition.tryCommitDestination();
        }
    }

    RetainedPresentation {
        id: polkitPresentation
        parent: surfaceBackground
        transition: contentTransition
        layerKind: surface.coordinator.ownerPolkitModal
        workActive: surface.polkit
        presentationSource: polkitLoader.item
    }

    Loader {
        id: sessionLoader

        parent: surfaceBackground
        width: item === null ? 0 : item.implicitWidth
        height: item === null ? 0 : item.implicitHeight
        active: (surface.session || contentTransition.retainsKind(
                     surface.coordinator.ownerSession)) && surface.sessionService !== null
        visible: active
        enabled: surface.session && contentTransition.revealedForCurrent()
        Accessible.ignored: !enabled

        sourceComponent: Component {
            SessionView {
                active: surface.session
                reducedMotion: surface.reducedMotion
                maximumViewportWidth: surface.maximumInteractiveViewportWidth
                maximumViewportHeight: surface.maximumInteractiveViewportHeight
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
            contentTransition.tryCommitDestination();
        }
    }

    RetainedPresentation {
        id: sessionPresentation
        parent: surfaceBackground
        transition: contentTransition
        layerKind: surface.coordinator.ownerSession
        workActive: surface.session
        presentationSource: sessionLoader.item
    }

    HoverHandler {
        id: hoverHandler
        enabled: surface.hoverInputEnabled
        onHoveredChanged: {
            if (surface.hoverInputEnabled) {
                surface.reportHover(hovered);
            }
        }
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        enabled: surface.expanded && !surface.surfaceState.explicitExpandedIntent
        onTapped: surface.requestDeliberateExpansion()
    }
}

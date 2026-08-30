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
        if (contentTransition.initialized && (snapshot.ownerKind !== contentTransition.currentKind
                                              || snapshot.ownerEpoch
                                              !== contentTransition.currentEpoch)) {
            capturePresentationPose();
            contentTransition.primeRetention();
        }
        surfaceState = snapshot;
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

    readonly property int geometryAnimationDuration: morphState.segmentDuration
    readonly property bool geometryAnimationRunning: morphState.active
    readonly property bool pointerHovered: hoverHandler.hovered
    readonly property real morphProgress: morphState.progress
    readonly property real morphNormalizedDistance: morphState.normalizedDistance
    readonly property bool morphExpansionSegment: morphState.expansionSegment
    readonly property int morphSequence: morphState.sequence
    readonly property real morphSegmentFromWidth: morphState.fromWidth
    readonly property real morphSegmentFromHeight: morphState.fromHeight
    readonly property real morphSegmentToWidth: morphState.toWidth
    readonly property real morphSegmentToHeight: morphState.toHeight
    readonly property bool morphFollowUpPending: morphState.followUpPending
    readonly property real renderedPanelWidth: morphState.initialized ? morphState.fromWidth + (
                                                                            morphState.toWidth
                                                                            - morphState.fromWidth)
                                                                        * morphState.progress :
                                                                        morphState.canonicalWidth
    readonly property real renderedPanelHeight: morphState.initialized ? morphState.fromHeight + (
                                                                             morphState.toHeight
                                                                             - morphState.fromHeight)
                                                                         * morphState.progress :
                                                                         morphState.canonicalHeight
    readonly property point panelMappedTopLeft: Qt.point(surfaceBackground.x, surfaceBackground.y)
    readonly property point panelMappedBottomRight: Qt.point(surfaceBackground.x
                                                             + surfaceBackground.width,
                                                             surfaceBackground.y
                                                             + surfaceBackground.height)
    readonly property real backgroundRadius: surfaceBackground.radius
    readonly property bool blurRequested: Theme.snapshot.blurEnabled
    readonly property real renderedShadowOpacity: shadowOutline.visible ? Theme.opacity.shadow
                                                                          * morphState.elevationFactor :
                                                                          0
    readonly property int shadowLayerCount: shadowOutline.layer.enabled
                                            && shadowOutline.layer.effect !== null ? 1 : 0
    readonly property int requestedKwinBlurRegionCount: surface.BackgroundEffect.blurRegion
                                                        === null ? 0 : 1

    readonly property bool contentTransitionRunning: contentTransition.active
    readonly property bool contentTransitionDestinationReady: contentTransition.destinationReady
    readonly property int contentTransitionFromKind: contentTransition.fromKind
    readonly property int contentTransitionToKind: contentTransition.toKind
    readonly property int contentTransitionDirection: contentTransition.direction
    readonly property var contentOutgoingItem: contentTransition.outgoingItem
    readonly property var contentIncomingItem: contentTransition.incomingItem
    readonly property real contentOutgoingOpacity: contentTransition.outgoingOpacity()
    readonly property real contentIncomingOpacity: contentTransition.incomingOpacity()
    readonly property real contentOutgoingOffset: contentTransition.offsetForKind(
                                                      contentTransition.fromKind)
    readonly property real contentIncomingOffset: contentTransition.offsetForKind(
                                                      contentTransition.toKind)
    readonly property bool contentOutgoingEnabled: contentOutgoingItem !== null
                                                   && contentOutgoingItem.enabled
    readonly property bool contentOutgoingAccessibleIgnored: contentOutgoingItem === null
                                                             || contentOutgoingItem.Accessible.ignored
    readonly property bool contentOutgoingRendered: contentTransition.retainedRendered()
    readonly property bool contentOutgoingWorkActive: contentTransition.retainedWorkActive()
    readonly property int retainedPresentationCount: contentTransition.retainedKeys.length
    readonly property real contentRenderedOpacityTotal: contentTransition.totalOpacity()
    readonly property bool clockContinuityActive: idleClockPresentation.matchedActive
                                                  || expandedClockPresentation.matchedActive
    readonly property bool mediaContinuityActive: idleMediaPresentation.matchedActive
                                                  || expandedMediaPresentation.matchedActive
    readonly property real clockContinuityOpacityTotal: idleClockPresentation.opacity
                                                        + expandedClockPresentation.opacity
    readonly property real mediaContinuityOpacityTotal: idleMediaPresentation.opacity
                                                        + expandedMediaPresentation.opacity
    readonly property bool clockContinuityGeometryAligned: !clockContinuityActive || (Math.abs(
                                                                                          idleClockPresentation.x
                                                                                          - expandedClockPresentation.x)
                                                                                      <= 0.5 && Math.abs(
                                                                                          idleClockPresentation.y
                                                                                          - expandedClockPresentation.y)
                                                                                      <= 0.5 && Math.abs(
                                                                                          idleClockPresentation.width
                                                                                          - expandedClockPresentation.width)
                                                                                      <= 0.5 && Math.abs(
                                                                                          idleClockPresentation.height
                                                                                          - expandedClockPresentation.height)
                                                                                      <= 0.5)
    readonly property bool mediaContinuityGeometryAligned: !mediaContinuityActive || (Math.abs(
                                                                                          idleMediaPresentation.x
                                                                                          - expandedMediaPresentation.x)
                                                                                      <= 0.5 && Math.abs(
                                                                                          idleMediaPresentation.y
                                                                                          - expandedMediaPresentation.y)
                                                                                      <= 0.5 && Math.abs(
                                                                                          idleMediaPresentation.width
                                                                                          - expandedMediaPresentation.width)
                                                                                      <= 0.5 && Math.abs(
                                                                                          idleMediaPresentation.height
                                                                                          - expandedMediaPresentation.height)
                                                                                      <= 0.5)

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

    function capturePresentationPose() {
        idlePresentation.capturePose();
        expandedPresentation.capturePose();
        transientPresentationLayer.capturePose();
        launcherPresentation.capturePose();
        historyPresentation.capturePose();
        trayPresentation.capturePose();
        audioPresentation.capturePose();
        weatherPresentation.capturePose();
        polkitPresentation.capturePose();
        sessionPresentation.capturePose();
        idleClockPresentation.capturePose();
        expandedClockPresentation.capturePose();
        idleMediaPresentation.capturePose();
        expandedMediaPresentation.capturePose();
    }

    function contentOpacityForKind(kind) {
        return contentTransition.opacityForKind(kind);
    }

    function contentOffsetForKind(kind) {
        return contentTransition.offsetForKind(kind);
    }

    function contentStartOpacityForKind(kind) {
        return contentTransition.startOpacityForKind(kind);
    }

    function contentStartOffsetForKind(kind) {
        return contentTransition.startOffsetForKind(kind);
    }

    function transitionDirection(fromKind, toKind) {
        const fromInteractive = isInteractiveKind(fromKind);
        const toInteractive = isInteractiveKind(toKind);
        if (!fromInteractive && !toInteractive) {
            return 0;
        }
        if (!fromInteractive) {
            return 1;
        }
        if (!toInteractive) {
            return -1;
        }
        if (fromKind === toKind) {
            return 0;
        }
        return toKind > fromKind ? 1 : -1;
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

        property int fromSurfaceGeneration: 0
        property int fromKind: surface.coordinator.ownerNone
        property real fromEpoch: 0
        property real fromRevision: 0
        property int toSurfaceGeneration: 0
        property int toKind: surface.coordinator.ownerNone
        property real toEpoch: 0
        property real toRevision: 0

        property var outgoingItem: null
        property var incomingItem: null
        property int direction: 0
        property var retainedKeys: []
        property var startOpacities: ({})
        property var startOffsets: ({})
        property var targetOffsets: ({})
        property var retainedZOrder: []

        function initialize() {
            if (initialized) {
                return;
            }
            currentSurfaceGeneration = surface.hostSurfaceGeneration;
            currentKind = surface.ownerKind;
            currentEpoch = surface.ownerEpoch;
            currentRevision = surface.ownerRevision;
            fromSurfaceGeneration = currentSurfaceGeneration;
            fromKind = currentKind;
            fromEpoch = currentEpoch;
            fromRevision = currentRevision;
            toSurfaceGeneration = currentSurfaceGeneration;
            toKind = currentKind;
            toEpoch = currentEpoch;
            toRevision = currentRevision;
            incomingItem = surface.visualLayerForKind(currentKind);
            destinationReady = surface.visualLayerReady(currentKind);
            initialized = true;
        }

        function queueIdentityReconciliation() {
            if (identityReconcileQueued) {
                return;
            }
            identityReconcileQueued = true;
            Qt.callLater(function () {
                contentTransition.identityReconcileQueued = false;
                contentTransition.handleIdentityChanged();
            });
        }

        function valueFor(values, kind, fallback) {
            const key = surface.visualKey(kind);
            const value = values[key];
            return typeof value === "number" ? value : fallback;
        }

        function uniqueVisualKeys(keys) {
            const result = [];
            for (let index = 0; index < keys.length; index += 1) {
                const key = surface.visualKey(keys[index]);
                if (key !== surface.coordinator.ownerNone && result.indexOf(key) < 0) {
                    result.push(key);
                }
            }
            return result;
        }

        function rawOpacityForKind(kind) {
            const key = surface.visualKey(kind);
            if (key === surface.coordinator.ownerNone) {
                return 0;
            }
            const start = valueFor(startOpacities, key, 0);
            const target = key === surface.visualKey(toKind) ? 1 : 0;
            return start + (target - start) * morphState.progress;
        }

        function rawOpacityTotal() {
            const keys = surface.visualKeys();
            let total = 0;
            for (let index = 0; index < keys.length; index += 1) {
                total += rawOpacityForKind(keys[index]);
            }
            return total;
        }

        function opacityForKind(kind) {
            const key = surface.visualKey(kind);
            if (key === surface.coordinator.ownerNone) {
                return 0;
            }
            if (!active) {
                return key === surface.visualKey(currentKind) ? 1 : 0;
            }
            const total = rawOpacityTotal();
            return total > 0.000001 ? rawOpacityForKind(key) / total : key === surface.visualKey(
                                          toKind) ? 1 : 0;
        }

        function startOpacityForKind(kind) {
            return valueFor(startOpacities, kind, opacityForKind(kind));
        }

        function offsetForKind(kind) {
            const key = surface.visualKey(kind);
            if (!active || key === surface.coordinator.ownerNone) {
                return 0;
            }
            const start = valueFor(startOffsets, key, 0);
            const target = valueFor(targetOffsets, key, 0);
            return start + (target - start) * morphState.progress;
        }

        function startOffsetForKind(kind) {
            return valueFor(startOffsets, kind, offsetForKind(kind));
        }

        function zForKind(kind) {
            const key = surface.visualKey(kind);
            if (!active) {
                return key === surface.visualKey(currentKind) ? 1 : 0;
            }
            const retainedIndex = retainedZOrder.indexOf(key);
            if (retainedIndex >= 0) {
                return retainedZOrder.length - retainedIndex + 2;
            }
            return key === surface.visualKey(toKind) ? 1 : 0;
        }

        function visibleVisualKeys() {
            const candidates = surface.visualKeys();
            const visible = [];
            for (let index = 0; index < candidates.length; index += 1) {
                const key = candidates[index];
                if (opacityForKind(key) > 0.0001 && surface.visualLayerForKind(key) !== null) {
                    visible.push(key);
                }
            }
            visible.sort(function (first, second) {
                return contentTransition.zForKind(second) - contentTransition.zForKind(first);
            });
            return visible;
        }

        function primeRetention() {
            retainedKeys = uniqueVisualKeys(visibleVisualKeys());
        }

        function retainsKind(kind) {
            return retainedKeys.indexOf(surface.visualKey(kind)) >= 0;
        }

        function layerVisible(kind) {
            const key = surface.visualKey(kind);
            return surface.visualKey(surface.ownerKind) === key || retainsKind(key);
        }

        function outgoingOpacity() {
            if (!active) {
                return 0;
            }
            const destinationKey = surface.visualKey(toKind);
            if (surface.visualKey(fromKind) === destinationKey) {
                return 1;
            }
            let opacity = 0;
            for (let index = 0; index < retainedKeys.length; index += 1) {
                if (retainedKeys[index] !== destinationKey) {
                    opacity += opacityForKind(retainedKeys[index]);
                }
            }
            return Math.min(1, opacity);
        }

        function incomingOpacity() {
            return active ? destinationReady ? opacityForKind(toKind) : 0 : incomingItem === null
                                               ? 0 : 1;
        }

        function totalOpacity() {
            if (!active) {
                return incomingItem === null ? 0 : 1;
            }
            const keys = uniqueVisualKeys(retainedKeys.concat([surface.visualKey(toKind)]));
            let opacity = 0;
            for (let index = 0; index < keys.length; index += 1) {
                opacity += opacityForKind(keys[index]);
            }
            return Math.min(1, opacity);
        }

        function retainedRendered() {
            if (!active || retainedKeys.length === 0) {
                return false;
            }
            for (let index = 0; index < retainedKeys.length; index += 1) {
                const layer = surface.visualLayerForKind(retainedKeys[index]);
                if (layer === null || layer.sourceItem === null || !layer.visible || opacityForKind(
                            retainedKeys[index]) <= 0) {
                    return false;
                }
            }
            return true;
        }
        function retainedWorkActive() {
            const destinationKey = surface.visualKey(toKind);
            for (let index = 0; index < retainedKeys.length; index += 1) {
                if (retainedKeys[index] !== destinationKey && surface.presentationWorkActive(
                            retainedKeys[index])) {
                    return true;
                }
            }
            return false;
        }

        function matchedPairActive(firstKind, secondKind) {
            if (!active || !destinationReady) {
                return false;
            }
            const fromKey = surface.visualKey(fromKind);
            const toKey = surface.visualKey(toKind);
            const firstKey = surface.visualKey(firstKind);
            const secondKey = surface.visualKey(secondKind);
            return (fromKey === firstKey && toKey === secondKey) || (fromKey === secondKey && toKey
                                                                     === firstKey);
        }

        function finishPriorDestination() {
            const item = surface.visualLayerForKind(currentKind);
            const source = item === null ? null : item.sourceItem;
            if (surface.isTransientKind(currentKind) && source !== null
                    && typeof source.finishTransition === "function") {
                source.finishTransition(currentSurfaceGeneration, currentEpoch, currentRevision);
            }
        }

        function captureBlend(destinationKind) {
            const visible = uniqueVisualKeys(visibleVisualKeys());
            const destinationKey = surface.visualKey(destinationKind);
            const nextStartOpacities = {};
            const nextStartOffsets = {};
            const nextTargetOffsets = {};
            const nextRetained = [];
            const nextDirection = surface.transitionDirection(currentKind, destinationKind);
            for (let index = 0; index < visible.length; index += 1) {
                const key = visible[index];
                nextStartOpacities[key] = opacityForKind(key);
                nextStartOffsets[key] = offsetForKind(key);
                nextTargetOffsets[key] = key === destinationKey ? 0 : -nextDirection
                                                                  * Theme.spacing.xl;
                if (key !== destinationKey && nextStartOpacities[key] > 0.0001) {
                    nextRetained.push(key);
                }
            }
            const priorKey = surface.visualKey(currentKind);
            if (priorKey !== surface.coordinator.ownerNone && priorKey !== destinationKey
                    && surface.visualLayerForKind(priorKey) !== null && nextRetained.indexOf(
                        priorKey) < 0) {
                nextStartOpacities[priorKey] = active ? Math.max(0.0001, opacityForKind(priorKey)) :
                                                        1;
                nextStartOffsets[priorKey] = offsetForKind(priorKey);
                nextTargetOffsets[priorKey] = -nextDirection * Theme.spacing.xl;
                nextRetained.push(priorKey);
            }
            if (typeof nextStartOpacities[destinationKey] !== "number") {
                nextStartOpacities[destinationKey] = 0;
                nextStartOffsets[destinationKey] = nextDirection * Theme.spacing.xl;
                nextTargetOffsets[destinationKey] = 0;
            }
            startOpacities = nextStartOpacities;
            startOffsets = nextStartOffsets;
            targetOffsets = nextTargetOffsets;
            retainedKeys = nextRetained;
            retainedZOrder = nextRetained.slice();
            direction = nextDirection;
        }

        function rebaseBlend() {
            const visible = uniqueVisualKeys(visibleVisualKeys());
            const destinationKey = surface.visualKey(toKind);
            const nextStartOpacities = {};
            const nextStartOffsets = {};
            const nextTargetOffsets = {};
            const nextRetained = [];
            for (let index = 0; index < visible.length; index += 1) {
                const key = visible[index];
                nextStartOpacities[key] = opacityForKind(key);
                nextStartOffsets[key] = offsetForKind(key);
                nextTargetOffsets[key] = valueFor(targetOffsets, key, 0);
                if (key !== destinationKey && nextStartOpacities[key] > 0.0001) {
                    nextRetained.push(key);
                }
            }
            for (let index = 0; index < retainedKeys.length; index += 1) {
                const key = retainedKeys[index];
                if (key !== destinationKey && nextRetained.indexOf(key) < 0) {
                    nextRetained.push(key);
                }
            }
            if (typeof nextStartOpacities[destinationKey] !== "number") {
                nextStartOpacities[destinationKey] = opacityForKind(destinationKey);
                nextStartOffsets[destinationKey] = offsetForKind(destinationKey);
                nextTargetOffsets[destinationKey] = 0;
            }
            startOpacities = nextStartOpacities;
            startOffsets = nextStartOffsets;
            targetOffsets = nextTargetOffsets;
            retainedKeys = nextRetained;
            retainedZOrder = nextRetained.slice();
        }

        function request(generation, kind, epoch, revision) {
            if (!initialized) {
                initialize();
            }
            if (generation === currentSurfaceGeneration && kind === currentKind && epoch
                    === currentEpoch) {
                currentRevision = revision;
                toRevision = revision;
                morphState.handleIdentityChanged();
                return;
            }

            const priorGeneration = currentSurfaceGeneration;
            const priorKind = currentKind;
            const priorEpoch = currentEpoch;
            const priorRevision = currentRevision;
            const priorItem = surface.visualLayerForKind(priorKind);
            if (active) {
                finishPriorDestination();
            }

            captureBlend(kind);
            morphState.holdCurrentPose();
            cancelPendingCommit();
            requestSerial += 1;
            fromSurfaceGeneration = priorGeneration;
            fromKind = priorKind;
            fromEpoch = priorEpoch;
            fromRevision = priorRevision;
            toSurfaceGeneration = generation;
            toKind = kind;
            toEpoch = epoch;
            toRevision = revision;
            currentSurfaceGeneration = generation;
            currentKind = kind;
            currentEpoch = epoch;
            currentRevision = revision;
            outgoingItem = priorItem;
            incomingItem = null;
            destinationReady = false;
            preparing = true;
            active = true;
            tryCommitDestination();
        }

        function tryCommitDestination() {
            if (!active || !preparing || commitQueued || !surface.visualLayerReady(toKind)) {
                return;
            }

            if (surface.reducedMotion) {
                commitQueued = true;
                commitDestination(requestSerial);
                return;
            }

            const layer = surface.visualLayerForKind(toKind);
            if (layer === null || layer.sourceItem === null) {
                return;
            }

            commitQueued = true;
            layer.scheduleUpdate();
            destinationFramePrime.serial = requestSerial;
            destinationFramePrime.frameCount = 0;
            destinationFramePrime.restart();
        }

        function beginDestinationCommit(serial) {
            if (!active || !preparing || serial !== requestSerial) {
                return;
            }
            destinationCommit.serial = serial;
            destinationCommit.expectedWidth = morphState.canonicalWidth;
            destinationCommit.expectedHeight = morphState.canonicalHeight;
            destinationCommit.stabilityAttempts = 0;
            destinationCommit.stableTicks = 0;
            destinationCommit.restart();
        }

        function cancelPendingCommit() {
            destinationFramePrime.stop();
            destinationCommit.stop();
            commitQueued = false;
        }

        function commitDestination(serial, expectedWidth, expectedHeight) {
            if (!active || !preparing || serial !== requestSerial) {
                return;
            }
            commitQueued = false;
            if (toSurfaceGeneration !== surface.hostSurfaceGeneration || toKind
                    !== surface.ownerKind || toEpoch !== surface.ownerEpoch ||
                    !surface.visualLayerReady(toKind)) {
                return;
            }
            if (!surface.reducedMotion && typeof expectedWidth === "number"
                    && destinationCommit.stabilityAttempts < 12) {
                const targetChanged = morphState.targetsDiffer(expectedWidth, expectedHeight,
                                                               morphState.canonicalWidth,
                                                               morphState.canonicalHeight);
                if (targetChanged || destinationCommit.stableTicks < 1) {
                    commitQueued = true;
                    if (targetChanged) {
                        destinationCommit.expectedWidth = morphState.canonicalWidth;
                        destinationCommit.expectedHeight = morphState.canonicalHeight;
                        destinationCommit.stableTicks = 0;
                    } else {
                        destinationCommit.stableTicks += 1;
                    }
                    destinationCommit.stabilityAttempts += 1;
                    destinationCommit.restart();
                    return;
                }
            }

            toRevision = surface.ownerRevision;
            currentRevision = surface.ownerRevision;
            const item = surface.visualLayerForKind(toKind);
            const source = item === null ? null : item.sourceItem;
            incomingItem = item;
            if (surface.isTransientKind(toKind) && source !== null
                    && typeof source.prepareTransition === "function" && !source.prepareTransition(
                        toSurfaceGeneration, toEpoch, toRevision)) {
                incomingItem = null;
                return;
            }

            destinationReady = true;
            preparing = false;
            surface.queuePresentationAcknowledgement();
            surface.queueOwnerFocus();
            if (surface.reducedMotion) {
                settleSynchronously();
            } else {
                morphState.beginPreparedSegment(morphState.currentWidth(), morphState.currentHeight(
                                                    ), morphState.canonicalWidth,
                                                morphState.canonicalHeight, true);
            }
        }

        function finish(identity) {
            if (!active || !destinationReady || identity === null || identity.surfaceGeneration !== toSurfaceGeneration
                    || identity.ownerKind !== toKind || identity.ownerEpoch !== toEpoch
                    || identity.ownerRevision !== toRevision || identity.sequence
                    !== morphState.sequence || surface.hostSurfaceGeneration
                    !== toSurfaceGeneration || surface.ownerKind !== toKind || surface.ownerEpoch
                    !== toEpoch || surface.ownerRevision !== toRevision) {
                return false;
            }

            const item = surface.visualLayerForKind(toKind);
            const source = item === null ? null : item.sourceItem;
            if (surface.isTransientKind(toKind) && source !== null
                    && typeof source.finishTransition === "function") {
                source.finishTransition(toSurfaceGeneration, toEpoch, toRevision);
            }
            active = false;
            preparing = false;
            destinationReady = true;
            commitQueued = false;
            outgoingItem = null;
            incomingItem = item;
            retainedKeys = [];
            retainedZOrder = [];
            startOpacities = {};
            startOffsets = {};
            targetOffsets = {};
            fromSurfaceGeneration = toSurfaceGeneration;
            fromKind = toKind;
            fromEpoch = toEpoch;
            fromRevision = toRevision;
            direction = 0;
            surface.queuePresentationAcknowledgement();
            surface.queueOwnerFocus();
            return true;
        }

        function settleSynchronously() {
            if (!active) {
                return;
            }
            if (!destinationReady) {
                cancelPendingCommit();
                if (surface.visualLayerReady(toKind)) {
                    commitQueued = true;
                    commitDestination(requestSerial);
                } else {
                    tryCommitDestination();
                }
                return;
            }
            if (surface.reducedMotion) {
                morphState.settleAt(morphState.canonicalWidth, morphState.canonicalHeight, false);
                finish({
                           "surfaceGeneration": toSurfaceGeneration,
                           "ownerKind": toKind,
                           "ownerEpoch": toEpoch,
                           "ownerRevision": toRevision,
                           "sequence": morphState.sequence
                       });
                return;
            }
            morphState.settleSynchronously();
        }

        function cancelStale() {
            requestSerial += 1;
            cancelPendingCommit();
            const item = surface.visualLayerForKind(currentKind);
            const source = item === null ? null : item.sourceItem;
            if (active && surface.isTransientKind(currentKind) && source !== null
                    && typeof source.cancelStaleTransition === "function") {
                source.cancelStaleTransition();
            }
            active = false;
            preparing = false;
            destinationReady = surface.visualLayerReady(currentKind);
            outgoingItem = null;
            incomingItem = item;
            retainedKeys = [];
            retainedZOrder = [];
            startOpacities = {};
            startOffsets = {};
            targetOffsets = {};
            fromSurfaceGeneration = currentSurfaceGeneration;
            fromKind = currentKind;
            fromEpoch = currentEpoch;
            fromRevision = currentRevision;
            toKind = currentKind;
            toEpoch = currentEpoch;
            toRevision = currentRevision;
            direction = 0;
        }

        function handleIdentityChanged() {
            if (!initialized) {
                return;
            }
            if (surface.hostSurfaceGeneration !== currentSurfaceGeneration) {
                cancelStale();
                currentSurfaceGeneration = surface.hostSurfaceGeneration;
                currentKind = surface.ownerKind;
                currentEpoch = surface.ownerEpoch;
                currentRevision = surface.ownerRevision;
                fromSurfaceGeneration = currentSurfaceGeneration;
                fromKind = currentKind;
                fromEpoch = currentEpoch;
                fromRevision = currentRevision;
                toSurfaceGeneration = currentSurfaceGeneration;
                toKind = currentKind;
                toEpoch = currentEpoch;
                toRevision = currentRevision;
                incomingItem = surface.visualLayerForKind(currentKind);
                destinationReady = surface.visualLayerReady(currentKind);
                morphState.handleIdentityChanged();
                return;
            }
            if (active && surface.ownerKind === toKind && surface.hostSurfaceGeneration
                    === toSurfaceGeneration) {
                currentEpoch = surface.ownerEpoch;
                currentRevision = surface.ownerRevision;
                toEpoch = surface.ownerEpoch;
                toRevision = surface.ownerRevision;
                morphState.handleIdentityChanged();
                return;
            }
            if (surface.ownerKind !== currentKind || surface.ownerEpoch !== currentEpoch) {
                request(surface.hostSurfaceGeneration, surface.ownerKind, surface.ownerEpoch,
                        surface.ownerRevision);
                return;
            }
            currentRevision = surface.ownerRevision;
            toRevision = surface.ownerRevision;
            morphState.handleIdentityChanged();
        }
    }

    QtObject {
        id: morphState

        readonly property real tolerance: 1
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
        readonly property string currentOwnerKey: surface.hostSurfaceGeneration + ":"
                                                  + surface.surfaceState.ownerKind + ":"
                                                  + surface.surfaceState.ownerEpoch + ":"
                                                  + surface.surfaceState.revision
        readonly property size currentScreenBounds: Qt.size(surface.screen === null ? 0 :
                                                                                      surface.screen.width,
                                                            surface.screen === null ? 0 :
                                                                                      surface.screen.height)

        property bool initialized: false
        property bool active: false
        property real progress: 1
        property real elevationFromFactor: 1
        readonly property real elevationFactor: Math.max(0, Math.min(1, elevationFromFactor + (1
                                                                                               - elevationFromFactor)
                                                                     * progress - 0.18 * 4
                                                                     * progress * (1 - progress)))
        property int sequence: 0
        property bool followUpPending: false
        property bool expansionSegment: false
        property bool reconcileQueued: false
        property real normalizedDistance: 0
        property int segmentDuration: 0

        property int segmentSurfaceGeneration: 0
        property int segmentOwnerKind: surface.coordinator.ownerNone
        property real segmentOwnerEpoch: 0
        property real segmentOwnerRevision: 0
        property var segmentScreen: null
        property real segmentScreenWidth: 0
        property real segmentScreenHeight: 0
        property real fromWidth: 0
        property real fromHeight: 0
        property real toWidth: 0
        property real toHeight: 0

        function targetsDiffer(firstWidth, firstHeight, secondWidth, secondHeight) {
            return Math.abs(firstWidth - secondWidth) > tolerance || Math.abs(firstHeight
                                                                              - secondHeight)
                    > tolerance;
        }

        function currentWidth() {
            return fromWidth + (toWidth - fromWidth) * progress;
        }

        function currentHeight() {
            return fromHeight + (toHeight - fromHeight) * progress;
        }

        function distanceFor(startWidth, startHeight, endWidth, endHeight) {
            const widthDistance = Math.abs(endWidth - startWidth) / Math.max(1, startWidth,
                                                                             endWidth);
            const heightDistance = Math.abs(endHeight - startHeight) / Math.max(1, startHeight,
                                                                                endHeight);
            return Math.min(1, Math.max(0, widthDistance, heightDistance));
        }

        function durationFor(distance, expansion) {
            if (Theme.motion.scale <= 0) {
                return 0;
            }
            const minimum = expansion ? Theme.motion.durationExpansionMinimum :
                                        Theme.motion.durationMorphMinimum;
            const maximum = expansion ? Theme.motion.durationExpansionMaximum :
                                        Theme.motion.durationMorphMaximum;
            return Math.max(1, Math.round(minimum + (maximum - minimum) * distance));
        }

        function isIdleExpandedTransition() {
            return (contentTransition.fromKind === surface.coordinator.ownerIdle
                    && contentTransition.toKind === surface.coordinator.ownerExpanded) || (
                        contentTransition.fromKind === surface.coordinator.ownerExpanded
                        && contentTransition.toKind === surface.coordinator.ownerIdle);
        }

        function recordIdentity() {
            segmentSurfaceGeneration = surface.hostSurfaceGeneration;
            segmentOwnerKind = surface.surfaceState.ownerKind;
            segmentOwnerEpoch = surface.surfaceState.ownerEpoch;
            segmentOwnerRevision = surface.surfaceState.revision;
            segmentScreen = surface.screen;
            segmentScreenWidth = currentScreenBounds.width;
            segmentScreenHeight = currentScreenBounds.height;
        }

        function identitySnapshot() {
            return {
                "ownerEpoch": segmentOwnerEpoch,
                "ownerKind": segmentOwnerKind,
                "ownerRevision": segmentOwnerRevision,
                "screen": segmentScreen,
                "screenHeight": segmentScreenHeight,
                "screenWidth": segmentScreenWidth,
                "sequence": sequence,
                "surfaceGeneration": segmentSurfaceGeneration
            };
        }

        function identityBaseMatches() {
            return segmentSurfaceGeneration === surface.hostSurfaceGeneration && segmentOwnerKind
                    === surface.surfaceState.ownerKind && segmentOwnerEpoch
                    === surface.surfaceState.ownerEpoch && segmentScreen === surface.screen
                    && segmentScreenWidth === currentScreenBounds.width && segmentScreenHeight
                    === currentScreenBounds.height;
        }

        function identityMatches() {
            return identityBaseMatches() && segmentOwnerRevision === surface.surfaceState.revision;
        }

        function settleAt(width, height, notifyCompletion) {
            morphProgressAnimation.stop();
            reconcileQueued = false;
            fromWidth = width;
            fromHeight = height;
            toWidth = width;
            toHeight = height;
            progress = 1;
            elevationFromFactor = 1;
            followUpPending = false;
            recordIdentity();
            active = false;
            if (notifyCompletion) {
                contentTransition.finish(identitySnapshot());
            }
        }

        function settleSynchronously() {
            if (!initialized || contentTransition.preparing) {
                return;
            }
            settleAt(canonicalWidth, canonicalHeight, true);
        }

        function holdCurrentPose() {
            if (!initialized) {
                return;
            }
            const width = currentWidth();
            const height = currentHeight();
            const elevation = elevationFactor;
            morphProgressAnimation.stop();
            reconcileQueued = false;
            fromWidth = width;
            fromHeight = height;
            toWidth = width;
            toHeight = height;
            elevationFromFactor = elevation;
            progress = 0;
            normalizedDistance = 0;
            segmentDuration = 0;
            followUpPending = false;
            active = false;
        }

        function initialize() {
            if (initialized) {
                return;
            }
            const width = canonicalWidth;
            const height = canonicalHeight;
            fromWidth = width;
            fromHeight = height;
            toWidth = width;
            toHeight = height;
            progress = 1;
            elevationFromFactor = 1;
            normalizedDistance = 0;
            segmentDuration = 0;
            followUpPending = false;
            recordIdentity();
            initialized = true;
        }

        function beginPreparedSegment(startWidth, startHeight, endWidth, endHeight, forceVisual) {
            const visualChange = forceVisual === true;
            const geometryChange = targetsDiffer(startWidth, startHeight, endWidth, endHeight);
            normalizedDistance = distanceFor(startWidth, startHeight, endWidth, endHeight);
            expansionSegment = isIdleExpandedTransition();
            segmentDuration = durationFor(normalizedDistance, expansionSegment);
            if (!visualChange && !geometryChange) {
                settleAt(endWidth, endHeight, true);
                return;
            }

            if (active && contentTransition.active) {
                contentTransition.rebaseBlend();
            }
            const elevation = elevationFactor;
            morphProgressAnimation.stop();
            reconcileQueued = false;
            fromWidth = startWidth;
            fromHeight = startHeight;
            toWidth = endWidth;
            toHeight = endHeight;
            elevationFromFactor = elevation;
            progress = 0;
            followUpPending = false;
            sequence += 1;
            recordIdentity();
            if (surface.reducedMotion || segmentDuration <= 0) {
                settleAt(endWidth, endHeight, true);
                return;
            }
            active = true;
            morphProgressAnimation.runSequence = sequence;
            morphProgressAnimation.restart();
        }

        function interruptSemantic(force) {
            if (!initialized || (!force && identityMatches())) {
                return;
            }

            const startWidth = currentWidth();
            const startHeight = currentHeight();
            reconcileQueued = false;
            beginPreparedSegment(startWidth, startHeight, canonicalWidth, canonicalHeight, false);
        }

        function handleIdentityChanged() {
            if (!initialized || identityMatches()) {
                return;
            }
            if (surface.reducedMotion) {
                settleSynchronously();
                return;
            }
            if (active && !identityBaseMatches()) {
                interruptSemantic(false);
                return;
            }
            queueCanonicalReconcile();
        }

        function forceScreenBoundInterrupt() {
            contentTransition.cancelStale();
            interruptSemantic(true);
        }

        function reconcileCanonicalTarget() {
            if (!initialized || contentTransition.preparing) {
                return;
            }
            if (surface.reducedMotion) {
                settleSynchronously();
                return;
            }
            if (!identityMatches()) {
                interruptSemantic(false);
                return;
            }
            if (active) {
                followUpPending = targetsDiffer(toWidth, toHeight, canonicalWidth, canonicalHeight);
                return;
            }

            beginPreparedSegment(currentWidth(), currentHeight(), canonicalWidth, canonicalHeight,
                                 false);
        }

        function queueCanonicalReconcile() {
            if (reconcileQueued) {
                return;
            }
            reconcileQueued = true;
            Qt.callLater(function () {
                if (!morphState.reconcileQueued) {
                    return;
                }
                morphState.reconcileQueued = false;
                morphState.reconcileCanonicalTarget();
            });
        }

        function handleCanonicalTargetChanged() {
            if (!initialized || contentTransition.preparing) {
                return;
            }
            if (surface.reducedMotion) {
                settleSynchronously();
                return;
            }
            if (!identityMatches()) {
                contentTransition.queueIdentityReconciliation();
                return;
            }
            if (active) {
                followUpPending = targetsDiffer(toWidth, toHeight, canonicalWidth, canonicalHeight);
                return;
            }
            queueCanonicalReconcile();
        }

        function finishSegment(expectedSequence) {
            if (!active || expectedSequence !== sequence) {
                return;
            }

            progress = 1;
            if (surface.reducedMotion) {
                settleSynchronously();
                return;
            }
            if (!identityMatches()) {
                if (identityBaseMatches()) {
                    queueCanonicalReconcile();
                } else {
                    beginPreparedSegment(toWidth, toHeight, canonicalWidth, canonicalHeight, false);
                }
                return;
            }

            followUpPending = targetsDiffer(toWidth, toHeight, canonicalWidth, canonicalHeight);
            if (followUpPending) {
                const startWidth = currentWidth();
                const startHeight = currentHeight();
                beginPreparedSegment(startWidth, startHeight, canonicalWidth, canonicalHeight,
                                     false);
                return;
            }

            toWidth = canonicalWidth;
            toHeight = canonicalHeight;
            followUpPending = false;
            recordIdentity();
            active = false;
            contentTransition.finish(identitySnapshot());
        }

        onCanonicalWidthChanged: handleCanonicalTargetChanged()
        onCanonicalHeightChanged: handleCanonicalTargetChanged()
        onCurrentOwnerKeyChanged: contentTransition.handleIdentityChanged()
        onCurrentScreenBoundsChanged: forceScreenBoundInterrupt()
    }

    function interruptMorphForScreenBounds() {
        morphState.forceScreenBoundInterrupt();
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
        id: morphProgressAnimation

        property int runSequence: 0

        target: morphState
        property: "progress"
        from: 0
        to: 1
        duration: surface.geometryAnimationDuration
        easing.type: Theme.motion.easingMorph
        onFinished: morphState.finishSegment(runSequence)
    }

    onScreenChanged: morphState.forceScreenBoundInterrupt()
    onBackingWindowChanged: {
        shellWindowWasActive = false;
        if (backingWindow !== null) {
            handleWindowActivation(backingWindow.active);
        }
    }
    onReducedMotionChanged: {
        if (reducedMotion) {
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
        focusHandoffPending = focusTarget !== coordinator.focusNone;
        contentTransition.queueIdentityReconciliation();
    }
    onHostSurfaceGenerationChanged: {
        contentTransition.handleIdentityChanged();
        queuePresentationAcknowledgement();
        if (hoverInputEnabled && hostSurfaceGeneration > 0 && hoverHandler.hovered) {
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

    onFocusTargetChanged: focusHandoffPending = focusTarget !== coordinator.focusNone
    onFocusRequestSerialChanged: queueOwnerFocus()
    onOwnerEpochChanged: {
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
    implicitHeight: windowGutterTop + renderedPanelHeight + windowGutterBottom
    implicitWidth: windowGutterLeft + renderedPanelWidth + windowGutterRight

    margins.top: edgeInset - windowGutterTop
    margins.left: screen === null ? edgeInset - windowGutterLeft : Math.round((screen.width
                                                                               - renderedPanelWidth)
                                                                              / 2) - windowGutterLeft

    Rectangle {
        id: shadowOutline

        x: surface.windowGutterLeft
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
        x: surface.windowGutterLeft
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
        property bool sourceAvailable: presentationSource !== null
        property real liveX: 0
        property real liveY: 0
        property real liveWidth: presentationSource === null ? 0 : presentationSource.width
        property real liveHeight: presentationSource === null ? 0 : presentationSource.height
        property bool matchEnabled: false
        property int peerLayerKind: -1
        property var peerPresentation: null
        property real progress: 1
        property real capturedX: 0
        property real capturedY: 0
        property real capturedWidth: 0
        property real capturedHeight: 0
        property bool releasingTexture: false

        readonly property var pairedPeer: peerPresentation === null ? retainedPresentation :
                                                                      peerPresentation
        readonly property bool matchedActive: matchEnabled && peerPresentation !== null
                                              && sourceItem !== null && peerPresentation.sourceItem
                                              !== null && transition.matchedPairActive(layerKind,
                                                                                       peerLayerKind)
        readonly property bool destinationIsThis: transition.toKind === layerKind
        readonly property real ownX: workActive ? liveX : capturedX
        readonly property real ownY: workActive ? liveY : capturedY
        readonly property real ownWidth: workActive ? liveWidth : capturedWidth
        readonly property real ownHeight: workActive ? liveHeight : capturedHeight
        readonly property real pairedStartX: destinationIsThis ? pairedPeer.capturedX : capturedX
        readonly property real pairedStartY: destinationIsThis ? pairedPeer.capturedY : capturedY
        readonly property real pairedStartWidth: destinationIsThis ? pairedPeer.capturedWidth :
                                                                     capturedWidth
        readonly property real pairedStartHeight: destinationIsThis ? pairedPeer.capturedHeight :
                                                                      capturedHeight
        readonly property real pairedEndX: destinationIsThis ? liveX : pairedPeer.liveX
        readonly property real pairedEndY: destinationIsThis ? liveY : pairedPeer.liveY
        readonly property real pairedEndWidth: destinationIsThis ? liveWidth : pairedPeer.liveWidth
        readonly property real pairedEndHeight: destinationIsThis ? liveHeight :
                                                                    pairedPeer.liveHeight

        sourceItem: transition.layerVisible(layerKind) && sourceAvailable ? presentationSource :
                                                                            null
        live: sourceItem === null ? releasingTexture : workActive
        hideSource: sourceItem !== null
        recursive: false
        mipmap: false
        visible: transition.layerVisible(layerKind) && sourceItem !== null
        enabled: false
        Accessible.ignored: true
        onSourceItemChanged: {
            if (sourceItem === null) {
                releasingTexture = true;
                releaseTextureTimer.restart();
            } else {
                releasingTexture = false;
                releaseTextureTimer.stop();
                transition.tryCommitDestination();
            }
        }
        opacity: transition.opacityForKind(layerKind)
        z: transition.zForKind(layerKind)
        x: matchedActive ? pairedStartX + (pairedEndX - pairedStartX) * progress : ownX
        y: matchedActive ? pairedStartY + (pairedEndY - pairedStartY) * progress : ownY
        width: sourceItem === null ? 0 : matchedActive ? pairedStartWidth + (pairedEndWidth
                                                                             - pairedStartWidth)
                                                         * progress : ownWidth
        height: sourceItem === null ? 0 : matchedActive ? pairedStartHeight + (pairedEndHeight
                                                                               - pairedStartHeight)
                                                          * progress : ownHeight
        transform: Translate {
            x: retainedPresentation.matchedActive ? 0 :
                                                    retainedPresentation.transition.offsetForKind(
                                                        retainedPresentation.layerKind)
        }

        Timer {
            id: releaseTextureTimer

            interval: 0
            repeat: false
            onTriggered: retainedPresentation.releasingTexture = false
        }

        function capturePose() {
            capturedX = x;
            capturedY = y;
            capturedWidth = width;
            capturedHeight = height;
        }
    }

    Loader {
        id: transientLoader

        parent: surfaceBackground
        anchors.fill: parent
        active: ((surface.transientOwner && surface.transientPresentation !== null)
                 || contentTransition.retainsKind(surface.coordinator.ownerWorkspace))
        visible: active
        enabled: surface.transientOwner
        Accessible.ignored: !enabled

        sourceComponent: Component {
            TransientView {
                active: surface.transientOwner
                kind: surface.transientOwner ? surface.surfaceState.ownerName : ""
                ownerEpoch: surface.ownerEpoch
                ownerRevision: surface.ownerRevision
                presentation: surface.transientPresentation ?? ({})
                surfaceGeneration: surface.hostSurfaceGeneration
                transitionManaged: contentTransition.active && (surface.isTransientKind(
                                                                    contentTransition.fromKind)
                                                                || surface.isTransientKind(
                                                                    contentTransition.toKind))
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
        liveWidth: surfaceBackground.width
        liveHeight: surfaceBackground.height
        progress: surface.morphProgress
    }

    IdleIsland {
        id: idleContent

        parent: surfaceBackground
        anchors.centerIn: parent
        visible: contentTransition.layerVisible(surface.coordinator.ownerIdle)
        enabled: surface.ownerKind === surface.coordinator.ownerIdle
        Accessible.ignored: !enabled
        workActive: enabled
        externalClockPresentation: true
        externalMediaPresentation: true
        virtualDesktops: surface.virtualDesktops
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
        liveX: idleContent.x
        liveY: idleContent.y
        liveWidth: idleContent.width
        liveHeight: idleContent.height
        progress: surface.morphProgress
    }

    ExpandedDashboard {
        id: expandedContent

        parent: surfaceBackground
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: boundedWidth
        height: boundedHeight
        visible: contentTransition.layerVisible(surface.coordinator.ownerExpanded)
        enabled: surface.expanded
        Accessible.ignored: !enabled
        active: surface.expanded
        gamingPerformance: surface.gamingPerformance
        gamingIndicatorEnabled: UserConfig.snapshot.island.gamingIndicator
        retainMatchedPresentation: contentTransition.retainsKind(surface.coordinator.ownerExpanded)
        externalClockPresentation: true
        externalMediaPresentation: true
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
        onCloseRequested: surface.cancelDashboard()
    }

    RetainedPresentation {
        id: expandedPresentation

        parent: surfaceBackground
        transition: contentTransition
        layerKind: surface.coordinator.ownerExpanded
        workActive: expandedContent.active
        presentationSource: expandedContent
        liveX: expandedContent.x
        liveY: expandedContent.y
        liveWidth: expandedContent.width
        liveHeight: expandedContent.height
        progress: surface.morphProgress
    }

    RetainedPresentation {
        id: idleClockPresentation
        parent: surfaceBackground
        transition: contentTransition
        layerKind: surface.coordinator.ownerIdle
        workActive: idleContent.workActive
        presentationSource: idleContent.clockPresentationItem
        sourceAvailable: idleContent.clockPresentationItem !== null
        liveX: {
            const layoutDependency = idleContent.x + idleContent.clockPresentationItem.x
                  + surface.renderedPanelWidth;
            return idleContent.clockPresentationItem.mapToItem(surfaceBackground, 0, 0).x;
        }
        liveY: {
            const layoutDependency = idleContent.y + idleContent.clockPresentationItem.y
                  + surface.renderedPanelHeight;
            return idleContent.clockPresentationItem.mapToItem(surfaceBackground, 0, 0).y;
        }
        liveWidth: idleContent.clockPresentationItem.width
        liveHeight: idleContent.clockPresentationItem.height
        matchEnabled: true
        peerLayerKind: surface.coordinator.ownerExpanded
        peerPresentation: expandedClockPresentation
        progress: surface.morphProgress
    }

    RetainedPresentation {
        id: expandedClockPresentation

        parent: surfaceBackground
        transition: contentTransition
        layerKind: surface.coordinator.ownerExpanded
        workActive: expandedContent.active
        presentationSource: expandedContent.clockPresentationItem
        sourceAvailable: expandedContent.clockPresentationItem !== null
        liveX: {
            const layoutDependency = expandedContent.x + expandedContent.viewportItem.contentX
                  + surface.renderedPanelWidth;
            return presentationSource === null ? 0 : presentationSource.mapToItem(surfaceBackground,
                                                                                  0, 0).x;
        }
        liveY: {
            const layoutDependency = expandedContent.y + expandedContent.viewportItem.contentY
                  + surface.renderedPanelHeight;
            return presentationSource === null ? 0 : presentationSource.mapToItem(surfaceBackground,
                                                                                  0, 0).y;
        }
        liveWidth: presentationSource === null ? 0 : presentationSource.width
        liveHeight: presentationSource === null ? 0 : presentationSource.height
        matchEnabled: true
        peerLayerKind: surface.coordinator.ownerIdle
        peerPresentation: idleClockPresentation
        progress: surface.morphProgress
    }

    RetainedPresentation {
        id: idleMediaPresentation
        parent: surfaceBackground
        transition: contentTransition
        layerKind: surface.coordinator.ownerIdle
        workActive: idleContent.workActive
        presentationSource: idleContent.mediaPresentationItem
        sourceAvailable: idleContent.mediaPresentationItem !== null
        liveX: {
            const layoutDependency = idleContent.x + idleContent.mediaPresentationItem.x
                  + surface.renderedPanelWidth;
            return idleContent.mediaPresentationItem.mapToItem(surfaceBackground, 0, 0).x;
        }
        liveY: {
            const layoutDependency = idleContent.y + idleContent.mediaPresentationItem.y
                  + surface.renderedPanelHeight;
            return idleContent.mediaPresentationItem.mapToItem(surfaceBackground, 0, 0).y;
        }
        liveWidth: idleContent.mediaPresentationItem.width
        liveHeight: idleContent.mediaPresentationItem.height
        matchEnabled: true
        peerLayerKind: surface.coordinator.ownerExpanded
        peerPresentation: expandedMediaPresentation
        progress: surface.morphProgress
    }

    RetainedPresentation {
        id: expandedMediaPresentation

        parent: surfaceBackground
        transition: contentTransition
        layerKind: surface.coordinator.ownerExpanded
        workActive: expandedContent.active
        presentationSource: expandedContent.mediaPresentationItem
        sourceAvailable: expandedContent.mediaPresentationItem !== null
        liveX: {
            const layoutDependency = expandedContent.x + expandedContent.viewportItem.contentX
                  + surface.renderedPanelWidth;
            return presentationSource === null ? 0 : presentationSource.mapToItem(surfaceBackground,
                                                                                  0, 0).x;
        }
        liveY: {
            const layoutDependency = expandedContent.y + expandedContent.viewportItem.contentY
                  + surface.renderedPanelHeight;
            return presentationSource === null ? 0 : presentationSource.mapToItem(surfaceBackground,
                                                                                  0, 0).y;
        }
        liveWidth: presentationSource === null ? 0 : presentationSource.width
        liveHeight: presentationSource === null ? 0 : presentationSource.height
        matchEnabled: true
        peerLayerKind: surface.coordinator.ownerIdle
        peerPresentation: idleMediaPresentation
        progress: surface.morphProgress
    }

    Loader {
        id: launcherLoader

        parent: surfaceBackground
        anchors.fill: parent
        active: (surface.launcher || contentTransition.retainsKind(
                     surface.coordinator.ownerLauncher)) && surface.applicationModel !== null
        visible: active
        enabled: surface.launcher
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
        liveWidth: surfaceBackground.width
        liveHeight: surfaceBackground.height
        progress: surface.morphProgress
    }

    Loader {
        id: historyLoader

        parent: surfaceBackground
        anchors.fill: parent
        active: (surface.history || contentTransition.retainsKind(
                     surface.coordinator.ownerHistory)) && surface.notificationService !== null
        visible: active
        enabled: surface.history
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
        liveWidth: surfaceBackground.width
        liveHeight: surfaceBackground.height
        progress: surface.morphProgress
    }

    Loader {
        id: trayLoader

        parent: surfaceBackground
        anchors.fill: parent
        active: (surface.tray || contentTransition.retainsKind(surface.coordinator.ownerTray))
                && surface.trayAdapter !== null
        visible: active
        enabled: surface.tray
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
        liveWidth: surfaceBackground.width
        liveHeight: surfaceBackground.height
        progress: surface.morphProgress
    }

    Loader {
        id: audioLoader

        parent: surfaceBackground
        anchors.fill: parent
        active: (surface.audio || contentTransition.retainsKind(surface.coordinator.ownerAudio))
                && surface.audioAdapter !== null
        visible: active
        enabled: surface.audio
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
        liveWidth: surfaceBackground.width
        liveHeight: surfaceBackground.height
        progress: surface.morphProgress
    }

    Loader {
        id: weatherLoader

        parent: surfaceBackground
        anchors.fill: parent
        active: (surface.weatherDetails || contentTransition.retainsKind(
                     surface.coordinator.ownerWeather)) && surface.weather !== null
        visible: active
        enabled: surface.weatherDetails
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
        liveWidth: surfaceBackground.width
        liveHeight: surfaceBackground.height
        progress: surface.morphProgress
    }

    Loader {
        id: polkitLoader

        parent: surfaceBackground
        anchors.fill: parent
        active: surface.polkit || (surface.polkitControllerReady && contentTransition.retainsKind(
                                       surface.coordinator.ownerPolkitModal))
        visible: active
        enabled: surface.polkit
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
        liveWidth: surfaceBackground.width
        liveHeight: surfaceBackground.height
        progress: surface.morphProgress
    }

    Loader {
        id: sessionLoader

        parent: surfaceBackground
        anchors.fill: parent
        active: (surface.session || contentTransition.retainsKind(
                     surface.coordinator.ownerSession)) && surface.sessionService !== null
        visible: active
        enabled: surface.session
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
        liveWidth: surfaceBackground.width
        liveHeight: surfaceBackground.height
        progress: surface.morphProgress
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

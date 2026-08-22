import Quickshell
import QtQuick

PanelWindow {
    id: surface

    required property var coordinator
    required property int hostSurfaceGeneration

    // Normalized idle data sources. Null keeps the matching block collapsed,
    // so harnesses can mount the surface without the full adapter set.
    property var virtualDesktops: null
    property var clock: null
    property var weather: null
    property var media: null
    property bool reducedMotion: false
    property var sessionService: null
    property var notificationService: null
    property var applicationModel: null
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

    readonly property int ownerKind: coordinator.ownerKind
    readonly property real ownerEpoch: coordinator.ownerEpoch
    readonly property real ownerRevision: coordinator.revision
    readonly property int focusTarget: coordinator.focusTarget
    readonly property real focusRequestSerial: coordinator.focusRequestSerial
    readonly property bool expanded: ownerKind === coordinator.ownerExpanded
    readonly property bool launcher: ownerKind === coordinator.ownerLauncher
    readonly property bool session: ownerKind === coordinator.ownerSession
    readonly property bool history: ownerKind === coordinator.ownerHistory
    readonly property bool transientOwner: ownerKind === coordinator.ownerWorkspace || ownerKind
                                           === coordinator.ownerBrightness || ownerKind
                                           === coordinator.ownerVolume || ownerKind
                                           === coordinator.ownerNotification
    readonly property bool notificationTransient: ownerKind === coordinator.ownerNotification
    readonly property bool largeContent: expanded || launcher || history || session
    readonly property int edgeInset: Theme.spacing.sm
    readonly property int preferredWidth: largeContent ? Theme.size.islandExpandedWidth :
                                                         transientOwner ? (notificationTransient
                                                                           ? Theme.size.islandTransientNotificationWidth :
                                                                             Theme.size.islandTransientCompactWidth) :
                                                                          Math.max(Theme.size.islandIdleWidth,
                                                                                   idleContentWidth)
    readonly property int preferredHeight: largeContent ? Theme.size.islandExpandedHeight :
                                                          transientOwner ? (notificationTransient
                                                                            ? Theme.size.islandTransientNotificationHeight :
                                                                              Theme.size.islandTransientCompactHeight) :
                                                                           Theme.size.islandIdleHeight
    readonly property int idleContentWidth: idleContent.visible ? idleContent.implicitWidth :
                                                                  Theme.size.islandIdleWidth
    readonly property bool transientCommitted: transientLoader.item !== null
                                               && transientLoader.item.committed
    readonly property bool transientEntryAnimationRunning: transientLoader.item !== null
                                                           && transientLoader.item.entryAnimationRunning
    readonly property string transientPrimaryText: transientLoader.item === null ? "" :
                                                                                   transientLoader.item.primaryText
    readonly property string transientDetailText: transientLoader.item === null ? "" :
                                                                                  transientLoader.item.detailText
    readonly property int geometryAnimationDuration: reducedMotion ? 0 : Theme.motion.durationSlow
    readonly property bool dashboardFocused: expandedContent.activeFocus
    readonly property int loadedDashboardRegionCount: expandedContent.loadedRegionCount
    readonly property bool launcherFocused: launcherLoader.item !== null
                                            && launcherLoader.item.searchFocused
    readonly property int launcherResultCount: launcherLoader.item === null ? 0 :
                                                                              launcherLoader.item.resultCount
    readonly property string launcherSelectedId: launcherLoader.item === null ? "" :
                                                                                launcherLoader.item.selectedId
    readonly property bool sessionFocused: sessionLoader.item !== null
                                           && sessionLoader.item.activeFocus
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
        const resolved = source.resolveTransient(coordinator.ownerSourceToken,
                                                 coordinator.ownerSourceGeneration,
                                                 coordinator.ownerSourceRevision);
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
        const transientVisible = transientOwner && transientLoader.item !== null
              && transientLoader.item.visible && transientLoader.item.committed;
        if (!idleVisible && !dashboardVisible && !launcherVisible && !historyVisible &&
                !sessionVisible && !transientVisible) {
            return;
        }

        coordinator.acknowledgeVisible(generation, epoch, contentRevision);
    }

    function cancelDashboard() {
        if (hostSurfaceGeneration <= 0) {
            return false;
        }

        // Explicit close/cancel also suppresses the current hover sample. The
        // HoverHandler will report true again only after a real pointer exit
        // and re-entry, so Close is never an inert control.
        const explicitAccepted = coordinator.setExplicitExpanded(hostSurfaceGeneration, false);
        const hoverAccepted = coordinator.setHover(hostSurfaceGeneration, false);
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
            surface.acknowledgePresentation(generation, epoch, contentRevision);
        });
    }

    function reportHover(hovered) {
        return coordinator.setHover(hostSurfaceGeneration, hovered);
    }

    function requestDeliberateExpansion() {
        return coordinator.setExplicitExpanded(hostSurfaceGeneration, true);
    }

    function safeLogicalSize(preferredSize, screenSize) {
        if (screenSize <= 0) {
            return preferredSize;
        }

        return Math.min(preferredSize, Math.max(1, screenSize - edgeInset * 2));
    }

    Component.onCompleted: queuePresentationAcknowledgement()
    onHostSurfaceGenerationChanged: {
        queuePresentationAcknowledgement();
        if (hostSurfaceGeneration > 0 && hoverHandler.hovered) {
            reportHover(true);
        }
    }

    Connections {
        target: surface.coordinator

        function onFocusRequestSerialChanged() {
            surface.queueOwnerFocus();
        }

        function onPresentationVisibleChanged() {
            if (surface.coordinator.presentationVisible) {
                Qt.callLater(surface.queueOwnerFocus);
            }
        }

        function onOwnerEpochChanged() {
            surface.focusedOwnerEpoch = 0;
            surface.queuePresentationAcknowledgement();
        }

        function onRevisionChanged() {
            surface.queuePresentationAcknowledgement();
        }
    }

    Connections {
        target: surface.applicationModel
        ignoreUnknownSignals: true

        function onLaunchAccepted(requestId, desktopFileId) {
            if (requestId !== surface.launcherRequestId) {
                return;
            }
            const epoch = surface.launcherRequestOwnerEpoch;
            surface.launcherRequestId = 0;
            surface.launcherRequestOwnerEpoch = 0;
            surface.coordinator.completeInteractive(epoch);
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
    anchors.top: true
    color: "transparent"
    exclusiveZone: 0
    focusable: focusedOwnerEpoch === ownerEpoch && appliedFocusRequestSerial === focusRequestSerial
               && ((expanded && focusTarget === coordinator.focusExpandedDashboard) || (launcher
                                                                                        && focusTarget
                                                                                        === coordinator.focusLauncherSearch)
                   || (history && focusTarget === coordinator.focusNotificationHistory) || (session
                                                                                            && focusTarget
                                                                                            === coordinator.focusSessionActions))
    implicitHeight: safeLogicalSize(preferredHeight, screen === null ? 0 : screen.height)
    implicitWidth: safeLogicalSize(preferredWidth, screen === null ? 0 : screen.width)

    Behavior on implicitHeight {
        NumberAnimation {
            duration: surface.geometryAnimationDuration
            easing.type: Theme.motion.easingEmphasized
        }
    }

    Behavior on implicitWidth {
        NumberAnimation {
            duration: surface.geometryAnimationDuration
            easing.type: Theme.motion.easingEmphasized
        }
    }

    margins.top: edgeInset

    IslandPanel {
        id: islandPanel

        anchors.fill: parent
        radius: surface.notificationTransient ? Theme.radius.lg : surface.largeContent
                                                ? Theme.radius.xl : Theme.radius.pill

        Behavior on radius {
            NumberAnimation {
                duration: surface.geometryAnimationDuration
                easing.type: Theme.motion.easingEmphasized
            }
        }
    }

    Loader {
        id: transientLoader

        anchors.fill: parent
        active: surface.transientOwner && surface.transientPresentation !== null
        visible: active

        sourceComponent: Component {
            TransientView {
                active: transientLoader.visible
                kind: surface.coordinator.ownerName
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
        weather: surface.weather
        media: surface.media
        reducedMotion: surface.reducedMotion
    }

    ExpandedDashboard {
        id: expandedContent

        anchors.fill: parent
        visible: surface.expanded
        mediaContent: surface.dashboardMediaContent
        clockContent: surface.dashboardClockContent
        quickControlsContent: surface.dashboardQuickControlsContent
        audioContent: surface.dashboardAudioContent
        notificationsContent: surface.dashboardNotificationsContent
        navigationContent: surface.dashboardNavigationContent
        onCloseRequested: surface.cancelDashboard()
    }

    Loader {
        id: launcherLoader

        anchors.fill: parent
        active: surface.launcher && surface.applicationModel !== null
        visible: active

        sourceComponent: Component {
            LauncherView {
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
        active: surface.history && surface.notificationService !== null
        visible: active

        sourceComponent: Component {
            NotificationHistoryView {
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
        id: sessionLoader

        anchors.fill: parent
        active: surface.session && surface.sessionService !== null
        visible: active

        sourceComponent: Component {
            SessionView {
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

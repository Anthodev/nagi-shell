pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

Scope {
    id: host

    required property var coordinator

    // Normalized idle data sources relayed to the island surface.
    property var virtualDesktops: null
    property var clock: null
    property var weather: null
    property var media: null
    property var sessionService: null
    property var polkitController: null
    property var notificationService: null
    property var applicationModel: null
    property var trayAdapter: null
    property var audioAdapter: null
    property var workspaceTransientSource: null
    property var brightnessTransientSource: null
    property var volumeTransientSource: null
    property var notificationTransientSource: null
    property bool reducedMotion: false
    property Component dashboardMediaContent: null
    property Component dashboardClockContent: null
    property Component dashboardQuickControlsContent: null
    property Component dashboardAudioContent: null
    property Component dashboardNotificationsContent: null
    property Component dashboardNavigationContent: null

    readonly property int surfaceGeneration: ownership.surfaceGeneration
    readonly property var surfaceToken: ownership.surfaceToken
    readonly property int surfaceWidth: ownership.liveSurface === null ? 0 :
                                                                         ownership.liveSurface.width

    readonly property int surfaceHeight: ownership.liveSurface === null ? 0 :
                                                                          ownership.liveSurface.height

    // Requested layer-shell geometry is observable on Wayland even though the
    // compositor does not publish a trustworthy global QWindow position.
    readonly property int surfaceScreenWidth: ownership.liveSurface === null
                                              || ownership.liveSurface.screen === null ? 0 :
                                                                                         ownership.liveSurface.screen.width
    readonly property int surfaceLeftMargin: ownership.liveSurface === null ? 0 :
                                                                              ownership.liveSurface.margins.left
    readonly property int surfaceTopMargin: ownership.liveSurface === null ? 0 :
                                                                             ownership.liveSurface.margins.top

    readonly property int surfacePreferredWidth: ownership.liveSurface === null ? 0 :
                                                                                  ownership.liveSurface.preferredWidth
    readonly property int surfacePreferredHeight: ownership.liveSurface === null ? 0 :
                                                                                   ownership.liveSurface.preferredHeight
    readonly property bool backgroundCoversSurface: ownership.liveSurface !== null
                                                    && ownership.liveSurface.backgroundCoversSurface
    readonly property real backgroundRadius: ownership.liveSurface === null ? 0 :
                                                                              ownership.liveSurface.backgroundRadius

    readonly property bool surfaceFocusable: ownership.liveSurface !== null
                                             && ownership.liveSurface.focusable
    readonly property bool dashboardFocused: ownership.liveSurface !== null
                                             && ownership.liveSurface.dashboardFocused
    readonly property int loadedDashboardRegionCount: ownership.liveSurface === null ? 0 :
                                                                                       ownership.liveSurface.loadedDashboardRegionCount
    readonly property bool interactiveExitRunning: ownership.liveSurface !== null
                                                   && ownership.liveSurface.interactiveExitRunning
    readonly property int interactiveExitDuration: ownership.liveSurface === null ? 0 :
                                                                                    ownership.liveSurface.interactiveExitDuration
    readonly property real interactiveExitOffset: ownership.liveSurface === null ? 0 :
                                                                                   ownership.liveSurface.interactiveExitOffset
    readonly property real interactiveExitLoaderX: ownership.liveSurface === null ? 0 :
                                                                                    ownership.liveSurface.interactiveExitLoaderX
    readonly property real interactiveExitMappedX: ownership.liveSurface === null ? 0 :
                                                                                    ownership.liveSurface.interactiveExitMappedX
    readonly property bool interactiveExitLoaderEnabled: ownership.liveSurface !== null
                                                         && ownership.liveSurface.interactiveExitLoaderEnabled
    readonly property var interactiveExitItem: ownership.liveSurface === null ? null :
                                                                                ownership.liveSurface.interactiveExitItem
    readonly property bool launcherLoaded: ownership.liveSurface !== null
                                           && ownership.liveSurface.launcherLoaded
    readonly property bool launcherFocused: ownership.liveSurface !== null
                                            && ownership.liveSurface.launcherFocused
    readonly property int launcherResultCount: ownership.liveSurface === null ? 0 :
                                                                                ownership.liveSurface.launcherResultCount
    readonly property bool launcherResultScrollVisible: ownership.liveSurface !== null
                                                        && ownership.liveSurface.launcherResultScrollVisible
    readonly property string launcherSelectedId: ownership.liveSurface === null ? "" :
                                                                                  ownership.liveSurface.launcherSelectedId
    readonly property bool sessionLoaded: ownership.liveSurface !== null
                                          && ownership.liveSurface.sessionLoaded
    readonly property bool sessionFocused: ownership.liveSurface !== null
                                           && ownership.liveSurface.sessionFocused
    readonly property bool trayLoaded: ownership.liveSurface !== null
                                       && ownership.liveSurface.trayLoaded
    readonly property bool trayFocused: ownership.liveSurface !== null
                                        && ownership.liveSurface.trayFocused
    readonly property bool audioLoaded: ownership.liveSurface !== null
                                        && ownership.liveSurface.audioLoaded
    readonly property bool audioFocused: ownership.liveSurface !== null
                                         && ownership.liveSurface.audioFocused
    readonly property bool polkitLoaded: ownership.liveSurface !== null
                                         && ownership.liveSurface.polkitLoaded
    readonly property bool polkitFocused: ownership.liveSurface !== null
                                          && ownership.liveSurface.polkitFocused
    readonly property bool polkitResponseFocused: ownership.liveSurface !== null
                                                  && ownership.liveSurface.polkitResponseFocused
    readonly property int polkitIdentityCount: ownership.liveSurface === null ? 0 :
                                                                                ownership.liveSurface.polkitIdentityCount
    readonly property bool polkitResponseFieldVisible: ownership.liveSurface !== null
                                                       && ownership.liveSurface.polkitResponseFieldVisible
    readonly property bool historyLoaded: ownership.liveSurface !== null
                                          && ownership.liveSurface.historyLoaded
    readonly property bool historyFocused: ownership.liveSurface !== null
                                           && ownership.liveSurface.historyFocused
    readonly property int historyRowCount: ownership.liveSurface === null ? 0 :
                                                                            ownership.liveSurface.historyRowCount
    readonly property bool historyEmptyStateVisible: ownership.liveSurface !== null
                                                     && ownership.liveSurface.historyEmptyStateVisible
    readonly property int geometryAnimationDuration: ownership.liveSurface === null ? 0 :
                                                                                      ownership.liveSurface.geometryAnimationDuration
    readonly property bool geometryAnimationRunning: ownership.liveSurface !== null
                                                     && ownership.liveSurface.geometryAnimationRunning
    readonly property bool transientCommitted: ownership.liveSurface !== null
                                               && ownership.liveSurface.transientCommitted
    readonly property bool transientEntryAnimationRunning: ownership.liveSurface !== null
                                                           && ownership.liveSurface.transientEntryAnimationRunning
    readonly property string transientPrimaryText: ownership.liveSurface === null ? "" :
                                                                                    ownership.liveSurface.transientPrimaryText
    readonly property string transientDetailText: ownership.liveSurface === null ? "" :
                                                                                   ownership.liveSurface.transientDetailText

    function cancelDashboard() {
        return ownership.liveSurface !== null && ownership.liveSurface.cancelDashboard();
    }

    function requestDeliberateExpansion() {
        return ownership.liveSurface !== null && ownership.liveSurface.requestDeliberateExpansion();
    }

    QtObject {
        id: ownership

        // QsWindow can report provisional screens while the layer-shell surface settles.
        readonly property int surfaceSettleDelay: 50
        property var liveSurface: null
        property var ownerScreen: null
        property var pendingSurface: null
        property bool replacementPending: false
        property var replacementScreen: null
        property int surfaceGeneration: 0
        property var surfaceToken: null

        function completeSurfaceReplacement() {
            surfaceLoader.active = true;
        }

        function isConnected(screen) {
            for (let index = 0; index < Quickshell.screens.length; index += 1) {
                if (Quickshell.screens[index] === screen) {
                    return true;
                }
            }

            return false;
        }

        function queueSurfaceRegistration(surface) {
            const targetScreen = replacementScreen;
            replacementScreen = null;

            if (targetScreen !== null && isConnected(targetScreen)) {
                surface.screen = targetScreen;
            }

            liveSurface = surface;
            pendingSurface = surface;
            surfaceSettleTimer.restart();
        }

        function reconcileOwner() {
            if (ownerScreen === null || isConnected(ownerScreen)) {
                return;
            }

            const rehomedScreen = liveSurface === null ? null : liveSurface.screen;
            if (rehomedScreen !== null && isConnected(rehomedScreen)) {
                replacementScreen = rehomedScreen;
                replaceSurface();
            }
        }

        function replaceSurface() {
            if (replacementPending) {
                return;
            }

            replacementPending = true;
            if (surfaceToken !== null) {
                host.coordinator.detachSurface(surfaceToken, surfaceGeneration);
            }
            surfaceToken = null;
            surfaceLoader.active = false;
            Qt.callLater(completeSurfaceReplacement);
        }

        function settleSurfaceRegistration() {
            if (pendingSurface === null) {
                return;
            }

            ownerScreen = pendingSurface.screen;
            pendingSurface = null;
            surfaceGeneration += 1;
            surfaceToken = {};
            replacementPending = false;
            host.coordinator.attachSurface(surfaceToken, surfaceGeneration);
        }

        function unregisterSurface(surface) {
            if (liveSurface !== surface) {
                return;
            }

            if (pendingSurface === surface) {
                pendingSurface = null;
                surfaceSettleTimer.stop();
            }

            liveSurface = null;
            if (surfaceToken !== null) {
                host.coordinator.detachSurface(surfaceToken, surfaceGeneration);
            }
            surfaceToken = null;
            ownerScreen = null;
        }
    }

    Timer {
        id: surfaceSettleTimer

        interval: ownership.surfaceSettleDelay
        onTriggered: ownership.settleSurfaceRegistration()
    }

    Connections {
        target: Quickshell

        function onScreensChanged() {
            ownership.reconcileOwner();
        }
    }

    LazyLoader {
        id: surfaceLoader

        active: true

        IslandSurface {
            id: island

            coordinator: host.coordinator
            hostSurfaceGeneration: host.surfaceGeneration
            virtualDesktops: host.virtualDesktops
            clock: host.clock
            weather: host.weather
            media: host.media
            sessionService: host.sessionService
            polkitController: host.polkitController
            notificationService: host.notificationService
            applicationModel: host.applicationModel
            trayAdapter: host.trayAdapter
            audioAdapter: host.audioAdapter
            workspaceTransientSource: host.workspaceTransientSource
            brightnessTransientSource: host.brightnessTransientSource
            volumeTransientSource: host.volumeTransientSource
            notificationTransientSource: host.notificationTransientSource
            reducedMotion: host.reducedMotion
            dashboardMediaContent: host.dashboardMediaContent
            dashboardClockContent: host.dashboardClockContent
            dashboardQuickControlsContent: host.dashboardQuickControlsContent
            dashboardAudioContent: host.dashboardAudioContent
            dashboardNotificationsContent: host.dashboardNotificationsContent
            dashboardNavigationContent: host.dashboardNavigationContent

            Component.onCompleted: ownership.queueSurfaceRegistration(island)
            Component.onDestruction: ownership.unregisterSurface(island)
            onScreenChanged: {
                if (ownership.pendingSurface === island) {
                    surfaceSettleTimer.restart();
                } else {
                    ownership.reconcileOwner();
                }
            }
        }
    }
}

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

    readonly property int surfacePreferredWidth: ownership.liveSurface === null ? 0 :
                                                                                  ownership.liveSurface.preferredWidth
    readonly property int surfacePreferredHeight: ownership.liveSurface === null ? 0 :
                                                                                   ownership.liveSurface.preferredHeight

    readonly property bool surfaceFocusable: ownership.liveSurface !== null
                                             && ownership.liveSurface.focusable
    readonly property bool dashboardFocused: ownership.liveSurface !== null
                                             && ownership.liveSurface.dashboardFocused
    readonly property int loadedDashboardRegionCount: ownership.liveSurface === null ? 0 :
                                                                                       ownership.liveSurface.loadedDashboardRegionCount
    readonly property int geometryAnimationDuration: ownership.liveSurface === null ? 0 :
                                                                                      ownership.liveSurface.geometryAnimationDuration

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

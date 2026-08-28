pragma ComponentBehavior: Bound

import Nagi.Platform 1.0
import Quickshell
import QtQuick

Scope {
    id: host

    required property var coordinator

    property var virtualDesktops: null
    property var clock: null
    property var weather: null
    property var media: null
    property var gamingPerformance: null
    property var sessionService: null
    property var polkitController: null
    property var notificationService: null
    property var connectivityAdapter: null
    property var applicationModel: null
    property var trayAdapter: null
    property var audioAdapter: null
    property var easyEffectsStatusService: null
    property var workspaceTransientSource: null
    property var brightnessTransientSource: null
    property var volumeTransientSource: null
    property var notificationTransientSource: null
    property Component dashboardMediaContent: null
    property Component dashboardClockContent: null
    property Component dashboardQuickControlsContent: null
    property Component dashboardAudioContent: null
    property Component dashboardNotificationsContent: null
    property Component dashboardNavigationContent: null

    signal controlCenterRequested(var initiatingSurfaceToken)
    signal controlCenterRouteRequested(string routeId, var initiatingSurfaceToken)
    property bool reducedMotion: false

    readonly property int revision: displays.revision + registryRevision
    readonly property int liveSurfaceCount: registry.length
    readonly property int enabledDisplayCount: displays.enabledDisplayCount
    readonly property var rememberedDisplays: displays.rememberedDisplays
    readonly property var surfaceToken: routeFallbackToken(null)
    readonly property int surfaceGeneration: generationForToken(surfaceToken)
    readonly property var menuParentWindow: fallbackSurface
    readonly property var fallbackSurface: surfaceForToken(surfaceToken)
    readonly property int surfaceWidth: fallbackSurface === null ? 0 : fallbackSurface.width
    readonly property int surfaceHeight: fallbackSurface === null ? 0 : fallbackSurface.height
    readonly property int surfaceScreenWidth: fallbackSurface === null || fallbackSurface.screen
                                              === null ? 0 : fallbackSurface.screen.width
    readonly property int surfaceScreenHeight: fallbackSurface === null || fallbackSurface.screen
                                               === null ? 0 : fallbackSurface.screen.height
    readonly property int surfaceLeftMargin: fallbackSurface === null ? 0 :
                                                                        fallbackSurface.margins.left
    readonly property int surfaceTopMargin: fallbackSurface === null ? 0 :
                                                                       fallbackSurface.margins.top
    readonly property int surfacePreferredWidth: fallbackSurface === null ? 0 :
                                                                            fallbackSurface.preferredWidth
    readonly property int surfacePreferredHeight: fallbackSurface === null ? 0 :
                                                                             fallbackSurface.preferredHeight
    readonly property bool backgroundCoversSurface: fallbackSurface !== null
                                                    && fallbackSurface.backgroundCoversSurface
    readonly property real backgroundRadius: fallbackSurface === null ? 0 :
                                                                        fallbackSurface.backgroundRadius
    readonly property bool blurRequested: fallbackSurface !== null && fallbackSurface.blurRequested
    readonly property bool surfaceFocusable: fallbackSurface !== null && fallbackSurface.focusable
    readonly property bool gamingPerformanceBadgeVisible: fallbackSurface !== null
                                                          && fallbackSurface.gamingPerformanceBadgeVisible
    readonly property bool dashboardFocused: fallbackSurface !== null
                                             && fallbackSurface.dashboardFocused
    readonly property int loadedDashboardRegionCount: fallbackSurface === null ? 0 :
                                                                                 fallbackSurface.loadedDashboardRegionCount
    readonly property bool interactiveExitRunning: fallbackSurface !== null
                                                   && fallbackSurface.interactiveExitRunning
    readonly property int interactiveExitDuration: fallbackSurface === null ? 0 :
                                                                              fallbackSurface.interactiveExitDuration
    readonly property real interactiveExitOffset: fallbackSurface === null ? 0 :
                                                                             fallbackSurface.interactiveExitOffset
    readonly property real interactiveExitLoaderX: fallbackSurface === null ? 0 :
                                                                              fallbackSurface.interactiveExitLoaderX
    readonly property real interactiveExitMappedX: fallbackSurface === null ? 0 :
                                                                              fallbackSurface.interactiveExitMappedX
    readonly property real interactiveExitLoaderZ: fallbackSurface === null ? 0 :
                                                                              fallbackSurface.interactiveExitLoaderZ
    readonly property bool interactiveExitLoaderEnabled: fallbackSurface !== null
                                                         && fallbackSurface.interactiveExitLoaderEnabled
    readonly property var interactiveExitItem: fallbackSurface === null ? null :
                                                                          fallbackSurface.interactiveExitItem
    readonly property var interactiveContent: fallbackSurface === null ? null :
                                                                         fallbackSurface.interactiveContent
    readonly property bool launcherLoaded: fallbackSurface !== null
                                           && fallbackSurface.launcherLoaded
    readonly property bool launcherFocused: fallbackSurface !== null
                                            && fallbackSurface.launcherFocused
    readonly property int launcherResultCount: fallbackSurface === null ? 0 :
                                                                          fallbackSurface.launcherResultCount
    readonly property bool launcherResultScrollVisible: fallbackSurface !== null
                                                        && fallbackSurface.launcherResultScrollVisible
    readonly property string launcherSelectedId: fallbackSurface === null ? "" :
                                                                            fallbackSurface.launcherSelectedId
    readonly property bool sessionLoaded: fallbackSurface !== null && fallbackSurface.sessionLoaded
    readonly property bool sessionFocused: fallbackSurface !== null
                                           && fallbackSurface.sessionFocused
    readonly property bool trayLoaded: fallbackSurface !== null && fallbackSurface.trayLoaded
    readonly property bool trayFocused: fallbackSurface !== null && fallbackSurface.trayFocused
    readonly property bool audioLoaded: fallbackSurface !== null && fallbackSurface.audioLoaded
    readonly property bool audioFocused: fallbackSurface !== null && fallbackSurface.audioFocused
    readonly property bool weatherLoaded: fallbackSurface !== null && fallbackSurface.weatherLoaded
    readonly property bool weatherFocused: fallbackSurface !== null
                                           && fallbackSurface.weatherFocused
    readonly property bool polkitLoaded: fallbackSurface !== null && fallbackSurface.polkitLoaded
    readonly property bool polkitFocused: fallbackSurface !== null && fallbackSurface.polkitFocused
    readonly property bool polkitResponseFocused: fallbackSurface !== null
                                                  && fallbackSurface.polkitResponseFocused
    readonly property int polkitIdentityCount: fallbackSurface === null ? 0 :
                                                                          fallbackSurface.polkitIdentityCount
    readonly property bool polkitResponseFieldVisible: fallbackSurface !== null
                                                       && fallbackSurface.polkitResponseFieldVisible
    readonly property bool historyLoaded: fallbackSurface !== null && fallbackSurface.historyLoaded
    readonly property bool historyFocused: fallbackSurface !== null
                                           && fallbackSurface.historyFocused
    readonly property int historyRowCount: fallbackSurface === null ? 0 :
                                                                      fallbackSurface.historyRowCount
    readonly property bool historyEmptyStateVisible: fallbackSurface !== null
                                                     && fallbackSurface.historyEmptyStateVisible
    readonly property int geometryAnimationDuration: fallbackSurface === null ? 0 :
                                                                                fallbackSurface.geometryAnimationDuration
    readonly property bool geometryAnimationRunning: fallbackSurface !== null
                                                     && fallbackSurface.geometryAnimationRunning
    readonly property bool transientCommitted: fallbackSurface !== null
                                               && fallbackSurface.transientCommitted
    readonly property bool transientEntryAnimationRunning: fallbackSurface !== null
                                                           && fallbackSurface.transientEntryAnimationRunning
    readonly property string transientPrimaryText: fallbackSurface === null ? "" :
                                                                              fallbackSurface.transientPrimaryText
    readonly property string transientDetailText: fallbackSurface === null ? "" :
                                                                             fallbackSurface.transientDetailText
    readonly property string lastFailure: failureText

    property var registry: []
    property var entries: []
    property int registryRevision: 0
    property int nextSurfaceGeneration: 0
    property string failureText: ""

    function activeDisplays() {
        const ignored = revision;
        return displays.activeDisplays();
    }

    function beginShellMenu(token) {
        const surface = surfaceForToken(token);
        return surface !== null && surface.beginShellMenu();
    }

    function cancelDashboard() {
        return fallbackSurface !== null && fallbackSurface.cancelDashboard();
    }

    function requestDeliberateExpansion() {
        return fallbackSurface !== null && fallbackSurface.requestDeliberateExpansion();
    }
    function completeShellMenuAction(token) {
        const surface = surfaceForToken(token);
        return surface !== null && surface.completeShellMenuAction();
    }

    function confirmForget(identity) {
        failureText
                = "Disconnected displays cannot be remembered without a stable platform identity.";
        return false;
    }

    function entryForScreen(screen) {
        for (let index = 0; index < entries.length; index += 1) {
            if (entries[index].targetScreen === screen) {
                return entries[index];
            }
        }
        return null;
    }

    function finishShellMenuOpen(token, result) {
        const surface = surfaceForToken(token);
        return surface !== null && surface.finishShellMenuOpen(result);
    }

    function generationForToken(token) {
        const record = registryRecordForToken(token);
        return record === null ? 0 : record.generation;
    }

    function isConnected(screen) {
        for (let index = 0; index < Quickshell.screens.length; index += 1) {
            if (Quickshell.screens[index] === screen) {
                return true;
            }
        }
        return false;
    }

    function reconcileScreens() {
        displays.syncScreens();
        const kept = [];
        for (let index = 0; index < entries.length; index += 1) {
            const entry = entries[index];
            if (isConnected(entry.targetScreen)) {
                kept.push(entry);
            } else {
                entry.destroy();
            }
        }
        entries = kept;

        for (let index = 0; index < Quickshell.screens.length; index += 1) {
            const screen = Quickshell.screens[index];
            if (entryForScreen(screen) === null) {
                const entry = surfaceEntryComponent.createObject(host, {
                                                                     "targetScreen": screen
                                                                 });
                if (entry !== null) {
                    const next = entries.slice();
                    next.push(entry);
                    entries = next;
                }
            }
        }
        registryRevision += 1;
    }

    function registerSurface(entry, surface) {
        nextSurfaceGeneration += 1;
        entry.surfaceGeneration = nextSurfaceGeneration;
        entry.surfaceToken = {};
        entry.liveSurface = surface;
        const next = registry.slice();
        next.push({
                      "entry": entry,
                      "generation": entry.surfaceGeneration,
                      "screen": entry.targetScreen,
                      "surface": surface,
                      "token": entry.surfaceToken
                  });
        registry = next;
        registryRevision += 1;
        coordinator.attachSurface(entry.surfaceToken, entry.surfaceGeneration);
    }

    function registryRecordForToken(token) {
        if (token === null || token === undefined) {
            return null;
        }
        for (let index = 0; index < registry.length; index += 1) {
            if (registry[index].token === token) {
                return registry[index];
            }
        }
        return null;
    }

    function routeFallbackToken(excludedToken) {
        const fallback = displays.fallbackScreen;
        for (let index = 0; index < registry.length; index += 1) {
            if (registry[index].token !== excludedToken && registry[index].screen === fallback) {
                return registry[index].token;
            }
        }
        for (let index = 0; index < registry.length; index += 1) {
            if (registry[index].token !== excludedToken) {
                return registry[index].token;
            }
        }
        return null;
    }

    function routeSurfaceToken(excludedToken) {
        for (let index = 0; index < registry.length; index += 1) {
            const record = registry[index];
            if (record.token !== excludedToken && PointerRouter.isPointerOnWindowScreen(
                        record.surface.backingWindow)) {
                return record.token;
            }
        }
        return routeFallbackToken(excludedToken);
    }

    function setEnabled(screen, enabled) {
        failureText = "";
        const entry = entryForScreen(screen);
        if (entry === null) {
            failureText = "The display is no longer connected.";
            return false;
        }
        if (!enabled && entry.surfaceToken !== null && !coordinator.prepareSurfaceDisable(
                    entry.surfaceToken)) {
            failureText = coordinator.modalHostToken === entry.surfaceToken
                    ? "Authentication must finish before this island can be disabled." :
                      "The active task could not be transferred safely.";
            return false;
        }
        if (!displays.requestEnabled(screen, enabled)) {
            failureText = "At least one island must remain enabled.";
            return false;
        }
        registryRevision += 1;
        return true;
    }

    function setFallback(screen) {
        failureText = "";
        if (!displays.requestFallback(screen)) {
            failureText = "The fallback must be an active enabled display.";
            return false;
        }
        registryRevision += 1;
        return true;
    }

    function surfaceForToken(token) {
        const record = registryRecordForToken(token);
        return record === null ? null : record.surface;
    }
    function screenForToken(token) {
        const record = registryRecordForToken(token);
        return record === null ? null : record.screen;
    }

    function unregisterSurface(entry, surface) {
        const next = [];
        let removed = null;
        for (let index = 0; index < registry.length; index += 1) {
            if (registry[index].entry === entry && registry[index].surface === surface) {
                removed = registry[index];
            } else {
                next.push(registry[index]);
            }
        }
        registry = next;
        registryRevision += 1;
        if (removed !== null) {
            coordinator.detachSurface(removed.token, removed.generation);
        }
        if (entry.liveSurface === surface) {
            entry.liveSurface = null;
            entry.surfaceToken = null;
            entry.surfaceGeneration = 0;
        }
    }

    function windowForToken(token) {
        const record = registryRecordForToken(token);
        return record === null || record.surface === null ? null : record.surface.backingWindow;
    }

    DisplayManager {
        id: displays

        onChangeRejected: reason => host.failureText = reason
    }

    Component {
        id: surfaceEntryComponent

        Scope {
            id: entry

            required property var targetScreen
            property var liveSurface: null
            property var surfaceToken: null
            property int surfaceGeneration: 0
            readonly property bool enabled: displays.isEnabled(targetScreen)

            Component {
                id: dashboardMedia

                DashboardMedia {
                    media: host.media
                }
            }

            Component {
                id: dashboardClock

                DashboardClock {
                    clock: host.clock
                }
            }

            Component {
                id: dashboardQuickControls

                DashboardQuickControls {
                    centerStatusInMainLane: host.media === null || !host.media.available ||
                                            !UserConfig.snapshot.media.dashboardVisible
                    applicationModel: host.applicationModel
                    tray: host.trayAdapter
                    menuParentWindow: entry.liveSurface
                    connectivity: host.connectivityAdapter
                    onExternalActionDispatched: host.completeShellMenuAction(entry.surfaceToken)
                    onShellMenuOpening: host.beginShellMenu(entry.surfaceToken)
                    onShellMenuOpenResult: result => host.finishShellMenuOpen(entry.surfaceToken,
                                                                              result)
                    onWifiManagerRequested: host.controlCenterRouteRequested("wifi",
                                                                             entry.surfaceToken)
                    onBluetoothManagerRequested: host.controlCenterRouteRequested("bluetooth",
                                                                                  entry.surfaceToken)
                }
            }

            Component {
                id: dashboardAudio

                DashboardAudio {
                    audio: host.audioAdapter
                    onDeviceSelectionRequested: host.coordinator.openAudio(entry.surfaceToken)
                }
            }

            Component {
                id: dashboardNotifications

                DashboardNotifications {
                    service: host.notificationService
                }
            }

            Component {
                id: dashboardNavigation

                DashboardNavigation {
                    coordinator: host.coordinator
                    surfaceToken: entry.surfaceToken
                    applicationModel: host.applicationModel
                    showHistory: host.notificationService === null
                                 || host.notificationService.historyVisible !== false
                    onControlCenterRequested: host.controlCenterRequested(entry.surfaceToken)
                    onSystemSettingsOpened: host.coordinator.resetToIdle(entry.surfaceToken)
                }
            }

            LazyLoader {
                id: surfaceLoader

                active: entry.enabled

                IslandSurface {
                    id: island

                    screen: entry.targetScreen
                    coordinator: host.coordinator
                    hostSurfaceToken: entry.surfaceToken
                    hostSurfaceGeneration: entry.surfaceGeneration
                    surfaceHost: host
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
                    easyEffectsStatusService: host.easyEffectsStatusService
                    gamingPerformance: host.gamingPerformance
                    workspaceTransientSource: host.workspaceTransientSource
                    brightnessTransientSource: host.brightnessTransientSource
                    volumeTransientSource: host.volumeTransientSource
                    notificationTransientSource: host.notificationTransientSource
                    reducedMotion: host.reducedMotion
                    dashboardMediaContent: host.dashboardMediaContent !== null
                                           ? host.dashboardMediaContent : host.media !== null
                                             && host.media.available
                                             && UserConfig.snapshot.media.dashboardVisible
                                             ? dashboardMedia : null
                    dashboardClockContent: host.dashboardClockContent !== null
                                           ? host.dashboardClockContent : dashboardClock
                    dashboardQuickControlsContent: host.dashboardQuickControlsContent !== null
                                                   ? host.dashboardQuickControlsContent :
                                                     dashboardQuickControls
                    dashboardAudioContent: host.dashboardAudioContent !== null
                                           ? host.dashboardAudioContent : dashboardAudio
                    dashboardNotificationsContent: host.dashboardNotificationsContent !== null
                                                   ? host.dashboardNotificationsContent :
                                                     host.notificationService === null
                                                     || host.notificationService.dashboardVisible
                                                     !== false ? dashboardNotifications : null
                    dashboardNavigationContent: host.dashboardNavigationContent !== null
                                                ? host.dashboardNavigationContent :
                                                  dashboardNavigation

                    Component.onCompleted: host.registerSurface(entry, island)
                    Component.onDestruction: host.unregisterSurface(entry, island)
                    onScreenChanged: {
                        if (screen !== entry.targetScreen && !host.isConnected(
                                entry.targetScreen)) {
                            surfaceLoader.active = false;
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: Quickshell

        function onScreensChanged() {
            host.reconcileScreens();
        }
    }

    Component.onCompleted: {
        coordinator.surfaceRouter = host;
        reconcileScreens();
    }
    Component.onDestruction: {
        if (coordinator.surfaceRouter === host) {
            coordinator.surfaceRouter = null;
        }
        const doomed = entries.slice();
        entries = [];
        for (let index = 0; index < doomed.length; index += 1) {
            doomed[index].destroy();
        }
    }
}

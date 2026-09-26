//@ pragma UseQApplication
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import Nagi.Platform 1.0
import "qml"

ShellRoot {
    property bool stabilityReadyLogged: false
    readonly property var controlCenter: controlCenterLoader.item
    property bool stabilityControlCenterCompact: false
    property var stabilityObjectTokens: new Map()
    property int stabilityNextObjectToken: 0

    function reportStabilityReady() {
        if (!stabilityReadyLogged && Quickshell.env("NAGI_STABILITY_PROBE") === "1"
                && UserConfig.status === "ready") {
            stabilityReadyLogged = true;
            console.log("Configuration Loaded");
        }
    }

    Component.onCompleted: reportStabilityReady()

    Connections {
        target: UserConfig

        function onStatusChanged() {
            reportStabilityReady();
        }
    }

    function stabilityArrayCount(value) {
        if (value === null || value === undefined) {
            return 0;
        }
        return Number.isInteger(value.length) && value.length >= 0 ? value.length : -1;
    }

    function stabilityObjectCount(value) {
        return value !== null && typeof value === "object" ? Object.keys(value).length : -1;
    }

    function stabilitySurfaceMetric(propertyName) {
        let total = 0;
        for (let index = 0; index < islandHost.registry.length; index += 1) {
            const surface = islandHost.registry[index].surface;
            const value = surface === null ? -1 : surface[propertyName];
            if (!Number.isInteger(value) || value < 0) {
                return -1;
            }
            total += value;
        }
        return total;
    }

    function stabilityVisibleSurfaceCount() {
        let total = 0;
        for (let index = 0; index < islandHost.registry.length; index += 1) {
            if (islandHost.registry[index].surface !== null
                    && islandHost.registry[index].surface.visible) {
                total += 1;
            }
        }
        return total;
    }

    function stabilityUnownedTopLevelWindowCount() {
        const ownedWindows = [];
        let ownedTopLevelCount = 0;
        const onboardingWindow = onboarding.onboardingWindow.backingWindow;
        if (onboardingWindow !== null) {
            ownedWindows.push(onboardingWindow);
            if (RuntimeIntrospection.isTopLevelWindow(onboardingWindow)) {
                ownedTopLevelCount += 1;
            }
        }
        for (let index = 0; index < islandHost.registry.length; index += 1) {
            const surface = islandHost.registry[index].surface;
            const backingWindow = surface === null ? null : surface.backingWindow;
            if (backingWindow === null || ownedWindows.indexOf(backingWindow) !== -1) {
                return -1;
            }
            ownedWindows.push(backingWindow);
            if (RuntimeIntrospection.isTopLevelWindow(backingWindow)) {
                ownedTopLevelCount += 1;
            }
        }
        return RuntimeIntrospection.topLevelWindowCount() - ownedTopLevelCount;
    }

    function stabilityProcessWideServices() {
        return [virtualDesktops, wallpaperService, clockState, islandState, globalShortcut,
                weatherLocationSearch, weather, mediaAdapter, audioAdapter, easyEffectsStatus,
                brightness, gamingPerformance, connectivityAdapter, session, applicationModel,
                notificationService, trayAdapter, appearance, islandHost];
    }

    function stabilityObjectToken(object) {
        if (object === null || object === undefined) {
            return 0;
        }
        if (!stabilityObjectTokens.has(object)) {
            stabilityNextObjectToken += 1;
            stabilityObjectTokens.set(object, stabilityNextObjectToken);
        }
        return stabilityObjectTokens.get(object);
    }

    function stabilityProcessWideObjectIdentity() {
        const objects = stabilityProcessWideServices().concat([notificationService.historyModel,
                                                               notificationService.dashboardModel]);
        const tokens = [];
        for (let index = 0; index < objects.length; index += 1) {
            tokens.push(stabilityObjectToken(objects[index]));
        }
        return tokens.join(".");
    }

    function stabilityProcessWideServiceCount() {
        const services = stabilityProcessWideServices();
        let total = 0;
        for (let index = 0; index < services.length; index += 1) {
            if (services[index] !== null && services[index] !== undefined) {
                total += 1;
            }
        }
        return total;
    }

    function stabilityResourceCounts() {
        return {
            "processWideServices": stabilityProcessWideServiceCount(),
            "islandSurfaces": islandHost.liveSurfaceCount,
            "controlCenterWindows": controlCenter === null ? 0 : 1,
            "controlCenterPages": controlCenter === null ? 0 : controlCenter.loadedPageCount,
            "applications": stabilityArrayCount(applicationModel.applications),
            "applicationPins": stabilityArrayCount(applicationModel.pinIds),
            "applicationRecency": stabilityArrayCount(applicationModel.recencyIds),
            "notificationLive": notificationService.liveCount,
            "notificationRuntimePlugins": notificationService.historyModel !== null
                                          && notificationService.dashboardModel !== null ? 1 : 0,
            "notificationHistory": notificationService.historyCount,
            "notificationWatchers": stabilityObjectCount(notificationService.watchers),
            "notificationPopups": stabilityObjectCount(notificationService.admittedPopups),
            "mediaPlayers": mediaAdapter.trackedPlayerCount,
            "audioObjects": audioAdapter.trackedObjectCount,
            "audioCandidates": stabilityArrayCount(audioAdapter.outputCandidates)
                               + stabilityArrayCount(audioAdapter.inputCandidates),
            "trayItems": trayAdapter.itemCount,
            "trayTrackedItems": trayAdapter.trackedItemCount,
            "wifiNetworks": stabilityArrayCount(connectivityAdapter.wifiNetworks),
            "bluetoothDevices": stabilityArrayCount(connectivityAdapter.bluetoothDevices),
            "wallpaperScreens": stabilityArrayCount(wallpaperService.screens),
            "wallpaperDirectories": stabilityArrayCount(wallpaperService.directories),
            "wallpaperImages": stabilityArrayCount(wallpaperService.images),
            "wallpaperPreview": wallpaperService.preview === null ? 0 : 1,
            "wallpaperApplyResults": stabilityArrayCount(wallpaperService.applyResults),
            "easyEffectsPresets": stabilityArrayCount(easyEffectsStatus.outputPresets)
                                  + stabilityArrayCount(easyEffectsStatus.inputPresets),
            "weatherModels": weather.model === null ? 0 : 1,
            "weatherHourlyRows": stabilityArrayCount(weather.hourly),
            "weatherDailyRows": stabilityArrayCount(weather.daily),
            "brightnessDisplays": stabilityArrayCount(brightness.displays),
            "virtualDesktops": virtualDesktops.desktopCount
        };
    }

    function stabilityBoundedCounts(resources) {
        return {
            "applicationPins": {
                "count": resources.applicationPins,
                "maximum": applicationModel.maximumPins
            },
            "applicationRecency": {
                "count": resources.applicationRecency,
                "maximum": applicationModel.maximumRecency
            },
            "notificationLive": {
                "count": resources.notificationLive,
                "maximum": 50
            },
            "notificationHistory": {
                "count": resources.notificationHistory,
                "maximum": 50
            },
            "trayTrackedItems": {
                "count": resources.trayTrackedItems,
                "maximum": trayAdapter.maximumMenuWatcherEntries
            },
            "wifiNetworks": {
                "count": resources.wifiNetworks,
                "maximum": 16
            },
            "bluetoothDevices": {
                "count": resources.bluetoothDevices,
                "maximum": 32
            },
            "wallpaperScreens": {
                "count": resources.wallpaperScreens,
                "maximum": 16
            },
            "wallpaperDirectories": {
                "count": resources.wallpaperDirectories,
                "maximum": 512
            },
            "wallpaperImages": {
                "count": resources.wallpaperImages,
                "maximum": 512
            },
            "wallpaperApplyResults": {
                "count": resources.wallpaperApplyResults,
                "maximum": 16
            },
            "easyEffectsPresets": {
                "count": resources.easyEffectsPresets,
                "maximum": easyEffectsStatus.maximumPresetEntries * 2
            },
            "weatherModels": {
                "count": resources.weatherModels,
                "maximum": 1
            },
            "weatherHourlyRows": {
                "count": resources.weatherHourlyRows,
                "maximum": 12
            },
            "weatherDailyRows": {
                "count": resources.weatherDailyRows,
                "maximum": 5
            },
            "brightnessDisplays": {
                "count": resources.brightnessDisplays,
                "maximum": 32
            }
        };
    }

    function controlCenterCapabilities() {
        return {
            "displayRouting": islandHost.liveSurfaceCount > 0,
            "audio": audioAdapter.available,
            "media": mediaAdapter.available,
            "wifi": connectivityAdapter.wifiAvailable,
            "bluetooth": connectivityAdapter.bluetoothAvailable,
            "gamingPerformance": gamingPerformance.available,
            "notifications": notificationService.serverOwned,
            "weather": weather.available
        };
    }

    function ensureControlCenterLoaded() {
        controlCenterLoader.active = true;
        return controlCenter !== null;
    }

    function unloadControlCenter() {
        controlCenterLoader.active = false;
    }

    function openControlCenter(routeId, initiatingSurfaceToken) {
        if (initiatingSurfaceToken !== null && initiatingSurfaceToken !== undefined) {
            islandState.resetToIdle(initiatingSurfaceToken);
        }
        return ensureControlCenterLoaded() && controlCenter.open(routeId, initiatingSurfaceToken);
    }

    KWinVirtualDesktopAdapter {
        id: virtualDesktops
        helperPath: Quickshell.shellPath("build/nagi-kwin-virtual-desktops")
    }

    WallpaperService {
        id: wallpaperService
        helperPath: Quickshell.env("NAGI_WALLPAPER_HELPER") ?? Quickshell.shellPath(
                        "build/wallpaper/nagi-wallpaper")
    }

    CompactClock {
        id: clockState
        format: UserConfig.snapshot.clock.format
        showSeconds: UserConfig.snapshot.clock.showSeconds
        dateFormat: UserConfig.snapshot.clock.dateFormat
        showIdleDate: UserConfig.snapshot.clock.showIdleDate
        scheduleActive: islandHost.liveSurfaceCount > 0 || (controlCenter !== null
                                                            && controlCenter.visible)
    }

    IslandStateCoordinator {
        id: islandState
        feedbackDuration: UserConfig.snapshot.island.feedbackDuration
    }

    GlobalShortcutAdapter {
        id: globalShortcut
        historyEnabled: UserConfig.snapshot.notifications.historyVisible

        coordinator: islandState
        helperPath: Quickshell.shellPath("build/global-shortcut/nagi-global-shortcut")
        onControlCenterRequested: {
            if (!islandState.modalPresent) {
                openControlCenter("control-center", islandHost.routeSurfaceToken(null));
            }
        }
    }

    WeatherLocationSearchAdapter {
        id: weatherLocationSearch
        allowed: controlCenter !== null && controlCenter.weatherLookupAllowed
    }

    WeatherAdapter {
        id: weather
        enabled: UserConfig.snapshot.weather.enabled
        label: UserConfig.snapshot.weather.locationLabel
        latitude: UserConfig.snapshot.weather.latitude ?? Number.NaN
        longitude: UserConfig.snapshot.weather.longitude ?? Number.NaN
        temperatureUnit: UserConfig.snapshot.weather.temperatureUnit
        windUnit: UserConfig.snapshot.weather.windUnit
        refreshPreset: UserConfig.snapshot.weather.refreshPreset
    }

    MediaAdapter {
        id: mediaAdapter
        enabled: UserConfig.snapshot.media.enabled
        detailsVisible: islandState.anyExpanded && UserConfig.snapshot.media.dashboardVisible
        playerPolicy: UserConfig.snapshot.media.playerPolicy
        preferredApplication: UserConfig.snapshot.media.preferredApplication
    }

    AudioAdapter {
        id: audioAdapter
        bridgePath: Quickshell.shellPath("build/nagi-pipewire-audio")
    }
    EasyEffectsStatusService {
        id: easyEffectsStatus
        helperPath: Quickshell.env("NAGI_EASYEFFECTS_STATUS_HELPER") ?? Quickshell.shellPath(
                        "build/nagi-easyeffects-status")
    }
    BrightnessAdapter {
        id: brightness
        helperPath: Quickshell.shellPath("build/nagi-brightness")
    }

    GamingPerformanceService {
        id: gamingPerformance
        helperPath: Quickshell.env("NAGI_GAMING_PERFORMANCE_HELPER") ?? Quickshell.shellPath(
                        "build/nagi-gaming-performance")
        enabled: UserConfig.snapshot.island.gamingIndicator
    }

    ConnectivityAdapter {
        id: connectivityAdapter
        helperPath: Quickshell.shellPath("build/nagi-connectivity")
    }

    SessionService {
        id: session
        helperPath: Quickshell.shellPath("build/nagi-session")
    }

    ApplicationModel {
        id: applicationModel

        helperPath: Quickshell.shellPath("build/nagi-applications")
    }

    OnboardingWindow {
        id: onboarding
        onControlCenterRequested: openControlCenter("control-center", islandHost.routeSurfaceToken(
                                                        null))
    }

    NotificationService {
        id: notificationService
        popupsEnabled: UserConfig.snapshot.notifications.popupsEnabled
        doNotDisturb: UserConfig.snapshot.notifications.doNotDisturb
        criticalMode: UserConfig.snapshot.notifications.criticalMode
        dashboardVisible: UserConfig.snapshot.notifications.dashboardVisible
        historyVisible: UserConfig.snapshot.notifications.historyVisible
    }

    TrayAdapter {
        id: trayAdapter
    }

    KdeAppearanceAdapter {
        id: appearance
    }

    Binding {
        target: Theme
        property: "systemAppearance"
        value: appearance.snapshot
    }

    IslandSurfaceHost {
        id: islandHost
        coordinator: islandState
        virtualDesktops: virtualDesktops
        clock: clockState
        weather: weather
        media: mediaAdapter
        gamingPerformance: gamingPerformance
        connectivityAdapter: connectivityAdapter
        sessionService: session
        notificationService: notificationService
        applicationModel: applicationModel
        trayAdapter: trayAdapter
        audioAdapter: audioAdapter
        easyEffectsStatusService: easyEffectsStatus
        workspaceTransientSource: virtualDesktops
        brightnessTransientSource: brightness
        volumeTransientSource: audioAdapter
        notificationTransientSource: notificationService
        reducedMotion: Theme.motion.effectiveMode === "minimal"
        onControlCenterRequested: token => openControlCenter("control-center", token)
        onControlCenterRouteRequested: (routeId, token) => openControlCenter(routeId, token)
    }

    Component {
        id: controlCenterComponent

        ControlCenterWindow {
            surfaceHost: islandHost
            implicitWidth: Quickshell.env("NAGI_STABILITY_PROBE") === "1"
                           && stabilityControlCenterCompact ? Theme.size.controlCenterMinimumWidth :
                                                              Theme.size.controlCenterPreferredWidth
            settingsModel: UserConfig
            clock: clockState
            media: mediaAdapter
            notificationService: notificationService
            weather: weather
            locationSearch: weatherLocationSearch
            wifi: connectivityAdapter
            wallpaper: wallpaperService
            reducedMotion: Theme.motion.effectiveMode === "minimal"
            capabilities: controlCenterCapabilities()
            onUnloadRequested: Qt.callLater(() => unloadControlCenter())
        }
    }

    Loader {
        id: controlCenterLoader

        active: false
        asynchronous: false
        sourceComponent: controlCenterComponent

        onItemChanged: {
            if (item === null) {
                controlCenterResourceRelease.restart();
            } else {
                controlCenterResourceRelease.stop();
            }
        }
    }

    Timer {
        id: controlCenterResourceRelease

        interval: 1000
        onTriggered: RuntimeIntrospection.releaseUnusedQmlResources()
    }

    IpcHandler {
        target: "nagi"

        function activate(reason: string): bool {
            if (reason !== "control-center" && reason !== "island" && reason !== "appearance" && reason
                    !== "clock-date" && reason !== "media" && reason !== "weather" && reason
                    !== "notifications" && reason !== "wifi" && reason !== "bluetooth" && reason
                    !== "wallpaper" && reason !== "displays" && reason !== "about") {
                return false;
            }
            return openControlCenter(reason, null);
        }

        function stabilitySnapshot(): string {
            if (Quickshell.env("NAGI_STABILITY_PROBE") !== "1") {
                return "";
            }
            const retainedControlCenter = controlCenter === null ? 0 : 1;
            const pageInterestWork = (wallpaperService.pageOpen ? 1 : 0) + (
                      connectivityAdapter.wifiManagerOpen ? 1 : 0) + (
                      connectivityAdapter.bluetoothManagerOpen ? 1 : 0) + (
                      weatherLocationSearch.allowed ? 1 : 0) + (weatherLocationSearch.inFlight ? 1 :
                                                                                                 0);
            const activeAdapterTimers = audioAdapter.activeTimerCount + brightness.activeTimerCount
                  + connectivityAdapter.activeTimerCount + gamingPerformance.activeTimerCount
                  + notificationService.activeTimerCount + session.activeTimerCount
                  + wallpaperService.activeTimerCount + easyEffectsStatus.activeTimerCount + (
                      mediaAdapter.positionTimerRunning ? 1 : 0) + (weatherLocationSearch.inFlight
                                                                    ? 1 : 0);
            const resources = stabilityResourceCounts();
            const unownedTopLevelWindows = stabilityUnownedTopLevelWindowCount();
            const controlCenterTopLevelWindows = retainedControlCenter > 0
                  && unownedTopLevelWindows > 0 ? 1 : 0;
            const extraProcessWindows = unownedTopLevelWindows - controlCenterTopLevelWindows;
            return JSON.stringify({
                                      "configurationRevision": UserConfig.snapshot.generation,
                                      "appearanceRevision": appearance.snapshot.generation,
                                      "processWideObjectIdentity":
                                      stabilityProcessWideObjectIdentity(),
                                      "islands": {
                                          "count": islandHost.liveSurfaceCount,
                                          "registryRevision": islandHost.registryRevision
                                      },
                                      "onboarding": {
                                          "visible": onboarding.onboardingVisible,
                                          "instantiatedWindowCount":
                                          onboarding.onboardingWindow.backingWindow === null ? 0 : 1
                                      },
                                      "controlCenter": {
                                          "visible": controlCenter !== null && controlCenter.visible,
                                          "instantiatedWindowCount": retainedControlCenter,
                                          "loadedPageCount": controlCenter === null ? 0 :
                                                                                      controlCenter.loadedPageCount,
                                          "pageInterestWorkCount": pageInterestWork,
                                          "pageOwnedActiveTimerCount": activeAdapterTimers
                                                                       + retainedControlCenter,
                                          "pageAnimationCount": retainedControlCenter,
                                          "hiddenFocusLoopCount": retainedControlCenter,
                                          "pageOwnedWindowOrEffectCount": retainedControlCenter
                                                                          + controlCenterTopLevelWindows,
                                          "resourceReleaseCount":
                                          RuntimeIntrospection.resourceReleaseCount
                                      },
                                      "wallpaper": {
                                          "pageInterest": wallpaperService.pageOpen,
                                          "activeTimerCount": wallpaperService.activeTimerCount
                                      },
                                      "connectivity": {
                                          "wifiManagerInterest": connectivityAdapter.wifiManagerOpen,
                                          "bluetoothManagerInterest":
                                          connectivityAdapter.bluetoothManagerOpen,
                                          "activeTimerCount": connectivityAdapter.activeTimerCount
                                      },
                                      "weatherSearch": {
                                          "allowed": weatherLocationSearch.allowed,
                                          "inFlight": weatherLocationSearch.inFlight
                                      },
                                      "media": {
                                          "detailsVisible": mediaAdapter.detailsVisible,
                                          "positionTimerRunning": mediaAdapter.positionTimerRunning
                                      },
                                      "easyEffects": {
                                          "interested": easyEffectsStatus.interested,
                                          "interestCount": easyEffectsStatus.interested ? 1 : 0,
                                          "activeTimerCount": easyEffectsStatus.activeTimerCount
                                      },
                                      "activeAdapterTimerCount": activeAdapterTimers,
                                      "resources": resources,
                                      "boundedCounts": stabilityBoundedCounts(resources),
                                      "gpu": {
                                          "visibleIslandCount": stabilityVisibleSurfaceCount(),
                                          "shadowLayerCount": stabilitySurfaceMetric(
                                                                  "shadowLayerCount"),
                                          "requestedKwinBlurRegionCount": stabilitySurfaceMetric(
                                                                              "requestedKwinBlurRegionCount"),
                                          "processWideServiceCount":
                                          stabilityProcessWideServiceCount(),
                                          "extraProcessWideServiceEffectObjectCount":
                                          extraProcessWindows
                                      },
                                      "polkitDormant": islandHost.polkitController === null
                                  });
        }

        function stabilityCloseControlCenter(): bool {
            if (Quickshell.env("NAGI_STABILITY_PROBE") !== "1") {
                return false;
            }
            if (controlCenter === null) {
                return false;
            }
            controlCenter.closeWindow();
            return true;
        }

        function stabilitySetControlCenterCompact(compact: bool): bool {
            if (Quickshell.env("NAGI_STABILITY_PROBE") !== "1") {
                return false;
            }
            stabilityControlCenterCompact = compact;
            if (!ensureControlCenterLoaded()) {
                return false;
            }
            const targetWidth = compact ? Theme.size.controlCenterMinimumWidth :
                                          Theme.size.controlCenterPreferredWidth;
            controlCenter.implicitWidth = targetWidth;
            if (controlCenter.backingWindow !== null) {
                controlCenter.backingWindow.width = targetWidth;
            }
            return true;
        }
    }

    TransientCoordinatorBridge {
        coordinator: islandState
        surfaceHost: islandHost
        workspaceSource: virtualDesktops
        brightnessSource: brightness
        audioSource: audioAdapter
        gamingPerformanceSource: gamingPerformance
        notificationSource: notificationService
    }
}

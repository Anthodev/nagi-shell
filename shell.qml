//@ pragma UseQApplication
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import "qml"

ShellRoot {

    function openControlCenter(routeId, initiatingSurfaceToken) {
        if (initiatingSurfaceToken !== null && initiatingSurfaceToken !== undefined) {
            islandState.resetToIdle(initiatingSurfaceToken);
        }
        return controlCenter.open(routeId, initiatingSurfaceToken);
    }

    KWinVirtualDesktopAdapter {
        id: virtualDesktops
        helperPath: Quickshell.shellPath("build/nagi-kwin-virtual-desktops")
    }

    WallpaperPaletteBridge {
        helperPath: Quickshell.env("NAGI_WALLPAPER_HELPER") ?? Quickshell.shellPath(
                        "build/wallpaper/nagi-wallpaper")
    }

    CompactClock {
        id: clockState
        format: UserConfig.snapshot.clock.format
        showSeconds: UserConfig.snapshot.clock.showSeconds
        dateFormat: UserConfig.snapshot.clock.dateFormat
        showIdleDate: UserConfig.snapshot.clock.showIdleDate
        scheduleActive: islandHost.liveSurfaceCount > 0 || controlCenter.visible
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

    WeatherAdapter {
        id: weather
        enabled: UserConfig.snapshot.weather.enabled && UserConfig.snapshot.island.showWeather
        latitude: UserConfig.snapshot.weather.latitude ?? Number.NaN
        longitude: UserConfig.snapshot.weather.longitude ?? Number.NaN
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
    BrightnessAdapter {
        id: brightness
        helperPath: Quickshell.shellPath("build/nagi-brightness")
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
        connectivityAdapter: connectivityAdapter
        sessionService: session
        notificationService: notificationService
        applicationModel: applicationModel
        trayAdapter: trayAdapter
        audioAdapter: audioAdapter
        workspaceTransientSource: virtualDesktops
        brightnessTransientSource: brightness
        volumeTransientSource: audioAdapter
        notificationTransientSource: notificationService
        reducedMotion: Theme.motion.effectiveMode === "minimal"
        onControlCenterRequested: token => openControlCenter("control-center", token)
    }

    ControlCenterWindow {
        id: controlCenter

        surfaceHost: islandHost
        settingsModel: UserConfig
        clock: clockState
        media: mediaAdapter
        notificationService: notificationService
        reducedMotion: Theme.motion.effectiveMode === "minimal"
        capabilities: ({
                           "displayRouting": islandHost.liveSurfaceCount > 0,
                           "audio": audioAdapter.available,
                           "media": mediaAdapter.available,
                           "wifi": connectivityAdapter.wifiAvailable,
                           "bluetooth": connectivityAdapter.bluetoothAvailable,
                           "notifications": notificationService.serverOwned,
                           "weather": weather.available
                       })
    }

    IpcHandler {
        target: "nagi"

        function activate(reason: string): bool {
            if (reason !== "control-center" && reason !== "island" && reason !== "appearance" && reason
                    !== "clock-date" && reason !== "media" && reason !== "notifications" && reason
                    !== "displays" && reason !== "about") {
                return false;
            }
            return openControlCenter(reason, null);
        }
    }

    TransientCoordinatorBridge {
        coordinator: islandState
        workspaceSource: virtualDesktops
        brightnessSource: brightness
        audioSource: audioAdapter
        notificationSource: notificationService
    }
}

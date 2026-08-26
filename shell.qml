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
        dateFormat: UserConfig.snapshot.clock.dateFormat
        showIdleDate: UserConfig.snapshot.clock.showIdleDate
    }

    IslandStateCoordinator {
        id: islandState
    }

    GlobalShortcutAdapter {
        id: globalShortcut

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
        enabled: UserConfig.snapshot.weather.enabled
        latitude: UserConfig.snapshot.weather.latitude ?? Number.NaN
        longitude: UserConfig.snapshot.weather.longitude ?? Number.NaN
    }

    MediaAdapter {
        id: mediaAdapter
        enabled: UserConfig.snapshot.media.enabled
        detailsVisible: islandState.anyExpanded
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
    }

    TrayAdapter {
        id: trayAdapter
    }

    ReducedMotion {
        id: motion
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
        reducedMotion: motion.active
        onControlCenterRequested: token => openControlCenter("control-center", token)
    }

    ControlCenterWindow {
        id: controlCenter

        surfaceHost: islandHost
        settingsModel: UserConfig
        reducedMotion: motion.active
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
            if (reason !== "control-center" && reason !== "displays" && reason !== "about") {
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

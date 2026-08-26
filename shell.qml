//@ pragma UseQApplication
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import "qml"

ShellRoot {
    property int systemSettingsRequestId: 0
    property string systemSettingsFailure: ""
    readonly property string visibleSettingsFailure: systemSettingsFailure !== ""
                                                     ? systemSettingsFailure :
                                                       UserConfig.errorMessage

    function launchSystemSettings(initiatingSurfaceToken) {
        systemSettingsFailure = "";
        const requestId = applicationModel.dispatchLaunch("systemsettings.desktop");
        if (requestId === 0) {
            systemSettingsFailure
                    = "System Settings is unavailable. Open it from the application launcher.";
            settingsFailureTimer.restart();
            return false;
        }
        systemSettingsRequestId = requestId;
        if (initiatingSurfaceToken !== null && initiatingSurfaceToken !== undefined) {
            islandState.resetToIdle(initiatingSurfaceToken);
        }
        return true;
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
        onSystemSettingsRequested: {
            if (!islandState.modalPresent) {
                launchSystemSettings(islandHost.routeSurfaceToken(null));
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
        settingsFailure: visibleSettingsFailure
        onSystemSettingsRequested: launchSystemSettings(islandHost.routeSurfaceToken(null))
    }

    NotificationService {
        id: notificationService
    }

    TrayAdapter {
        id: trayAdapter
    }

    Connections {
        target: applicationModel

        function onLaunchAccepted(requestId, desktopFileId) {
            if (requestId === systemSettingsRequestId) {
                systemSettingsRequestId = 0;
                systemSettingsFailure = "";
                settingsFailureTimer.stop();
            }
        }

        function onLaunchRejected(requestId, category) {
            if (requestId === systemSettingsRequestId) {
                systemSettingsRequestId = 0;
                systemSettingsFailure
                        = "System Settings could not be opened. Open it from the application launcher.";
                settingsFailureTimer.restart();
            }
        }
    }

    Timer {
        id: settingsFailureTimer

        interval: 5000
        onTriggered: systemSettingsFailure = ""
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
        settingsFailure: visibleSettingsFailure
        onSystemSettingsRequested: token => launchSystemSettings(token)
    }

    TransientCoordinatorBridge {
        coordinator: islandState
        workspaceSource: virtualDesktops
        brightnessSource: brightness
        audioSource: audioAdapter
        notificationSource: notificationService
    }
}

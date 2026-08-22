//@ pragma UseQApplication
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import QtQuick.Layouts
import "qml"

ShellRoot {
    KWinVirtualDesktopAdapter {
        id: virtualDesktops
        helperPath: Quickshell.shellPath("build/nagi-kwin-virtual-desktops")
    }

    CompactClock {
        id: clockState
    }

    IslandStateCoordinator {
        id: islandState
    }

    LauncherShortcutAdapter {
        id: launcherShortcut

        coordinator: islandState
        helperPath: Quickshell.shellPath("build/launcher-shortcut/nagi-launcher-shortcut")
    }

    WeatherAdapter {
        id: weather
    }

    MediaAdapter {
        id: mediaAdapter
        detailsVisible: islandState.ownerKind === islandState.ownerExpanded
                        && islandState.presentationVisible
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

    NotificationService {
        id: notificationService
    }

    TrayAdapter {
        id: trayAdapter
    }

    Component {
        id: dashboardMedia

        DashboardMedia {
            media: mediaAdapter
        }
    }

    Component {
        id: dashboardClock

        DashboardClock {
            clock: clockState
        }
    }

    Component {
        id: dashboardQuickControls

        DashboardQuickControls {
            connectivity: connectivityAdapter
            audio: audioAdapter
            applicationModel: applicationModel
            tray: trayAdapter
        }
    }

    Component {
        id: dashboardAudio

        DashboardAudio {
            audio: audioAdapter
        }
    }

    Component {
        id: dashboardNotifications

        DashboardNotifications {
            service: notificationService
        }
    }

    Component {
        id: dashboardNavigation

        RowLayout {
            spacing: Theme.spacing.sm

            LauncherEntry {
                Layout.fillWidth: true
                shortcutAvailable: launcherShortcut.available
                activeShortcut: launcherShortcut.activeShortcut
                preferredConflict: launcherShortcut.preferredConflict
                onOpenRequested: islandState.openLauncher(islandHost.surfaceToken)
            }

            NotificationHistoryEntry {
                Layout.fillWidth: true
                onOpenRequested: islandState.openHistory(islandHost.surfaceToken)
            }

            SessionEntry {
                Layout.fillWidth: true
                onOpenRequested: islandState.openSession(islandHost.surfaceToken)
            }
        }
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
        sessionService: session
        notificationService: notificationService
        applicationModel: applicationModel
        workspaceTransientSource: virtualDesktops
        brightnessTransientSource: brightness
        volumeTransientSource: audioAdapter
        notificationTransientSource: notificationService
        reducedMotion: motion.active
        dashboardMediaContent: mediaAdapter.available ? dashboardMedia : null
        dashboardClockContent: dashboardClock
        dashboardQuickControlsContent: dashboardQuickControls
        dashboardAudioContent: dashboardAudio
        dashboardNotificationsContent: dashboardNotifications
        dashboardNavigationContent: dashboardNavigation
    }

    TransientCoordinatorBridge {
        coordinator: islandState
        surfaceToken: islandHost.surfaceToken
        workspaceSource: virtualDesktops
        brightnessSource: brightness
        audioSource: audioAdapter
        notificationSource: notificationService
    }
}

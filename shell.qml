//@ pragma UseQApplication
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
        id: clock
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
        id: media
    }

    AudioAdapter {
        id: audio
        bridgePath: Quickshell.shellPath("build/nagi-pipewire-audio")
    }
    BrightnessAdapter {
        id: brightness
        helperPath: Quickshell.shellPath("build/nagi-brightness")
    }

    ConnectivityAdapter {
        id: connectivity
        helperPath: Quickshell.shellPath("build/nagi-connectivity")
    }

    SessionService {
        id: session
        helperPath: Quickshell.shellPath("build/nagi-session")
    }

    ApplicationModel {
        id: applications

        helperPath: Quickshell.shellPath("build/nagi-applications")
    }

    NotificationService {
        id: notifications
    }

    TrayAdapter {
        id: tray
    }

    Component {
        id: trayDashboardContent

        TrayView {
            adapter: tray
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
        clock: clock
        weather: weather
        media: media
        sessionService: session
        notificationService: notifications
        applicationModel: applications
        workspaceTransientSource: virtualDesktops
        brightnessTransientSource: brightness
        volumeTransientSource: audio
        notificationTransientSource: notifications
        reducedMotion: motion.active
        dashboardQuickControlsContent: tray.available ? trayDashboardContent : null
        dashboardNavigationContent: dashboardNavigation
    }

    TransientCoordinatorBridge {
        coordinator: islandState
        surfaceToken: islandHost.surfaceToken
        workspaceSource: virtualDesktops
        brightnessSource: brightness
        audioSource: audio
        notificationSource: notifications
    }
}

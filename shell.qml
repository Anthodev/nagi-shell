//@ pragma UseQApplication
import Quickshell
import QtQuick
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
        id: sessionDashboardEntry

        SessionEntry {
            onOpenRequested: islandState.openSession(islandHost.surfaceToken)
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
        reducedMotion: motion.active
        dashboardQuickControlsContent: tray.available ? trayDashboardContent : null
        dashboardNavigationContent: sessionDashboardEntry
    }
}

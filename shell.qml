//@ pragma UseQApplication
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "qml"

ShellRoot {
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
            centerStatusInMainLane: !mediaAdapter.available
            connectivity: connectivityAdapter
            applicationModel: applicationModel
            tray: trayAdapter
        }
    }

    Component {
        id: dashboardAudio

        DashboardAudio {
            audio: audioAdapter
            onDeviceSelectionRequested: islandState.openAudio(islandHost.surfaceToken)
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

        Item {
            implicitWidth: Math.max(navigationTopCluster.implicitWidth,
                                    navigationSession.implicitWidth)
            implicitHeight: navigationTopCluster.implicitHeight + Theme.spacing.xl
                            + navigationSession.implicitHeight

            ColumnLayout {
                id: navigationTopCluster
                objectName: "dashboardNavigationTopCluster"
                anchors.top: parent.top
                anchors.right: parent.right
                spacing: Theme.spacing.sm

                RailButton {
                    objectName: "dashboardTray"
                    meaning: "tray"
                    accessibleName: "System tray"
                    onOpenRequested: islandState.openTray(islandHost.surfaceToken)
                }

                RailButton {
                    objectName: "dashboardLauncher"
                    meaning: "launcher"
                    accessibleName: "Launcher"
                    onOpenRequested: islandState.openLauncher(islandHost.surfaceToken)
                }

                RailButton {
                    objectName: "dashboardHistory"
                    meaning: "history"
                    accessibleName: "Notification history"
                    onOpenRequested: islandState.openHistory(islandHost.surfaceToken)
                }
            }

            RailButton {
                id: navigationSession
                objectName: "dashboardSession"
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                meaning: "session"
                accessibleName: "Session"
                onOpenRequested: islandState.openSession(islandHost.surfaceToken)
            }
        }
    }

    component RailButton: AbstractButton {
        id: control

        required property string meaning
        required property string accessibleName

        signal openRequested

        implicitWidth: Theme.size.controlHeightMd
        implicitHeight: Theme.size.controlHeightMd
        focusPolicy: Qt.StrongFocus
        hoverEnabled: true
        Accessible.role: Accessible.Button
        Accessible.name: accessibleName
        onClicked: openRequested()

        background: Rectangle {
            radius: Theme.radius.md
            color: control.pressed ? Theme.color.surfaceActive : control.hovered ? Theme.color.surfaceHover :
                                                                                   "transparent"
        }
        contentItem: Item {
            IslandIcon {
                anchors.centerIn: parent
                meaning: control.meaning
            }
        }
        IslandFocusRing {
            visible: control.visualFocus
        }
        ToolTip.delay: Theme.motion.durationSlow
        ToolTip.visible: hovered || visualFocus
        ToolTip.text: accessibleName
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
        trayAdapter: trayAdapter
        audioAdapter: audioAdapter
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

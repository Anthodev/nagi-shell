pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    objectName: "dashboardNavigation"

    required property var coordinator
    property var surfaceToken: null
    property string settingsFailure: ""
    signal systemSettingsRequested

    readonly property alias topCluster: navigationTopCluster
    readonly property alias bottomCluster: navigationBottomCluster
    readonly property alias settingsButton: navigationSettings
    readonly property alias sessionButton: navigationSession

    implicitWidth: Math.max(navigationTopCluster.implicitWidth,
                            navigationBottomCluster.implicitWidth)
    implicitHeight: navigationTopCluster.implicitHeight + Theme.spacing.xl
                    + navigationBottomCluster.implicitHeight

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
            onOpenRequested: root.coordinator.openTray(root.surfaceToken)
        }

        RailButton {
            objectName: "dashboardLauncher"
            meaning: "launcher"
            accessibleName: "Launcher"
            onOpenRequested: root.coordinator.openLauncher(root.surfaceToken)
        }

        RailButton {
            objectName: "dashboardHistory"
            meaning: "history"
            accessibleName: "Notification history"
            onOpenRequested: root.coordinator.openHistory(root.surfaceToken)
        }
    }

    ColumnLayout {
        id: navigationBottomCluster

        objectName: "dashboardNavigationBottomCluster"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: Theme.spacing.sm

        RailButton {
            id: navigationSettings

            objectName: "dashboardSettings"
            meaning: "settings"
            accessibleName: "System Settings"
            failureText: root.settingsFailure
            onOpenRequested: root.systemSettingsRequested()
        }

        RailButton {
            id: navigationSession

            objectName: "dashboardSession"
            meaning: "session"
            accessibleName: "Session"
            onOpenRequested: root.coordinator.openSession(root.surfaceToken)
        }
    }

    component RailButton: AbstractButton {
        id: control

        required property string meaning
        required property string accessibleName
        property string failureText: ""

        signal openRequested

        implicitWidth: Theme.size.controlHeightMd
        implicitHeight: Theme.size.controlHeightMd
        focusPolicy: Qt.StrongFocus
        hoverEnabled: true
        Accessible.role: Accessible.Button
        Accessible.name: accessibleName
        Accessible.description: failureText
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
        ToolTip.text: failureText !== "" ? failureText : accessibleName
    }
}

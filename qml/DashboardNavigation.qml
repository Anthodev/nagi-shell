pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    objectName: "dashboardNavigation"

    required property var coordinator
    property var surfaceToken: null
    property bool showHistory: true
    property var applicationModel: null
    readonly property string systemSettingsDesktopId: "systemsettings.desktop"
    property int systemSettingsRequestId: 0
    property string systemSettingsFailure: ""
    signal controlCenterRequested
    signal systemSettingsOpened

    function openSystemSettings() {
        if (systemSettingsRequestId !== 0) {
            return false;
        }
        systemSettingsFailure = "";
        if (applicationModel === null || typeof applicationModel.dispatchLaunch !== "function") {
            systemSettingsFailure = "KDE Plasma System Settings is unavailable.";
            return false;
        }
        const requestId = applicationModel.dispatchLaunch(systemSettingsDesktopId);
        if (requestId <= 0) {
            systemSettingsFailure = "KDE Plasma System Settings could not be opened.";
            return false;
        }
        systemSettingsRequestId = requestId;
        return true;
    }

    readonly property alias topCluster: navigationTopCluster
    readonly property alias bottomCluster: navigationBottomCluster
    readonly property alias settingsButton: navigationSettings
    readonly property alias systemSettingsButton: navigationSystemSettings
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
            visible: root.showHistory
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
            accessibleName: "Nagi Control Center"
            onOpenRequested: root.controlCenterRequested()
        }

        RailButton {
            id: navigationSystemSettings

            objectName: "dashboardSystemSettings"
            meaning: "systemSettings"
            accessibleName: "KDE Plasma System Settings"
            failureText: root.systemSettingsFailure
            onOpenRequested: root.openSystemSettings()
        }

        RailButton {
            id: navigationSession

            objectName: "dashboardSession"
            meaning: "session"
            accessibleName: "Session"
            onOpenRequested: root.coordinator.openSession(root.surfaceToken)
        }
    }

    Connections {
        target: root.applicationModel
        ignoreUnknownSignals: true

        function onLaunchAccepted(requestId, desktopFileId) {
            if (requestId !== root.systemSettingsRequestId || desktopFileId
                    !== root.systemSettingsDesktopId) {
                return;
            }
            root.systemSettingsRequestId = 0;
            root.systemSettingsOpened();
        }

        function onLaunchRejected(requestId, category) {
            if (requestId !== root.systemSettingsRequestId) {
                return;
            }
            root.systemSettingsRequestId = 0;
            root.systemSettingsFailure = "KDE Plasma System Settings could not be opened.";
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

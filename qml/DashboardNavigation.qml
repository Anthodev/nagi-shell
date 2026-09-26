pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Expanded maps this flat rail from the glance top to the instruments/feed
// bottom; the two clusters remain ordered independently at those stage edges.

Item {
    id: root
    objectName: "dashboardNavigation"

    required property var coordinator
    property var surfaceToken: null
    property var activationSurface: null
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
            systemSettingsFailure = qsTr("KDE Plasma System Settings is unavailable.");
            return false;
        }
        const requestId = applicationModel.dispatchLaunch(systemSettingsDesktopId);
        if (requestId <= 0) {
            systemSettingsFailure = qsTr("KDE Plasma System Settings could not be opened.");
            return false;
        }
        systemSettingsRequestId = requestId;
        return true;
    }
    function openInteractive(kind, point) {
        const surface = activationSurface;
        const pointer = point !== null && point !== undefined && surface !== null;
        if (pointer)
            surface.beginNavigationPointer(kind, point);
        const accepted = kind === "tray" ? coordinator.openTray(surfaceToken) : kind === "history" ? coordinator.openHistory(
                                                                                                         surfaceToken) :
                                                                                                     coordinator.openLauncher(
                                                                                                         surfaceToken);
        if (pointer)
            surface.finishNavigationPointer(kind, accepted);
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
            accessibleName: qsTr("System tray")
            onOpenRequested: point => root.openInteractive("tray", point)
        }

        RailButton {
            objectName: "dashboardLauncher"
            meaning: "launcher"
            accessibleName: qsTr("Launcher")
            onOpenRequested: point => root.openInteractive("launcher", point)
        }

        RailButton {
            visible: root.showHistory
            objectName: "dashboardHistory"
            meaning: "history"
            accessibleName: qsTr("Notification history")
            onOpenRequested: point => root.openInteractive("history", point)
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
            accessibleName: qsTr("Nagi Control Center")
            onOpenRequested: root.controlCenterRequested()
        }

        RailButton {
            id: navigationSystemSettings

            objectName: "dashboardSystemSettings"
            meaning: "systemSettings"
            accessibleName: qsTr("KDE Plasma System Settings")
            failureText: root.systemSettingsFailure
            onOpenRequested: root.openSystemSettings()
        }

        RailButton {
            id: navigationSession

            objectName: "dashboardSession"
            meaning: "session"
            accessibleName: qsTr("Session")
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
            root.systemSettingsFailure = qsTr("KDE Plasma System Settings could not be opened.");
        }
    }

    component RailButton: AbstractButton {
        id: control

        required property string meaning
        required property string accessibleName
        property string failureText: ""
        property var pointerPressPoint: null
        signal openRequested(var point)

        implicitWidth: Theme.size.controlHeightMd
        implicitHeight: Theme.size.controlHeightMd
        focusPolicy: Qt.StrongFocus
        hoverEnabled: true
        Accessible.role: Accessible.Button
        Accessible.name: accessibleName
        Accessible.description: failureText
        onClicked: {
            const activation = pointerPressPoint === null || root.activationSurface === null ? null :
                                                                                               control.mapToItem(
                                                                                                   root.activationSurface.contentItem,
                                                                                                   pointerPressPoint);
            pointerPressPoint = null;
            openRequested(activation);
        }
        onCanceled: pointerPressPoint = null
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key
                    === Qt.Key_Enter)
                control.pointerPressPoint = null;
            event.accepted = false;
        }

        TapHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
            onPressedChanged: {
                if (pressed)
                    control.pointerPressPoint = Qt.point(point.position.x, point.position.y);
            }
            onCanceled: control.pointerPressPoint = null
        }

        background: Rectangle {
            radius: Theme.radius.md
            color: control.pressed ? Theme.color.surfaceActive : control.hovered ? Theme.color.surfaceHover :
                                                                                   "transparent"
        }
        contentItem: Item {
            IslandIcon {
                anchors.centerIn: parent
                meaning: control.meaning
                tint: control.pressed ? Theme.snapshot.surfaceActiveForeground : control.hovered
                                        ? Theme.snapshot.surfaceHoverForeground : semanticTint
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

import QtQuick
import QtQuick.Layouts

// Presentation-only shell for Expanded. Each semantic region mounts a real
// downstream component or disappears completely; this component owns no
// platform action, state arbitration, collapse timer, or placeholder control.
FocusScope {
    id: dashboard

    property Component mediaContent: null
    property Component clockContent: null
    property Component quickControlsContent: null
    property Component audioContent: null
    property Component notificationsContent: null
    property Component navigationContent: null

    readonly property int loadedRegionCount: (mediaRegion.ready ? 1 : 0) + (clockRegion.ready ? 1 :
                                                                                                0) + (quickControlsRegion.ready
                                                                                                      ? 1 : 0)
                                             + (audioRegion.ready ? 1 : 0) + (
                                                 notificationsRegion.ready ? 1 : 0) + (
                                                 navigationRegion.ready ? 1 : 0)

    signal closeRequested

    function focusInitialControl() {
        closeButton.forceActiveFocus(Qt.ShortcutFocusReason);
    }

    Keys.priority: Keys.BeforeItem
    Keys.onEscapePressed: event => {
        dashboard.closeRequested();
        event.accepted = true;
    }

    GridLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing.xl
        anchors.topMargin: Theme.spacing.xl + closeButton.implicitHeight + Theme.spacing.sm
        columns: 2
        columnSpacing: Theme.spacing.lg
        rowSpacing: Theme.spacing.lg

        DashboardRegion {
            id: mediaRegion

            objectName: "dashboardMediaRegion"
            content: dashboard.mediaContent
            active: dashboard.visible
            Layout.row: 0
            Layout.column: 0
            Layout.columnSpan: dashboard.clockContent === null ? 2 : 1
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        DashboardRegion {
            id: clockRegion

            objectName: "dashboardClockRegion"
            content: dashboard.clockContent
            active: dashboard.visible
            Layout.row: 0
            Layout.column: dashboard.mediaContent === null ? 0 : 1
            Layout.columnSpan: dashboard.mediaContent === null ? 2 : 1
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        DashboardRegion {
            id: quickControlsRegion

            objectName: "dashboardQuickControlsRegion"
            content: dashboard.quickControlsContent
            active: dashboard.visible
            Layout.row: 1
            Layout.column: 0
            Layout.columnSpan: 2
            Layout.fillWidth: true
        }

        DashboardRegion {
            id: audioRegion

            objectName: "dashboardAudioRegion"
            content: dashboard.audioContent
            active: dashboard.visible
            Layout.row: 2
            Layout.column: 0
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        DashboardRegion {
            id: notificationsRegion

            objectName: "dashboardNotificationsRegion"
            content: dashboard.notificationsContent
            active: dashboard.visible
            Layout.row: 2
            Layout.column: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        DashboardRegion {
            id: navigationRegion

            objectName: "dashboardNavigationRegion"
            content: dashboard.navigationContent
            active: dashboard.visible
            Layout.row: 3
            Layout.column: 0
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignBottom
        }
    }

    IslandButton {
        id: closeButton

        objectName: "dashboardCloseButton"
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Theme.spacing.xl
        anchors.rightMargin: Theme.spacing.xl
        label: "Close"
        onClicked: dashboard.closeRequested()
    }
}

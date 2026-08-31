import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property string text
    property bool separated: true
    readonly property int topSeparation: separated ? Theme.spacing.lg : 0
    default property alias contentData: entries.data

    Layout.fillWidth: true
    Layout.topMargin: topSeparation
    spacing: Theme.spacing.sm
    focus: false
    activeFocusOnTab: false
    Accessible.role: Accessible.Grouping
    Accessible.name: root.text

    ControlCenterSectionHeading {
        Layout.fillWidth: true
        text: root.text
        separated: false
    }

    IslandPanel {
        objectName: "controlCenterSectionSurface"
        Layout.fillWidth: true
        implicitWidth: entries.implicitWidth + Theme.spacing.lg * 2
        implicitHeight: entries.implicitHeight
        radius: Theme.radius.lg
        color: Theme.color.controlFill
        clip: true
        border.color: "transparent"

        ColumnLayout {
            id: entries
            objectName: "controlCenterSectionEntries"

            anchors.fill: parent
            anchors.leftMargin: Theme.spacing.lg
            anchors.rightMargin: Theme.spacing.lg
            spacing: 0
        }
    }
}

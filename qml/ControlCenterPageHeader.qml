import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property string iconMeaning: ""
    property string title: ""
    property string description: ""

    implicitWidth: headerLayout.implicitWidth
    implicitHeight: headerLayout.implicitHeight

    ColumnLayout {
        id: headerLayout

        anchors.fill: parent
        spacing: Theme.spacing.sm

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.md

            IslandIcon {
                objectName: "controlCenterPageHeaderIcon"
                Layout.alignment: Qt.AlignVCenter
                meaning: root.iconMeaning
                size: "lg"
                Accessible.ignored: true
            }

            IslandText {
                objectName: "controlCenterPageHeaderTitle"
                Layout.fillWidth: true
                text: root.title
                size: "pageTitle"
                font.weight: Theme.type.weightSemibold
                wrapMode: Text.Wrap
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
        }

        IslandText {
            objectName: "controlCenterPageHeaderDescription"
            Layout.fillWidth: true
            visible: root.description !== ""
            text: root.description
            size: "body"
            tone: "secondary"
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }
    }
}

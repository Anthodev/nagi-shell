import QtQuick
import QtQuick.Layouts

IslandPanel {
    id: root

    property string label: ""
    property string description: ""
    property string errorText: ""
    default property alias controlData: controlSlot.data

    implicitWidth: rowLayout.implicitWidth + Theme.spacing.lg * 2
    implicitHeight: contentLayout.implicitHeight + Theme.spacing.md * 2
    Accessible.role: Accessible.Grouping
    Accessible.name: label
    Accessible.description: errorText !== "" ? description + ". Error: " + errorText : description

    ColumnLayout {
        id: contentLayout

        anchors.fill: parent
        anchors.margins: Theme.spacing.md
        spacing: Theme.spacing.sm

        RowLayout {
            id: rowLayout

            Layout.fillWidth: true
            spacing: Theme.spacing.lg

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.xs

                IslandText {
                    Layout.fillWidth: true
                    text: root.label
                    size: "body"
                    font.weight: Theme.type.weightMedium
                    wrapMode: Text.Wrap
                }

                IslandText {
                    Layout.fillWidth: true
                    visible: root.description !== ""
                    text: root.description
                    size: "caption"
                    color: Theme.color.textSecondary
                    wrapMode: Text.Wrap
                }
            }

            Item {
                id: controlSlot

                Layout.alignment: Qt.AlignVCenter
                implicitWidth: childrenRect.width
                implicitHeight: childrenRect.height
            }
        }

        IslandText {
            Layout.fillWidth: true
            visible: root.errorText !== ""
            text: root.errorText
            size: "caption"
            color: Theme.color.danger
            wrapMode: Text.Wrap
            Accessible.role: Accessible.AlertMessage
            Accessible.name: text
        }
    }
}

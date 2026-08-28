import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property string label: ""
    property string description: ""
    property string errorText: ""
    default property alias controlData: controlSlot.data
    readonly property bool stacked: width > 0 && width < Theme.size.controlCenterRowStackBreakpoint

    implicitWidth: contentLayout.implicitWidth
    implicitHeight: contentLayout.implicitHeight + Theme.spacing.sm * 2
    Accessible.role: Accessible.Grouping
    Accessible.name: label
    Accessible.description: errorText !== "" ? description === "" ? qsTr("Error: %1").arg(
                                                                        errorText) : qsTr(
                                                                        "%1 Error: %2").arg(
                                                                        description).arg(errorText) :
                                                                    description

    ColumnLayout {
        id: contentLayout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Theme.spacing.sm
        spacing: Theme.spacing.sm

        GridLayout {
            id: rowLayout

            Layout.fillWidth: true
            columns: root.stacked ? 1 : 2
            columnSpacing: Theme.spacing.lg
            rowSpacing: Theme.spacing.sm

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.xs

                IslandText {
                    Layout.fillWidth: true
                    text: root.label
                    size: "body"
                    font.weight: Theme.type.weightSemibold
                    wrapMode: Text.Wrap
                }

                IslandText {
                    Layout.fillWidth: true
                    visible: root.description !== ""
                    text: root.description
                    size: "caption"
                    tone: "muted"
                    wrapMode: Text.Wrap
                }
            }

            Item {
                id: controlSlot

                Layout.fillWidth: root.stacked
                Layout.alignment: root.stacked ? Qt.AlignLeft : Qt.AlignRight | Qt.AlignVCenter
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

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Theme.size.hairlineWidth
        color: Theme.color.surfaceBorder
        opacity: 0.72
    }
}

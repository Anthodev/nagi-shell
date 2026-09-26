import QtQuick
import QtQuick.Layouts

Item {
    id: root

    enum ControlPlacement {
        Auto,
        Inline,
        Below
    }

    property string label: ""
    property string description: ""
    property string errorText: ""
    property int controlPlacement: ControlCenterSettingRow.Auto
    required property bool separatorVisible
    default property alias controlData: controlSlot.data
    readonly property bool stacked: controlPlacement === ControlCenterSettingRow.Below || (
                                        controlPlacement === ControlCenterSettingRow.Auto && width
                                        > 0 && width
                                        < Theme.size.controlCenterInlineLabelMinimumWidth
                                        + Theme.spacing.lg + controlSlot.implicitWidth)

    Layout.minimumHeight: Theme.size.controlCenterSettingRowMinimumHeight
    implicitWidth: contentLayout.implicitWidth
    implicitHeight: Math.max(Theme.size.controlCenterSettingRowMinimumHeight,
                             contentLayout.implicitHeight + Theme.spacing.md * 2)
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
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacing.sm

        GridLayout {
            id: rowLayout

            Layout.fillWidth: true
            columns: root.stacked ? 1 : 2
            columnSpacing: Theme.spacing.lg
            rowSpacing: Theme.spacing.sm

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: root.stacked ? 0 :
                                                    Theme.size.controlCenterInlineLabelMinimumWidth
                spacing: Theme.spacing.xs

                IslandText {
                    Layout.fillWidth: true
                    text: root.label
                    size: "body"
                    font.weight: Theme.type.weightSemibold
                    color: Theme.snapshot.controlFillForeground
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

            RowLayout {
                id: controlSlot

                Layout.fillWidth: root.stacked
                Layout.alignment: root.stacked ? Qt.AlignLeft : Qt.AlignRight | Qt.AlignVCenter
                spacing: 0
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
        objectName: "controlCenterSettingRowSeparator"

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: root.separatorVisible
        height: Theme.size.hairlineWidth
        color: Theme.color.surfaceBorder
        opacity: 0.72
    }
}

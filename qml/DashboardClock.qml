import QtQuick
import QtQuick.Layouts

// Minute-precision clock/date presentation. CompactClock remains the single
// clock source, so Expanded adds no timer or duplicate time state.
FocusScope {
    id: root

    required property var clock

    implicitWidth: 300
    implicitHeight: 132

    IslandPanel {
        anchors.fill: parent
        radius: Theme.radius.lg
        color: Theme.color.controlFill
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing.lg
        spacing: Theme.spacing.xs

        IslandText {
            Layout.fillWidth: true
            text: root.clock === null ? "" : root.clock.text
            textFormat: Text.PlainText
            font.pixelSize: Theme.type.display
            font.weight: Theme.type.weightRegular
            horizontalAlignment: Text.AlignHCenter
        }

        IslandText {
            Layout.fillWidth: true
            text: root.clock === null ? "" : root.clock.dateText
            textFormat: Text.PlainText
            tone: "secondary"
            font.weight: Theme.type.weightMedium
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        IslandText {
            Layout.fillWidth: true
            text: root.clock === null ? "" : root.clock.weekText
            textFormat: Text.PlainText
            tone: "muted"
            size: "caption"
            horizontalAlignment: Text.AlignHCenter
        }
    }
}

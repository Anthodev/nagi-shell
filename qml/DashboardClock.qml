import QtQuick
import QtQuick.Layouts

// CompactClock remains the sole minute/date source, so Expanded adds no timer.
FocusScope {
    id: root

    required property var clock

    implicitWidth: clockColumn.implicitWidth
    implicitHeight: clockColumn.implicitHeight

    ColumnLayout {
        id: clockColumn

        spacing: Theme.spacing.xs

        IslandText {
            objectName: "dashboardTime"
            Layout.preferredWidth: Theme.spacing.xxl * 6
            text: root.clock === null ? "" : root.clock.text
            textFormat: Text.PlainText
            font.pixelSize: Theme.type.display
            font.weight: Theme.type.weightRegular
            horizontalAlignment: Text.AlignHCenter
        }

        IslandText {
            objectName: "dashboardDate"
            Layout.fillWidth: true
            text: root.clock === null ? "" : root.clock.dateText
            textFormat: Text.PlainText
            tone: "secondary"
            font.weight: Theme.type.weightMedium
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }
}

import Quickshell
import QtQuick

PanelWindow {
    id: island

    anchors.top: true
    color: "transparent"
    exclusiveZone: 0
    implicitHeight: 36
    implicitWidth: 120
    margins.top: 8

    Rectangle {
        anchors.fill: parent
        color: "#f5080d16"
        radius: height / 2

        border.color: "#263448"
        border.width: 1
    }
}

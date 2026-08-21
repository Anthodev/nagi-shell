import Quickshell
import QtQuick

PanelWindow {
    readonly property int edgeInset: 8
    readonly property int preferredHeight: 36
    readonly property int preferredWidth: 120

    function safeLogicalSize(preferredSize, screenSize) {
        if (screenSize <= 0) {
            return preferredSize;
        }

        return Math.min(preferredSize, Math.max(1, screenSize - edgeInset * 2));
    }

    // Leave screen unassigned at creation so Qt selects the startup primary/default output.
    anchors.top: true
    color: "transparent"
    exclusiveZone: 0
    implicitHeight: safeLogicalSize(preferredHeight, screen === null ? 0 : screen.height)
    implicitWidth: safeLogicalSize(preferredWidth, screen === null ? 0 : screen.width)
    margins.top: edgeInset

    Rectangle {
        anchors.fill: parent
        color: "#f5080d16"
        radius: height / 2

        border.color: "#263448"
        border.width: 1
    }
}

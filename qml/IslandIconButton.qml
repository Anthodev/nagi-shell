import QtQuick
import QtQuick.Controls
import Quickshell.Widgets

// Icon button primitive: circular button rendering a single icon. The icon
// accepts any image URL, including Quickshell icon URLs for theme icons.
// States match IslandButton; disabled controls flatten instead of changing
// hue.
AbstractButton {
    id: control

    property string source: ""
    property string size: "md"
    property string label: ""

    focusPolicy: Qt.StrongFocus
    hoverEnabled: true
    implicitWidth: size === "sm" ? Theme.size.controlHeightSm : size === "lg"
                                   ? Theme.size.controlHeightLg : Theme.size.controlHeightMd
    implicitHeight: implicitWidth
    opacity: enabled ? 1 : Theme.opacity.disabled

    scale: pressed ? 0.95 : 1

    Behavior on scale {
        NumberAnimation {
            duration: Theme.motion.durationFast
            easing.type: Theme.motion.easingStandard
        }
    }

    function fillColor() {
        if (!enabled) {
            return Theme.color.controlFill;
        }
        return pressed ? Theme.color.controlFillPressed : hovered ? Theme.color.controlFillHover :
                                                                    Theme.color.controlFill;
    }

    function outlineColor() {
        if (!enabled) {
            return "transparent";
        }
        return pressed ? Theme.color.surfaceBorderPressed : hovered
                         ? Theme.color.surfaceBorderHover : Theme.color.surfaceBorder;
    }

    background: IslandPanel {
        color: control.fillColor()
        border.color: control.outlineColor()
    }

    contentItem: Item {
        IconImage {
            anchors.centerIn: parent
            source: control.source
            implicitSize: control.size === "sm" ? Theme.size.iconSizeSm : control.size === "lg"
                                                  ? Theme.size.iconSizeLg : Theme.size.iconSizeMd
        }
    }

    IslandFocusRing {
        visible: control.visualFocus
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        enabled: control.enabled
    }

    Keys.onTabPressed: {
        const next = control.nextItemInFocusChain(true);
        if (next !== null) {
            next.forceActiveFocus(Qt.TabFocusReason);
        }
    }

    Keys.onBacktabPressed: {
        const previous = control.nextItemInFocusChain(false);
        if (previous !== null) {
            previous.forceActiveFocus(Qt.BacktabFocusReason);
        }
    }

    Accessible.role: Accessible.Button
    Accessible.name: control.label
}

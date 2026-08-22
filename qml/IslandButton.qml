import QtQuick
import QtQuick.Controls

// Button primitive: text button with standard, accent, and danger variants.
// Renders hover, pressed, keyboard-focus, and disabled states. The focus ring
// appears only for keyboard focus, and disabled controls flatten (dimmed
// content, no border) instead of changing hue.
AbstractButton {
    id: control

    property string variant: "standard"
    property string label: ""

    focusPolicy: Qt.StrongFocus
    hoverEnabled: true
    leftPadding: Theme.spacing.md
    rightPadding: Theme.spacing.md
    topPadding: Theme.spacing.xs
    bottomPadding: Theme.spacing.xs
    implicitHeight: Theme.size.controlHeightMd
    implicitWidth: implicitContentWidth + leftPadding + rightPadding
    opacity: enabled ? 1 : Theme.opacity.disabled

    scale: pressed ? 0.97 : 1

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
        if (variant === "accent") {
            return pressed ? Theme.color.accentPressed : hovered ? Theme.color.accentHover :
                                                                   Theme.color.accent;
        }
        if (variant === "danger") {
            return pressed ? Theme.color.dangerFillPressed : hovered ? Theme.color.dangerFillHover :
                                                                       Theme.color.dangerFill;
        }
        return pressed ? Theme.color.controlFillPressed : hovered ? Theme.color.controlFillHover :
                                                                    Theme.color.controlFill;
    }

    function contentColor() {
        if (variant === "accent") {
            return Theme.color.accentForeground;
        }
        if (variant === "danger") {
            return Theme.color.danger;
        }
        return Theme.color.textPrimary;
    }

    function outlineColor() {
        if (variant !== "standard" || !enabled) {
            return "transparent";
        }
        return pressed ? Theme.color.surfaceBorderPressed : hovered
                         ? Theme.color.surfaceBorderHover : Theme.color.surfaceBorder;
    }

    background: IslandPanel {
        color: control.fillColor()
        border.color: control.outlineColor()
    }

    contentItem: IslandText {
        text: control.label
        size: "body"
        font.weight: Theme.type.weightMedium
        color: control.contentColor()
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
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

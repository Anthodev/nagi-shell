import QtQuick
import QtQuick.Controls

ControlCenterSettingRow {
    id: root

    required property bool value
    property bool writable: true

    signal valueRequested(bool value)
    function requestToggle() {
        if (!writable) {
            return false;
        }
        valueRequested(!value);
        return true;
    }

    AbstractButton {
        id: toggle

        width: Theme.spacing.xxl + Theme.spacing.md
        height: Theme.size.controlHeightMd
        enabled: root.writable
        focusPolicy: Qt.StrongFocus
        hoverEnabled: true
        opacity: enabled ? 1 : Theme.opacity.disabled
        Accessible.role: Accessible.CheckBox
        Accessible.name: root.label
        Accessible.description: root.description
        Accessible.checked: root.value
        onClicked: root.requestToggle()

        background: Rectangle {
            radius: Theme.radius.md
            color: root.value ? toggle.pressed ? Theme.snapshot.accentPressed : toggle.hovered
                                                 ? Theme.snapshot.accentHover :
                                                   Theme.snapshot.accent : toggle.pressed
                                                   ? Theme.snapshot.controlFillPressed :
                                                     toggle.hovered
                                                     ? Theme.snapshot.controlFillHover :
                                                       Theme.color.controlFill
            border.width: Theme.size.hairlineWidth
            border.color: toggle.visualFocus ? Theme.snapshot.focusRing : toggle.enabled
                                               ? Theme.color.surfaceBorder : "transparent"

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: root.value ? parent.width - width - Theme.spacing.xs : Theme.spacing.xs
                width: Theme.spacing.lg
                height: width
                radius: width / 2
                color: root.value ? Theme.snapshot.accentForeground : Theme.color.textPrimary
            }
        }

        IslandFocusRing {
            visible: toggle.visualFocus
            controlRadius: Theme.radius.md
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            enabled: toggle.enabled
        }
    }
}

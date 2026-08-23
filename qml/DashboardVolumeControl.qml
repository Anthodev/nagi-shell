import QtQuick
import QtQuick.Controls

// Pointer and keyboard gestures emit requests while the confirmed adapter value
// remains authoritative for the visible track and accessibility state.
Control {
    id: root

    required property string label
    required property bool available
    required property var volume
    required property bool muted
    required property bool overamplified
    required property bool pendingVolume

    signal volumeRequested(real value, bool finalValue)

    readonly property real confirmedVolume: typeof volume === "number" && Number.isFinite(volume)
                                            ? Math.min(1, Math.max(0, volume)) : 0
    readonly property string percentageText: Math.round(confirmedVolume * 100) + "%"
    readonly property string stateText: !available ? "Unavailable" : pendingVolume
                                                     ? "Pending · confirmed " + percentageText :
                                                       muted ? "Muted · " + percentageText :
                                                               percentageText + (overamplified
                                                                                 ? " · Amplified" :
                                                                                   "")

    implicitWidth: track.implicitWidth
    implicitHeight: track.implicitHeight
    focusPolicy: enabled ? Qt.StrongFocus : Qt.NoFocus
    enabled: available
    opacity: enabled ? 1 : Theme.opacity.disabled
    Accessible.role: Accessible.Slider
    Accessible.name: label
    Accessible.description: stateText

    function request(value, finalValue) {
        if (!available || typeof value !== "number" || !Number.isFinite(value)) {
            return false;
        }
        volumeRequested(Math.min(1, Math.max(0, value)), finalValue === true);
        return true;
    }

    function requestAt(x, finalValue) {
        return request(track.width <= 0 ? 0 : x / track.width, finalValue);
    }

    function requestStep(offset) {
        return request(confirmedVolume + offset, true);
    }

    Keys.priority: Keys.BeforeItem
    Keys.onLeftPressed: event => {
        root.requestStep(-0.05);
        event.accepted = true;
    }
    Keys.onDownPressed: event => {
        root.requestStep(-0.05);
        event.accepted = true;
    }
    Keys.onRightPressed: event => {
        root.requestStep(0.05);
        event.accepted = true;
    }
    Keys.onUpPressed: event => {
        root.requestStep(0.05);
        event.accepted = true;
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Home) {
            root.request(0, true);
            event.accepted = true;
        } else if (event.key === Qt.Key_End) {
            root.request(1, true);
            event.accepted = true;
        }
    }

    contentItem: Item {
        id: track

        implicitWidth: Theme.spacing.xxl * 7
        implicitHeight: Theme.size.controlHeightSm

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Theme.size.progressBarHeight
            radius: height / 2
            color: Theme.color.progressTrack
        }

        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * root.confirmedVolume
            height: Theme.size.progressBarHeight
            radius: height / 2
            color: Theme.color.progressFill
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(parent.width - width, parent.width * root.confirmedVolume
                                    - width / 2))
            width: Theme.spacing.md
            height: width
            radius: width / 2
            color: Theme.color.textPrimary
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            onPressed: mouse => {
                root.forceActiveFocus(Qt.MouseFocusReason);
                root.requestAt(mouse.x, false);
            }
            onPositionChanged: mouse => {
                if (pressed) {
                    root.requestAt(mouse.x, false);
                }
            }
            onReleased: mouse => root.requestAt(mouse.x, true)
        }
    }

    background: IslandFocusRing {
        objectName: root.label === "Output" ? "dashboardOutputVolumeFocusRing" :
                                              "dashboardInputVolumeFocusRing"
        controlRadius: Theme.radius.sm
        visible: root.visualFocus
    }
}

import QtQuick
import QtQuick.Layouts

// A backend-confirmed volume control. Pointer and keyboard gestures emit
// requests, while the track and value remain bound to confirmed adapter state.
FocusScope {
    id: root

    required property string label
    required property bool available
    required property var volume
    required property bool muted
    required property bool overamplified
    required property bool pendingVolume
    required property bool pendingMute

    signal volumeRequested(real value, bool finalValue)
    signal muteRequested(bool muted)

    readonly property real confirmedVolume: typeof volume === "number" && Number.isFinite(volume)
                                            ? Math.min(1, Math.max(0, volume)) : 0
    readonly property string stateText: !available ? "Unavailable" : pendingVolume || pendingMute
                                                     ? "Pending · confirmed " + Math.round(
                                                           confirmedVolume * 100) + "%" : muted
                                                       ? "Muted · " + Math.round(confirmedVolume
                                                                                 * 100) + "%" :
                                                         Math.round(confirmedVolume * 100) + (
                                                             overamplified ? "% · Amplified" : "%")

    implicitHeight: 48
    activeFocusOnTab: enabled
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

    RowLayout {
        anchors.fill: parent
        spacing: Theme.spacing.sm

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.xs

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.sm

                IslandText {
                    Layout.fillWidth: true
                    text: root.label
                    textFormat: Text.PlainText
                    font.weight: Theme.type.weightMedium
                }

                IslandText {
                    text: root.stateText
                    textFormat: Text.PlainText
                    tone: root.pendingVolume || root.pendingMute ? "secondary" : "muted"
                    size: "caption"
                }
            }

            Item {
                id: track

                Layout.fillWidth: true
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
                    color: Theme.color.accent
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(0, Math.min(parent.width - width, parent.width
                                            * root.confirmedVolume - width / 2))
                    width: Theme.spacing.md
                    height: width
                    radius: width / 2
                    color: Theme.color.textPrimary
                    border.width: Theme.size.hairlineWidth
                    border.color: Theme.color.surfaceBorderPressed
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
        }

        IslandButton {
            objectName: root.label === "Output" ? "dashboardOutputMute" : "dashboardInputMute"
            label: root.muted ? "Unmute" : "Mute"
            enabled: root.available && !root.pendingMute
            Accessible.description: (root.muted ? "Unmute " : "Mute ") + root.label.toLowerCase()
            onClicked: root.muteRequested(!root.muted)
        }
    }

    IslandFocusRing {
        visible: root.activeFocus
    }
}

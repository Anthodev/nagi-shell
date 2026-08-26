import QtQuick
import QtQuick.Controls

ControlCenterSettingRow {
    id: root

    required property real value
    required property real from
    required property real to
    property real stepSize: 1
    property string valueText: String(value)
    property bool writable: true

    signal valueRequested(real value, bool continuous)

    function bounded(candidate) {
        if (!Number.isFinite(candidate) || to <= from) {
            return from;
        }
        const stepped = Math.round((candidate - from) / stepSize) * stepSize + from;
        return Math.max(from, Math.min(to, stepped));
    }

    function requestAt(position, continuous) {
        valueRequested(bounded(from + Math.max(0, Math.min(1, position)) * (to - from)),
                       continuous);


        return true;
    }

    Row {
        spacing: Theme.spacing.sm

        Control {
            id: slider

            width: Theme.spacing.xxl * 5
            height: Theme.size.controlHeightMd
            enabled: root.writable
            focusPolicy: Qt.StrongFocus
            Accessible.role: Accessible.Slider
            Accessible.name: root.label
            Accessible.description: root.description + ". Current value: " + root.valueText

            readonly property real ratio: root.to <= root.from ? 0 : (root.value - root.from) / (
                                                                     root.to - root.from)

            Keys.onLeftPressed: event => {
                root.valueRequested(root.bounded(root.value - root.stepSize), true);
                event.accepted = true;
            }
            Keys.onRightPressed: event => {
                root.valueRequested(root.bounded(root.value + root.stepSize), true);
                event.accepted = true;
            }
            Keys.onReleased: event => {
                if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                    root.valueRequested(root.value, false);
                    event.accepted = true;
                }
            }

            contentItem: Item {
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
                    width: parent.width * Math.max(0, Math.min(1, slider.ratio))
                    height: Theme.size.progressBarHeight
                    radius: height / 2
                    color: Theme.color.progressFill
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(0, Math.min(parent.width - width, parent.width * slider.ratio
                                            - width / 2))
                    width: Theme.spacing.md
                    height: width
                    radius: width / 2
                    color: Theme.color.textPrimary
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: slider.enabled
                    onPressed: mouse => {
                        slider.forceActiveFocus(Qt.MouseFocusReason);
                        root.requestAt(mouse.x / Math.max(1, width), true);
                    }
                    onPositionChanged: mouse => {
                        if (pressed) {
                            root.requestAt(mouse.x / Math.max(1, width), true);
                        }
                    }
                    onReleased: mouse => root.requestAt(mouse.x / Math.max(1, width), false)
                }
            }

            background: IslandFocusRing {
                visible: slider.visualFocus
                controlRadius: Theme.radius.sm
            }
        }

        IslandText {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.spacing.xxl
            text: root.valueText
            size: "caption"
            horizontalAlignment: Text.AlignRight
            Accessible.ignored: true
        }
    }
}

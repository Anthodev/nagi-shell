import QtQuick

// Progress primitive: determinate or indeterminate horizontal progress.
// Progress is communicated by geometry and, when indeterminate, by motion —
// never by hue alone.
Item {
    id: bar

    property real value: 0
    property bool indeterminate: false
    property string label: ""
    property real phase: 0

    readonly property real effectiveValue: Math.min(1, Math.max(0, value))

    implicitWidth: Theme.size.islandIdleWidth
    implicitHeight: Theme.size.progressBarHeight
    opacity: enabled ? 1 : Theme.opacity.disabled

    Rectangle {
        id: track

        anchors.fill: parent
        radius: height / 2
        color: Theme.color.progressTrack
    }

    Rectangle {
        id: fill

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: bar.indeterminate ? bar.width * Theme.size.progressIndeterminateSpan : bar.width
                                   * bar.effectiveValue
        x: bar.indeterminate ? (bar.width + width) * bar.phase - width : 0
        radius: height / 2
        color: Theme.color.accent
        visible: bar.indeterminate || bar.effectiveValue > 0

        NumberAnimation {
            target: bar
            property: "phase"
            running: bar.indeterminate && bar.enabled && bar.visible
            loops: Animation.Infinite
            from: 0
            to: 1
            duration: Theme.motion.durationSlow
            easing.type: Theme.motion.easingStandard
        }
    }

    Accessible.role: Accessible.ProgressBar
    Accessible.name: bar.label
}

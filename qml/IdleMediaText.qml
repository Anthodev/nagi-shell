pragma ComponentBehavior: Bound

import QtQuick

// Bounded compact media label for the idle island.
//
// Renders the adapter's plain-text "Artist — Track" summary. Text that fits
// stays static; overflow starts one slow marquee loop after a delay, pauses
// at both endpoints, and only runs while the island is visible, the media is
// available, and motion is allowed. Reduced motion renders a static ellipsis
// instead. A hidden label performs no animation or painting work.
Item {
    id: media

    property string summary: ""
    property int maximumWidth: Theme.size.islandIdleMediaMaximumWidth
    property bool scrolling: false
    property bool reducedMotion: false

    // Verification seams for the bounded marquee timing; production values
    // keep the motion calm.
    property int startDelayMs: 2500
    property int endpointPauseMs: 1400
    property int pixelsPerSecond: 24

    readonly property int viewportWidth: Math.max(0, maximumWidth)
    readonly property bool overflowing: label.implicitWidth > viewportWidth
    readonly property real scrollDistance: overflowing ? label.implicitWidth - viewportWidth : 0
    readonly property int scrollDurationMs: scrollDistance > 1 ? Math.max(1, Math.round(
                                                                              scrollDistance
                                                                              / pixelsPerSecond
                                                                              * 1000)) : 1
    readonly property bool marqueeEligible: scrolling && visible && summary !== "" && overflowing
                                            && !reducedMotion

    implicitWidth: Math.min(label.implicitWidth, viewportWidth)
    implicitHeight: label.implicitHeight
    clip: true

    function resetScroll() {
        marquee.stop();
        label.x = 0;
    }

    // Verification seams: the animated text item and its marquee state.
    readonly property alias labelItem: label
    readonly property alias marqueeRunning: marquee.running

    onSummaryChanged: resetScroll()
    onOverflowingChanged: resetScroll()
    onReducedMotionChanged: resetScroll()
    onScrollingChanged: {
        if (!scrolling) {
            resetScroll();
        }
    }

    IslandText {
        id: label

        text: media.summary
        tone: "secondary"
        size: "body"
        font.weight: Theme.type.weightRegular
        elide: media.reducedMotion ? Text.ElideRight : Text.ElideNone
    }

    SequentialAnimation {
        id: marquee

        running: media.marqueeEligible
        loops: Animation.Infinite

        PauseAnimation {
            duration: media.startDelayMs
        }

        NumberAnimation {
            target: label
            property: "x"
            to: -media.scrollDistance
            duration: media.scrollDurationMs
            easing.type: Easing.Linear
        }

        PauseAnimation {
            duration: media.endpointPauseMs
        }

        NumberAnimation {
            target: label
            property: "x"
            to: 0
            duration: media.scrollDurationMs
            easing.type: Easing.Linear
        }

        PauseAnimation {
            duration: media.endpointPauseMs
        }
    }
}

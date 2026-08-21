import QtQuick

// Focus primitive: an offset keyboard-focus ring hugging the owner geometry
// from the outside. Bind `visible` to the owner's keyboard-focus signal (for
// example `control.visualFocus`). The ring is a shape cue, so keyboard focus
// never relies on hue alone.
Rectangle {
    id: ring

    anchors.fill: parent
    anchors.margins: -(Theme.size.focusRingGap)
    radius: Theme.radius.pill
    color: "transparent"

    border.color: Theme.color.focusRing
    border.width: Theme.size.focusRingWidth
    visible: false
}

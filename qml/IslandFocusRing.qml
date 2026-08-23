import QtQuick

// Focus primitive: an offset keyboard-focus ring hugging the owner geometry
// from the outside. Bind `visible` to the owner's keyboard-focus signal (for
// example `control.visualFocus`). The ring is a shape cue, so keyboard focus
// never relies on hue alone.
Rectangle {
    id: ring

    objectName: "islandFocusRing"
    property real controlRadius: Theme.radius.md
    anchors.fill: parent
    anchors.margins: -(Theme.size.focusRingGap)
    radius: controlRadius + Theme.size.focusRingGap
    color: "transparent"

    border.color: Theme.snapshot.focusRing
    border.width: Theme.size.focusRingWidth
    visible: false
}

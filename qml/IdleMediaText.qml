pragma ComponentBehavior: Bound

import QtQuick

// Bounded compact media label for the idle island.
//
// Idle is event-driven: long summaries use a static ellipsis instead of a
// marquee that would continuously wake the scene graph. Expanded media keeps
// the detailed metadata available when the user asks for it.
Item {
    id: media

    property string summary: ""
    property int maximumWidth: Theme.size.islandIdleMediaMaximumWidth

    readonly property int viewportWidth: Math.max(0, maximumWidth)
    readonly property bool overflowing: label.implicitWidth > viewportWidth

    implicitWidth: Math.min(label.implicitWidth, viewportWidth)
    implicitHeight: label.implicitHeight
    clip: true

    // Verification seam for the bounded static text.
    readonly property alias labelItem: label

    IslandText {
        id: label

        width: media.viewportWidth
        text: media.summary
        tone: "secondary"
        size: "body"
        font.weight: Theme.type.weightRegular
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
    }
}

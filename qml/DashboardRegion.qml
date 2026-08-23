import QtQuick

// Mounts one real dashboard contribution ahead of the expansion morph. Null
// content still removes the region completely; visibility only controls
// presentation, so entering Expanded never constructs the content mid-frame.
Item {
    id: region

    property Component content: null
    property bool active: true

    readonly property Item item: contentLoader.item
    readonly property bool ready: contentLoader.status === Loader.Ready && item !== null

    visible: active && ready
    implicitWidth: ready ? item.implicitWidth : 0
    implicitHeight: ready ? item.implicitHeight : 0
    clip: true

    Loader {
        id: contentLoader

        anchors.fill: parent
        active: region.content !== null
        visible: region.active
        sourceComponent: region.content
    }
}

import QtQuick

// Mounts one dashboard contribution only while Expanded owns preparation or
// presentation work. Retained outgoing pixels are owned by IslandSurface, so
// releasing this Loader immediately cannot expose an empty transition frame.
Item {
    id: region

    property Component content: null
    property bool active: true
    property bool presentationExcluded: false

    readonly property Item item: contentLoader.item
    readonly property bool ready: contentLoader.status === Loader.Ready && item !== null

    visible: active && ready
    implicitWidth: ready ? item.implicitWidth : 0
    implicitHeight: ready ? item.implicitHeight : 0
    clip: true

    Loader {
        id: contentLoader

        anchors.fill: parent
        active: region.active && region.content !== null
        visible: active
        opacity: region.presentationExcluded ? 0 : 1
        sourceComponent: region.content
    }
}

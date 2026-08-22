import QtQuick

// Lazily mounts one real dashboard contribution. Null content removes the
// region completely, so unavailable downstream features never leave a card,
// label, or inert control behind.
Item {
    id: region

    property Component content: null
    property bool active: true

    readonly property Item item: contentLoader.item
    readonly property bool ready: contentLoader.status === Loader.Ready && item !== null

    visible: active && content !== null
    implicitWidth: ready ? item.implicitWidth : 0
    implicitHeight: ready ? item.implicitHeight : 0
    clip: true

    Loader {
        id: contentLoader

        anchors.fill: parent
        active: region.visible
        sourceComponent: region.content
    }
}

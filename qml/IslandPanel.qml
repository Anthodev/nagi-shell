import QtQuick

// Semantic surface primitive. Inner controls use the medium radius by default;
// outer island surfaces opt into the outer radius explicitly.
Rectangle {
    id: panel

    implicitWidth: Theme.size.islandIdleWidth
    implicitHeight: Theme.size.islandIdleHeight
    radius: Theme.radius.md
    color: Theme.color.surface

    border.color: "transparent"
    border.width: border.color.a > 0 ? Theme.size.hairlineWidth : 0
}

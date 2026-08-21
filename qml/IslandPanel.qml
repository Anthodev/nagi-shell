import QtQuick

// Surface primitive: the rounded card every island region renders on. All
// visuals come from Theme tokens; consumers may override `radius` for nested
// cards but must keep using tokens.
Rectangle {
    id: panel

    implicitWidth: Theme.size.islandIdleWidth
    implicitHeight: Theme.size.islandIdleHeight
    radius: Theme.radius.pill
    color: Theme.color.surface

    border.color: Theme.color.surfaceBorder
    border.width: Theme.size.hairlineWidth
}

pragma ComponentBehavior: Bound

import Quickshell.Widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

// Presentation-only tray row. It renders normalized snapshots and delegates
// every platform action back to TrayAdapter.
FocusScope {
    id: root

    required property var adapter

    readonly property int itemCount: adapter === null ? 0 : adapter.items.length
    readonly property bool empty: itemCount === 0
    readonly property int controlExtent: Theme.size.controlHeightMd
    readonly property var currentItem: trayList.currentItem

    implicitHeight: empty ? 0 : column.implicitHeight
    visible: !empty

    function menuPosition(button) {
        return button.mapToItem(null, button.width / 2, button.height);
    }

    function openMenu(token, button) {
        if (adapter === null || button === null || button.Window.window === null) {
            return "rejected";
        }
        const position = menuPosition(button);
        return adapter.openMenu(token, button.Window.window, position.x, position.y);
    }

    function primaryAction(item, button) {
        if (adapter === null || item === null) {
            return "rejected";
        }
        return item.onlyMenu ? openMenu(item.token, button) : adapter.activate(item.token);
    }

    function secondaryAction(item) {
        if (adapter === null || item === null) {
            return "rejected";
        }
        return adapter.secondaryActivate(item.token);
    }

    function moveFocus(index, offset) {
        if (itemCount <= 0) {
            return;
        }
        const targetIndex = (index + offset + itemCount) % itemCount;
        trayList.currentIndex = targetIndex;
        const target = trayList.itemAtIndex(targetIndex);
        if (target !== null) {
            target.forceActiveFocus(Qt.TabFocusReason);
        }
    }

    ColumnLayout {
        id: column

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.spacing.sm

        IslandText {
            text: "System tray"
            tone: "secondary"
            size: "caption"
            font.weight: Font.Medium
        }

        ListView {
            id: trayList

            objectName: "trayItemList"
            Layout.fillWidth: true
            Layout.preferredHeight: root.controlExtent
            orientation: ListView.Horizontal
            spacing: Theme.spacing.sm
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: false
            model: root.adapter === null ? [] : root.adapter.items

            delegate: AbstractButton {
                id: button

                required property int index
                required property var modelData
                objectName: "trayItemButton"
                width: root.controlExtent
                height: root.controlExtent
                focusPolicy: Qt.StrongFocus
                hoverEnabled: true
                Accessible.role: Accessible.Button
                Accessible.name: modelData.label
                Accessible.description: modelData.hasMenu
                                        ? "System tray item; context menu available" :
                                          "System tray item"

                onClicked: root.primaryAction(modelData, button)

                Keys.priority: Keys.BeforeItem
                Keys.onLeftPressed: event => {
                    root.moveFocus(index, -1);
                    event.accepted = true;
                }
                Keys.onRightPressed: event => {
                    root.moveFocus(index, 1);
                    event.accepted = true;
                }
                Keys.onPressed: event => {
                    if (modelData.hasMenu && (event.key === Qt.Key_Menu || (event.key
                                                                            === Qt.Key_F10 && (
                                                                                event.modifiers
                                                                                & Qt.ShiftModifier)))) {
                        root.openMenu(modelData.token, button);
                        event.accepted = true;
                    }
                }
                Keys.onTabPressed: {
                    const next = button.nextItemInFocusChain(true);
                    if (next !== null) {
                        next.forceActiveFocus(Qt.TabFocusReason);
                    }
                }
                Keys.onBacktabPressed: {
                    const previous = button.nextItemInFocusChain(false);
                    if (previous !== null) {
                        previous.forceActiveFocus(Qt.BacktabFocusReason);
                    }
                }

                background: IslandPanel {
                    color: button.pressed ? Theme.color.controlFillPressed : button.hovered
                                            ? Theme.color.controlFillHover : Theme.color.controlFill
                    border.color: button.modelData.status === "needsAttention" ? Theme.color.accent :
                                                                                 button.hovered
                                                                                 ? Theme.color.surfaceBorderHover :
                                                                                   Theme.color.surfaceBorder
                }

                contentItem: Item {
                    IslandText {
                        anchors.centerIn: parent
                        visible: trayIcon.status !== Image.Ready
                        text: button.modelData.label.slice(0, 1).toUpperCase()
                        tone: "secondary"
                        font.weight: Font.DemiBold
                    }

                    Image {
                        id: trayIcon

                        anchors.centerIn: parent
                        width: Theme.size.iconSizeMd
                        height: Theme.size.iconSizeMd
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                        source: button.modelData.iconSource
                        sourceSize.width: Theme.size.iconSizeMd
                        sourceSize.height: Theme.size.iconSizeMd
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: Theme.spacing.xs
                        width: 5
                        height: 5
                        radius: width / 2
                        color: Theme.color.accent
                        visible: button.modelData.status === "needsAttention"
                    }
                }

                IslandFocusRing {
                    visible: button.visualFocus
                }

                ToolTip.delay: 500
                ToolTip.visible: button.hovered
                ToolTip.text: modelData.tooltip

                TapHandler {
                    acceptedButtons: Qt.RightButton
                    enabled: button.modelData.hasMenu
                    onTapped: root.openMenu(button.modelData.token, button)
                }

                TapHandler {
                    acceptedButtons: Qt.MiddleButton
                    onTapped: root.secondaryAction(button.modelData)
                }
            }
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

// Presentation-only normalized tray content inside the shared interactive frame.
FocusScope {
    id: root

    required property var adapter
    required property real ownerEpoch
    property bool active: true
    property bool reducedMotion: false
    property var menuParentWindow: null

    readonly property int itemCount: adapter === null ? 0 : adapter.items.length
    readonly property bool empty: itemCount === 0
    readonly property int controlExtent: Theme.size.controlHeightMd
    readonly property int gridCellExtent: controlExtent + Theme.spacing.sm
    readonly property int maximumGridColumns: 5
    readonly property int maximumVisibleRows: 3
    readonly property int maximumVisibleItems: maximumGridColumns * maximumVisibleRows
    readonly property int gridColumns: Math.min(maximumGridColumns, Math.max(1, itemCount))
    readonly property int gridRows: Math.max(1, Math.ceil(itemCount / gridColumns))
    readonly property int visibleGridRows: Math.min(gridRows, maximumVisibleRows)
    readonly property bool gridScrollVisible: gridRows > maximumVisibleRows
    readonly property real gridViewportWidth: gridColumns * controlExtent + Math.max(0, gridColumns
                                                                                     - 1) * Theme.spacing.sm
    readonly property real gridViewportHeight: visibleGridRows * controlExtent + Math.max(0,
                                                                                          visibleGridRows
                                                                                          - 1) * Theme.spacing.sm
    readonly property real contentWidth: empty ? Theme.spacing.xxl * 4 : gridViewportWidth
    readonly property var currentItem: trayList.currentItem === null ? null :
                                                                       trayList.currentItem.control

    readonly property bool trayFocused: trayList.activeFocus
    readonly property bool backFocused: frame.backControl.activeFocus

    implicitWidth: frame.implicitWidth
    implicitHeight: frame.implicitHeight
    visible: active

    signal cancelled(real ownerEpoch)
    signal externalActionDispatched
    signal shellMenuOpening
    signal shellMenuOpenResult(string result)

    Connections {
        target: root.adapter
        ignoreUnknownSignals: true

        function onMenuActionTriggered(token) {
            if (!root.active) {
                return;
            }
            for (let index = 0; index < root.adapter.items.length; ++index) {
                if (root.adapter.items[index].token === token) {
                    root.externalActionDispatched();
                    return;
                }
            }
        }
    }

    function focusInitialControl() {
        if (trayList.count > 0) {
            trayList.currentIndex = Math.max(0, trayList.currentIndex);
            const item = trayList.itemAtIndex(trayList.currentIndex);
            if (item !== null) {
                item.forceActiveFocus(Qt.ShortcutFocusReason);
                return true;
            }
        }
        return frame.focusInitialControl();
    }

    function menuPosition(button) {
        return button.mapToItem(null, button.width / 2, button.height);
    }

    function completeExternalAction(result) {
        if (result === "dispatched") {
            externalActionDispatched();
        }
        return result;
    }

    function openMenu(token, button) {
        if (adapter === null || button === null || menuParentWindow === null) {
            return "rejected";
        }
        const position = menuPosition(button);
        shellMenuOpening();
        const result = adapter.openMenu(token, menuParentWindow, position.x, position.y);
        shellMenuOpenResult(result);
        return result;
    }

    function primaryAction(item, button) {
        if (adapter === null || item === null) {
            return "rejected";
        }
        return item.onlyMenu ? openMenu(item.token, button) : completeExternalAction(
                                   adapter.activate(item.token));
    }

    function secondaryAction(item) {
        if (adapter === null || item === null) {
            return "rejected";
        }
        return completeExternalAction(adapter.secondaryActivate(item.token));
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

    SubviewFrame {
        id: frame

        anchors.fill: parent
        active: root.active
        title: "System tray"
        reducedMotion: root.reducedMotion
        initialFocusItem: root.currentItem
        onBackRequested: root.cancelled(root.ownerEpoch)
        onEscapePressed: root.cancelled(root.ownerEpoch)

        Item {
            id: gridContainer

            implicitWidth: root.contentWidth
            implicitHeight: root.gridViewportHeight
            width: implicitWidth
            height: implicitHeight
            clip: true

            // GridView counts whole cells, so its layout viewport includes one
            // extra gap. Centering each control in that cell and clipping half
            // a gap at both edges yields exact token gaps with no trailing blank.
            GridView {
                id: trayList

                objectName: "trayItemList"
                x: -Theme.spacing.sm / 2
                y: -Theme.spacing.sm / 2
                width: parent.width + Theme.spacing.sm
                height: parent.height + Theme.spacing.sm
                clip: false
                interactive: root.gridScrollVisible
                cellWidth: root.gridCellExtent
                cellHeight: root.gridCellExtent
                keyNavigationEnabled: false
                model: root.adapter === null ? [] : root.adapter.items

                delegate: FocusScope {
                    id: cell

                    required property int index
                    required property var modelData
                    readonly property alias control: trayButton
                    width: root.gridCellExtent
                    height: root.gridCellExtent

                    function forceActiveFocus(reason) {
                        trayButton.forceActiveFocus(reason);
                    }

                    AbstractButton {
                        id: trayButton

                        readonly property bool attention: cell.modelData.status === "needsAttention"
                        readonly property var modelData: cell.modelData
                        objectName: "trayItemButton"
                        anchors.centerIn: parent
                        width: root.controlExtent
                        height: root.controlExtent
                        focusPolicy: Qt.StrongFocus
                        hoverEnabled: true
                        Accessible.role: Accessible.Button
                        Accessible.name: cell.modelData.label
                        Accessible.description: cell.modelData.hasMenu
                                                ? "System tray item; context menu available" :
                                                  "System tray item"

                        onClicked: root.primaryAction(cell.modelData, trayButton)

                        Keys.priority: Keys.BeforeItem
                        Keys.onLeftPressed: event => {
                            root.moveFocus(cell.index, -1);
                            event.accepted = true;
                        }
                        Keys.onRightPressed: event => {
                            root.moveFocus(cell.index, 1);
                            event.accepted = true;
                        }
                        Keys.onUpPressed: event => {
                            root.moveFocus(cell.index, -root.gridColumns);
                            event.accepted = true;
                        }
                        Keys.onDownPressed: event => {
                            root.moveFocus(cell.index, root.gridColumns);
                            event.accepted = true;
                        }
                        Keys.onPressed: event => {
                            if (cell.modelData.hasMenu && (event.key === Qt.Key_Menu || (event.key
                                                                                         === Qt.Key_F10
                                                                                         && (event.modifiers
                                                                                             & Qt.ShiftModifier)))) {
                                root.openMenu(cell.modelData.token, trayButton);
                                event.accepted = true;
                            }
                        }

                        background: Rectangle {
                            radius: Theme.radius.md
                            color: trayButton.pressed ? Theme.color.surfaceActive :
                                                        trayButton.hovered
                                                        ? Theme.color.surfaceHover :
                                                          trayButton.attention
                                                          ? Theme.color.surfaceActive :
                                                            "transparent"
                        }

                        contentItem: Item {
                            IslandText {
                                objectName: "trayApplicationFallbackLetter"
                                anchors.centerIn: parent
                                visible: trayIcon.showingFallback
                                text: cell.modelData.label.slice(0, 1).toUpperCase()
                                tone: "secondary"
                                font.weight: Font.DemiBold
                            }

                            IslandIcon {
                                id: trayIcon

                                objectName: "trayApplicationIcon"
                                anchors.centerIn: parent
                                visible: !showingFallback
                                meaning: "trayApplication"
                                semanticState: "normal"
                                size: "md"
                                applicationSource: cell.modelData.iconSource
                                applicationName: cell.modelData.label
                            }

                            Rectangle {
                                objectName: "trayAttentionDot"
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: Theme.spacing.xs
                                width: 5
                                height: 5
                                radius: width / 2
                                color: Theme.snapshot.accent
                                visible: trayButton.attention
                            }
                        }

                        IslandFocusRing {
                            visible: trayButton.visualFocus
                        }

                        ToolTip.delay: Theme.motion.durationSlow
                        ToolTip.visible: trayButton.hovered || trayButton.visualFocus
                        ToolTip.text: cell.modelData.tooltip === "" ? cell.modelData.label :
                                                                      cell.modelData.tooltip

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton | Qt.MiddleButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton && cell.modelData.hasMenu) {
                                    root.openMenu(cell.modelData.token, trayButton);
                                } else if (mouse.button === Qt.MiddleButton) {
                                    root.secondaryAction(cell.modelData);
                                }
                            }
                        }
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    objectName: "trayGridScrollBar"
                    policy: root.gridScrollVisible ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                }
            }

            IslandText {
                anchors.centerIn: parent
                visible: root.empty
                text: "No tray items"
                textFormat: Text.PlainText
                tone: "secondary"
            }
        }
    }
}

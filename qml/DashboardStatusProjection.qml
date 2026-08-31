pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Presentation-only projection over the authoritative tray adapter. The
// adapter keeps item state and menu ownership; this component only selects the
// bounded active/attention subset used by the Expanded glance spine.
FocusScope {
    id: root

    required property var tray
    property var menuParentWindow: null
    property bool active: true

    readonly property var emptyStatusItems: Object.freeze([])
    readonly property var statusItems: active && tray !== null ? projectTrayItems(tray.items) :
                                                                 emptyStatusItems

    readonly property int delegateCount: statusRepeater.count
    property int openedMenuToken: 0

    objectName: "dashboardStatusLane"
    visible: active && statusItems.length > 0
    implicitWidth: Theme.spacing.xxl * 6
    implicitHeight: statusItems.length > 0 ? statusGroup.implicitHeight + Theme.size.focusRingGap * 2 :
                                             0

    signal externalActionDispatched
    signal shellMenuOpening
    signal shellMenuOpenResult(string result)
    onActiveChanged: {
        if (!active) {
            openedMenuToken = 0;
        }
    }

    Connections {
        target: root.tray
        enabled: root.active
        ignoreUnknownSignals: true

        function onMenuActionTriggered(token) {
            if (root.openedMenuToken === 0 || token !== root.openedMenuToken) {
                return;
            }
            root.openedMenuToken = 0;
            root.externalActionDispatched();
        }
    }

    function projectTrayItems(items) {
        const projected = [];
        const includedTokens = {};
        const statuses = ["needsAttention", "active"];
        for (let statusIndex = 0; statusIndex < statuses.length && projected.length < 4; statusIndex
             += 1) {
            const status = statuses[statusIndex];
            for (let itemIndex = 0; itemIndex < items.length && projected.length < 4; itemIndex
                 += 1) {
                const item = items[itemIndex];
                const tokenKey = typeof item.token + ":" + String(item.token);
                if (item.status === status && includedTokens[tokenKey] !== true) {
                    includedTokens[tokenKey] = true;
                    projected.push(item);
                }
            }
        }
        return Object.freeze(projected);
    }

    function completeExternalAction(result) {
        if (result === "dispatched") {
            externalActionDispatched();
        }
        return result;
    }

    function activateStatusItem(token) {
        return !active || tray === null ? "rejected" : completeExternalAction(tray.activate(token));
    }

    function statusMenuPosition(button) {
        return button.mapToItem(null, button.width / 2, button.height);
    }

    function openStatusMenu(item, button) {
        if (!active || tray === null || item === null || button === null || menuParentWindow
                === null || item.hasMenu !== true) {
            return "rejected";
        }
        const position = statusMenuPosition(button);
        openedMenuToken = item.token;
        shellMenuOpening();
        const result = tray.openMenu(item.token, menuParentWindow, position.x, position.y);
        if (result !== "dispatched") {
            openedMenuToken = 0;
        }
        shellMenuOpenResult(result);
        return result;
    }

    function statusDescription(item) {
        if (item.hasMenu !== true) {
            return item.tooltip;
        }
        return item.tooltip === "" ? qsTr("Context menu available") : qsTr(
                                         "%1. Context menu available").arg(item.tooltip);
    }

    function primaryStatusAction(item, button) {
        if (tray === null || item === null) {
            return "rejected";
        }
        return item.onlyMenu === true ? openStatusMenu(item, button) : activateStatusItem(
                                            item.token);

    }

    RowLayout {
        id: statusGroup

        objectName: "dashboardStatusItems"
        anchors.centerIn: parent
        width: implicitWidth
        height: implicitHeight
        spacing: Theme.spacing.sm
        Accessible.role: Accessible.List
        Accessible.name: qsTr("Active and attention applications")

        Repeater {
            id: statusRepeater
            model: root.statusItems

            delegate: AbstractButton {
                id: statusButton

                required property var modelData

                objectName: "dashboardStatusItem"
                implicitWidth: Theme.size.controlHeightMd
                implicitHeight: Theme.size.controlHeightMd
                focusPolicy: Qt.StrongFocus
                hoverEnabled: true
                Accessible.role: Accessible.Button
                Accessible.name: modelData.label
                Accessible.description: root.statusDescription(modelData)
                onClicked: root.primaryStatusAction(modelData, statusButton)

                Keys.onPressed: event => {
                    if (modelData.hasMenu === true && (event.key === Qt.Key_Menu || (event.key
                                                                                     === Qt.Key_F10
                                                                                     && (event.modifiers
                                                                                         & Qt.ShiftModifier)))) {
                        root.openStatusMenu(modelData, statusButton);
                        event.accepted = true;
                    }
                }

                background: Rectangle {
                    radius: Theme.radius.md
                    color: statusButton.pressed ? Theme.color.surfaceActive : statusButton.hovered
                                                  ? Theme.color.surfaceHover : "transparent"
                }
                contentItem: Item {
                    IslandIcon {
                        objectName: "dashboardStatusIcon"
                        anchors.centerIn: parent
                        meaning: "application"
                        semanticState: statusButton.modelData.status === "needsAttention"
                                       ? "attention" : "active"
                        applicationSource: statusButton.modelData.iconSource
                        applicationName: statusButton.modelData.label
                    }
                }
                IslandFocusRing {
                    visible: statusButton.visualFocus
                }
                ToolTip.delay: Theme.motion.durationSlow
                ToolTip.visible: hovered || visualFocus
                ToolTip.text: modelData.tooltip

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    enabled: statusButton.modelData.hasMenu === true
                    onClicked: root.openStatusMenu(statusButton.modelData, statusButton)
                }
            }
        }
    }
}

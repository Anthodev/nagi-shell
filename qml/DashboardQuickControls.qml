pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Connectivity uses backend-confirmed state. A bounded active/attention tray
// projection is mirrored here; menus remain in the Tray view.
FocusScope {
    id: root

    required property var connectivity
    required property var applicationModel
    required property var tray

    readonly property int pinCount: applicationModel === null ? 0 :
                                                                applicationModel.pinnedApplications.length
    readonly property var statusItems: projectTrayItems(tray === null ? [] : tray.items)
    property bool centerStatusInMainLane: false
    readonly property string wifiState: connectivity === null || !connectivity.wifiAvailable
                                        ? "Unavailable" : connectivity.wifiEnabled ? "On" : "Off"
    readonly property string bluetoothState: connectivity === null ||
                                             !connectivity.bluetoothAvailable ? "Unavailable" :
                                                                                connectivity.bluetoothEnabled
                                                                                ? "On" : "Off"
    readonly property bool wifiFailureVisible: connectivity !== null && connectivity.wifiFailure
                                               !== "none"
    readonly property bool bluetoothFailureVisible: connectivity !== null
                                                    && connectivity.bluetoothFailure !== "none"
    readonly property string wifiSemanticState: connectivity === null ||
                                                !connectivity.wifiAvailable ? "disabled" :
                                                                              connectivity.wifiPending
                                                                              ? "pending" :
                                                                                wifiFailureVisible
                                                                                ? "error" :
                                                                                  connectivity.wifiEnabled
                                                                                  ? "active" : "off"
    readonly property string bluetoothSemanticState: connectivity === null ||
                                                     !connectivity.bluetoothAvailable ? "disabled" :
                                                                                        connectivity.bluetoothPending
                                                                                        ? "pending" :
                                                                                          bluetoothFailureVisible
                                                                                          ? "error" :
                                                                                            connectivity.bluetoothEnabled
                                                                                            ? "active" :
                                                                                              "off"

    implicitWidth: controlsColumn.implicitWidth
    implicitHeight: controlsColumn.implicitHeight

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

    function surfaceForState(state) {
        if (state === "error") {
            return Theme.color.dangerFill;
        }
        if (state === "pending") {
            return Theme.color.surfaceHover;
        }
        if (state === "active") {
            return Theme.color.surfaceActive;
        }
        if (state === "off") {
            return Theme.color.controlFill;
        }
        return Theme.color.surface;
    }

    function toggleWifi() {
        return connectivity !== null && connectivity.wifiAvailable && !connectivity.wifiPending
                && connectivity.toggleWifi();
    }

    function toggleBluetooth() {
        return connectivity !== null && connectivity.bluetoothAvailable &&
                !connectivity.bluetoothPending && connectivity.toggleBluetooth();
    }

    function activateStatusItem(token) {
        return tray !== null && tray.activate(token);
    }

    function reveal(flickable, item) {
        if (item.x < flickable.contentX) {
            flickable.contentX = item.x;
        } else if (item.x + item.width > flickable.contentX + flickable.width) {
            flickable.contentX = item.x + item.width - flickable.width;
        }
    }

    function launchPin(index) {
        if (applicationModel === null || applicationModel.launchPending || index < 0 || index
                >= applicationModel.pinnedApplications.length) {
            return 0;
        }
        return applicationModel.dispatchLaunch(applicationModel.pinnedApplications[index].id);
    }

    ColumnLayout {
        id: controlsColumn

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.spacing.sm

        RowLayout {
            id: quickRow
            objectName: "dashboardQuickControlRow"
            Layout.fillWidth: true
            spacing: Theme.spacing.sm

            AbstractButton {
                id: wifiButton

                readonly property color restingColor: root.surfaceForState(root.wifiSemanticState)

                objectName: "dashboardWifi"
                implicitWidth: Theme.size.controlHeightLg
                implicitHeight: Theme.size.controlHeightLg
                focusPolicy: Qt.StrongFocus
                hoverEnabled: true
                enabled: root.connectivity !== null && root.connectivity.wifiAvailable &&
                         !root.connectivity.wifiPending
                Accessible.role: Accessible.Button
                Accessible.name: "Wi-Fi"
                Accessible.description: "Toggle Wi-Fi. Confirmed state " + root.wifiState + (
                                            root.wifiFailureVisible ? ". Last request failed." : "")
                onClicked: root.toggleWifi()

                background: Rectangle {
                    radius: Theme.radius.lg
                    color: wifiButton.pressed ? Theme.color.surfaceActive : wifiButton.hovered
                                                ? Theme.color.surfaceHover : wifiButton.restingColor
                }
                contentItem: Item {
                    IslandIcon {
                        objectName: "dashboardWifiIcon"
                        anchors.centerIn: parent
                        meaning: "wifi"
                        semanticState: root.wifiSemanticState
                        size: "lg"
                    }
                }
                IslandFocusRing {
                    controlRadius: Theme.radius.lg
                    visible: wifiButton.visualFocus
                }
                ToolTip.delay: Theme.motion.durationSlow
                ToolTip.visible: hovered || visualFocus
                ToolTip.text: "Wi-Fi · " + root.wifiState
            }

            AbstractButton {
                id: bluetoothButton

                readonly property color restingColor: root.surfaceForState(
                                                          root.bluetoothSemanticState)

                objectName: "dashboardBluetooth"
                implicitWidth: Theme.size.controlHeightLg
                implicitHeight: Theme.size.controlHeightLg
                focusPolicy: Qt.StrongFocus
                hoverEnabled: true
                enabled: root.connectivity !== null && root.connectivity.bluetoothAvailable &&
                         !root.connectivity.bluetoothPending
                Accessible.role: Accessible.Button
                Accessible.name: "Bluetooth"
                Accessible.description: "Toggle Bluetooth. Confirmed state " + root.bluetoothState
                                        + (root.bluetoothFailureVisible ? ". Last request failed." :
                                                                          "")
                onClicked: root.toggleBluetooth()

                background: Rectangle {
                    radius: Theme.radius.lg
                    color: bluetoothButton.pressed ? Theme.color.surfaceActive :
                                                     bluetoothButton.hovered
                                                     ? Theme.color.surfaceHover :
                                                       bluetoothButton.restingColor
                }
                contentItem: Item {
                    IslandIcon {
                        objectName: "dashboardBluetoothIcon"
                        anchors.centerIn: parent
                        meaning: "bluetooth"
                        semanticState: root.bluetoothSemanticState
                        size: "lg"
                    }
                }
                IslandFocusRing {
                    controlRadius: Theme.radius.lg
                    visible: bluetoothButton.visualFocus
                }
                ToolTip.delay: Theme.motion.durationSlow
                ToolTip.visible: hovered || visualFocus
                ToolTip.text: "Bluetooth · " + root.bluetoothState
            }

            Item {
                Layout.fillWidth: true
            }

            Item {
                id: statusLane

                objectName: "dashboardStatusLane"
                visible: root.statusItems.length > 0
                Layout.preferredWidth: Theme.spacing.xxl * 6
                Layout.preferredHeight: statusGroup.implicitHeight
                readonly property real centeredX: Math.max(bluetoothButton.x
                                                           + bluetoothButton.width
                                                           + Theme.spacing.sm, (quickRow.width
                                                                                - width) / 2)

                transform: Translate {
                    x: root.centerStatusInMainLane ? statusLane.centeredX - statusLane.x : 0
                }

                RowLayout {
                    id: statusGroup

                    objectName: "dashboardStatusItems"
                    anchors.centerIn: parent
                    width: implicitWidth
                    height: implicitHeight
                    spacing: Theme.spacing.sm
                    Accessible.role: Accessible.List
                    Accessible.name: "Active and attention applications"

                    Repeater {
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
                            Accessible.description: modelData.tooltip
                            onClicked: root.activateStatusItem(modelData.token)

                            background: Rectangle {
                                radius: Theme.radius.md
                                color: statusButton.pressed ? Theme.color.surfaceActive :
                                                              statusButton.hovered
                                                              ? Theme.color.surfaceHover :
                                                                "transparent"
                            }
                            contentItem: Item {
                                IslandIcon {
                                    objectName: "dashboardStatusIcon"
                                    anchors.centerIn: parent
                                    meaning: "application"
                                    semanticState: statusButton.modelData.status
                                                   === "needsAttention" ? "attention" : "active"
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
                        }
                    }
                }
            }
        }

        RowLayout {
            visible: root.pinCount > 0
            spacing: Theme.spacing.sm

            IslandText {
                text: "Pinned"
                textFormat: Text.PlainText
                tone: "muted"
                size: "caption"
            }

            Flickable {
                id: pinFlickable

                Layout.preferredWidth: Math.min(pinRow.implicitWidth, Theme.spacing.xxl * 12)
                Layout.preferredHeight: Theme.size.controlHeightMd
                contentWidth: pinRow.implicitWidth
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                Accessible.role: Accessible.List
                Accessible.name: "Pinned applications"

                Row {
                    id: pinRow

                    height: parent.height
                    spacing: Theme.spacing.sm

                    Repeater {
                        model: root.applicationModel === null ? [] :
                                                                root.applicationModel.pinnedApplications

                        delegate: IslandButton {
                            required property int index
                            required property var modelData
                            objectName: "dashboardPinnedApplication"

                            width: Math.min(Theme.spacing.xxl * 6, implicitWidth)
                            label: modelData.name
                            enabled: root.applicationModel !== null &&
                                     !root.applicationModel.launchPending
                            Accessible.description: "Launch pinned application " + modelData.name
                            onActiveFocusChanged: {
                                if (activeFocus) {
                                    root.reveal(pinFlickable, this);
                                }
                            }
                            onClicked: root.launchPin(index)
                        }
                    }
                }
            }
        }
    }
}

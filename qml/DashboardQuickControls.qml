pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Connectivity and pinned applications form the Expanded command stage.
// Backend-confirmed adapter state remains authoritative.
FocusScope {
    id: root

    required property var connectivity
    required property var applicationModel

    readonly property int pinCount: applicationModel === null ? 0 :
                                                                applicationModel.pinnedApplications.length
    readonly property string wifiState: connectivity === null || !connectivity.wifiAvailable ? qsTr(
                                                                                                   "Unavailable") :
                                                                                               connectivity.wifiEnabled
                                                                                               ? qsTr("On") :
                                                                                                 qsTr("Off")
    readonly property string bluetoothState: connectivity === null ||
                                             !connectivity.bluetoothAvailable ? qsTr("Unavailable") :
                                                                                connectivity.bluetoothEnabled
                                                                                ? qsTr("On") : qsTr(
                                                                                      "Off")
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

    implicitWidth: Math.max(quickRow.implicitWidth, pinnedControlsRow.implicitWidth)
    implicitHeight: controlsColumn.implicitHeight

    signal externalActionDispatched

    signal wifiManagerRequested
    signal bluetoothManagerRequested

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
        const requestId = applicationModel.dispatchLaunch(
                  applicationModel.pinnedApplications[index].id);
        if (requestId > 0) {
            externalActionDispatched();
        }
        return requestId;
    }

    ColumnLayout {
        id: controlsColumn

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.spacing.md

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
                Accessible.name: qsTr("Wi-Fi")
                Accessible.description: root.wifiFailureVisible ? qsTr(
                                                                      "Toggle Wi-Fi. Confirmed state: %1. The last request failed. Right-click or press Shift+Enter to manage networks.").arg(
                                                                      root.wifiState) : qsTr(
                                                                      "Toggle Wi-Fi. Confirmed state: %1. Right-click or press Shift+Enter to manage networks.").arg(
                                                                      root.wifiState)
                onClicked: root.toggleWifi()
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Menu || (event.key === Qt.Key_Return && (event.modifiers
                                                                                      & Qt.ShiftModifier)
                                                      !== 0)) {
                        root.wifiManagerRequested();
                        event.accepted = true;
                    }
                }

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
                ToolTip.text: qsTr("Wi-Fi · %1 · Right-click to manage").arg(root.wifiState)
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: root.wifiManagerRequested()
                }
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
                Accessible.name: qsTr("Bluetooth")
                Accessible.description: root.bluetoothFailureVisible ? qsTr(
                                                                           "Toggle Bluetooth. Confirmed state: %1. The last request failed. Right-click or press Shift+Enter to manage devices.").arg(
                                                                           root.bluetoothState) :
                                                                       qsTr("Toggle Bluetooth. Confirmed state: %1. Right-click or press Shift+Enter to manage devices.").arg(
                                                                           root.bluetoothState)
                onClicked: root.toggleBluetooth()
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Menu || (event.key === Qt.Key_Return && (event.modifiers
                                                                                      & Qt.ShiftModifier)
                                                      !== 0)) {
                        root.bluetoothManagerRequested();
                        event.accepted = true;
                    }
                }

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
                ToolTip.text: qsTr("Bluetooth · %1 · Right-click to manage").arg(
                                  root.bluetoothState)
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: root.bluetoothManagerRequested()
                }
            }
        }

        RowLayout {
            id: pinnedControlsRow
            visible: root.pinCount > 0
            spacing: Theme.spacing.sm

            IslandText {
                text: qsTr("Pinned")
                textFormat: Text.PlainText
                tone: "muted"
                size: "caption"
            }

            Flickable {
                id: pinFlickable

                Layout.preferredWidth: Math.min(pinRow.implicitWidth, Theme.spacing.xxl * 9)
                Layout.preferredHeight: Theme.size.controlHeightMd
                contentWidth: pinRow.implicitWidth
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                Accessible.role: Accessible.List
                Accessible.name: qsTr("Pinned applications")

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
                            Accessible.description: qsTr("Launch pinned application %1").arg(
                                                        modelData.name)
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

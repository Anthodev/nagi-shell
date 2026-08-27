pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root

    required property var bluetooth
    property bool reducedMotion: false
    property bool managerInterestActive: false
    property int unpairToken: 0
    property string unpairName: ""

    readonly property bool backendUnavailable: bluetooth === null || !bluetooth.backendReady ||
                                               !bluetooth.bluetoothAvailable
    readonly property bool operationPending: bluetooth !== null && bluetooth.bluetoothBusy
    readonly property var connectedDevices: groupedDevices("connected")
    readonly property var pairedDevices: groupedDevices("paired")
    readonly property var availableDevices: groupedDevices("available")

    clip: true
    contentWidth: width
    contentHeight: content.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {
        policy: root.contentHeight > root.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
    }

    function groupedDevices(group) {
        if (bluetooth === null) {
            return [];
        }
        return bluetooth.bluetoothDevices.filter(device => group === "connected" ? device.connected :
                                                                                   group === "paired"
                                                                                   ? device.paired
                                                                                     && !device.connected :
                                                                                     !device.paired
                                                                                     && !device.connected);
    }

    function pairingDeviceName() {
        if (bluetooth === null) {
            return "Bluetooth device";
        }
        for (let index = 0; index < bluetooth.bluetoothDevices.length; index += 1) {
            const device = bluetooth.bluetoothDevices[index];
            if (device.token === bluetooth.bluetoothPairingToken) {
                return device.name;
            }
        }
        return "Bluetooth device";
    }

    function clearPrivateState() {
        pairingPanel.clearPrivateState();
        unpairToken = 0;
        unpairName = "";
    }

    function updateInterest() {
        if (bluetooth === null) {
            managerInterestActive = false;
            return;
        }
        const wanted = visible && bluetooth.backendReady;
        if (wanted === managerInterestActive) {
            return;
        }
        if (bluetooth.setBluetoothManagerOpen(wanted)) {
            managerInterestActive = wanted;
        } else if (!wanted) {
            managerInterestActive = false;
        }
    }

    function requestUnpair(token, name) {
        if (operationPending || token < 1) {
            return false;
        }
        unpairToken = token;
        unpairName = name;
        return true;
    }

    function confirmUnpair() {
        if (unpairToken < 1 || operationPending) {
            return false;
        }
        const token = unpairToken;
        unpairToken = 0;
        unpairName = "";
        return bluetooth.unpairBluetooth(token);
    }

    function operationMessage() {
        if (bluetooth === null)
            return "";
        if (bluetooth.bluetoothOperationFailure === "connection-failed")
            return "Pairing succeeded, but the connection failed. You can retry Connect.";
        if (bluetooth.bluetoothOperationFailure === "trust-failed")
            return "Pairing succeeded, but BlueZ could not trust the device.";
        if (bluetooth.bluetoothOperationFailure === "rejected")
            return "The pairing request was rejected.";
        if (bluetooth.bluetoothOperationFailure === "timeout")
            return "The Bluetooth operation timed out in BlueZ.";
        if (bluetooth.bluetoothOperationFailure !== "none")
            return "The Bluetooth operation could not be completed.";
        if (bluetooth.bluetoothOperationResult === "paired-connected")
            return "Paired and connected.";
        if (bluetooth.bluetoothOperationResult === "connected")
            return "Connected.";
        if (bluetooth.bluetoothOperationResult === "disconnected")
            return "Disconnected.";
        if (bluetooth.bluetoothOperationResult === "unpaired")
            return "Pairing removed.";
        return "";
    }

    Component.onCompleted: updateInterest()
    Component.onDestruction: {
        clearPrivateState();
        if (bluetooth !== null && managerInterestActive) {
            bluetooth.setBluetoothManagerOpen(false);
        }
        managerInterestActive = false;
    }
    onVisibleChanged: {
        if (!visible) {
            clearPrivateState();
        }
        updateInterest();
    }

    Connections {
        target: root.bluetooth
        ignoreUnknownSignals: true

        function onBackendReadyChanged() {
            if (!root.bluetooth.backendReady) {
                root.clearPrivateState();
                root.managerInterestActive = false;
            }
            root.updateInterest();
        }

        function onBluetoothOperationGenerationChanged() {
            pairingPanel.clearPrivateState();
        }

        function onBluetoothOperationFailureChanged() {
            pairingPanel.clearPrivateState();
        }
    }

    ColumnLayout {
        id: content

        width: root.width - (root.contentHeight > root.height ? Theme.spacing.md : 0)
        spacing: Theme.spacing.md

        IslandText {
            text: "Bluetooth"
            size: "title"
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }

        IslandPanel {
            Layout.fillWidth: true
            implicitHeight: unavailableColumn.implicitHeight + Theme.spacing.lg * 2
            color: Theme.color.controlFill
            visible: root.backendUnavailable

            ColumnLayout {
                id: unavailableColumn

                anchors.fill: parent
                anchors.margins: Theme.spacing.lg
                spacing: Theme.spacing.sm

                IslandText {
                    Layout.fillWidth: true
                    text: "Bluetooth management unavailable"
                    size: "title"
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }

                IslandText {
                    Layout.fillWidth: true
                    text: "BlueZ or a Bluetooth controller is unavailable. Use KDE System Settings to inspect the system service or hardware state."
                    textFormat: Text.PlainText
                    size: "body"
                    color: Theme.color.textSecondary
                    wrapMode: Text.Wrap
                    Accessible.name: text
                }
            }
        }

        SettingToggleRow {
            Layout.fillWidth: true
            visible: !root.backendUnavailable
            label: "Bluetooth radio"
            description: root.bluetooth.bluetoothControllerCount > 1
                         ? "Backend-confirmed aggregate state across "
                           + root.bluetooth.bluetoothControllerCount + " controllers." :
                           "Backend-confirmed BlueZ state."
            value: root.bluetooth.bluetoothEnabled
            writable: !root.operationPending
            onValueRequested: value => root.bluetooth.requestBluetoothEnabled(value)
        }

        RowLayout {
            Layout.fillWidth: true
            visible: !root.backendUnavailable && root.bluetooth.bluetoothEnabled
                     && root.bluetooth.bluetoothOperation !== "pairing" && root.unpairToken === 0
            spacing: Theme.spacing.sm

            IslandButton {
                objectName: "bluetoothScanButton"
                label: root.bluetooth.bluetoothDiscovering ? "Stop scan" : "Scan"
                reducedMotion: root.reducedMotion
                enabled: !root.operationPending
                Accessible.description: root.bluetooth.bluetoothDiscovering
                                        ? "Stop this Bluetooth discovery session" :
                                          "Start one 30 second Bluetooth discovery session"
                onClicked: root.bluetooth.bluetoothDiscovering ? root.bluetooth.stopBluetoothScan() :
                                                                 root.bluetooth.scanBluetooth()
            }

            IslandText {
                visible: root.bluetooth.bluetoothDiscovering
                text: "Discovery stops automatically after 30 seconds."
                size: "caption"
                color: Theme.color.textSecondary
                Accessible.name: text
            }

            Item {
                Layout.fillWidth: true
            }
        }

        IslandText {
            Layout.fillWidth: true
            visible: !root.backendUnavailable && root.operationMessage() !== ""
            text: root.operationMessage()
            textFormat: Text.PlainText
            size: "caption"
            color: root.bluetooth.bluetoothOperationFailure === "none" ? Theme.color.textSecondary :
                                                                         Theme.color.dangerText
            wrapMode: Text.Wrap
            Accessible.name: text
        }

        BluetoothPairingPanel {
            id: pairingPanel
            objectName: "bluetoothPairingPanel"

            visible: !root.backendUnavailable && root.bluetooth.bluetoothOperation === "pairing"
            deviceName: root.pairingDeviceName()
            prompt: root.bluetooth.bluetoothPairingPrompt
            displayValue: root.bluetooth.bluetoothPairingValue
            entered: root.bluetooth.bluetoothPairingEntered
            operationPending: false
            reducedMotion: root.reducedMotion
            onResponseRequested: (accepted, response) => root.bluetooth.respondBluetoothPairing(
                                                             accepted, response)
            onCancelRequested: root.bluetooth.cancelBluetoothPairing()
        }

        IslandPanel {
            Layout.fillWidth: true
            visible: root.unpairToken > 0
            implicitHeight: unpairColumn.implicitHeight + Theme.spacing.lg * 2
            color: Theme.color.dangerFill

            ColumnLayout {
                id: unpairColumn

                anchors.fill: parent
                anchors.margins: Theme.spacing.lg
                spacing: Theme.spacing.md

                IslandText {
                    Layout.fillWidth: true
                    text: "Unpair " + root.unpairName + "?"
                    textFormat: Text.PlainText
                    size: "title"
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }

                IslandText {
                    Layout.fillWidth: true
                    text: "This removes only the local BlueZ pairing relationship."
                    size: "body"
                    color: Theme.color.textSecondary
                    wrapMode: Text.Wrap
                    Accessible.name: text
                }

                RowLayout {
                    spacing: Theme.spacing.sm

                    IslandButton {
                        label: "Unpair"
                        variant: "danger"
                        reducedMotion: root.reducedMotion
                        enabled: !root.operationPending
                        onClicked: root.confirmUnpair()
                    }

                    IslandButton {
                        label: "Cancel"
                        reducedMotion: root.reducedMotion
                        onClicked: {
                            root.unpairToken = 0;
                            root.unpairName = "";
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: !root.backendUnavailable && root.bluetooth.bluetoothEnabled
                     && root.bluetooth.bluetoothOperation !== "pairing" && root.unpairToken === 0
            spacing: Theme.spacing.lg

            BluetoothDeviceGroup {
                title: "Connected"
                devices: root.connectedDevices
                busy: root.operationPending
                reducedMotion: root.reducedMotion
                onPairRequested: token => root.bluetooth.pairBluetooth(token)
                onConnectRequested: token => root.bluetooth.connectBluetooth(token)
                onDisconnectRequested: token => root.bluetooth.disconnectBluetooth(token)
                onUnpairRequested: (token, name) => root.requestUnpair(token, name)
            }

            BluetoothDeviceGroup {
                title: "Paired"
                devices: root.pairedDevices
                busy: root.operationPending
                reducedMotion: root.reducedMotion
                onPairRequested: token => root.bluetooth.pairBluetooth(token)
                onConnectRequested: token => root.bluetooth.connectBluetooth(token)
                onDisconnectRequested: token => root.bluetooth.disconnectBluetooth(token)
                onUnpairRequested: (token, name) => root.requestUnpair(token, name)
            }

            BluetoothDeviceGroup {
                title: "Available"
                devices: root.availableDevices
                busy: root.operationPending
                reducedMotion: root.reducedMotion
                onPairRequested: token => root.bluetooth.pairBluetooth(token)
                onConnectRequested: token => root.bluetooth.connectBluetooth(token)
                onDisconnectRequested: token => root.bluetooth.disconnectBluetooth(token)
                onUnpairRequested: (token, name) => root.requestUnpair(token, name)
            }

            IslandText {
                Layout.fillWidth: true
                visible: root.bluetooth.bluetoothDevices.length === 0 &&
                         !root.bluetooth.bluetoothDiscovering
                text: "No paired or connected devices. Select Scan to discover nearby devices."
                size: "body"
                color: Theme.color.textSecondary
                wrapMode: Text.Wrap
                Accessible.name: text
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.spacing.lg
        }
    }
}

import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    property var parsedSnapshot: null

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            return false;
        }
        return true;
    }

    function radio(available, enabled, hardwareEnabled, pending, failure, requestId, networks, operation,
                   operationGeneration, operationFailure, operationResult) {
        return {
            "available": available,
            "enabled": enabled,
            "hardwareEnabled": hardwareEnabled,
            "networkingEnabled": available,
            "pending": pending,
            "failure": failure,
            "requestId": requestId,
            "scanning": operation === "scanning",
            "currentNetwork": "",
            "networks": networks ?? [],
            "controllerCount": available ? 1 : 0,
            "selectedController": available ? 1 : 0,
            "discovering": operation === "discovering",
            "discoveryDeadlineMs": operation === "discovering" ? 30000 : 0,
            "devices": [],
            "operation": operation ?? "idle",
            "operationGeneration": operationGeneration ?? 0,
            "operationFailure": operationFailure ?? "none",
            "operationResult": operationResult ?? "none",
            "pairingPrompt": "none",
            "pairingValue": "",
            "pairingEntered": 0,
            "pairingToken": 0
        };
    }

    function bluetoothRadio(devices, operation, generation, prompt, value, result, failure) {
        return {
            "available": true,
            "enabled": true,
            "hardwareEnabled": true,
            "pending": false,
            "failure": "none",
            "requestId": 0,
            "controllerCount": 2,
            "selectedController": 1,
            "discovering": operation === "discovering",
            "discoveryDeadlineMs": operation === "discovering" ? 30000 : 0,
            "devices": devices,
            "operation": operation,
            "operationGeneration": generation,
            "operationFailure": failure ?? "none",
            "operationResult": result ?? "none",
            "pairingPrompt": prompt ?? "none",
            "pairingValue": value ?? "",
            "pairingEntered": 0,
            "pairingToken": operation === "pairing" ? devices[0].token : 0
        };
    }

    function emitSnapshot(wifi, bluetooth) {
        fakeBridge.snapshotReceived({
                                        "wifi": wifi,
                                        "bluetooth": bluetooth
                                    });
    }

    function run() {
        parser.acceptLine("not json");
        parser.acceptLine("{\"type\":\"state\",\"wifi\":{}}");
        parser.acceptLine("x".repeat(parser.maximumLineLength + 1));
        parser.acceptLine(JSON.stringify({
                                             "type": "state",
                                             "wifi": radio(true, true, true, false, "none", 0),
                                             "bluetooth": radio(false, false, false, false, "none",
                                                                0)
                                         }));
        if (!require(parsedSnapshot !== null && parsedSnapshot.wifi.enabled,
                     "bridge accepts only a complete normalized snapshot")) {
            return;
        }

        emitSnapshot(radio(true, true, true, false, "none", 0), radio(false, false, false, false, "none",
                                                                      0));
        if (!require(adapter.backendReady, "injected backend is ready") || !require(
                    adapter.wifiAvailable && adapter.wifiEnabled,
                    "Wi-Fi availability and enabled state are exposed") || !require(
                    !adapter.bluetoothAvailable && !adapter.bluetoothEnabled,
                    "unavailable Bluetooth has no active state") || !require(
                    !adapter.requestBluetoothEnabled(true),
                    "unavailable Bluetooth rejects actions")) {
            return;
        }

        if (!require(adapter.toggleWifi(), "available Wi-Fi accepts a toggle") || !require(
                    adapter.wifiPending, "dispatch is pending before backend acknowledgement") ||
                !require(fakeBridge.commands.length === 1 && fakeBridge.commands[0].adapter
                         === "wifi" && fakeBridge.commands[0].enabled === false,
                         "toggle sends one bounded Wi-Fi request") || !require(!adapter.toggleWifi(),
                                                                               "dispatch pending blocks duplicate actions")) {
            return;
        }
        const wifiRequestId = fakeBridge.commands[0].requestId;
        emitSnapshot(radio(true, true, true, true, "none", wifiRequestId), radio(false, false, false,
                                                                                 false, "none", 0));
        if (!require(adapter.wifiEnabled && adapter.wifiPending,
                     "pending state preserves the confirmed Wi-Fi value")) {
            return;
        }
        emitSnapshot(radio(true, false, true, false, "none", wifiRequestId), radio(false, false,
                                                                                   false, false,
                                                                                   "none", 0));
        if (!require(!adapter.wifiEnabled && !adapter.wifiPending,
                     "confirmed Wi-Fi state completes the action")) {
            return;
        }

        emitSnapshot(radio(true, false, false, false, "none", wifiRequestId), radio(true, false,
                                                                                    true, false,
                                                                                    "none", 0));
        if (!require(!adapter.requestWifiEnabled(true),
                     "hardware-disabled Wi-Fi rejects active controls") || !require(
                    adapter.requestBluetoothEnabled(true),
                    "available Bluetooth accepts a toggle")) {
            return;
        }
        const bluetoothRequestId = fakeBridge.commands[1].requestId;
        emitSnapshot(radio(true, false, false, false, "none", wifiRequestId), radio(true, false,
                                                                                    true, true,
                                                                                    "none", bluetoothRequestId));
        emitSnapshot(radio(true, false, false, false, "none", wifiRequestId), radio(true, false,
                                                                                    true, false,
                                                                                    "denied", bluetoothRequestId));
        if (!require(!adapter.bluetoothEnabled && !adapter.bluetoothPending
                     && adapter.bluetoothFailure === "denied",
                     "denial keeps confirmed state and exposes normalized failure")) {
            return;
        }

        emitSnapshot(radio(true, true, true, false, "none", wifiRequestId), radio(true, true, true, false,
                                                                                  "none", bluetoothRequestId));
        if (!require(adapter.wifiEnabled && adapter.bluetoothEnabled,
                     "external snapshots update both adapters without requests")) {
            return;
        }

        const networks = [{
                "token": 9,
                "ssid": "Protected",
                "security": "wpa-personal",
                "strength": 77,
                "connected": false,
                "saved": false,
                "forgettable": false,
                "connectable": true,
                "forgetReason": "none"
            }];
        emitSnapshot(radio(true, true, true, false, "none", wifiRequestId, networks), radio(
                         true, true, true, false, "none", bluetoothRequestId));
        if (!require(adapter.wifiNetworks.length === 1 && adapter.wifiNetworks[0].ssid
                     === "Protected" && adapter.setWifiManagerOpen(true),
                     "shared manager exposes one bounded logical model and accepts page interest")
                || !require(adapter.refreshWifi(), "manual refresh dispatches once")) {
            return;
        }
        const scanCommand = fakeBridge.commands[fakeBridge.commands.length - 1];
        emitSnapshot(radio(true, true, true, false, "none", wifiRequestId, networks, "scanning",
                           scanCommand.requestId), radio(true, true, true, false, "none",
                                                         bluetoothRequestId));
        if (!require(adapter.wifiScanning && adapter.connectWifi(9, "fixture-password", true),
                     "connect explicitly replaces scan through one operation generation")) {
            return;
        }
        const connectCommand = fakeBridge.commands[fakeBridge.commands.length - 1];
        if (!require(connectCommand.operation === "connect" && connectCommand.token === 9
                     && connectCommand.secretLength === 16 && connectCommand.remember
                     && JSON.stringify(connectCommand).indexOf("fixture-password") === -1,
                     "secret crosses only as a method argument and is not retained by the model")) {
            return;
        }
        emitSnapshot(radio(true, true, true, false, "none", wifiRequestId, networks, "connecting",
                           connectCommand.requestId), radio(true, true, true, false, "none",
                                                            bluetoothRequestId));
        if (!require(adapter.wifiOperation === "connecting" && adapter.wifiBusy,
                     "one shared mutable generation disables incompatible work")) {
            return;
        }
        if (!require(adapter.setWifiManagerOpen(false)
                     && fakeBridge.commands[fakeBridge.commands.length - 1].operation === "interest"
                     && !fakeBridge.commands[fakeBridge.commands.length - 1].interested
                     && adapter.wifiOperation === "connecting",
                     "closing the page ends scan interest without cancelling an explicit connection")) {
            return;
        }
        const bluetoothDevices = [{
                "token": 21,
                "name": "Fixture Headphones",
                "type": "audio",
                "signal": 72,
                "paired": false,
                "connected": false,
                "trusted": false,
                "pairable": true,
                "connectable": false,
                "disconnectable": false,
                "unpairable": false
            }];
        emitSnapshot(radio(true, true, true, false, "none", wifiRequestId),
                     bluetoothRadio(bluetoothDevices, "idle", 0));
        if (!require(adapter.bluetoothDevices.length === 1
                     && adapter.bluetoothControllerCount === 2
                     && adapter.setBluetoothManagerOpen(true),
                     "Bluetooth exposes bounded aggregate devices and accepts page interest")
                || !require(adapter.scanBluetooth(), "explicit Bluetooth Scan dispatches once")) {
            return;
        }
        const bluetoothScan = fakeBridge.commands[fakeBridge.commands.length - 1];
        emitSnapshot(radio(true, true, true, false, "none", wifiRequestId),
                     bluetoothRadio(bluetoothDevices, "discovering", bluetoothScan.requestId));
        if (!require(adapter.bluetoothDiscovering && adapter.pairBluetooth(21),
                     "pairing explicitly replaces discovery without a free queue")) {
            return;
        }
        const pairCommand = fakeBridge.commands[fakeBridge.commands.length - 1];
        emitSnapshot(radio(true, true, true, false, "none", wifiRequestId),
                     bluetoothRadio(bluetoothDevices, "pairing", pairCommand.requestId,
                                    "enter-pin"));
        if (!require(adapter.bluetoothPairingPrompt === "enter-pin"
                     && adapter.respondBluetoothPairing(true, "4821"),
                     "pairing input crosses only through the current operation generation")) {
            return;
        }
        const responseCommand = fakeBridge.commands[fakeBridge.commands.length - 1];
        if (!require(responseCommand.operation === "bluetooth-agent-response"
                     && responseCommand.responseLength === 4
                     && JSON.stringify(responseCommand).indexOf("4821") === -1,
                     "Bluetooth PIN is not retained by the adapter model or fake command log")) {
            return;
        }
        emitSnapshot(radio(true, true, true, false, "none", wifiRequestId),
                     bluetoothRadio(bluetoothDevices, "idle", pairCommand.requestId, "none", "",
                                    "paired-connected"));
        if (!require(adapter.bluetoothOperationResult === "paired-connected"
                     && adapter.setBluetoothManagerOpen(false),
                     "pair completion remains shared while page close ends manager interest")) {
            return;
        }

        emitSnapshot(radio(true, true, true, false, "none", wifiRequestId, networks, "idle",
                           connectCommand.requestId, "none", "connected"), radio(
                         true, true, true, false, "none", bluetoothRequestId));
        if (!require(adapter.wifiOperationResult === "connected" && !adapter.wifiBusy,
                     "connection completion remains process-wide after page close")) {
            return;
        }

        fakeBridge.fatalFailure();
        if (!require(!adapter.wifiAvailable && !adapter.bluetoothAvailable && adapter.wifiFailure
                     === "backend" && adapter.bluetoothFailure === "backend",
                     "fatal backend cleanup removes writable state")) {
            return;
        }

        console.warn("connectivity adapter tests passed");
        Qt.exit(0);
    }

    QtObject {
        id: fakeBridge

        property bool ready: true
        property var commands: []

        signal snapshotReceived(var snapshot)
        signal fatalFailure

        function setEnabled(adapter, requestId, enabled) {
            commands.push({
                              "adapter": adapter,
                              "requestId": requestId,
                              "enabled": enabled
                          });
            return true;
        }

        function setWifiInterest(requestId, interested) {
            commands.push({
                              "operation": "interest",
                              "requestId": requestId,
                              "interested": interested
                          });
            return true;
        }

        function scanWifi(requestId) {
            commands.push({
                              "operation": "scan",
                              "requestId": requestId
                          });
            return true;
        }

        function connectWifi(requestId, token, secret, remember) {
            commands.push({
                              "operation": "connect",
                              "requestId": requestId,
                              "token": token,
                              "secretLength": secret.length,
                              "remember": remember
                          });
            return true;
        }

        function connectHiddenWifi(requestId, ssid, security, secret, remember) {
            commands.push({
                              "operation": "hidden-connect",
                              "requestId": requestId,
                              "ssidLength": ssid.length,
                              "security": security,
                              "secretLength": secret.length,
                              "remember": remember
                          });
            return true;
        }

        function disconnectWifi(requestId) {
            commands.push({
                              "operation": "disconnect",
                              "requestId": requestId
                          });
            return true;
        }

        function setBluetoothInterest(requestId, interested) {
            commands.push({
                              "operation": "bluetooth-interest",
                              "requestId": requestId,
                              "interested": interested
                          });
            return true;
        }

        function scanBluetooth(requestId) {
            commands.push({
                              "operation": "bluetooth-scan",
                              "requestId": requestId
                          });
            return true;
        }

        function stopBluetoothScan(requestId) {
            commands.push({
                              "operation": "bluetooth-stop-scan",
                              "requestId": requestId
                          });
            return true;
        }

        function pairBluetooth(requestId, token) {
            commands.push({
                              "operation": "bluetooth-pair",
                              "requestId": requestId,
                              "token": token
                          });
            return true;
        }

        function connectBluetooth(requestId, token) {
            commands.push({
                              "operation": "bluetooth-connect",
                              "requestId": requestId,
                              "token": token
                          });
            return true;
        }

        function disconnectBluetooth(requestId, token) {
            commands.push({
                              "operation": "bluetooth-disconnect",
                              "requestId": requestId,
                              "token": token
                          });
            return true;
        }

        function unpairBluetooth(requestId, token) {
            commands.push({
                              "operation": "bluetooth-unpair",
                              "requestId": requestId,
                              "token": token
                          });
            return true;
        }

        function cancelBluetoothPairing(requestId) {
            commands.push({
                              "operation": "bluetooth-cancel",
                              "requestId": requestId
                          });
            return true;
        }

        function respondBluetoothAgent(requestId, generation, accepted, response) {
            commands.push({
                              "operation": "bluetooth-agent-response",
                              "requestId": requestId,
                              "generation": generation,
                              "accepted": accepted,
                              "responseLength": response.length
                          });
            return true;
        }

        function forgetWifi(requestId, token) {
            commands.push({
                              "operation": "forget",
                              "requestId": requestId,
                              "token": token
                          });
            return true;
        }
    }

    ConnectivityBridge {
        id: parser

        helperPath: ""
        enabled: false
        onSnapshotReceived: snapshot => test.parsedSnapshot = snapshot
    }

    ConnectivityAdapter {
        id: adapter

        helperPath: ""
        bridge: fakeBridge
    }

    Component.onCompleted: Qt.callLater(test.run)
}

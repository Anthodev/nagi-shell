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

    function commandCount(operation) {
        let count = 0;
        for (let index = 0; index < fakeBridge.commands.length; ++index) {
            if (fakeBridge.commands[index].operation === operation) {
                ++count;
            }
        }
        return count;
    }

    function pairingStateIsClear() {
        return adapter.bluetoothPairingPrompt === "none"
                && adapter.bluetoothPairingValue === ""
                && adapter.bluetoothPairingEntered === 0
                && adapter.bluetoothPairingToken === 0;
    }

    function runManagerSoak(wifiRequestId, bluetoothRequestId, networks, devices) {
        const wifiScansBefore = commandCount("scan");
        const bluetoothScansBefore = commandCount("bluetooth-scan");
        const bluetoothStopsBefore = commandCount("bluetooth-stop-scan");
        if (!require(adapter.setWifiManagerOpen(true)
                     && adapter.setBluetoothManagerOpen(true),
                     "manager soak opens each shared page-interest seam exactly once")) {
            return false;
        }

        for (let cycle = 0; cycle < 50; ++cycle) {
            emitSnapshot(radio(true, true, true, false, "none", wifiRequestId, networks, "idle",
                               cycle, "none", "none"),
                         bluetoothRadio(devices, "idle", cycle));
            const wifiModelBefore = JSON.stringify(adapter.wifiNetworks);
            if (!require(adapter.refreshWifi(), "Wi-Fi soak accepts one explicit scan")) {
                return false;
            }
            const wifiScan = fakeBridge.commands[fakeBridge.commands.length - 1];
            const wifiFloodStart = fakeBridge.commands.length;
            for (let request = 0; request < 8; ++request) {
                if (!require(!adapter.refreshWifi()
                             && !adapter.connectWifi(9, "queued-psk", false)
                             && !adapter.connectHiddenWifi("Queued", "wpa-personal",
                                                           "queued-hidden-psk", false)
                             && !adapter.disconnectWifi() && !adapter.forgetWifi(9),
                             "Wi-Fi mutable generation rejects every flooded manager request")) {
                    return false;
                }
            }
            if (!require(fakeBridge.commands.length === wifiFloodStart
                         && adapter.wifiOperation === "idle"
                         && JSON.stringify(adapter.wifiNetworks) === wifiModelBefore,
                         "rejected Wi-Fi flood neither queues work nor mutates backend-owned state")) {
                return false;
            }

            emitSnapshot(radio(true, true, true, false, "none", wifiRequestId, networks,
                               "scanning", wifiScan.requestId),
                         bluetoothRadio(devices, "idle", cycle));
            if (!require(adapter.wifiScanning && adapter.setWifiManagerOpen(false),
                         "Wi-Fi explicit scan starts and page close stops its interest")) {
                return false;
            }
            const wifiStop = fakeBridge.commands[fakeBridge.commands.length - 1];
            emitSnapshot(radio(true, true, true, false, "none", wifiRequestId, networks, "idle",
                               wifiStop.requestId, "none", "cancelled"),
                         bluetoothRadio(devices, "idle", cycle));
            if (!require(!adapter.wifiManagerOpen && !adapter.wifiScanning
                         && adapter.wifiOperationResult === "cancelled"
                         && adapter.setWifiManagerOpen(true),
                         "Wi-Fi scan cancellation settles before the next bounded cycle")) {
                return false;
            }

            emitSnapshot(radio(true, true, true, false, "none", wifiRequestId, networks, "idle",
                               cycle, "none", "none"),
                         bluetoothRadio(devices, "idle", cycle));
            const bluetoothModelBefore = JSON.stringify(adapter.bluetoothDevices);
            if (!require(adapter.scanBluetooth(),
                         "Bluetooth soak accepts one explicit discovery start")) {
                return false;
            }
            const bluetoothScan = fakeBridge.commands[fakeBridge.commands.length - 1];
            const bluetoothFloodStart = fakeBridge.commands.length;
            for (let request = 0; request < 8; ++request) {
                if (!require(!adapter.scanBluetooth() && !adapter.stopBluetoothScan()
                             && !adapter.pairBluetooth(21) && !adapter.connectBluetooth(21)
                             && !adapter.disconnectBluetooth(21) && !adapter.unpairBluetooth(21)
                             && !adapter.cancelBluetoothPairing()
                             && !adapter.respondBluetoothPairing(true, "queued-pin"),
                             "Bluetooth mutable generation rejects every flooded manager request")) {
                    return false;
                }
            }
            if (!require(fakeBridge.commands.length === bluetoothFloodStart
                         && adapter.bluetoothOperation === "idle"
                         && JSON.stringify(adapter.bluetoothDevices) === bluetoothModelBefore,
                         "rejected Bluetooth flood neither queues work nor mutates backend-owned state")) {
                return false;
            }

            emitSnapshot(radio(true, true, true, false, "none", wifiRequestId, networks, "idle",
                               cycle, "none", "none"),
                         bluetoothRadio(devices, "discovering", bluetoothScan.requestId));
            if (!require(adapter.bluetoothDiscovering && adapter.stopBluetoothScan(),
                         "Bluetooth explicit discovery starts and accepts one explicit stop")) {
                return false;
            }
            const bluetoothStop = fakeBridge.commands[fakeBridge.commands.length - 1];
            const bluetoothStopFloodStart = fakeBridge.commands.length;
            for (let request = 0; request < 8; ++request) {
                if (!require(!adapter.scanBluetooth() && !adapter.stopBluetoothScan()
                             && !adapter.pairBluetooth(21) && !adapter.connectBluetooth(21),
                             "Bluetooth stop generation rejects every flooded request")) {
                    return false;
                }
            }
            if (!require(fakeBridge.commands.length === bluetoothStopFloodStart,
                         "Bluetooth stop flood leaves no queued command")) {
                return false;
            }
            emitSnapshot(radio(true, true, true, false, "none", wifiRequestId, networks, "idle",
                               cycle, "none", "none"),
                         bluetoothRadio(devices, "idle", bluetoothStop.requestId, "none", "",
                                        "stopped"));
            if (!require(!adapter.bluetoothDiscovering && adapter.bluetoothOperation === "idle"
                         && adapter.bluetoothOperationResult === "stopped"
                         && pairingStateIsClear(),
                         "Bluetooth discovery stop settles with clean operation and secret state")) {
                return false;
            }
        }

        return require(commandCount("scan") - wifiScansBefore === 50
                       && commandCount("bluetooth-scan") - bluetoothScansBefore === 50
                       && commandCount("bluetooth-stop-scan") - bluetoothStopsBefore === 50,
                       "manager soak performs exactly 50 Wi-Fi and Bluetooth start-stop cycles");
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
                     && pairingStateIsClear() && adapter.setBluetoothManagerOpen(false),
                     "pair completion clears PIN state while page close ends manager interest")) {
            return;
        }

        emitSnapshot(radio(true, true, true, false, "none", wifiRequestId, networks, "idle",
                           connectCommand.requestId, "none", "connected"), radio(
                         true, true, true, false, "none", bluetoothRequestId));
        if (!require(adapter.wifiOperationResult === "connected" && !adapter.wifiBusy,
                     "connection completion remains process-wide after page close")) {
            return;
        }

        const bridgeBeforeSoak = adapter.bridge;
        if (!runManagerSoak(wifiRequestId, bluetoothRequestId, networks, bluetoothDevices)) {
            return;
        }

        emitSnapshot(radio(true, true, true, false, "none", wifiRequestId, networks, "idle",
                           connectCommand.requestId, "none", "connected"),
                     bluetoothRadio(bluetoothDevices, "pairing", 6001, "enter-pin"));
        if (!require(adapter.respondBluetoothPairing(false, "7319"),
                     "pairing rejection submits through the current generation")) {
            return;
        }
        const rejectedResponse = fakeBridge.commands[fakeBridge.commands.length - 1];
        emitSnapshot(radio(true, true, true, false, "none", wifiRequestId, networks, "idle",
                           connectCommand.requestId, "none", "connected"),
                     bluetoothRadio(bluetoothDevices, "idle", 6001, "none", "", "cancelled",
                                    "cancelled"));
        if (!require(rejectedResponse.responseLength === 4
                     && JSON.stringify(rejectedResponse).indexOf("7319") === -1
                     && adapter.bluetoothOperationFailure === "cancelled"
                     && pairingStateIsClear(),
                     "pairing cancellation clears PIN and operation state")) {
            return;
        }

        emitSnapshot(radio(true, true, true, false, "none", wifiRequestId, networks, "idle",
                           connectCommand.requestId, "none", "connected"),
                     bluetoothRadio(bluetoothDevices, "pairing", 6002, "enter-pin"));
        if (!require(adapter.respondBluetoothPairing(true, "8642"),
                     "pairing failure probe submits through the current generation")) {
            return;
        }
        const failedResponse = fakeBridge.commands[fakeBridge.commands.length - 1];
        emitSnapshot(radio(true, true, true, false, "none", wifiRequestId, networks, "idle",
                           connectCommand.requestId, "none", "connected"),
                     bluetoothRadio(bluetoothDevices, "idle", 6002, "none", "", "none",
                                    "backend"));
        if (!require(failedResponse.responseLength === 4
                     && JSON.stringify(failedResponse).indexOf("8642") === -1
                     && adapter.bluetoothOperationFailure === "backend"
                     && pairingStateIsClear(),
                     "pairing failure clears PIN and operation state")) {
            return;
        }

        const commandTranscript = JSON.stringify(fakeBridge.commands);
        if (!require(commandTranscript.indexOf("fixture-password") === -1
                     && commandTranscript.indexOf("queued-psk") === -1
                     && commandTranscript.indexOf("queued-hidden-psk") === -1
                     && commandTranscript.indexOf("queued-pin") === -1
                     && commandTranscript.indexOf("4821") === -1
                     && commandTranscript.indexOf("7319") === -1
                     && commandTranscript.indexOf("8642") === -1,
                     "submitted, rejected, and flooded secrets are absent from retained commands")) {
            return;
        }

        for (let replacement = 0; replacement < 5; ++replacement) {
            if (replacement === 0) {
                emitSnapshot(radio(true, true, true, false, "none", wifiRequestId, networks,
                                   "connecting", 7001),
                             bluetoothRadio(bluetoothDevices, "pairing", 7001, "display-pin",
                                            "9753"));
            }
            const commandsBeforeLoss = fakeBridge.commands.length;
            fakeBridge.fatalFailure();
            if (!require(adapter.bridge === bridgeBeforeSoak
                         && fakeBridge.commands.length === commandsBeforeLoss
                         && !adapter.wifiManagerOpen && !adapter.bluetoothManagerOpen
                         && !adapter.wifiAvailable && !adapter.bluetoothAvailable
                         && adapter.wifiFailure === "backend"
                         && adapter.bluetoothFailure === "backend"
                         && adapter.wifiOperation === "idle"
                         && adapter.bluetoothOperation === "idle" && pairingStateIsClear(),
                         "owner loss clears operations and secrets without duplicating the bridge")) {
                return;
            }

            emitSnapshot(radio(true, true, true, false, "none", wifiRequestId, networks, "idle",
                               7100 + replacement, "none", "none"),
                         bluetoothRadio(bluetoothDevices, "idle", 7100 + replacement));
            if (!require(adapter.bridge === bridgeBeforeSoak && adapter.backendReady
                         && adapter.wifiAvailable && adapter.bluetoothAvailable
                         && adapter.wifiEnabled && adapter.bluetoothEnabled
                         && adapter.wifiOperation === "idle"
                         && adapter.bluetoothOperation === "idle" && pairingStateIsClear(),
                         "replacement restores backend-owned state on the original bridge")) {
                return;
            }
        }

        if (!require(adapter.bridge === bridgeBeforeSoak && adapter.activeTimerCount === 0
                     && parser.activeTimerCount === 0,
                     "soak ends on the original bridge with exact zero fixture timers")) {
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

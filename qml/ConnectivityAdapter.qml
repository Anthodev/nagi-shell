pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

// Stable shared connectivity boundary for presentation and coordinator consumers.
// NetworkManager identity, D-Bus paths, profiles, BSSIDs, and secrets stay native.
Scope {
    id: root

    required property string helperPath

    // Verification seam. Production owns one native ConnectivityBridge.
    property var bridge: null

    readonly property bool backendReady: engine.currentBridge !== null && engine.currentBridge.ready
    readonly property bool wifiManagerOpen: engine.wifiInterest
    readonly property bool bluetoothManagerOpen: engine.bluetoothInterest

    readonly property bool wifiAvailable: engine.snapshot.wifi.available
    readonly property bool wifiEnabled: engine.snapshot.wifi.enabled
    readonly property bool wifiHardwareEnabled: engine.snapshot.wifi.hardwareEnabled
    readonly property bool wifiPending: engine.snapshot.wifi.pending || engine.wifiDispatchPending
                                        || engine.wifiManagerDispatchPending
    readonly property string wifiFailure: engine.snapshot.wifi.failure
    readonly property bool wifiScanning: engine.snapshot.wifi.scanning
    readonly property string wifiCurrentNetwork: engine.snapshot.wifi.currentNetwork
    readonly property var wifiNetworks: engine.snapshot.wifi.networks
    readonly property string wifiOperation: engine.snapshot.wifi.operation
    readonly property int wifiOperationGeneration: engine.snapshot.wifi.operationGeneration
    readonly property string wifiOperationFailure: engine.snapshot.wifi.operationFailure
    readonly property string wifiOperationResult: engine.snapshot.wifi.operationResult
    readonly property bool wifiBusy: wifiOperation !== "idle" || engine.wifiManagerDispatchPending

    readonly property bool bluetoothAvailable: engine.snapshot.bluetooth.available
    readonly property bool bluetoothEnabled: engine.snapshot.bluetooth.enabled
    readonly property bool bluetoothPending: engine.snapshot.bluetooth.pending
                                             || engine.bluetoothDispatchPending
                                             || engine.bluetoothManagerDispatchPending
    readonly property string bluetoothFailure: engine.snapshot.bluetooth.failure
    readonly property int bluetoothControllerCount: engine.snapshot.bluetooth.controllerCount
    readonly property int bluetoothSelectedController: engine.snapshot.bluetooth.selectedController
    readonly property bool bluetoothDiscovering: engine.snapshot.bluetooth.discovering
    readonly property int bluetoothDiscoveryDeadlineMs:
    engine.snapshot.bluetooth.discoveryDeadlineMs
    readonly property var bluetoothDevices: engine.snapshot.bluetooth.devices
    readonly property string bluetoothOperation: engine.snapshot.bluetooth.operation
    readonly property int bluetoothOperationGeneration:
    engine.snapshot.bluetooth.operationGeneration
    readonly property string bluetoothOperationFailure: engine.snapshot.bluetooth.operationFailure
    readonly property string bluetoothOperationResult: engine.snapshot.bluetooth.operationResult
    readonly property string bluetoothPairingPrompt: engine.snapshot.bluetooth.pairingPrompt
    readonly property string bluetoothPairingValue: engine.snapshot.bluetooth.pairingValue
    readonly property int bluetoothPairingEntered: engine.snapshot.bluetooth.pairingEntered
    readonly property int bluetoothPairingToken: engine.snapshot.bluetooth.pairingToken
    readonly property bool bluetoothBusy: bluetoothOperation !== "idle" && bluetoothOperation
                                          !== "discovering"
                                          || engine.bluetoothManagerDispatchPending

    readonly property int activeTimerCount: root.bridge === null ? nativeBridge.activeTimerCount : 0

    function requestWifiEnabled(enabled) {
        return engine.request("wifi", enabled === true);
    }

    function requestBluetoothEnabled(enabled) {
        return engine.request("bluetooth", enabled === true);
    }

    function toggleWifi() {
        return requestWifiEnabled(!wifiEnabled);
    }

    function toggleBluetooth() {
        return requestBluetoothEnabled(!bluetoothEnabled);
    }

    function setWifiManagerOpen(open) {
        return engine.setWifiInterest(open === true);
    }

    function refreshWifi() {
        return engine.dispatchWifiCommand("scan", {});
    }

    function connectWifi(token, secret, remember) {
        return engine.dispatchWifiCommand("connect", {
                                              "token": token,
                                              "secret": secret,
                                              "remember": remember === true
                                          });
    }

    function connectHiddenWifi(ssid, security, secret, remember) {
        return engine.dispatchWifiCommand("hidden-connect", {
                                              "ssid": ssid,
                                              "security": security,
                                              "secret": secret,
                                              "remember": remember === true
                                          });
    }

    function disconnectWifi() {
        return engine.dispatchWifiCommand("disconnect", {});
    }

    function forgetWifi(token) {
        return engine.dispatchWifiCommand("forget", {
                                              "token": token
                                          });
    }

    function setBluetoothManagerOpen(open) {
        return engine.setBluetoothInterest(open === true);
    }

    function scanBluetooth() {
        return engine.dispatchBluetoothCommand("scan", {});
    }

    function stopBluetoothScan() {
        return engine.dispatchBluetoothCommand("stop-scan", {});
    }

    function pairBluetooth(token) {
        return engine.dispatchBluetoothCommand("pair", {
                                                   "token": token
                                               });
    }

    function connectBluetooth(token) {
        return engine.dispatchBluetoothCommand("connect", {
                                                   "token": token
                                               });
    }

    function disconnectBluetooth(token) {
        return engine.dispatchBluetoothCommand("disconnect", {
                                                   "token": token
                                               });
    }

    function unpairBluetooth(token) {
        return engine.dispatchBluetoothCommand("unpair", {
                                                   "token": token
                                               });
    }

    function cancelBluetoothPairing() {
        return engine.dispatchBluetoothCommand("cancel", {});
    }

    function respondBluetoothPairing(accepted, response) {
        return engine.respondBluetoothPairing(accepted === true, typeof response === "string"
                                              ? response : "");
    }

    onBridgeChanged: engine.resetSnapshot("none")
    Component.onDestruction: engine.cleanup()

    ConnectivityBridge {
        id: nativeBridge

        helperPath: root.helperPath
        enabled: root.bridge === null
    }

    Connections {
        target: engine.currentBridge
        ignoreUnknownSignals: true

        function onSnapshotReceived(snapshot) {
            engine.acceptSnapshot(snapshot);
        }

        function onFatalFailure() {
            engine.resetSnapshot("backend");
        }
    }

    QtObject {
        id: engine

        property var currentBridge: root.bridge === null ? nativeBridge : root.bridge
        property int nextRequestId: 1
        property bool wifiDispatchPending: false
        property bool bluetoothDispatchPending: false
        property int wifiDispatchedRequestId: 0
        property int bluetoothDispatchedRequestId: 0
        property bool wifiManagerDispatchPending: false
        property int wifiManagerDispatchedGeneration: 0
        property bool wifiInterest: false
        property bool bluetoothManagerDispatchPending: false
        property int bluetoothManagerDispatchedGeneration: 0
        property bool bluetoothInterest: false
        property var snapshot: ({
                                    "wifi": unavailableWifiState("none"),
                                    "bluetooth": unavailableBluetoothState("none")
                                })

        function acceptSnapshot(candidate) {
            if (candidate === null || typeof candidate !== "object" || Array.isArray(candidate)
                    || candidate.wifi === null || candidate.bluetooth === null) {
                return;
            }
            if (wifiDispatchPending && candidate.wifi.requestId === wifiDispatchedRequestId) {
                wifiDispatchPending = false;
                wifiDispatchedRequestId = 0;
            }
            if (wifiManagerDispatchPending && candidate.wifi.operationGeneration
                    === wifiManagerDispatchedGeneration) {
                wifiManagerDispatchPending = false;
                wifiManagerDispatchedGeneration = 0;
            }
            if (bluetoothDispatchPending && candidate.bluetooth.requestId
                    === bluetoothDispatchedRequestId) {
                bluetoothDispatchPending = false;
                bluetoothDispatchedRequestId = 0;
            }
            if (bluetoothManagerDispatchPending && candidate.bluetooth.operationGeneration
                    === bluetoothManagerDispatchedGeneration) {
                bluetoothManagerDispatchPending = false;
                bluetoothManagerDispatchedGeneration = 0;
            }
            snapshot = candidate;
        }

        function allocateRequestId() {
            const requestId = nextRequestId;
            nextRequestId = nextRequestId >= 2147483647 ? 1 : nextRequestId + 1;
            return requestId;
        }

        function request(adapter, enabled) {
            const current = snapshot[adapter];
            const dispatchPending = adapter === "wifi" ? wifiDispatchPending :
                                                         bluetoothDispatchPending;
            if (currentBridge === null || !currentBridge.ready || current === undefined ||
                    !current.available || current.pending || dispatchPending || current.enabled
                    === enabled || (adapter === "wifi" && (!current.hardwareEnabled || (
                                                               current.operation !== "idle"
                                                               && current.operation
                                                               !== "scanning")))) {
                return false;
            }

            const requestId = allocateRequestId();
            if (!currentBridge.setEnabled(adapter, requestId, enabled)) {
                return false;
            }
            if (adapter === "wifi") {
                wifiDispatchPending = true;
                wifiDispatchedRequestId = requestId;
            } else {
                bluetoothDispatchPending = true;
                bluetoothDispatchedRequestId = requestId;
            }
            return true;
        }

        function setWifiInterest(interested) {
            if (currentBridge === null || !currentBridge.ready || wifiInterest === interested) {
                return false;
            }
            const generation = allocateRequestId();
            if (!currentBridge.setWifiInterest(generation, interested)) {
                return false;
            }
            wifiInterest = interested;
            return true;
        }

        function dispatchWifiCommand(operation, payload) {
            const current = snapshot.wifi;
            if (currentBridge === null || !currentBridge.ready || !wifiInterest ||
                    !current.available || !current.enabled || current.pending
                    || wifiManagerDispatchPending || (current.operation !== "idle"
                                                      && current.operation !== "scanning")) {
                return false;
            }
            const generation = allocateRequestId();
            let accepted = false;
            if (operation === "scan") {
                accepted = current.operation === "idle" && currentBridge.scanWifi(generation);
            } else if (operation === "connect") {
                accepted = Number.isInteger(payload.token) && payload.token > 0
                        && typeof payload.secret === "string" && currentBridge.connectWifi(
                            generation, payload.token, payload.secret, payload.remember === true);
            } else if (operation === "hidden-connect") {
                accepted = typeof payload.ssid === "string" && typeof payload.security === "string"
                        && typeof payload.secret === "string" && currentBridge.connectHiddenWifi(
                            generation, payload.ssid, payload.security, payload.secret,
                            payload.remember === true);
            } else if (operation === "disconnect") {
                accepted = current.operation === "idle" && current.currentNetwork !== ""
                        && currentBridge.disconnectWifi(generation);
            } else if (operation === "forget") {
                accepted = current.operation === "idle" && Number.isInteger(payload.token)
                        && payload.token > 0 && currentBridge.forgetWifi(generation, payload.token);
            }
            if (!accepted) {
                return false;
            }
            wifiManagerDispatchPending = true;
            wifiManagerDispatchedGeneration = generation;
            return true;
        }

        function setBluetoothInterest(interested) {
            if (currentBridge === null || !currentBridge.ready || bluetoothInterest
                    === interested) {
                return false;
            }
            const generation = allocateRequestId();
            if (!currentBridge.setBluetoothInterest(generation, interested)) {
                return false;
            }
            bluetoothInterest = interested;
            return true;
        }

        function dispatchBluetoothCommand(operation, payload) {
            const current = snapshot.bluetooth;
            if (currentBridge === null || !currentBridge.ready || !bluetoothInterest ||
                    !current.available || !current.enabled || current.pending
                    || bluetoothManagerDispatchPending) {
                return false;
            }
            const generation = allocateRequestId();
            let accepted = false;
            if (operation === "scan") {
                accepted = current.operation === "idle" && currentBridge.scanBluetooth(generation);
            } else if (operation === "stop-scan") {
                accepted = current.operation === "discovering" && currentBridge.stopBluetoothScan(
                            generation);
            } else if (operation === "pair") {
                accepted = (current.operation === "idle" || current.operation === "discovering")
                        && Number.isInteger(payload.token) && payload.token > 0
                        && currentBridge.pairBluetooth(generation, payload.token);
            } else if (operation === "connect") {
                accepted = (current.operation === "idle" || current.operation === "discovering")
                        && Number.isInteger(payload.token) && payload.token > 0
                        && currentBridge.connectBluetooth(generation, payload.token);
            } else if (operation === "disconnect") {
                accepted = (current.operation === "idle" || current.operation === "discovering")
                        && Number.isInteger(payload.token) && payload.token > 0
                        && currentBridge.disconnectBluetooth(generation, payload.token);
            } else if (operation === "unpair") {
                accepted = (current.operation === "idle" || current.operation === "discovering")
                        && Number.isInteger(payload.token) && payload.token > 0
                        && currentBridge.unpairBluetooth(generation, payload.token);
            } else if (operation === "cancel") {
                accepted = current.operation === "pairing" && currentBridge.cancelBluetoothPairing(
                            generation);
            }
            if (!accepted) {
                return false;
            }
            bluetoothManagerDispatchPending = true;
            bluetoothManagerDispatchedGeneration = generation;
            return true;
        }

        function respondBluetoothPairing(accepted, response) {
            const current = snapshot.bluetooth;
            if (currentBridge === null || !currentBridge.ready || !bluetoothInterest
                    || current.operation !== "pairing" || current.pairingPrompt === "none"
                    || bluetoothManagerDispatchPending || typeof response !== "string"
                    || response.length > 16) {
                return false;
            }
            const requestId = allocateRequestId();
            if (!currentBridge.respondBluetoothAgent(requestId, current.operationGeneration,
                                                     accepted, response)) {
                return false;
            }
            return true;
        }

        function unavailableWifiState(failure) {
            return {
                "available": false,
                "enabled": false,
                "hardwareEnabled": false,
                "networkingEnabled": false,
                "pending": false,
                "failure": failure,
                "requestId": 0,
                "scanning": false,
                "currentNetwork": "",
                "networks": Object.freeze([]),
                "operation": "idle",
                "operationGeneration": 0,
                "operationFailure": failure,
                "operationResult": "none"
            };
        }

        function unavailableBluetoothState(failure) {
            return {
                "available": false,
                "enabled": false,
                "hardwareEnabled": false,
                "pending": false,
                "failure": failure,
                "requestId": 0,
                "controllerCount": 0,
                "selectedController": 0,
                "discovering": false,
                "discoveryDeadlineMs": 0,
                "devices": Object.freeze([]),
                "operation": "idle",
                "operationGeneration": 0,
                "operationFailure": failure,
                "operationResult": "none",
                "pairingPrompt": "none",
                "pairingValue": "",
                "pairingEntered": 0,
                "pairingToken": 0
            };
        }

        function resetSnapshot(failure) {
            wifiDispatchPending = false;
            bluetoothDispatchPending = false;
            wifiDispatchedRequestId = 0;
            bluetoothDispatchedRequestId = 0;
            wifiManagerDispatchPending = false;
            wifiManagerDispatchedGeneration = 0;
            wifiInterest = false;
            bluetoothManagerDispatchPending = false;
            bluetoothManagerDispatchedGeneration = 0;
            bluetoothInterest = false;
            snapshot = {
                "wifi": unavailableWifiState(failure),
                "bluetooth": unavailableBluetoothState(failure)
            };
        }

        function cleanup() {
            currentBridge = null;
            resetSnapshot("none");
        }
    }
}

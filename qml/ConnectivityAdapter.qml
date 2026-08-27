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
    readonly property string bluetoothFailure: engine.snapshot.bluetooth.failure

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
        property var snapshot: ({
                                    "wifi": unavailableWifiState("none"),
                                    "bluetooth": unavailableState("none")
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

        function unavailableState(failure) {
            return {
                "available": false,
                "enabled": false,
                "hardwareEnabled": false,
                "pending": false,
                "failure": failure,
                "requestId": 0
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
            snapshot = {
                "wifi": unavailableWifiState(failure),
                "bluetooth": unavailableState(failure)
            };
        }

        function cleanup() {
            currentBridge = null;
            resetSnapshot("none");
        }
    }
}

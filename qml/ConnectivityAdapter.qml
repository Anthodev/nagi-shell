pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

// Stable connectivity boundary for presentation and coordinator consumers.
// Only normalized adapter state and toggle requests cross this object.
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
    readonly property string wifiFailure: engine.snapshot.wifi.failure

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
        property var snapshot: ({
                                    "wifi": unavailableState("none"),
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
                    === enabled || (adapter === "wifi" && !current.hardwareEnabled)) {
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
            snapshot = {
                "wifi": unavailableState(failure),
                "bluetooth": unavailableState(failure)
            };
        }

        function cleanup() {
            currentBridge = null;
            resetSnapshot("none");
        }
    }
}

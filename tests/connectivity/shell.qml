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

    function radio(available, enabled, hardwareEnabled, pending, failure, requestId) {
        return {
            "available": available,
            "enabled": enabled,
            "hardwareEnabled": hardwareEnabled,
            "pending": pending,
            "failure": failure,
            "requestId": requestId
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

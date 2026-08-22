import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    property int stage: 0
    property bool initialWifi: false
    property bool initialBluetooth: false
    property bool sawWifiPending: false
    property bool sawBluetoothPending: false

    function fail(message) {
        console.error("FAIL: " + message);
        Qt.exit(1);
    }

    function advance() {
        if (adapter.wifiPending) {
            sawWifiPending = true;
        }
        if (adapter.bluetoothPending) {
            sawBluetoothPending = true;
        }

        if (stage === 0) {
            if (!adapter.backendReady || !adapter.wifiAvailable || !adapter.wifiHardwareEnabled ||
                    !adapter.bluetoothAvailable) {
                return;
            }
            initialWifi = adapter.wifiEnabled;
            initialBluetooth = adapter.bluetoothEnabled;
            stage = 1;
            if (!adapter.requestWifiEnabled(!initialWifi)) {
                fail("live Wi-Fi change was rejected");
            }
            return;
        }
        if (stage === 1 && !adapter.wifiPending && adapter.wifiEnabled === !initialWifi) {
            stage = 2;
            if (!adapter.requestWifiEnabled(initialWifi)) {
                fail("live Wi-Fi restoration was rejected");
            }
            return;
        }
        if (stage === 2 && !adapter.wifiPending && adapter.wifiEnabled === initialWifi) {
            stage = 3;
            if (!adapter.requestBluetoothEnabled(!initialBluetooth)) {
                fail("live Bluetooth change was rejected");
            }
            return;
        }
        if (stage === 3 && !adapter.bluetoothPending && adapter.bluetoothEnabled ===
                !initialBluetooth) {
            stage = 4;
            if (!adapter.requestBluetoothEnabled(initialBluetooth)) {
                fail("live Bluetooth restoration was rejected");
            }
            return;
        }
        if (stage === 4 && !adapter.bluetoothPending && adapter.bluetoothEnabled
                === initialBluetooth) {
            if (!sawWifiPending || !sawBluetoothPending || adapter.wifiFailure !== "none"
                    || adapter.bluetoothFailure !== "none" || adapter.activeTimerCount !== 0) {
                fail("live actions did not settle cleanly");
                return;
            }
            timeout.stop();
            console.warn("live Wi-Fi and Bluetooth changes restored successfully");
            Qt.exit(0);
        }
    }

    ConnectivityAdapter {
        id: adapter

        helperPath: Quickshell.env("NAGI_CONNECTIVITY_HELPER")
        onBackendReadyChanged: Qt.callLater(test.advance)
        onWifiAvailableChanged: Qt.callLater(test.advance)
        onWifiHardwareEnabledChanged: Qt.callLater(test.advance)
        onWifiEnabledChanged: Qt.callLater(test.advance)
        onWifiPendingChanged: Qt.callLater(test.advance)
        onWifiFailureChanged: Qt.callLater(test.advance)
        onBluetoothAvailableChanged: Qt.callLater(test.advance)
        onBluetoothEnabledChanged: Qt.callLater(test.advance)
        onBluetoothPendingChanged: Qt.callLater(test.advance)
        onBluetoothFailureChanged: Qt.callLater(test.advance)
    }

    Timer {
        id: timeout

        interval: 15000
        running: true
        onTriggered: test.fail("live connectivity timed out at stage " + test.stage + " (ready="
                               + adapter.backendReady + ", wifi=" + adapter.wifiAvailable + "/"
                               + adapter.wifiEnabled + "/" + adapter.wifiPending + "/"
                               + adapter.wifiFailure + ", bluetooth=" + adapter.bluetoothAvailable
                               + "/" + adapter.bluetoothEnabled + "/" + adapter.bluetoothPending
                               + "/" + adapter.bluetoothFailure + ")")
    }

    Component.onCompleted: Qt.callLater(test.advance)
}

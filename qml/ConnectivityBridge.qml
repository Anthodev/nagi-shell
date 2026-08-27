pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

// Bounded JSON-lines wrapper for the Nagi-owned D-Bus helper. The helper
// contains every NetworkManager and BlueZ object path, property, and error.
Scope {
    id: root

    required property string helperPath
    property bool enabled: true

    readonly property bool ready: state.ready
    readonly property int activeTimerCount: restartTimer.running ? 1 : 0
    readonly property int maximumLineLength: 16384
    readonly property int maximumDiagnostics: 4

    signal snapshotReceived(var snapshot)
    signal fatalFailure

    function setEnabled(adapter, requestId, enabled) {
        return send({
                        "op": "set",
                        "adapter": adapter,
                        "requestId": requestId,
                        "enabled": enabled
                    });
    }

    function setWifiInterest(requestId, interested) {
        return send({
                        "op": "wifi-interest",
                        "requestId": requestId,
                        "interested": interested
                    });
    }

    function scanWifi(requestId) {
        return send({
                        "op": "scan",
                        "requestId": requestId
                    });
    }

    function connectWifi(requestId, token, secret, remember) {
        return send({
                        "op": "connect",
                        "requestId": requestId,
                        "token": token,
                        "secret": secret,
                        "remember": remember
                    });
    }

    function connectHiddenWifi(requestId, ssid, security, secret, remember) {
        return send({
                        "op": "hidden-connect",
                        "requestId": requestId,
                        "ssid": ssid,
                        "security": security,
                        "secret": secret,
                        "remember": remember
                    });
    }

    function disconnectWifi(requestId) {
        return send({
                        "op": "disconnect",
                        "requestId": requestId
                    });
    }

    function forgetWifi(requestId, token) {
        return send({
                        "op": "forget",
                        "requestId": requestId,
                        "token": token
                    });
    }

    function setBluetoothInterest(requestId, interested) {
        return send({
                        "op": "bluetooth-interest",
                        "requestId": requestId,
                        "interested": interested
                    });
    }

    function scanBluetooth(requestId) {
        return send({
                        "op": "bluetooth-scan",
                        "requestId": requestId
                    });
    }

    function stopBluetoothScan(requestId) {
        return send({
                        "op": "bluetooth-stop-scan",
                        "requestId": requestId
                    });
    }

    function pairBluetooth(requestId, token) {
        return send({
                        "op": "bluetooth-pair",
                        "requestId": requestId,
                        "token": token
                    });
    }

    function connectBluetooth(requestId, token) {
        return send({
                        "op": "bluetooth-connect",
                        "requestId": requestId,
                        "token": token
                    });
    }

    function disconnectBluetooth(requestId, token) {
        return send({
                        "op": "bluetooth-disconnect",
                        "requestId": requestId,
                        "token": token
                    });
    }

    function unpairBluetooth(requestId, token) {
        return send({
                        "op": "bluetooth-unpair",
                        "requestId": requestId,
                        "token": token
                    });
    }

    function cancelBluetoothPairing(requestId) {
        return send({
                        "op": "bluetooth-cancel",
                        "requestId": requestId
                    });
    }

    function respondBluetoothAgent(requestId, generation, accepted, response) {
        return send({
                        "op": "bluetooth-agent-response",
                        "requestId": requestId,
                        "generation": generation,
                        "accepted": accepted,
                        "response": response
                    });
    }

    function send(command) {
        if (!state.ready || !helper.running) {
            return false;
        }
        const line = JSON.stringify(command);
        if (line.length === 0 || line.length > root.maximumLineLength) {
            return false;
        }
        helper.write(line + "\n");
        return true;
    }

    function acceptLine(line) {
        if (typeof line !== "string" || line.length === 0 || line.length > root.maximumLineLength) {
            warnBounded("invalid helper line length");
            return;
        }

        let message;
        try {
            message = JSON.parse(line);
        } catch (error) {
            warnBounded("malformed helper line");
            return;
        }
        if (message === null || typeof message !== "object" || Array.isArray(message)
                || typeof message.type !== "string") {
            warnBounded("invalid helper message");
            return;
        }
        if (message.type === "ready") {
            state.ready = true;
            state.restartAttempts = 0;
            return;
        }
        if (message.type !== "state" || !validWifiState(message.wifi) || !validBluetoothState(
                    message.bluetooth)) {
            warnBounded("invalid helper state");
            return;
        }

        root.snapshotReceived({
                                  "wifi": normalizedWifiState(message.wifi),
                                  "bluetooth": normalizedBluetoothState(message.bluetooth)
                              });
    }

    function normalizedBluetoothState(candidate) {
        return {
            "available": candidate.available,
            "enabled": candidate.enabled,
            "hardwareEnabled": candidate.hardwareEnabled,
            "pending": candidate.pending,
            "failure": candidate.failure,
            "requestId": candidate.requestId,
            "controllerCount": candidate.controllerCount,
            "selectedController": candidate.selectedController,
            "discovering": candidate.discovering,
            "discoveryDeadlineMs": candidate.discoveryDeadlineMs,
            "devices": candidate.devices.map(device => ({
                "token": device.token,
                "name": device.name,
                "type": device.type,
                "signal": device.signal,
                "paired": device.paired,
                "connected": device.connected,
                "trusted": device.trusted,
                "pairable": device.pairable,
                "connectable": device.connectable,
                "disconnectable": device.disconnectable,
                "unpairable": device.unpairable
            })),
        "operation": candidate.operation,
        "operationGeneration": candidate.operationGeneration,
        "operationFailure": candidate.operationFailure,
        "operationResult": candidate.operationResult,
        "pairingPrompt": candidate.pairingPrompt,
        "pairingValue": candidate.pairingValue,
        "pairingEntered": candidate.pairingEntered,
        "pairingToken": candidate.pairingToken
    };
    }

        function normalizedWifiState(candidate) {
        return {
        "available": candidate.available,
        "enabled": candidate.enabled,
        "hardwareEnabled": candidate.hardwareEnabled,
        "networkingEnabled": candidate.networkingEnabled,
        "pending": candidate.pending,
        "failure": candidate.failure,
        "requestId": candidate.requestId,
        "scanning": candidate.scanning,
        "currentNetwork": candidate.currentNetwork,
        "networks": candidate.networks.map(network => ({
        "token": network.token,
        "ssid": network.ssid,
        "security": network.security,
        "strength": network.strength,
        "connected": network.connected,
        "saved": network.saved,
        "forgettable": network.forgettable,
        "connectable": network.connectable,
        "forgetReason": network.forgetReason
    })),
        "operation": candidate.operation,
        "operationGeneration": candidate.operationGeneration,
        "operationFailure": candidate.operationFailure,
        "operationResult": candidate.operationResult
    };
    }

        function validWifiState(candidate) {
        if (!validAdapterState(candidate) || typeof candidate.networkingEnabled !== "boolean"
        || typeof candidate.scanning !== "boolean" || typeof candidate.currentNetwork !== "string"
        || candidate.currentNetwork.length > 32 || !Array.isArray(candidate.networks)
        || candidate.networks.length > 16 || !validOperation(candidate.operation) ||
        !Number.isInteger(candidate.operationGeneration) || candidate.operationGeneration < 0
        || candidate.operationGeneration > 2147483647 || !validOperationFailure(
        candidate.operationFailure) || !validOperationResult(candidate.operationResult)) {
        return false;
    }
        for (let index = 0; index < candidate.networks.length; index += 1) {
        if (!validWifiNetwork(candidate.networks[index])) {
        return false;
    }
    }
        return candidate.available || (!candidate.scanning && candidate.currentNetwork === ""
        && candidate.networks.length === 0 && candidate.operation === "idle");
    }

        function validWifiNetwork(candidate) {
        return candidate !== null && typeof candidate === "object" && !Array.isArray(candidate)
        && Number.isInteger(candidate.token) && candidate.token >= 1 && candidate.token
        <= 2147483647 && typeof candidate.ssid === "string" && candidate.ssid.length >= 1
        && candidate.ssid.length <= 32 && (candidate.security === "open" || candidate.security === "wpa-personal"
        || candidate.security === "unsupported") && Number.isInteger(candidate.strength)
        && candidate.strength >= 0 && candidate.strength <= 100 && typeof candidate.connected
        === "boolean" && typeof candidate.saved === "boolean" && typeof candidate.forgettable
        === "boolean" && typeof candidate.connectable === "boolean" && (candidate.forgetReason
        === "none" || candidate.forgetReason === "admin-owned") && (!candidate.forgettable
        || candidate.saved);
    }

        function validOperation(operation) {
        return operation === "idle" || operation === "radio" || operation === "scanning"
        || operation === "connecting" || operation === "disconnecting" || operation
        === "forgetting";
    }

        function validOperationFailure(failure) {
        return validFailure(failure) || failure === "wrong-secret" || failure === "cooldown"
        || failure === "invalid" || failure === "busy";
    }

        function validOperationResult(result) {
        return result === "none" || result === "scan-complete" || result === "connected" || result
        === "disconnected" || result === "forgotten" || result === "radio-updated" || result
        === "cancelled" || result === "replaced";
    }

        function validBluetoothState(candidate) {
        if (!validAdapterState(candidate) || !Number.isInteger(candidate.controllerCount)
        || candidate.controllerCount < 0 || candidate.controllerCount > 2147483647 ||
        !Number.isInteger(candidate.selectedController) || candidate.selectedController < 0
        || candidate.selectedController > candidate.controllerCount || typeof candidate.discovering
        !== "boolean" || !Number.isInteger(candidate.discoveryDeadlineMs)
        || candidate.discoveryDeadlineMs < 0 || candidate.discoveryDeadlineMs > 30000 ||
        !Array.isArray(candidate.devices) || candidate.devices.length > 32 ||
        !validBluetoothOperation(candidate.operation) || !Number.isInteger(
        candidate.operationGeneration) || candidate.operationGeneration < 0
        || candidate.operationGeneration > 2147483647 || !validBluetoothFailure(
        candidate.operationFailure) || !validBluetoothResult(candidate.operationResult) ||
        !validPairingPrompt(candidate.pairingPrompt) || typeof candidate.pairingValue !== "string"
        || candidate.pairingValue.length > 16 || !Number.isInteger(candidate.pairingEntered)
        || candidate.pairingEntered < 0 || candidate.pairingEntered > 16 || !Number.isInteger(
        candidate.pairingToken) || candidate.pairingToken < 0 || candidate.pairingToken
        > 2147483647) {
        return false;
    }
        for (let index = 0; index < candidate.devices.length; index += 1) {
        if (!validBluetoothDevice(candidate.devices[index])) {
        return false;
    }
    }
        return candidate.available || (!candidate.enabled && !candidate.discovering
        && candidate.devices.length === 0 && candidate.operation === "idle");
    }

        function validBluetoothDevice(candidate) {
        return candidate !== null && typeof candidate === "object" && !Array.isArray(candidate)
        && Number.isInteger(candidate.token) && candidate.token >= 1 && candidate.token
        <= 2147483647 && typeof candidate.name === "string" && candidate.name.length >= 1
        && candidate.name.length <= 64 && (candidate.type === "audio" || candidate.type === "input"
        || candidate.type === "phone" || candidate.type === "computer" || candidate.type
        === "other") && Number.isInteger(candidate.signal) && candidate.signal >= -1
        && candidate.signal <= 100 && typeof candidate.paired === "boolean"
        && typeof candidate.connected === "boolean" && typeof candidate.trusted === "boolean"
        && typeof candidate.pairable === "boolean" && typeof candidate.connectable === "boolean"
        && typeof candidate.disconnectable === "boolean" && typeof candidate.unpairable
        === "boolean";
    }

        function validBluetoothOperation(operation) {
        return operation === "idle" || operation === "discovering" || operation === "pairing"
        || operation === "connecting" || operation === "disconnecting" || operation === "unpairing";
    }

        function validBluetoothFailure(failure) {
        return validFailure(failure) || failure === "cancelled" || failure === "rejected"
        || failure === "busy" || failure === "connection-failed" || failure === "trust-failed";
    }

        function validBluetoothResult(result) {
        return result === "none" || result === "stopped" || result === "expired" || result
        === "cancelled" || result === "replaced" || result === "connected" || result
        === "disconnected" || result === "unpaired" || result === "paired" || result
        === "paired-connected";
    }

        function validPairingPrompt(prompt) {
        return prompt === "none" || prompt === "enter-pin" || prompt === "display-pin" || prompt
        === "enter-passkey" || prompt === "display-passkey" || prompt === "confirm-passkey"
        || prompt === "authorize-pairing";
    }

        function validAdapterState(candidate) {
        return candidate !== null && typeof candidate === "object" && !Array.isArray(candidate)
        && typeof candidate.available === "boolean" && typeof candidate.enabled === "boolean"
        && typeof candidate.hardwareEnabled === "boolean" && typeof candidate.pending === "boolean"
        && validFailure(candidate.failure) && Number.isInteger(candidate.requestId)
        && candidate.requestId >= 0 && candidate.requestId <= 2147483647 && (!candidate.available ?
        !candidate.enabled && !candidate.hardwareEnabled && !candidate.pending : true);
    }

        function validFailure(failure) {
        return failure === "none" || failure === "unavailable" || failure === "hardware" || failure
        === "denied" || failure === "timeout" || failure === "backend";
    }

        function warnBounded(message) {
        if (state.diagnosticCount >= root.maximumDiagnostics) {
        return;
    }
        state.diagnosticCount += 1;
        console.warn("Connectivity bridge: " + message);
    }

        function forwardDiagnostic(message) {
        if (state.diagnosticCount >= root.maximumDiagnostics) {
        return;
    }
        state.diagnosticCount += 1;
        const bounded = typeof message === "string" ? message.slice(0, 256) :
        "invalid helper diagnostic";
        console.warn("Connectivity helper: " + bounded);
    }

        function failBridge() {
        state.ready = false;
        root.fatalFailure();
    }

        onEnabledChanged: {
        if (enabled) {
        state.restartAttempts = 0;
        state.restartAllowed = true;
    } else {
        restartTimer.stop();
        state.restartAllowed = false;
        state.ready = false;
    }
    }

        QtObject {
        id: state

        property bool ready: false
        property bool restartAllowed: true
        property bool destroying: false
        property int restartAttempts: 0
        property int diagnosticCount: 0
    }

        Timer {
        id: restartTimer

        interval: 250 * Math.pow(2, Math.max(0, state.restartAttempts - 1))
        onTriggered: state.restartAllowed = true
    }

        Process {
        id: helper

        command: [root.helperPath]
        stdinEnabled: true
        running: root.enabled && root.helperPath !== "" && state.restartAllowed

        stdout: SplitParser {
        onRead: data => root.acceptLine(data)
    }

        stderr: SplitParser {
        onRead: data => root.forwardDiagnostic(data)
    }

        onStarted: state.ready = false
        onExited: function (exitCode, exitStatus) {
        root.failBridge();
        if (!state.destroying && root.enabled && state.restartAttempts < 3) {
        state.restartAttempts += 1;
        state.restartAllowed = false;
        restartTimer.restart();
    } else {
        state.restartAllowed = false;
    }
    }
    }

        Component.onDestruction: {
        state.destroying = true;
        restartTimer.stop();
        if (helper.running && state.ready) {
        helper.write("{\"op\":\"shutdown\"}\n");
    }
        helper.running = false;
        state.ready = false;
    }
    }

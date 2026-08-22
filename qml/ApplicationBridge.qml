pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: root

    required property string helperPath
    required property string pinsPath
    required property string recencyPath
    property bool enabled: true

    readonly property bool ready: state.ready
    readonly property int maximumLineLength: 20 * 1024 * 1024
    readonly property int maximumCommandLength: 8192
    readonly property int maximumDiagnostics: 4

    signal initialized(var stores)
    signal generationReceived(var generation)
    signal writeReady(string store, int serial, bool success, string category)
    signal writeVerified(string store, int serial, bool success, string category)
    signal fatalFailure

    function scan(generation) {
        return send({
                        "op": "scan",
                        "generation": generation
                    });
    }

    function prepareWrite(store, serial) {
        return send({
                        "op": "prepare-write",
                        "store": store,
                        "serial": serial
                    });
    }

    function verifyWrite(store, serial) {
        return send({
                        "op": "verify-write",
                        "store": store,
                        "serial": serial
                    });
    }

    function send(command) {
        if (!state.ready || !helper.running) {
            return false;
        }
        const line = JSON.stringify(command);
        if (line.length === 0 || line.length > root.maximumCommandLength) {
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

        if (message.type === "initialized") {
            if (!validStores(message.stores)) {
                warnBounded("invalid initialization");
                return;
            }
            state.ready = true;
            state.restartAttempts = 0;
            root.initialized(message.stores);
            return;
        }
        if (message.type === "generation") {
            if (!validGeneration(message)) {
                warnBounded("invalid discovery generation");
                return;
            }
            root.generationReceived(message);
            return;
        }
        if (message.type === "write-ready" || message.type === "write-verified") {
            if (!validWriteResponse(message)) {
                warnBounded("invalid write response");
                return;
            }
            if (message.type === "write-ready") {
                root.writeReady(message.store, message.serial, message.success, message.category);
            } else {
                root.writeVerified(message.store, message.serial, message.success,
                                   message.category);
            }
            return;
        }
        if (message.type === "error") {
            warnBounded("helper protocol failure");
            return;
        }
        warnBounded("unknown helper message");
    }

    function validStores(stores) {
        return stores !== null && typeof stores === "object" && !Array.isArray(stores) && validStore(
                    stores.pins) && validStore(stores.recency);
    }

    function validStore(store) {
        if (store === null || typeof store !== "object" || Array.isArray(store)
                || typeof store.available !== "boolean" || !validCategory(store.category)) {
            return false;
        }
        const hasText = store.category === "loaded" || store.category === "empty";
        return hasText ? typeof store.text === "string" && store.text.length <= 128 * 1024 :
                         typeof store.text === "undefined";
    }

    function validGeneration(message) {
        if (!Number.isInteger(message.generation) || message.generation < 0 || message.generation
                > 2147483647 || typeof message.complete !== "boolean") {
            return false;
        }
        if (!message.complete) {
            return message.failure === "discovery";
        }
        if (!Array.isArray(message.entries) || message.entries.length > 4096) {
            return false;
        }
        const seen = {};
        for (let index = 0; index < message.entries.length; ++index) {
            const entry = message.entries[index];
            if (entry === null || typeof entry !== "object" || Array.isArray(entry) || !validDesktopId(
                        entry.id) || typeof entry.quickshellId !== "string"
                    || entry.quickshellId.length === 0 || entry.quickshellId + ".desktop"
                    !== entry.id || seen[entry.id] === true) {
                return false;
            }
            seen[entry.id] = true;
        }
        return true;
    }

    function validWriteResponse(message) {
        return (message.store === "pins" || message.store === "recency") && Number.isInteger(message.serial)
                && message.serial >= 0 && message.serial <= 2147483647 && typeof message.success === "boolean"
                && validCategory(message.category);
    }

    function validDesktopId(id) {
        if (typeof id !== "string" || id.length <= 8 || !id.endsWith(".desktop") || id.indexOf("\u0000")
                !== -1) {
            return false;
        }
        try {
            return unescape(encodeURIComponent(id)).length <= 4096;
        } catch (error) {
            return false;
        }
    }

    function validCategory(category) {
        return category === "none" || category === "missing" || category === "empty" || category
                === "loaded" || category === "oversized" || category === "utf8" || category
                === "path" || category === "directory" || category === "read" || category
                === "write" || category === "symlink" || category === "permissions" || category
                === "protocol" || category === "unavailable";
    }

    function warnBounded(message) {
        if (state.diagnosticCount >= root.maximumDiagnostics) {
            return;
        }
        state.diagnosticCount += 1;
        console.warn("Application bridge: " + message);
    }

    function forwardDiagnostic(message) {
        if (state.diagnosticCount >= root.maximumDiagnostics) {
            return;
        }
        state.diagnosticCount += 1;
        const bounded = typeof message === "string" ? message.slice(0, 256) :
                                                      "invalid helper diagnostic";
        console.warn("Application helper: " + bounded);
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

        command: [root.helperPath, root.pinsPath, root.recencyPath]
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

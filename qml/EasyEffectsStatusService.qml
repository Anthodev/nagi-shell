pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

// Visible-interest-only boundary for EasyEffects' official native status socket.
// Only bounded preset names and normalized states cross into presentation.
Scope {
    id: root

    required property string helperPath

    readonly property bool interested: state.ownerEpoch > 0
    readonly property bool ready: state.ready
    readonly property bool refreshing: state.pendingPipelines > 0
    readonly property string outputState: state.outputState
    readonly property string outputName: state.outputName
    readonly property string inputState: state.inputState
    readonly property string inputName: state.inputName
    readonly property var outputPresets: state.outputPresets
    readonly property string outputPresetsState: state.outputPresetsState
    readonly property var inputPresets: state.inputPresets
    readonly property string inputPresetsState: state.inputPresetsState
    readonly property bool loadPending: state.loadPending
    readonly property string loadPipeline: state.loadPipeline
    readonly property string loadState: state.loadState
    readonly property int activeTimerCount: restartTimer.running ? 1 : 0

    readonly property int maximumFrameLength: 4096
    readonly property int maximumPresetCharacters: 128
    readonly property int maximumPresetEntries: 128
    readonly property int maximumDiagnostics: 4

    function activate(ownerEpoch) {
        if (!validOwnerEpoch(ownerEpoch)) {
            return false;
        }
        if (state.ownerEpoch === ownerEpoch) {
            return true;
        }
        if (state.generation >= 2147483647) {
            state.restartAllowed = false;
            return false;
        }
        state.ownerEpoch = ownerEpoch;
        state.generation += 1;
        state.restartAttempts = 0;
        state.restartAllowed = true;
        clearPipelineState();
        if (state.ready) {
            requestInterest();
        }
        return true;
    }

    function deactivate(ownerEpoch) {
        if (!validOwnerEpoch(ownerEpoch) || state.ownerEpoch !== ownerEpoch) {
            return false;
        }
        if (state.ready) {
            send({
                     "op": "interest",
                     "generation": state.generation,
                     "active": false
                 });
        }
        state.ownerEpoch = 0;
        state.ready = false;
        state.restartAllowed = false;
        restartTimer.stop();
        clearPipelineState();
        return true;
    }

    function refresh(ownerEpoch) {
        if (!state.ready || state.ownerEpoch !== ownerEpoch || state.pendingPipelines > 0
                || state.loadPending) {
            return false;
        }
        state.loadPipeline = "";
        state.loadState = "none";
        beginPipelineRequest();
        const accepted = send({
                                  "op": "refresh",
                                  "generation": state.generation
                              });
        if (!accepted) {
            cancelPendingRequest();
        }
        return accepted;
    }

    function loadPreset(ownerEpoch, pipeline, name) {
        if (!state.ready || state.ownerEpoch !== ownerEpoch || state.pendingPipelines > 0
                || state.loadPending || !validPipeline(pipeline) || !validPresetName(name) ||
                !presetListed(pipeline, name)) {
            return false;
        }
        const currentState = pipeline === "output" ? state.outputState : state.inputState;
        const currentName = pipeline === "output" ? state.outputName : state.inputName;
        if (currentState === "lastLoaded" && currentName === name) {
            state.loadPipeline = pipeline;
            state.loadState = "confirmed";
            return true;
        }
        state.loadPending = true;
        state.loadPipeline = pipeline;
        state.loadState = "pending";
        const accepted = send({
                                  "op": "load",
                                  "generation": state.generation,
                                  "pipeline": pipeline,
                                  "name": name
                              });
        if (!accepted) {
            state.loadPending = false;
            state.loadState = "unavailable";
        }
        return accepted;
    }

    function requestInterest() {
        if (!state.ready || !interested) {
            return false;
        }
        clearPipelineState();
        beginPipelineRequest();
        const accepted = send({
                                  "op": "interest",
                                  "generation": state.generation,
                                  "active": true
                              });
        if (!accepted) {
            cancelPendingRequest();
        }
        return accepted;
    }

    function beginPipelineRequest() {
        state.outputPending = true;
        state.inputPending = true;
        state.outputPresetsPending = true;
        state.inputPresetsPending = true;
        state.pendingPipelines = 4;
    }

    function cancelPendingRequest() {
        state.pendingPipelines = 0;
        state.outputPending = false;
        state.inputPending = false;
        state.outputPresetsPending = false;
        state.inputPresetsPending = false;
    }

    function clearPipelineState() {
        state.outputState = "unknown";
        state.outputName = "";
        state.inputState = "unknown";
        state.inputName = "";
        state.outputPresets = [];
        state.outputPresetsState = "unknown";
        state.inputPresets = [];
        state.inputPresetsState = "unknown";
        state.pendingPipelines = 0;
        state.outputPending = false;
        state.inputPending = false;
        state.outputPresetsPending = false;
        state.inputPresetsPending = false;
        state.loadPending = false;
        state.loadPipeline = "";
        state.loadState = "none";
    }

    function send(command) {
        if (!state.ready || !helper.running) {
            return false;
        }
        const line = JSON.stringify(command);
        if (line.length === 0 || line.length > maximumFrameLength) {
            return false;
        }
        helper.write(line + "\n");
        return true;
    }

    function acceptLine(line) {
        if (typeof line !== "string" || line.length === 0 || line.length > maximumFrameLength) {
            warnBounded("invalid helper frame length");
            return;
        }
        let message;
        try {
            message = JSON.parse(line);
        } catch (error) {
            warnBounded("malformed helper frame");
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
            requestInterest();
            return;
        }
        if (message.type === "load") {
            if (!validGeneration(message.generation) || !validPipeline(message.pipeline) ||
                    !validLoadState(message.state)) {
                warnBounded("invalid load message");
                return;
            }
            if (!interested || message.generation !== state.generation || !state.loadPending
                    || message.pipeline !== state.loadPipeline) {
                return;
            }
            state.loadPending = false;
            state.loadState = message.state;
            return;
        }
        if (message.type === "presets") {
            if (!validGeneration(message.generation) || !validPipeline(message.pipeline) ||
                    !validPresetListState(message.state) || !Array.isArray(message.items)
                    || message.items.length > maximumPresetEntries) {
                warnBounded("invalid preset list message");
                return;
            }
            if (!interested || message.generation !== state.generation) {
                return;
            }
            const names = [];
            for (const name of message.items) {
                if (!validPresetName(name) || names.indexOf(name) !== -1) {
                    warnBounded("invalid preset list item");
                    return;
                }
                names.push(name);
            }
            if (message.pipeline === "output") {
                state.outputPresets = names;
                state.outputPresetsState = message.state;
                if (state.outputPresetsPending) {
                    state.outputPresetsPending = false;
                    state.pendingPipelines -= 1;
                }
            } else {
                state.inputPresets = names;
                state.inputPresetsState = message.state;
                if (state.inputPresetsPending) {
                    state.inputPresetsPending = false;
                    state.pendingPipelines -= 1;
                }
            }
            return;
        }
        if (message.type !== "pipeline" || !validGeneration(message.generation) || !validPipeline(
                    message.pipeline) || !validPipelineState(message.state)) {
            warnBounded("invalid pipeline message");
            return;
        }
        if (!interested || message.generation !== state.generation) {
            return;
        }
        let name = "";
        if (message.state === "lastLoaded") {
            if (!validPresetName(message.name)) {
                warnBounded("invalid preset name");
                return;
            }
            name = message.name;
        } else if (Object.prototype.hasOwnProperty.call(message, "name")) {
            warnBounded("unexpected preset name");
            return;
        }
        if (message.pipeline === "output") {
            state.outputState = message.state;
            state.outputName = name;
            if (state.outputPending) {
                state.outputPending = false;
                state.pendingPipelines -= 1;
            }
        } else {
            state.inputState = message.state;
            state.inputName = name;
            if (state.inputPending) {
                state.inputPending = false;
                state.pendingPipelines -= 1;
            }
        }
    }

    function validOwnerEpoch(value) {
        return typeof value === "number" && Number.isFinite(value) && value > 0;
    }

    function validPipeline(value) {
        return value === "output" || value === "input";
    }
    function validGeneration(value) {
        return Number.isInteger(value) && value > 0 && value <= 2147483647;
    }

    function validPipelineState(value) {
        return value === "none" || value === "lastLoaded" || value === "unavailable" || value
                === "invalid" || value === "timeout";
    }

    function validPresetListState(value) {
        return value === "ready" || value === "truncated" || value === "unavailable";
    }

    function presetListed(pipeline, name) {
        const presets = pipeline === "output" ? state.outputPresets : state.inputPresets;
        return Array.isArray(presets) && presets.indexOf(name) !== -1;
    }

    function validLoadState(value) {
        return value === "confirmed" || value === "mismatch" || value === "unavailable" || value
                === "invalid" || value === "timeout";
    }

    function validPresetName(value) {
        if (typeof value !== "string" || value.length === 0 || value.length
                > maximumPresetCharacters ||
                /[\u0000-\u001f\u007f:/\\\u200e-\u200f\u2028-\u202e\u2066-\u2069]/u.test(value)) {
            return false;
        }
        let byteCount = 0;
        let scalarCount = 0;
        for (let index = 0; index < value.length; ++index) {
            const codeUnit = value.charCodeAt(index);
            if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
                if (index + 1 >= value.length) {
                    return false;
                }
                const low = value.charCodeAt(index + 1);
                if (low < 0xdc00 || low > 0xdfff) {
                    return false;
                }
                index += 1;
                byteCount += 4;
            } else if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
                return false;
            } else if (codeUnit <= 0x7f) {
                byteCount += 1;
            } else if (codeUnit <= 0x7ff) {
                byteCount += 2;
            } else {
                byteCount += 3;
            }
            scalarCount += 1;
            if (byteCount > 100 || scalarCount > maximumPresetCharacters) {
                return false;
            }
        }
        return true;
    }

    function warnBounded(message) {
        if (state.diagnosticCount >= maximumDiagnostics) {
            return;
        }
        state.diagnosticCount += 1;
        console.warn("EasyEffects status service: " + message);
    }

    function forwardDiagnostic(message) {
        if (state.diagnosticCount >= maximumDiagnostics) {
            return;
        }
        state.diagnosticCount += 1;
        const bounded = typeof message === "string" ? message.slice(0, 256) :
                                                      "invalid helper diagnostic";
        console.warn("EasyEffects status helper: " + bounded);
    }

    QtObject {
        id: state

        property real ownerEpoch: 0
        property int generation: 0
        property bool ready: false
        property bool restartAllowed: false
        property int restartAttempts: 0
        property int diagnosticCount: 0
        property int pendingPipelines: 0
        property bool outputPending: false
        property bool inputPending: false
        property bool outputPresetsPending: false
        property bool inputPresetsPending: false
        property string outputState: "unknown"
        property string outputName: ""
        property string inputState: "unknown"
        property string inputName: ""
        property var outputPresets: []
        property string outputPresetsState: "unknown"
        property var inputPresets: []
        property string inputPresetsState: "unknown"
        property bool loadPending: false
        property string loadPipeline: ""
        property string loadState: "none"
        property bool destroying: false
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
        running: root.interested && root.helperPath !== "" && state.restartAllowed

        stdout: SplitParser {
            onRead: data => root.acceptLine(data)
        }
        stderr: SplitParser {
            onRead: data => root.forwardDiagnostic(data)
        }
        onStarted: state.ready = false
        onExited: function (exitCode, exitStatus) {
            state.ready = false;
            root.cancelPendingRequest();
            if (state.loadPending) {
                state.loadPending = false;
                state.loadState = "unavailable";
            }
            if (!state.destroying && root.interested && state.restartAttempts < 3) {
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
        if (state.ready) {
            send({
                     "op": "shutdown"
                 });
        }
    }
}

pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// PipeWire state behind Nagi's audio controls (ADR-0004 boundary).
//
// Quickshell owns graph/default discovery and one lazy tracker. A small native
// bridge owns volume/mute writes and reads them back after PipeWire core
// synchronization, so presentation sees only server-confirmed values. Raw
// objects, properties, channels, links, and session-local IDs remain private.
Scope {
    id: root

    // Verification seams. Production uses the Pipewire singleton, one native
    // tracker, and the Nagi-owned confirmation bridge.
    property var pipewireService: null
    property bool nativeTrackingEnabled: true
    property var nodeIdReader: null
    property string bridgePath: ""
    property var confirmationBridge: null
    property var preferredSinkWriter: null

    readonly property int maximumLabelCharacters: 128
    readonly property int maximumNameCharacters: 256
    readonly property int volumeCoalesceMs: 16
    readonly property int requestTimeoutMs: 2000
    readonly property int refreshLabelTimeoutMs: 3000
    readonly property int failureTimeoutMs: 3000

    // "unavailable", "tracking", or "ready". PipeWire graph readiness and
    // tracked-default readiness are intentionally distinct.
    readonly property string syncState: engine.syncState
    readonly property bool isSynchronized: engine.serviceReady
    readonly property bool available: engine.serviceReady && engine.bridgeReady

    readonly property bool outputAvailable: engine.output.available
    readonly property string outputEndpointKey: engine.output.endpointKey
    readonly property string outputSourceToken: engine.output.sourceToken
    readonly property int outputGeneration: engine.output.generation
    readonly property int outputRevision: engine.output.revision
    readonly property string outputLabel: engine.output.label
    readonly property string outputDisplayLabel: outputAvailable ? outputLabel :
                                                                   engine.lastOutputLabel
    readonly property var outputVolume: engine.output.volume
    readonly property bool outputOveramplified: engine.output.overamplified
    readonly property bool outputMuted: engine.output.muted

    readonly property bool inputAvailable: engine.input.available
    readonly property string inputEndpointKey: engine.input.endpointKey
    readonly property string inputSourceToken: engine.input.sourceToken
    readonly property int inputGeneration: engine.input.generation
    readonly property int inputRevision: engine.input.revision
    readonly property string inputLabel: engine.input.label
    readonly property string inputDisplayLabel: inputAvailable ? inputLabel : engine.lastInputLabel
    readonly property var inputVolume: engine.input.volume
    readonly property bool inputOveramplified: engine.input.overamplified
    readonly property bool inputMuted: engine.input.muted

    // Candidate entries contain only endpointKey, label, and isDefault.
    readonly property var outputCandidates: engine.publicCandidates

    readonly property bool pendingOutputVolume: engine.pendingOutputVolume
    readonly property bool pendingInputVolume: engine.pendingInputVolume
    readonly property bool pendingOutputMute: engine.pendingOutputMute
    readonly property bool pendingInputMute: engine.pendingInputMute
    readonly property bool pendingOutputSelection: engine.selectionTarget !== null
    readonly property string failure: engine.failure

    // Bounded verification visibility; no backend object is exposed.
    readonly property int trackedObjectCount: engine.trackedObjects.length
    readonly property bool confirmationBridgeReady: engine.bridgeReady
    readonly property int queuedVolumeWriteCount: (engine.queuedOutputVolume === null ? 0 : 1) + (
                                                      engine.queuedInputVolume === null ? 0 : 1)
    readonly property int activeTimerCount: (volumeCoalesceTimer.running ? 1 : 0) + (
                                                outputVolumeRequestTimer.running ? 1 : 0) + (
                                                inputVolumeRequestTimer.running ? 1 : 0) + (
                                                outputMuteRequestTimer.running ? 1 : 0) + (
                                                inputMuteRequestTimer.running ? 1 : 0) + (
                                                selectionRequestTimer.running ? 1 : 0) + (
                                                outputLabelTimer.running ? 1 : 0) + (
                                                inputLabelTimer.running ? 1 : 0) + (
                                                failureTimer.running ? 1 : 0)
                                            + engine.bridgeActiveTimerCount

    // Transient consumers receive only opaque bounded identity and revisions.
    // They resolve presentation through resolveConfirmedOutput/Input below.
    signal confirmedOutputChanged(string sourceToken, int sourceGeneration, int revision)
    signal confirmedInputChanged(string sourceToken, int sourceGeneration, int revision)
    signal confirmedOutputInvalidated(string sourceToken, int sourceGeneration)
    signal confirmedInputInvalidated(string sourceToken, int sourceGeneration)

    function requestOutputVolume(value, finalValue) {
        return engine.requestVolume("output", value, finalValue === true);
    }

    function requestInputVolume(value, finalValue) {
        return engine.requestVolume("input", value, finalValue === true);
    }

    function requestOutputMute(muted) {
        return engine.requestMute("output", muted);
    }

    function requestInputMute(muted) {
        return engine.requestMute("input", muted);
    }

    function requestOutputSelection(endpointKey) {
        return engine.requestSelection(endpointKey);
    }

    // Exact-latest resolution prevents a stale coordinator frame from reading
    // newer content under an older backend revision.
    function resolveConfirmedOutput(sourceToken, sourceGeneration, revision) {
        return engine.resolveEndpoint("output", sourceToken, sourceGeneration, revision);
    }

    function resolveConfirmedInput(sourceToken, sourceGeneration, revision) {
        return engine.resolveEndpoint("input", sourceToken, sourceGeneration, revision);
    }

    function resolveTransient(sourceToken, sourceGeneration, revision) {
        const confirmed = resolveConfirmedOutput(sourceToken, sourceGeneration, revision);
        if (confirmed === null || typeof confirmed.label !== "string" || typeof confirmed.volume
                !== "number" || !Number.isFinite(confirmed.volume) || typeof confirmed.muted
                !== "boolean" || typeof confirmed.overamplified !== "boolean") {
            return null;
        }

        const volume = Math.min(1, Math.max(0, confirmed.volume));
        let iconName = "audio-volume-high-symbolic";
        if (confirmed.muted || volume === 0) {
            iconName = "audio-volume-muted-symbolic";
        } else if (volume <= 0.33) {
            iconName = "audio-volume-low-symbolic";
        } else if (volume <= 0.66) {
            iconName = "audio-volume-medium-symbolic";
        }

        let detail = confirmed.muted ? "Muted" : "Output volume";
        if (confirmed.overamplified) {
            detail += " · Amplified";
        }
        return {
            "detail": detail,
            "iconName": iconName,
            "primary": confirmed.label !== "" ? confirmed.label : "Audio output",
            "progress": volume,
            "value": Math.round(volume * 100) + "%"
        };
    }

    // Deterministic deadline/flush seams used by the focused harness. Runtime
    // reaches the same functions through the timers below.
    function processPendingChanges() {
        engine.flushScheduled();
    }

    function processPendingVolumeWrites() {
        engine.flushVolumeWrites();
    }

    function volumeDeadlineReached(role) {
        engine.volumeDeadlineReached(role);
    }

    function muteDeadlineReached(role) {
        engine.muteDeadlineReached(role);
    }

    function selectionDeadlineReached() {
        engine.selectionDeadlineReached();
    }

    function refreshLabelDeadlineReached(role) {
        engine.refreshLabelDeadlineReached(role);
    }

    function failureDeadlineReached() {
        engine.failureDeadlineReached();
    }

    Component.onCompleted: {
        engine.completed = true;
        engine.synchronize();
    }
    Component.onDestruction: engine.cleanup()
    onPipewireServiceChanged: {
        if (engine.completed) {
            engine.replaceService();
        }
    }
    onConfirmationBridgeChanged: {
        if (engine.completed) {
            engine.replaceBridge();
        }
    }

    PwObjectTracker {
        objects: root.nativeTrackingEnabled ? engine.trackedObjects : []
    }

    PipeWireAudioBridge {
        id: nativeBridge

        helperPath: root.bridgePath
        enabled: root.confirmationBridge === null && engine.serviceReady
    }

    Connections {
        target: engine.currentBridge
        ignoreUnknownSignals: true

        function onReadyChanged() {
            engine.handleBridgeReadyChanged();
        }

        function onStateConfirmed(role, nodeId, generation, requestId, kind, volume, muted) {
            engine.handleBridgeState(role, nodeId, generation, requestId, kind, volume, muted);
        }

        function onRoleUnavailable(role, generation) {
            engine.handleBridgeUnavailable(role, generation);
        }

        function onRequestFailed(role, generation, requestId, kind, reason) {
            engine.handleBridgeRequestFailure(role, generation, requestId, kind);
        }

        function onFatalFailure() {
            engine.handleBridgeFatal();
        }
    }

    Timer {
        id: volumeCoalesceTimer

        interval: root.volumeCoalesceMs
        onTriggered: engine.flushVolumeWrites()
    }

    Timer {
        id: outputVolumeRequestTimer

        interval: root.requestTimeoutMs
        onTriggered: root.volumeDeadlineReached("output")
    }

    Timer {
        id: inputVolumeRequestTimer

        interval: root.requestTimeoutMs
        onTriggered: root.volumeDeadlineReached("input")
    }

    Timer {
        id: outputMuteRequestTimer

        interval: root.requestTimeoutMs
        onTriggered: root.muteDeadlineReached("output")
    }

    Timer {
        id: inputMuteRequestTimer

        interval: root.requestTimeoutMs
        onTriggered: root.muteDeadlineReached("input")
    }

    Timer {
        id: selectionRequestTimer

        interval: root.requestTimeoutMs
        onTriggered: root.selectionDeadlineReached()
    }

    Timer {
        id: outputLabelTimer

        interval: root.refreshLabelTimeoutMs
        onTriggered: root.refreshLabelDeadlineReached("output")
    }

    Timer {
        id: inputLabelTimer

        interval: root.refreshLabelTimeoutMs
        onTriggered: root.refreshLabelDeadlineReached("input")
    }

    Timer {
        id: failureTimer

        interval: root.failureTimeoutMs
        onTriggered: root.failureDeadlineReached()
    }

    Connections {
        target: engine.currentService
        ignoreUnknownSignals: true

        function onReadyChanged() {
            engine.scheduleSynchronize();
        }

        function onDefaultAudioSinkChanged() {
            engine.scheduleSynchronize();
        }

        function onDefaultAudioSourceChanged() {
            engine.scheduleSynchronize();
        }

        function onPreferredDefaultAudioSinkChanged() {
            engine.handlePreferredSinkChanged();
        }
    }

    Connections {
        target: engine.currentNodesModel
        ignoreUnknownSignals: true

        function onValuesChanged() {
            engine.scheduleSynchronize();
        }
    }

    Connections {
        target: engine.outputNode
        ignoreUnknownSignals: true

        function onReadyChanged() {
            engine.updateRole("output");
        }

        function onNameChanged() {
            engine.updateRole("output");
        }

        function onDescriptionChanged() {
            engine.updateRole("output");
        }

        function onNicknameChanged() {
            engine.updateRole("output");
        }

        function onAudioChanged() {
            engine.updateRole("output");
        }

        function onDestroyed() {
            engine.scheduleSynchronize();
        }
    }

    Connections {
        target: engine.inputNode
        ignoreUnknownSignals: true

        function onReadyChanged() {
            engine.updateRole("input");
        }

        function onNameChanged() {
            engine.updateRole("input");
        }

        function onDescriptionChanged() {
            engine.updateRole("input");
        }

        function onNicknameChanged() {
            engine.updateRole("input");
        }

        function onAudioChanged() {
            engine.updateRole("input");
        }

        function onDestroyed() {
            engine.scheduleSynchronize();
        }
    }

    Component {
        id: candidateWatcher

        Connections {
            ignoreUnknownSignals: true

            function onNameChanged() {
                engine.scheduleSynchronize();
            }

            function onDescriptionChanged() {
                engine.scheduleSynchronize();
            }

            function onNicknameChanged() {
                engine.scheduleSynchronize();
            }

            function onIsStreamChanged() {
                engine.scheduleSynchronize();
            }

            function onIsSinkChanged() {
                engine.scheduleSynchronize();
            }

            function onAudioChanged() {
                engine.scheduleSynchronize();
            }
        }
    }

    QtObject {
        id: engine

        property bool completed: false
        property bool scheduled: false
        property bool serviceReady: false
        property string syncState: "unavailable"
        property string failure: "unavailable"
        property int generationCounter: 0

        property var output: emptyEndpoint()
        property var input: emptyEndpoint()
        property var outputNode: null
        property var inputNode: null
        property var outputAudio: null
        property var inputAudio: null
        property var outputRecord: null
        property var inputRecord: null
        property var outputBridgeState: null
        property var inputBridgeState: null
        property bool outputPublishedInSession: false
        property bool inputPublishedInSession: false

        property string lastOutputLabel: ""
        property string lastInputLabel: ""
        property string lastOutputMatchName: ""
        property string lastInputMatchName: ""

        property var candidateRecords: []
        property var publicCandidates: []
        property var trackedObjects: []

        property var queuedOutputVolume: null
        property var queuedInputVolume: null
        property bool pendingOutputVolume: false
        property bool pendingInputVolume: false
        property bool pendingOutputMute: false
        property bool pendingInputMute: false
        property int requestCounter: 0
        property int pendingOutputVolumeRequestId: 0
        property int pendingInputVolumeRequestId: 0
        property int pendingOutputMuteRequestId: 0
        property int pendingInputMuteRequestId: 0
        property var selectionTarget: null

        readonly property var currentService: root.pipewireService !== null ? root.pipewireService :
                                                                              Pipewire
        readonly property var currentNodesModel: safeRead(currentService, "nodes", null)
        readonly property var currentBridge: root.confirmationBridge !== null
                                             ? root.confirmationBridge : nativeBridge
        readonly property bool bridgeReady: truthy(safeRead(currentBridge, "ready", false))
        readonly property int bridgeActiveTimerCount: {
            const count = safeRead(currentBridge, "activeTimerCount", 0);
            return Number.isInteger(count) && count >= 0 ? count : 0;
        }

        function emptyEndpoint() {
            return {
                "available": false,
                "endpointKey": "",
                "sourceToken": "",
                "generation": 0,
                "revision": 0,
                "label": "",
                "volume": null,
                "overamplified": false,
                "muted": false
            };
        }

        function safeRead(object, name, fallback) {
            if (object === null || object === undefined) {
                return fallback;
            }

            try {
                const value = object[name];
                return value === undefined ? fallback : value;
            } catch (error) {
                return fallback;
            }
        }

        function truthy(value) {
            return value === true;
        }

        function normalizeText(value, limit) {
            if (typeof value !== "string") {
                return "";
            }

            const cleaned = value.replace(/[\u0000-\u001f\u007f-\u009f]/g, " ").replace(/\s+/g,
                                                                                        " ").trim();
            return cleaned.length > limit ? cleaned.slice(0, limit) : cleaned;
        }

        function nodeId(node) {
            let value;
            try {
                value = root.nodeIdReader !== null ? root.nodeIdReader(node) : node.id;
            } catch (error) {
                return -1;
            }

            return typeof value === "number" && Number.isFinite(value) && value >= 0 && Math.floor(
                        value) === value ? value : -1;
        }

        function nodeName(node) {
            return normalizeText(safeRead(node, "name", ""), root.maximumNameCharacters);
        }

        function nodeLabel(node) {
            const description = normalizeText(safeRead(node, "description", ""),
                                              root.maximumLabelCharacters);
            if (description !== "") {
                return description;
            }

            const nickname = normalizeText(safeRead(node, "nickname", ""),
                                           root.maximumLabelCharacters);
            if (nickname !== "") {
                return nickname;
            }

            return normalizeText(safeRead(node, "name", ""), root.maximumLabelCharacters);
        }

        function endpointKey(role, node) {
            const identifier = nodeId(node);
            if (identifier < 0) {
                return "";
            }

            const name = nodeName(node);
            return role + "|" + name.length + ":" + name + "|" + identifier;
        }

        function nextRecord(role, node) {
            generationCounter += 1;
            return {
                "node": node,
                "generation": generationCounter,
                "sourceToken": "audio-" + role + "-" + generationCounter,
                "endpointKey": ""
            };
        }

        function disposeCandidateRecords() {
            for (let index = 0; index < candidateRecords.length; ++index) {
                const watcher = candidateRecords[index].watcher;
                if (watcher !== null) {
                    watcher.destroy();
                }
            }
            candidateRecords = [];
        }

        function listValues(model) {
            let values = safeRead(model, "values", null);
            if (values === null || typeof values !== "object" || typeof values.length
                    !== "number") {

                values = [];
            }
            return values;
        }

        function isOutputCandidate(node) {
            return node !== null && !truthy(safeRead(node, "isStream", false)) && truthy(safeRead(node, "isSink",
                                                                                                  false))
                    && safeRead(node, "audio", null) !== null && nodeId(node) >= 0;
        }

        function rebuildCandidates() {
            disposeCandidateRecords();
            if (!serviceReady) {
                publicCandidates = [];
                return;
            }

            const values = listValues(currentNodesModel);
            const records = [];
            for (let index = 0; index < values.length; ++index) {
                const node = values[index];
                if (!isOutputCandidate(node)) {
                    continue;
                }

                records.push({
                                 "node": node,
                                 "endpointKey": endpointKey("output", node),
                                 "label": nodeLabel(node),
                                 "id": nodeId(node),
                                 "watcher": candidateWatcher.createObject(root, {
                                                                              "target": node
                                                                          })
                             });
            }

            const confirmedDefault = safeRead(currentService, "defaultAudioSink", null);
            records.sort((left, right) => {
                const leftDefault = left.node === confirmedDefault;
                const rightDefault = right.node === confirmedDefault;
                if (leftDefault !== rightDefault) {
                    return leftDefault ? -1 : 1;
                }

                const leftLabel = left.label.toLowerCase();
                const rightLabel = right.label.toLowerCase();
                if (leftLabel < rightLabel) {
                    return -1;
                }
                if (leftLabel > rightLabel) {
                    return 1;
                }
                return left.id - right.id;
            });
            candidateRecords = records;

            const normalized = [];
            for (let recordIndex = 0; recordIndex < records.length; ++recordIndex) {
                normalized.push({
                                    "endpointKey": records[recordIndex].endpointKey,
                                    "label": records[recordIndex].label,
                                    "isDefault": records[recordIndex].node === confirmedDefault
                                });
            }
            publicCandidates = normalized;
            validateSelectionTarget();
        }

        function updateTrackedObjects() {
            const objects = [];
            if (serviceReady && outputNode !== null) {
                objects.push(outputNode);
            }
            if (serviceReady && inputNode !== null && inputNode !== outputNode) {
                objects.push(inputNode);
            }
            trackedObjects = objects;
        }

        function scheduleSynchronize() {
            if (scheduled) {
                return;
            }
            scheduled = true;
            Qt.callLater(engine.synchronize);
        }

        function flushScheduled() {
            if (scheduled) {
                synchronize();
            }
        }

        function synchronize() {
            scheduled = false;
            const ready = truthy(safeRead(currentService, "ready", false));
            if (!ready) {
                if (serviceReady || outputNode !== null || inputNode !== null
                        || candidateRecords.length > 0) {
                    hardReset(true);
                }
                serviceReady = false;
                syncState = "unavailable";
                failure = "unavailable";
                failureTimer.stop();
                return;
            }

            if (!serviceReady) {
                serviceReady = true;
                outputPublishedInSession = false;
                inputPublishedInSession = false;
                if (failure === "unavailable") {
                    failure = "none";
                }
            }

            const nextOutput = safeRead(currentService, "defaultAudioSink", null);
            const nextInput = safeRead(currentService, "defaultAudioSource", null);
            if (nextOutput !== outputNode) {
                replaceRoleNode("output", nextOutput);
            }
            if (nextInput !== inputNode) {
                replaceRoleNode("input", nextInput);
            }

            updateTrackedObjects();
            rebuildCandidates();
            updateRole("output");
            updateRole("input");
            evaluateSelectionDefault();
            updateSyncState();
        }

        function replaceService() {
            hardReset(true);
            serviceReady = false;
            syncState = "unavailable";
            scheduleSynchronize();
        }

        function replaceRoleNode(role, node) {
            const reconnectName = role === "output" ? lastOutputMatchName : lastInputMatchName;
            untrackRole(role);
            invalidateRole(role);
            clearRoleRequests(role);
            setRoleBridgeState(role, null);
            if (role === "output") {
                outputNode = node;
                outputAudio = null;
                outputRecord = node === null ? null : nextRecord(role, node);
                if (node !== null && reconnectName !== "" && nodeName(node) !== reconnectName) {
                    lastOutputLabel = "";
                    lastOutputMatchName = "";
                    outputLabelTimer.stop();
                }
            } else {
                inputNode = node;
                inputAudio = null;
                inputRecord = node === null ? null : nextRecord(role, node);
                if (node !== null && reconnectName !== "" && nodeName(node) !== reconnectName) {
                    lastInputLabel = "";
                    lastInputMatchName = "";
                    inputLabelTimer.stop();
                }
            }
            trackRole(role);
        }

        function roleNode(role) {
            return role === "output" ? outputNode : inputNode;
        }

        function roleAudio(role) {
            return role === "output" ? outputAudio : inputAudio;
        }

        function roleRecord(role) {
            return role === "output" ? outputRecord : inputRecord;
        }

        function roleBridgeState(role) {
            return role === "output" ? outputBridgeState : inputBridgeState;
        }

        function setRoleBridgeState(role, state) {
            if (role === "output") {
                outputBridgeState = state;
            } else {
                inputBridgeState = state;
            }
        }

        function trackRole(role) {
            const node = roleNode(role);
            const record = roleRecord(role);
            if (!bridgeReady || node === null || record === null) {
                return false;
            }
            const identifier = nodeId(node);
            if (identifier < 0) {
                return false;
            }
            try {
                return currentBridge.track(role, identifier, record.generation) === true;
            } catch (error) {
                return false;
            }
        }

        function untrackRole(role) {
            const record = roleRecord(role);
            if (!bridgeReady || record === null) {
                return;
            }
            try {
                currentBridge.untrack(role, record.generation);
            } catch (error) {}
        }

        function replaceBridge() {
            setRoleBridgeState("output", null);
            setRoleBridgeState("input", null);
            invalidateRole("output");
            invalidateRole("input");
            clearRoleRequests("output");
            clearRoleRequests("input");
            handleBridgeReadyChanged();
        }

        function handleBridgeReadyChanged() {
            if (!bridgeReady) {
                setRoleBridgeState("output", null);
                setRoleBridgeState("input", null);
                invalidateRole("output");
                invalidateRole("input");
                clearRoleRequests("output");
                clearRoleRequests("input");
                if (serviceReady) {
                    setFailure("bridge-unavailable");
                }
                updateSyncState();
                return;
            }
            const outputTracked = outputNode === null || trackRole("output");
            const inputTracked = inputNode === null || trackRole("input");
            if (!outputTracked || !inputTracked) {
                setFailure("bridge-unavailable");
            }
            updateSyncState();
        }

        function handleBridgeState(role, identifier, generation, requestId, kind, volume, muted) {
            const node = roleNode(role);
            const record = roleRecord(role);
            if (node === null || record === null || record.generation !== generation || nodeId(node)
                    !== identifier) {
                return;
            }
            setRoleBridgeState(role, {
                                   "nodeId": identifier,
                                   "generation": generation,
                                   "volume": volume,
                                   "muted": muted
                               });
            updateRole(role);

            if (kind === "volume" && requestId === pendingRequestId(role, kind)) {
                clearVolumePending(role);
                failure = "none";
                failureTimer.stop();
            } else if (kind === "mute" && requestId === pendingRequestId(role, kind)) {
                clearMutePending(role);
                failure = "none";
                failureTimer.stop();
            }
        }

        function handleBridgeUnavailable(role, generation) {
            const record = roleRecord(role);
            if (record === null || record.generation !== generation) {
                return;
            }
            setRoleBridgeState(role, null);
            invalidateRole(role);
            clearRoleRequests(role);
            setFailure("bridge-unavailable");
            updateSyncState();
        }

        function handleBridgeRequestFailure(role, generation, requestId, kind) {
            const record = roleRecord(role);
            if (record === null || record.generation !== generation || requestId
                    !== pendingRequestId(role, kind)) {
                return;
            }
            if (kind === "volume") {
                clearVolumePending(role);
            } else if (kind === "mute") {
                clearMutePending(role);
            }
            setFailure("backend");
        }

        function handleBridgeFatal() {
            setRoleBridgeState("output", null);
            setRoleBridgeState("input", null);
            invalidateRole("output");
            invalidateRole("input");
            clearRoleRequests("output");
            clearRoleRequests("input");
            setFailure(serviceReady ? "bridge-unavailable" : "unavailable");
            updateSyncState();
        }

        function pendingRequestId(role, kind) {
            if (kind === "volume") {
                return role === "output" ? pendingOutputVolumeRequestId :
                                           pendingInputVolumeRequestId;
            }
            return role === "output" ? pendingOutputMuteRequestId : pendingInputMuteRequestId;
        }

        function roleState(role) {
            return role === "output" ? output : input;
        }

        function setRoleAudio(role, audio) {
            if (role === "output") {
                outputAudio = audio;
            } else {
                inputAudio = audio;
            }
        }

        function setRoleRecord(role, record) {
            if (role === "output") {
                outputRecord = record;
            } else {
                inputRecord = record;
            }
        }

        function setRoleState(role, state) {
            if (role === "output") {
                output = state;
            } else {
                input = state;
            }
        }

        function rolePublished(role) {
            return role === "output" ? outputPublishedInSession : inputPublishedInSession;
        }

        function markRolePublished(role) {
            if (role === "output") {
                outputPublishedInSession = true;
            } else {
                inputPublishedInSession = true;
            }
        }

        function endpointEquals(left, right) {
            return left.available === right.available && left.endpointKey === right.endpointKey
                    && left.sourceToken === right.sourceToken && left.generation
                    === right.generation && left.label === right.label && left.volume
                    === right.volume && left.overamplified === right.overamplified && left.muted
                    === right.muted;
        }

        function isValidTrackedDefault(role, node) {
            return !truthy(safeRead(node, "isStream", false)) && (role === "output" ? truthy(safeRead(node,
                                                                                                      "isSink", false)) :
                                                                                      !truthy(safeRead(
                                                                                                  node, "isSink",
                                                                                                  true)));
        }

        function updateRole(role) {
            if (!serviceReady) {
                invalidateRole(role);
                return;
            }

            const node = roleNode(role);
            if (node === null || !truthy(safeRead(node, "ready", false))) {
                setRoleAudio(role, null);
                invalidateRole(role);
                updateSyncState();
                return;
            }

            const audio = safeRead(node, "audio", null);
            setRoleAudio(role, audio);
            const key = endpointKey(role, node);
            if (!isValidTrackedDefault(role, node) || audio === null || key === "") {
                invalidateRole(role);
                setFailure("invalid-default");
                updateSyncState();
                return;
            }

            let record = roleRecord(role);
            if (record === null || record.node !== node || (record.endpointKey !== "" && record.endpointKey
                                                            !== key)) {
                untrackRole(role);
                invalidateRole(role);
                setRoleBridgeState(role, null);
                record = nextRecord(role, node);
                setRoleRecord(role, record);
                trackRole(role);
            }
            record.endpointKey = key;

            const confirmed = roleBridgeState(role);
            if (confirmed === null || confirmed.nodeId !== nodeId(node) || confirmed.generation
                    !== record.generation) {
                invalidateRole(role);
                updateSyncState();
                return;
            }
            const volume = confirmed.volume;
            const muted = confirmed.muted;
            if (typeof volume !== "number" || !Number.isFinite(volume) || volume < 0
                    || typeof muted !== "boolean") {
                invalidateRole(role);
                setFailure("invalid-default");
                updateSyncState();
                return;
            }

            const oldState = roleState(role);
            const nextState = {
                "available": true,
                "endpointKey": key,
                "sourceToken": record.sourceToken,
                "generation": record.generation,
                "revision": oldState.available && oldState.generation === record.generation
                            ? oldState.revision : 0,
                "label": nodeLabel(node),
                "volume": Math.min(volume, 1),
                "overamplified": volume > 1,
                "muted": muted
            };
            if (endpointEquals(oldState, nextState)) {
                updateSyncState();
                return;
            }

            nextState.revision += 1;
            setRoleState(role, nextState);
            rememberConfirmedLabel(role, nextState.label, nodeName(node));
            if (rolePublished(role)) {
                emitConfirmed(role, nextState);
            } else {
                markRolePublished(role);
            }

            if (failure === "unavailable" || failure === "bridge-unavailable" || failure
                    === "invalid-default" || failure === "stale" || failure === "backend") {
                failure = "none";
                failureTimer.stop();
            }
            updateSyncState();
        }

        function emitConfirmed(role, state) {
            if (role === "output") {
                root.confirmedOutputChanged(state.sourceToken, state.generation, state.revision);
            } else {
                root.confirmedInputChanged(state.sourceToken, state.generation, state.revision);
            }
        }

        function invalidateRole(role) {
            const state = roleState(role);
            if (!state.available) {
                return;
            }

            setRoleState(role, emptyEndpoint());
            rememberConfirmedLabel(role, state.label, role === "output" ? lastOutputMatchName :
                                                                          lastInputMatchName);
            if (role === "output") {
                root.confirmedOutputInvalidated(state.sourceToken, state.generation);
            } else {
                root.confirmedInputInvalidated(state.sourceToken, state.generation);
            }
        }

        function rememberConfirmedLabel(role, label, matchName) {
            if (role === "output") {
                lastOutputLabel = label;
                lastOutputMatchName = matchName;
                if (output.available) {
                    outputLabelTimer.stop();
                } else {
                    outputLabelTimer.restart();
                }
            } else {
                lastInputLabel = label;
                lastInputMatchName = matchName;
                if (input.available) {
                    inputLabelTimer.stop();
                } else {
                    inputLabelTimer.restart();
                }
            }
        }

        function updateSyncState() {
            if (!serviceReady) {
                syncState = "unavailable";
                return;
            }

            const outputRecordValue = outputRecord;
            const inputRecordValue = inputRecord;
            const outputTracking = outputNode !== null && (!truthy(safeRead(outputNode, "ready",
                                                                            false))
                                                           || outputRecordValue === null
                                                           || outputBridgeState === null
                                                           || outputBridgeState.generation
                                                           !== outputRecordValue.generation);
            const inputTracking = inputNode !== null && (!truthy(safeRead(inputNode, "ready",
                                                                          false))
                                                         || inputRecordValue === null
                                                         || inputBridgeState === null
                                                         || inputBridgeState.generation
                                                         !== inputRecordValue.generation);
            syncState = !bridgeReady || outputTracking || inputTracking ? "tracking" : "ready";
        }

        function endpointForResolution(state, sourceToken, sourceGeneration, revision) {
            if (!state.available || state.sourceToken !== sourceToken || state.generation
                    !== sourceGeneration || state.revision !== revision) {
                return null;
            }

            return {
                "endpointKey": state.endpointKey,
                "label": state.label,
                "volume": state.volume,
                "overamplified": state.overamplified,
                "muted": state.muted
            };
        }

        function resolveEndpoint(role, sourceToken, sourceGeneration, revision) {
            return endpointForResolution(roleState(role), sourceToken, sourceGeneration, revision);
        }

        function validVolume(value) {
            return typeof value === "number" && Number.isFinite(value);
        }

        function requestVolume(role, value, finalValue) {
            const state = roleState(role);
            const node = roleNode(role);
            if (!state.available || node === null || !bridgeReady || !validVolume(value)) {
                setFailure(!bridgeReady && serviceReady ? "bridge-unavailable" : state.available
                                                          ? "invalid-request" : "unavailable");
                return false;
            }

            const boundedValue = Math.min(Math.max(value, 0), 1);
            if (!state.overamplified && Math.abs(state.volume - boundedValue) < 0.000001) {
                clearVolumePending(role);
                return true;
            }

            const write = {
                "node": node,
                "generation": state.generation,
                "value": boundedValue,
                "final": finalValue
            };
            if (role === "output") {
                queuedOutputVolume = write;
                pendingOutputVolume = true;
            } else {
                queuedInputVolume = write;
                pendingInputVolume = true;
            }

            if (finalValue) {
                takeAndDispatchVolume(role);
                armVolumeCoalescer();
            } else if (!volumeCoalesceTimer.running) {
                volumeCoalesceTimer.start();
            }
            return true;
        }

        function armVolumeCoalescer() {
            if (queuedOutputVolume !== null || queuedInputVolume !== null) {
                volumeCoalesceTimer.restart();
            } else {
                volumeCoalesceTimer.stop();
            }
        }

        function takeAndDispatchVolume(role) {
            const write = role === "output" ? queuedOutputVolume : queuedInputVolume;
            if (role === "output") {
                queuedOutputVolume = null;
            } else {
                queuedInputVolume = null;
            }
            if (write !== null) {
                dispatchVolume(role, write);
            }
        }

        function flushVolumeWrites() {
            volumeCoalesceTimer.stop();
            takeAndDispatchVolume("output");
            takeAndDispatchVolume("input");
            armVolumeCoalescer();
        }

        function dispatchVolume(role, write) {
            const state = roleState(role);
            if (!state.available || roleNode(role) !== write.node || state.generation
                    !== write.generation || !bridgeReady) {
                clearVolumePending(role);
                setFailure("stale");
                return;
            }

            const requestId = nextRequestId();
            if (role === "output") {
                pendingOutputVolumeRequestId = requestId;
            } else {
                pendingInputVolumeRequestId = requestId;
            }
            restartVolumeTimer(role);
            let accepted = false;
            try {
                accepted = currentBridge.setVolume(role, nodeId(write.node), write.generation,
                                                   requestId, write.value, write.final) === true;
            } catch (error) {
                accepted = false;
            }
            if (!accepted) {
                clearVolumePending(role);
                setFailure("bridge-unavailable");
            }
        }

        function restartVolumeTimer(role) {
            if (role === "output") {
                outputVolumeRequestTimer.restart();
            } else {
                inputVolumeRequestTimer.restart();
            }
        }

        function nextRequestId() {
            requestCounter = requestCounter >= 2147483647 ? 1 : requestCounter + 1;
            return requestCounter;
        }

        function clearVolumePending(role) {
            if (role === "output") {
                pendingOutputVolume = false;
                pendingOutputVolumeRequestId = 0;
                queuedOutputVolume = null;
                outputVolumeRequestTimer.stop();
            } else {
                pendingInputVolume = false;
                pendingInputVolumeRequestId = 0;
                queuedInputVolume = null;
                inputVolumeRequestTimer.stop();
            }
            armVolumeCoalescer();
        }

        function requestMute(role, muted) {
            const state = roleState(role);
            const node = roleNode(role);
            if (!state.available || node === null || !bridgeReady || typeof muted !== "boolean") {
                setFailure(!bridgeReady && serviceReady ? "bridge-unavailable" : state.available
                                                          ? "invalid-request" : "unavailable");
                return false;
            }

            if (state.muted === muted) {
                clearMutePending(role);
                return true;
            }

            const requestId = nextRequestId();
            if (role === "output") {
                pendingOutputMute = true;
                pendingOutputMuteRequestId = requestId;
                outputMuteRequestTimer.restart();
            } else {
                pendingInputMute = true;
                pendingInputMuteRequestId = requestId;
                inputMuteRequestTimer.restart();
            }

            let accepted = false;
            try {
                accepted = currentBridge.setMute(role, nodeId(node), state.generation, requestId,
                                                 muted) === true;
            } catch (error) {
                accepted = false;
            }
            if (!accepted) {
                clearMutePending(role);
                setFailure("bridge-unavailable");
                return false;
            }
            return true;
        }

        function clearMutePending(role) {
            if (role === "output") {
                pendingOutputMute = false;
                pendingOutputMuteRequestId = 0;
                outputMuteRequestTimer.stop();
            } else {
                pendingInputMute = false;
                pendingInputMuteRequestId = 0;
                inputMuteRequestTimer.stop();
            }
        }

        function candidateForKey(key) {
            for (let index = 0; index < candidateRecords.length; ++index) {
                if (candidateRecords[index].endpointKey === key) {
                    return candidateRecords[index];
                }
            }
            return null;
        }

        function requestSelection(key) {
            if (!serviceReady || typeof key !== "string" || key.length === 0) {
                setFailure(serviceReady ? "invalid-request" : "unavailable");
                return false;
            }

            const candidate = candidateForKey(key);
            if (candidate === null) {
                setFailure("removed");
                return false;
            }
            if (candidate.node === outputNode && output.available) {
                clearSelection();
                return true;
            }

            selectionTarget = {
                "node": candidate.node,
                "endpointKey": candidate.endpointKey,
                "matchName": nodeName(candidate.node),
                "startedDefault": safeRead(currentService, "defaultAudioSink", null)
            };
            selectionRequestTimer.restart();
            try {
                if (root.preferredSinkWriter !== null) {
                    root.preferredSinkWriter(currentService, candidate.node);
                } else {
                    currentService.preferredDefaultAudioSink = candidate.node;
                }
            } catch (error) {
                failSelection("stale");
                return false;
            }
            return true;
        }

        function validateSelectionTarget() {
            if (selectionTarget === null) {
                return;
            }

            let found = false;
            for (let index = 0; index < candidateRecords.length; ++index) {
                if (candidateRecords[index].node === selectionTarget.node) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                failSelection("removed");
            }
        }

        function evaluateSelectionDefault() {
            if (selectionTarget === null) {
                return;
            }

            const confirmed = safeRead(currentService, "defaultAudioSink", null);
            if (confirmed === selectionTarget.node) {
                clearSelection();
                failure = "none";
                failureTimer.stop();
            } else if (confirmed !== null && confirmed !== selectionTarget.startedDefault) {
                failSelection("diverged");
            }
        }

        function handlePreferredSinkChanged() {
            if (selectionTarget === null) {
                return;
            }

            const preferred = safeRead(currentService, "preferredDefaultAudioSink", null);
            if (preferred !== null && preferred !== selectionTarget.node) {
                failSelection("rejected");
            }
        }

        function clearSelection() {
            selectionTarget = null;
            selectionRequestTimer.stop();
        }

        function failSelection(kind) {
            clearSelection();
            setFailure(kind);
        }

        function clearRoleRequests(role) {
            clearVolumePending(role);
            clearMutePending(role);
            if (role === "output" && selectionTarget !== null && selectionTarget.node
                    === outputNode) {
                failSelection("removed");
            }
        }

        function volumeDeadlineReached(role) {
            const pending = role === "output" ? pendingOutputVolume : pendingInputVolume;
            clearVolumePending(role);
            if (pending) {
                setFailure("timeout");
            }
        }

        function muteDeadlineReached(role) {
            const pending = role === "output" ? pendingOutputMute : pendingInputMute;
            clearMutePending(role);
            if (pending) {
                setFailure("timeout");
            }
        }

        function selectionDeadlineReached() {
            if (selectionTarget !== null) {
                failSelection("timeout");
            }
        }

        function refreshLabelDeadlineReached(role) {
            if (role === "output" && !output.available) {
                lastOutputLabel = "";
                lastOutputMatchName = "";
                outputLabelTimer.stop();
            } else if (role === "input" && !input.available) {
                lastInputLabel = "";
                lastInputMatchName = "";
                inputLabelTimer.stop();
            }
        }

        function setFailure(kind) {
            failure = kind;
            if (kind === "unavailable" || kind === "none") {
                failureTimer.stop();
            } else {
                failureTimer.restart();
            }
        }

        function failureDeadlineReached() {
            failure = !serviceReady ? "unavailable" : bridgeReady ? "none" : "bridge-unavailable";
            failureTimer.stop();
        }

        function hardReset(preserveLabels) {
            untrackRole("output");
            untrackRole("input");
            invalidateRole("output");
            invalidateRole("input");
            clearVolumePending("output");
            clearVolumePending("input");
            clearMutePending("output");
            clearMutePending("input");
            clearSelection();
            disposeCandidateRecords();
            publicCandidates = [];
            outputNode = null;
            inputNode = null;
            outputAudio = null;
            inputAudio = null;
            outputRecord = null;
            inputRecord = null;
            outputBridgeState = null;
            inputBridgeState = null;
            trackedObjects = [];
            output = emptyEndpoint();
            input = emptyEndpoint();
            outputPublishedInSession = false;
            inputPublishedInSession = false;
            if (!preserveLabels) {
                lastOutputLabel = "";
                lastInputLabel = "";
                lastOutputMatchName = "";
                lastInputMatchName = "";
                outputLabelTimer.stop();
                inputLabelTimer.stop();
            }
        }

        function cleanup() {
            hardReset(false);
            serviceReady = false;
            syncState = "unavailable";
            failureTimer.stop();
        }
    }
}

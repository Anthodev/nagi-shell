import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import "qml"

ShellRoot {
    id: test

    property bool finished: false

    AudioAdapter {
        id: audio
        bridgePath: Quickshell.env("NAGI_AUDIO_HELPER") ?? ""
    }

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function inspect() {
        if (finished || audio.syncState !== "ready") {
            return;
        }

        let values = Pipewire.nodes.values;
        if (values === null || typeof values !== "object" || typeof values.length !== "number") {
            values = [];
        }
        let expectedOutputs = 0;
        for (let index = 0; index < values.length; ++index) {
            const node = values[index];
            if (!node.isStream && node.isSink && node.audio !== null) {
                expectedOutputs += 1;
            }
        }

        require(audio.isSynchronized && audio.syncState === "ready",
                "live graph and tracked defaults are ready");
        require(audio.trackedObjectCount <= 2,
                "live adapter tracks no more than confirmed sink and source");
        require(audio.outputCandidates.length === expectedOutputs,
                "live unbound output discovery is complete");
        for (let candidateIndex = 0; candidateIndex
             < audio.outputCandidates.length; ++candidateIndex) {
            const candidate = audio.outputCandidates[candidateIndex];
            require(candidate.node === undefined && candidate.properties === undefined,
                    "live candidates expose no PipeWire objects or raw properties");
        }

        if (Pipewire.defaultAudioSink !== null) {
            require(audio.outputAvailable && audio.outputCandidates.length > 0
                    && audio.outputCandidates[0].isDefault,
                    "live confirmed default output is tracked and ordered first");
            require(audio.resolveConfirmedOutput(audio.outputSourceToken, audio.outputGeneration,
                                                 audio.outputRevision) !== null,
                    "live output revision resolves normalized state");
            require(audio.requestOutputVolume(audio.outputVolume, true) &&
                    !audio.pendingOutputVolume,
                    "already-confirmed output volume is a bounded no-op");
            require(audio.requestOutputMute(audio.outputMuted) && !audio.pendingOutputMute,
                    "already-confirmed output mute is a bounded no-op");
            require(audio.requestOutputSelection(audio.outputEndpointKey) &&
                    !audio.pendingOutputSelection,
                    "already-confirmed output selection is a bounded no-op");
        } else {
            require(!audio.outputAvailable, "nullable live output never claims stale controls");
        }

        if (Pipewire.defaultAudioSource !== null) {
            require(audio.inputAvailable,
                    "live confirmed default input is tracked after synchronization");
            require(audio.resolveConfirmedInput(audio.inputSourceToken, audio.inputGeneration,
                                                audio.inputRevision) !== null,
                    "live input revision resolves normalized state");
            require(audio.requestInputVolume(audio.inputVolume, true) && !audio.pendingInputVolume,
                    "already-confirmed input volume is a bounded no-op");
            require(audio.requestInputMute(audio.inputMuted) && !audio.pendingInputMute,
                    "already-confirmed input mute is a bounded no-op");
        } else {
            require(!audio.inputAvailable, "nullable live input never claims stale controls");
        }

        require(audio.activeTimerCount === 0 && audio.queuedVolumeWriteCount === 0,
                "idle live adapter has no polling timer or queued write");

        finished = true;
        timeout.stop();
        console.warn("audio live probe passed: outputs=" + audio.outputCandidates.length
                     + " tracked=" + audio.trackedObjectCount + " timers=" + audio.activeTimerCount
                     + " output=" + audio.outputAvailable + " input=" + audio.inputAvailable);
        Qt.exit(0);
    }

    Connections {
        target: audio

        function onSyncStateChanged() {
            Qt.callLater(test.inspect);
        }
    }

    Timer {
        id: timeout

        interval: 5000
        running: true
        onTriggered: {
            console.error("FAIL: live PipeWire synchronization timed out: sync=" + audio.syncState
                          + " bridge=" + audio.confirmationBridgeReady + " tracked="
                          + audio.trackedObjectCount + " output=" + audio.outputAvailable
                          + " input=" + audio.inputAvailable + " sinkId=" + (
                              Pipewire.defaultAudioSink === null ? -1 :
                                                                   Pipewire.defaultAudioSink.id)
                          + " sourceId=" + (Pipewire.defaultAudioSource === null ? -1 :
                                                                                   Pipewire.defaultAudioSource.id));
            Qt.exit(2);
        }
    }

    Component.onCompleted: Qt.callLater(inspect)
}

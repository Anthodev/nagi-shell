import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    property var actions: []
    property int actionIndex: 0
    property bool waiting: false
    property bool restoringAfterFailure: false
    property int finalExitCode: 0
    property string finalMessage: ""
    property var original: null

    AudioAdapter {
        id: audio
        bridgePath: Quickshell.env("NAGI_AUDIO_HELPER") ?? ""
    }

    function near(left, right) {
        return Math.abs(left - right) <= 0.02;
    }

    function volumeTarget(value) {
        return value <= 0.9 ? value + 0.05 : value - 0.05;
    }

    function start() {
        if (original !== null || audio.syncState !== "ready") {
            return;
        }
        if (!audio.outputAvailable || !audio.inputAvailable) {
            fail("live confirmed-write probe requires default output and input");
            return;
        }

        original = {
            "outputEndpointKey": audio.outputEndpointKey,
            "outputVolume": audio.outputVolume,
            "outputMuted": audio.outputMuted,
            "inputVolume": audio.inputVolume,
            "inputMuted": audio.inputMuted,
            "outputOveramplified": audio.outputOveramplified,
            "inputOveramplified": audio.inputOveramplified
        };
        const requested = [];
        let alternateOutput = null;
        for (let index = 0; index < audio.outputCandidates.length; ++index) {
            if (!audio.outputCandidates[index].isDefault) {
                alternateOutput = audio.outputCandidates[index];
                break;
            }
        }
        if (alternateOutput !== null) {
            requested.push({
                               "role": "output",
                               "kind": "selection",
                               "value": alternateOutput.endpointKey
                           }, {
                               "role": "output",
                               "kind": "selection",
                               "value": original.outputEndpointKey
                           });
        }
        if (!original.outputOveramplified) {
            requested.push({
                               "role": "output",
                               "kind": "volume",
                               "value": volumeTarget(original.outputVolume)
                           }, {
                               "role": "output",
                               "kind": "volume",
                               "value": original.outputVolume
                           });
        }
        requested.push({
                           "role": "output",
                           "kind": "mute",
                           "value": !original.outputMuted
                       }, {
                           "role": "output",
                           "kind": "mute",
                           "value": original.outputMuted
                       });
        if (!original.inputOveramplified) {
            requested.push({
                               "role": "input",
                               "kind": "volume",
                               "value": volumeTarget(original.inputVolume)
                           }, {
                               "role": "input",
                               "kind": "volume",
                               "value": original.inputVolume
                           });
        }
        requested.push({
                           "role": "input",
                           "kind": "mute",
                           "value": !original.inputMuted
                       }, {
                           "role": "input",
                           "kind": "mute",
                           "value": original.inputMuted
                       });
        actions = requested;
        actionIndex = 0;
        dispatchNext();
    }

    function dispatchNext() {
        if (waiting) {
            return;
        }
        if (actionIndex >= actions.length) {
            finish();
            return;
        }

        const action = actions[actionIndex];
        waiting = true;
        stageTimeout.restart();
        let accepted = false;
        if (action.kind === "selection") {
            accepted = audio.requestOutputSelection(action.value);
        } else if (action.kind === "volume") {
            accepted = action.role === "output" ? audio.requestOutputVolume(action.value, true) :
                                                  audio.requestInputVolume(action.value, true);
        } else {
            accepted = action.role === "output" ? audio.requestOutputMute(action.value) :
                                                  audio.requestInputMute(action.value);
        }
        if (!accepted) {
            stageTimeout.stop();
            waiting = false;
            fail("audio adapter rejected a live confirmed-write action");
            return;
        }
        if (!pendingFor(action)) {
            Qt.callLater(completeAction);
        }
    }

    function pendingFor(action) {
        if (action.kind === "selection") {
            return audio.pendingOutputSelection;
        }
        if (action.kind === "volume") {
            return action.role === "output" ? audio.pendingOutputVolume : audio.pendingInputVolume;
        }
        return action.role === "output" ? audio.pendingOutputMute : audio.pendingInputMute;
    }

    function confirmedValue(action) {
        if (action.kind === "selection") {
            return audio.outputEndpointKey;
        }
        if (action.kind === "volume") {
            return action.role === "output" ? audio.outputVolume : audio.inputVolume;
        }
        return action.role === "output" ? audio.outputMuted : audio.inputMuted;
    }

    function pendingChanged() {
        if (!waiting || pendingFor(actions[actionIndex])) {
            return;
        }
        Qt.callLater(completeAction);
    }

    function completeAction() {
        if (!waiting) {
            return;
        }
        const action = actions[actionIndex];
        const confirmed = confirmedValue(action);
        const matches = action.kind === "volume" ? near(confirmed, action.value) : confirmed
                                                   === action.value;
        if (action.kind === "selection" && !matches && audio.failure === "none") {
            return;
        }
        if (!matches || audio.failure !== "none") {
            stageTimeout.stop();
            waiting = false;
            fail("PipeWire did not confirm action " + actionIndex + " " + action.role + " "
                 + action.kind + " target=" + action.value + " confirmed=" + confirmed
                 + " failure=" + audio.failure);
            return;
        }
        waiting = false;
        stageTimeout.stop();
        actionIndex += 1;
        dispatchNext();
    }

    function restorationActions() {
        if (original === null) {
            return [];
        }
        const restore = [];
        let originalOutputPresent = false;
        for (let index = 0; index < audio.outputCandidates.length; ++index) {
            originalOutputPresent = originalOutputPresent
                    || audio.outputCandidates[index].endpointKey === original.outputEndpointKey;
        }
        if (originalOutputPresent) {
            restore.push({
                             "role": "output",
                             "kind": "selection",
                             "value": original.outputEndpointKey
                         });
        }
        if (!original.outputOveramplified && audio.outputAvailable) {
            restore.push({
                             "role": "output",
                             "kind": "volume",
                             "value": original.outputVolume
                         });
        }
        if (audio.outputAvailable) {
            restore.push({
                             "role": "output",
                             "kind": "mute",
                             "value": original.outputMuted
                         });
        }
        if (!original.inputOveramplified && audio.inputAvailable) {
            restore.push({
                             "role": "input",
                             "kind": "volume",
                             "value": original.inputVolume
                         });
        }
        if (audio.inputAvailable) {
            restore.push({
                             "role": "input",
                             "kind": "mute",
                             "value": original.inputMuted
                         });
        }
        return restore;
    }

    function fail(message) {
        if (restoringAfterFailure || original === null) {
            console.error("FAIL: " + message);
            Qt.exit(2);
            return;
        }
        restoringAfterFailure = true;
        finalExitCode = 2;
        finalMessage = message;
        audio.volumeDeadlineReached("output");
        audio.volumeDeadlineReached("input");
        audio.muteDeadlineReached("output");
        audio.muteDeadlineReached("input");
        audio.failureDeadlineReached();
        waiting = false;
        actions = restorationActions();
        actionIndex = 0;
        dispatchNext();
    }

    function finish() {
        stageTimeout.stop();
        startupTimeout.stop();
        if (finalExitCode !== 0) {
            console.error("FAIL: " + finalMessage + " (audio state restored)");
            Qt.exit(finalExitCode);
            return;
        }
        if (audio.outputEndpointKey !== original.outputEndpointKey || (
                    !original.outputOveramplified && !near(audio.outputVolume,
                                                           original.outputVolume))
                || audio.outputMuted !== original.outputMuted || (!original.inputOveramplified &&
                                                                  !near(audio.inputVolume,
                                                                        original.inputVolume))
                || audio.inputMuted !== original.inputMuted) {
            fail("live audio state did not restore exactly");
            return;
        }
        console.warn("audio live confirmed-write probe passed and restored defaults");
        Qt.exit(0);
    }

    Connections {
        target: audio

        function onSyncStateChanged() {
            Qt.callLater(test.start);
        }

        function onOutputEndpointKeyChanged() {
            test.pendingChanged();
        }
        function onPendingOutputSelectionChanged() {
            test.pendingChanged();
        }

        function onPendingOutputVolumeChanged() {
            test.pendingChanged();
        }

        function onPendingInputVolumeChanged() {
            test.pendingChanged();
        }

        function onPendingOutputMuteChanged() {
            test.pendingChanged();
        }

        function onPendingInputMuteChanged() {
            test.pendingChanged();
        }
    }

    Timer {
        id: startupTimeout

        interval: 5000
        running: true
        onTriggered: test.fail("live PipeWire synchronization timed out")
    }

    Timer {
        id: stageTimeout

        interval: 5000
        onTriggered: {
            waiting = false;
            test.fail("live PipeWire confirmation timed out");
        }
    }

    Component.onCompleted: Qt.callLater(start)
}

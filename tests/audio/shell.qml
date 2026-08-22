import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function near(left, right) {
        return Math.abs(left - right) < 0.000001;
    }

    function makeAudio(volume, muted, volumes) {
        return audioFactory.createObject(test, {
                                             "volume": volume,
                                             "muted": muted,
                                             "volumes": volumes.slice()
                                         });
    }

    function makeNode(properties) {
        return nodeFactory.createObject(test, properties);
    }

    function makeBundle() {
        const model = modelFactory.createObject(test);
        const service = serviceFactory.createObject(test, {
                                                        "nodes": model
                                                    });
        const bridge = bridgeFactory.createObject(test);
        const capture = {
            "preferredWrites": [],
            "outputChanges": [],
            "inputChanges": [],
            "outputInvalidations": [],
            "inputInvalidations": []
        };
        const adapter = adapterFactory.createObject(test, {
                                                        "pipewireService": service,
                                                        "nativeTrackingEnabled": false,
                                                        "nodeIdReader": node => node.pipewireId,
                                                        "confirmationBridge": bridge,
                                                        "preferredSinkWriter": (backend, node)
                                                                               => capture.preferredWrites.push(
                                                                                      {
                                                                                          "backend":
                                                                                          backend,
                                                                                          "node": node
                                                                                      })
                                                    });
        adapter.confirmedOutputChanged.connect((token, generation, revision)
                                               => capture.outputChanges.push({
                                                                                 "token": token,
                                                                                 "generation":
                                                                                 generation,
                                                                                 "revision":
                                                                                 revision
                                                                             }));
        adapter.confirmedInputChanged.connect((token, generation, revision)
                                              => capture.inputChanges.push({
                                                                               "token": token,
                                                                               "generation":
                                                                               generation,
                                                                               "revision": revision
                                                                           }));
        adapter.confirmedOutputInvalidated.connect((token, generation)
                                                   => capture.outputInvalidations.push({
                                                                                           "token": token,
                                                                                           "generation":
                                                                                           generation
                                                                                       }));
        adapter.confirmedInputInvalidated.connect((token, generation)
                                                  => capture.inputInvalidations.push({
                                                                                         "token": token,
                                                                                         "generation":
                                                                                         generation
                                                                                     }));
        return {
            "adapter": adapter,
            "capture": capture,
            "model": model,
            "service": service,
            "bridge": bridge,
            "objects": []
        };
    }

    function own(bundle, object) {
        bundle.objects.push(object);
        return object;
    }

    function apply(bundle, mutation) {
        mutation();
        bundle.adapter.processPendingChanges();
    }

    function candidate(bundle, label) {
        for (let index = 0; index < bundle.adapter.outputCandidates.length; ++index) {
            if (bundle.adapter.outputCandidates[index].label === label) {
                return bundle.adapter.outputCandidates[index];
            }
        }
        return null;
    }

    function destroyBundle(bundle) {
        bundle.adapter.destroy();
        bundle.bridge.destroy();
        bundle.service.destroy();
        bundle.model.destroy();
        for (let index = 0; index < bundle.objects.length; ++index) {
            bundle.objects[index].destroy();
        }
    }

    Component {
        id: audioFactory

        QtObject {
            property real volume: 0
            property bool muted: false
            property var volumes: []
        }
    }

    Component {
        id: nodeFactory

        QtObject {
            property int pipewireId: 0
            property string name: ""
            property string description: ""
            property string nickname: ""
            property bool ready: false
            property bool isStream: false
            property bool isSink: false
            property var audio: null
        }
    }

    Component {
        id: modelFactory

        QtObject {
            property var values: []
        }
    }

    Component {
        id: serviceFactory

        QtObject {
            property bool ready: false
            property var nodes: null
            property var defaultAudioSink: null
            property var defaultAudioSource: null
            property var preferredDefaultAudioSink: null
        }
    }

    Component {
        id: bridgeFactory

        QtObject {
            property bool ready: true
            property var tracks: ({})
            property var volumeWrites: []
            property var muteWrites: []

            signal stateConfirmed(string role, int nodeId, int generation, int requestId, string kind,
                                  real volume, bool muted)
            signal roleUnavailable(string role, int generation)
            signal requestFailed(string role, int generation, int requestId, string kind,
                                 string reason)
            signal fatalFailure

            function track(role, nodeId, generation) {
                const next = Object.assign({}, tracks);
                next[role] = {
                    "nodeId": nodeId,
                    "generation": generation
                };
                tracks = next;
                return true;
            }

            function untrack(role, generation) {
                if (tracks[role] !== undefined && tracks[role].generation === generation) {
                    const next = Object.assign({}, tracks);
                    delete next[role];
                    tracks = next;
                }
                return true;
            }

            function setVolume(role, nodeId, generation, requestId, value, finalValue) {
                volumeWrites = volumeWrites.concat([
                                                       {
                                                           "role": role,
                                                           "nodeId": nodeId,
                                                           "generation": generation,
                                                           "requestId": requestId,
                                                           "value": value,
                                                           "final": finalValue
                                                       }
                                                   ]);
                return true;
            }

            function setMute(role, nodeId, generation, requestId, muted) {
                muteWrites = muteWrites.concat([
                                                   {
                                                       "role": role,
                                                       "nodeId": nodeId,
                                                       "generation": generation,
                                                       "requestId": requestId,
                                                       "muted": muted
                                                   }
                                               ]);
                return true;
            }

            function confirmTracked(role, volume, muted) {
                const track = tracks[role];
                test.require(track !== undefined, "bridge role is tracked before confirmation");
                stateConfirmed(role, track.nodeId, track.generation, 0, "external", volume, muted);
            }

            function confirmLastVolume(volume, muted) {
                test.require(volumeWrites.length > 0, "volume request exists before confirmation");
                const write = volumeWrites[volumeWrites.length - 1];
                stateConfirmed(write.role, write.nodeId, write.generation, write.requestId, "volume",
                               volume, muted);
            }

            function confirmLastMute(volume, muted) {
                test.require(muteWrites.length > 0, "mute request exists before confirmation");
                const write = muteWrites[muteWrites.length - 1];
                stateConfirmed(write.role, write.nodeId, write.generation, write.requestId, "mute",
                               volume, muted);
            }
        }
    }

    Component {
        id: adapterFactory

        AudioAdapter {}
    }

    Component.onCompleted: Qt.callLater(run)

    function run() {
        console.warn("audio: synchronization and discovery");
        const bundle = makeBundle();
        const outputAudio = own(bundle, makeAudio(1.25, false, [0.5, 1.0]));
        const inputAudio = own(bundle, makeAudio(0.4, false, [0.4]));
        const virtualAudio = own(bundle, makeAudio(0.62, false, [0.62, 0.62]));
        const otherAudio = own(bundle, makeAudio(0.8, false, [0.8, 0.8]));
        const streamAudio = own(bundle, makeAudio(0.3, false, [0.3, 0.3]));
        const physical = own(bundle, makeNode({
                                                  "pipewireId": 10,
                                                  "name": "alsa_output.main",
                                                  "description": "  Main\u0001   Output  ",
                                                  "nickname": "Main",
                                                  "ready": false,
                                                  "isSink": true,
                                                  "audio": outputAudio
                                              }));
        const virtual = own(bundle, makeNode({
                                                 "pipewireId": 20,
                                                 "name": "easyeffects_sink",
                                                 "description": "EasyEffects Sink",
                                                 "ready": false,
                                                 "isSink": true,
                                                 "audio": virtualAudio
                                             }));
        const other = own(bundle, makeNode({
                                               "pipewireId": 30,
                                               "name": "hdmi_output",
                                               "description": "HDMI Output",
                                               "ready": false,
                                               "isSink": true,
                                               "audio": otherAudio
                                           }));
        const source = own(bundle, makeNode({
                                                "pipewireId": 40,
                                                "name": "alsa_input.main",
                                                "nickname": "Desk Microphone",
                                                "ready": false,
                                                "isSink": false,
                                                "audio": inputAudio
                                            }));
        const stream = own(bundle, makeNode({
                                                "pipewireId": 50,
                                                "name": "application.stream",
                                                "description": "Application Stream",
                                                "ready": true,
                                                "isStream": true,
                                                "isSink": true,
                                                "audio": streamAudio
                                            }));

        require(!bundle.adapter.available && bundle.adapter.syncState === "unavailable"
                && bundle.adapter.failure === "unavailable",
                "cold unavailable PipeWire publishes no writable state");
        apply(bundle, () => {
            bundle.model.values = [stream, virtual, source, other, physical];
            bundle.service.defaultAudioSink = physical;
            bundle.service.defaultAudioSource = source;
            bundle.service.ready = true;
        });
        require(bundle.adapter.isSynchronized && bundle.adapter.syncState === "tracking",
                "PipeWire readiness precedes tracked-default readiness");
        require(!bundle.adapter.outputAvailable && !bundle.adapter.inputAvailable,
                "unready defaults publish no audio values");
        require(bundle.adapter.trackedObjectCount === 2,
                "one tracker contains only the default sink and source");
        require(bundle.adapter.outputCandidates.length === 3,
                "unbound discovery includes all non-stream sinks and excludes source and stream");
        require(bundle.adapter.outputCandidates[0].label === "Main Output"
                && bundle.adapter.outputCandidates[0].isDefault,
                "confirmed default sorts first and its label is normalized");
        require(bundle.adapter.outputCandidates[1].label === "EasyEffects Sink"
                && bundle.adapter.outputCandidates[2].label === "HDMI Output",
                "remaining outputs sort by normalized label");
        require(bundle.adapter.outputCandidates[0].node === undefined,
                "candidate contract exposes no backend node");

        bundle.bridge.ready = false;
        require(!bundle.adapter.available && bundle.adapter.syncState === "tracking"
                && bundle.adapter.failure === "bridge-unavailable",
                "confirmation bridge loss disables controls without dropping graph discovery");
        bundle.bridge.ready = true;
        require(bundle.adapter.confirmationBridgeReady && bundle.adapter.syncState === "tracking",
                "confirmation bridge recovery reacquires tracked defaults");

        apply(bundle, () => {
            bundle.service.defaultAudioSink = stream;
        });
        require(!bundle.adapter.outputAvailable && bundle.adapter.failure === "invalid-default",
                "application streams are never published even if reported as a default sink");
        apply(bundle, () => {
            bundle.service.defaultAudioSink = physical;
        });

        apply(bundle, () => {
            physical.ready = true;
            source.ready = true;
        });
        require(bundle.adapter.syncState === "tracking" && !bundle.adapter.outputAvailable &&
                !bundle.adapter.inputAvailable,
                "tracked defaults wait for independent server readback");
        bundle.bridge.confirmTracked("output", 1.25, false);
        bundle.bridge.confirmTracked("input", 0.4, false);
        require(bundle.adapter.syncState === "ready" && bundle.adapter.outputAvailable
                && bundle.adapter.inputAvailable, "tracked ready defaults publish atomically");
        require(bundle.adapter.outputLabel === "Main Output" && bundle.adapter.inputLabel
                === "Desk Microphone", "description, nickname, then name derive bounded labels");
        require(bundle.adapter.outputVolume === 1 && bundle.adapter.outputOveramplified &&
                !bundle.adapter.outputMuted,
                "external amplification is clamped and represented separately");
        const amplifiedPresentation = bundle.adapter.resolveTransient(
                  bundle.adapter.outputSourceToken, bundle.adapter.outputGeneration,
                  bundle.adapter.outputRevision);
        require(amplifiedPresentation !== null && amplifiedPresentation.primary === "Main Output"
                && amplifiedPresentation.detail === "Output volume · Amplified"
                && amplifiedPresentation.progress === 1 && amplifiedPresentation.value === "100%",
                "transient resolver presents normalized confirmed amplification explicitly");
        require(near(bundle.adapter.inputVolume, 0.4) && !bundle.adapter.inputOveramplified,
                "input state is normalized independently");
        require(bundle.capture.outputChanges.length === 0 && bundle.capture.inputChanges.length
                === 0, "initial synchronized publication does not replay a transient");

        console.warn("audio: confirmed external changes");
        outputAudio.volume = 0.73;
        require(bundle.adapter.outputVolume === 1,
                "Quickshell's optimistic cache never publishes as confirmed state");
        bundle.bridge.confirmTracked("output", 0.73, false);
        require(near(bundle.adapter.outputVolume, 0.73) && !bundle.adapter.outputOveramplified
                && bundle.capture.outputChanges.length === 1,
                "external output volume publishes immediately from server readback");
        outputAudio.muted = true;
        require(!bundle.adapter.outputMuted,
                "Quickshell's optimistic mute never publishes as confirmed state");
        bundle.bridge.confirmTracked("output", 0.73, true);
        require(bundle.adapter.outputMuted && bundle.capture.outputChanges.length === 2,
                "external output mute publishes immediately from server readback");
        inputAudio.volume = 1.4;
        bundle.bridge.confirmTracked("input", 1.4, false);
        require(bundle.adapter.inputVolume === 1 && bundle.adapter.inputOveramplified
                && bundle.capture.inputChanges.length === 1,
                "input amplification remains a confirmed input-only event");
        const latest = bundle.capture.outputChanges[bundle.capture.outputChanges.length - 1];
        const resolved = bundle.adapter.resolveConfirmedOutput(latest.token, latest.generation,
                                                               latest.revision);
        require(resolved !== null && resolved.label === "Main Output" && resolved.muted,
                "opaque latest output revision resolves to normalized presentation");
        const mutedPresentation = bundle.adapter.resolveTransient(latest.token, latest.generation,
                                                                  latest.revision);
        require(mutedPresentation !== null && mutedPresentation.primary === "Main Output"
                && mutedPresentation.detail === "Muted" && mutedPresentation.iconName
                === "audio-volume-muted-symbolic" && near(mutedPresentation.progress, 0.73)
                && mutedPresentation.value === "73%",
                "transient resolver presents the exact confirmed output, level, and mute state");
        require(bundle.adapter.resolveTransient(latest.token, latest.generation, latest.revision
                                                - 1) === null,
                "transient resolver cannot expose superseded confirmed output");
        require(bundle.adapter.resolveConfirmedOutput(latest.token, latest.generation,
                                                      latest.revision - 1) === null,
                "superseded backend revisions cannot resolve newer content");

        console.warn("audio: requested controls and coalescing");
        const channelSnapshot = outputAudio.volumes.slice();
        require(bundle.adapter.requestOutputVolume(0.2, false) && bundle.adapter.requestOutputVolume(
                    0.3, false) && bundle.adapter.requestOutputVolume(0.4, false),
                "rapid slider writes are accepted");
        require(bundle.bridge.volumeWrites.length === 0 && bundle.adapter.queuedVolumeWriteCount
                === 1 && bundle.adapter.pendingOutputVolume,
                "rapid writes occupy one last-write-wins slot with no queue");
        bundle.adapter.processPendingVolumeWrites();
        require(bundle.bridge.volumeWrites.length === 1 && near(bundle.bridge.volumeWrites[0].value,
                                                                0.4), "coalesced dispatch writes only the latest value");
        require(outputAudio.volumes[0] === channelSnapshot[0] && outputAudio.volumes[1]
                === channelSnapshot[1], "adapter never replaces individual channel volumes");
        require(near(bundle.adapter.outputVolume, 0.73),
                "requested volume is not published optimistically");
        bundle.bridge.confirmLastVolume(0.39, true);
        require(!bundle.adapter.pendingOutputVolume && near(bundle.adapter.outputVolume, 0.39),
                "backend minimum-step result clears pending and remains authoritative");
        require(bundle.adapter.requestOutputVolume(1.8, true) && bundle.bridge.volumeWrites.length
                === 2 && bundle.bridge.volumeWrites[1].value === 1,
                "final release dispatches immediately and cannot create amplification");
        bundle.bridge.confirmLastVolume(1, true);
        require(bundle.adapter.requestOutputVolume(-1, true)
                && bundle.bridge.volumeWrites[bundle.bridge.volumeWrites.length - 1].value === 0,
                "negative requests are bounded before dispatch");
        bundle.bridge.confirmLastVolume(0, true);
        require(!bundle.adapter.requestOutputVolume(Number.NaN, true) && bundle.adapter.failure === "invalid-request",
                "non-finite volume is rejected at the adapter boundary");
        bundle.adapter.failureDeadlineReached();

        require(bundle.adapter.requestOutputMute(false) && bundle.adapter.pendingOutputMute
                && bundle.bridge.muteWrites.length === 1 && bundle.adapter.outputMuted,
                "mute remains pending without optimistic publication");
        bundle.bridge.confirmLastMute(0, false);
        require(!bundle.adapter.pendingOutputMute && !bundle.adapter.outputMuted,
                "confirmed mute clears pending");
        require(bundle.adapter.requestInputVolume(0.25, true)
                && bundle.bridge.volumeWrites[bundle.bridge.volumeWrites.length - 1].role
                === "input", "input volume uses the same bounded average-volume contract");
        bundle.bridge.confirmLastVolume(0.24, false);
        require(!bundle.adapter.pendingInputVolume && near(bundle.adapter.inputVolume, 0.24),
                "input minimum-step confirmation clears pending");
        require(bundle.adapter.requestInputMute(true) && bundle.adapter.pendingInputMute,
                "input mute request is tracked independently");
        bundle.bridge.confirmLastMute(0.24, true);
        require(!bundle.adapter.pendingInputMute && bundle.adapter.inputMuted,
                "input mute publishes only the confirmed result");
        require(bundle.adapter.requestOutputVolume(0.5, true) && bundle.adapter.pendingOutputVolume,
                "unconfirmed output request remains pending");
        bundle.adapter.volumeDeadlineReached("output");
        require(!bundle.adapter.pendingOutputVolume && bundle.adapter.failure === "timeout",
                "bounded request timeout clears pending state");
        bundle.adapter.failureDeadlineReached();

        console.warn("audio: preferred versus confirmed output");
        virtual.ready = true;
        other.ready = true;
        bundle.adapter.processPendingChanges();
        const virtualCandidate = candidate(bundle, "EasyEffects Sink");
        const physicalCandidate = candidate(bundle, "Main Output");
        const otherCandidate = candidate(bundle, "HDMI Output");
        require(virtualCandidate !== null && physicalCandidate !== null && otherCandidate !== null,
                "physical and virtual candidate keys remain available");
        require(bundle.adapter.requestOutputSelection(virtualCandidate.endpointKey)
                && bundle.adapter.pendingOutputSelection && bundle.capture.preferredWrites.length
                === 1 && bundle.capture.preferredWrites[0].node === virtual,
                "selection writes the live candidate as the preferred sink");
        require(bundle.adapter.outputLabel === "Main Output",
                "preferred output never replaces the confirmed displayed truth");
        apply(bundle, () => {
            bundle.service.defaultAudioSink = virtual;
        });
        bundle.bridge.confirmTracked("output", virtualAudio.volume, virtualAudio.muted);
        require(!bundle.adapter.pendingOutputSelection && bundle.adapter.outputLabel
                === "EasyEffects Sink", "selection succeeds only after confirmed default matches");

        require(bundle.adapter.requestOutputSelection(physicalCandidate.endpointKey),
                "second selection request is accepted");
        apply(bundle, () => {
            bundle.service.defaultAudioSink = other;
        });
        bundle.bridge.confirmTracked("output", otherAudio.volume, otherAudio.muted);
        require(!bundle.adapter.pendingOutputSelection && bundle.adapter.failure === "diverged"
                && bundle.adapter.outputLabel === "HDMI Output",
                "divergent confirmed default fails selection without stale target labels");
        bundle.adapter.failureDeadlineReached();

        require(bundle.adapter.requestOutputSelection(physicalCandidate.endpointKey),
                "rejection scenario starts pending");
        bundle.service.preferredDefaultAudioSink = virtual;
        require(!bundle.adapter.pendingOutputSelection && bundle.adapter.failure === "rejected",
                "divergent preferred default is rejected");
        bundle.adapter.failureDeadlineReached();

        require(bundle.adapter.requestOutputSelection(physicalCandidate.endpointKey),
                "removal scenario starts pending");
        apply(bundle, () => {
            bundle.model.values = [stream, virtual, source, other];
        });
        require(!bundle.adapter.pendingOutputSelection && bundle.adapter.failure === "removed",
                "removed target clears pending state");
        bundle.adapter.failureDeadlineReached();
        require(bundle.adapter.requestOutputSelection(virtualCandidate.endpointKey),
                "timeout scenario starts pending");
        bundle.adapter.selectionDeadlineReached();
        require(!bundle.adapter.pendingOutputSelection && bundle.adapter.failure === "timeout",
                "selection timeout is bounded");
        bundle.adapter.failureDeadlineReached();

        console.warn("audio: nullable defaults and graph replacement");
        const oldGeneration = bundle.adapter.outputGeneration;
        const oldKey = bundle.adapter.outputEndpointKey;
        const oldSourceToken = bundle.adapter.outputSourceToken;
        const oldLabel = bundle.adapter.outputLabel;
        apply(bundle, () => {
            bundle.service.defaultAudioSink = null;
        });
        require(!bundle.adapter.outputAvailable && bundle.adapter.outputEndpointKey === ""
                && bundle.adapter.outputDisplayLabel === oldLabel,
                "brief null default disables controls and preserves only presentation label");
        require(bundle.capture.outputInvalidations.length > 0
                && bundle.capture.outputInvalidations[bundle.capture.outputInvalidations.length
                                                      - 1].token === oldSourceToken
                && bundle.adapter.resolveTransient(oldSourceToken, oldGeneration, latest.revision)
                === null, "endpoint disappearance invalidates its transient source and stale presentation");
        require(!bundle.adapter.requestOutputVolume(0.4, true),
                "brief null default rejects writes without claiming the old node");
        bundle.adapter.refreshLabelDeadlineReached("output");
        require(bundle.adapter.outputDisplayLabel === "",
                "short-refresh label expires at its bounded deadline");

        const replacementAudio = own(bundle, makeAudio(0.66, false, [0.5, 0.82]));
        const replacement = own(bundle, makeNode({
                                                     "pipewireId": 30,
                                                     "name": "hdmi_output",
                                                     "description": "HDMI Output",
                                                     "ready": true,
                                                     "isSink": true,
                                                     "audio": replacementAudio
                                                 }));
        apply(bundle, () => {
            bundle.model.values = [stream, virtual, source, replacement];
            bundle.service.defaultAudioSink = replacement;
        });
        bundle.bridge.confirmTracked("output", replacementAudio.volume, replacementAudio.muted);
        require(bundle.adapter.outputAvailable && bundle.adapter.outputGeneration > oldGeneration
                && bundle.adapter.outputEndpointKey === oldKey,
                "reacquired QObject gets a new generation even when role, name, and session ID match");
        require(bundle.adapter.outputSourceToken !== oldSourceToken,
                "reconnect matching never reuses the old live source generation");

        const changesBeforeFatal = bundle.capture.outputChanges.length;
        apply(bundle, () => {
            bundle.service.ready = false;
        });
        require(!bundle.adapter.available && bundle.adapter.syncState === "unavailable"
                && bundle.adapter.trackedObjectCount === 0
                && bundle.adapter.outputCandidates.length === 0,
                "fatal graph loss discards tracked QObjects, candidates, and writable state");
        require(bundle.adapter.outputGeneration === 0 && bundle.adapter.outputEndpointKey === "",
                "fatal graph loss discards old session IDs and generations");
        apply(bundle, () => {
            bundle.service.ready = true;
        });
        bundle.bridge.confirmTracked("output", replacementAudio.volume, replacementAudio.muted);
        bundle.bridge.confirmTracked("input", inputAudio.volume, inputAudio.muted);
        require(bundle.adapter.outputAvailable && bundle.adapter.outputGeneration > oldGeneration
                && bundle.capture.outputChanges.length === changesBeforeFatal,
                "fatal recovery reacquires defaults without replaying initial confirmed state");

        destroyBundle(bundle);
        console.warn("audio tests passed");
        Qt.exit(0);
    }
}

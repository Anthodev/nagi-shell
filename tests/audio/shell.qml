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

    function findObject(root, objectName) {
        if (root === null || root === undefined) {
            return null;
        }
        if (root.objectName === objectName) {
            return root;
        }
        const children = root.children === undefined ? [] : root.children;
        for (let index = 0; index < children.length; ++index) {
            const match = findObject(children[index], objectName);
            if (match !== null) {
                return match;
            }
        }
        return null;
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
            "preferredSourceWrites": [],
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
                                                                                      }),
                                                        "preferredSourceWriter": (backend, node)
                                                                                 => capture.preferredSourceWrites.push(
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

    function candidate(bundle, label, role) {
        const candidates = role === "input" ? bundle.adapter.inputCandidates :
                                              bundle.adapter.outputCandidates;
        for (let index = 0; index < candidates.length; ++index) {
            if (candidates[index].label === label) {
                return candidates[index];
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
            property var preferredDefaultAudioSource: null
        }
    }

    Component {
        id: bridgeFactory

        QtObject {
            property bool ready: true
            property var tracks: ({})
            property var volumeWrites: []
            property var muteWrites: []
            property var nodeMetadata: ({})

            signal stateConfirmed(string role, int nodeId, int generation, int requestId, string kind,
                                  real volume, bool muted)
            signal roleUnavailable(string role, int generation)
            signal requestFailed(string role, int generation, int requestId, string kind,
                                 string reason)
            signal fatalFailure

            function internalRole(nodeId) {
                const role = nodeMetadata[String(nodeId)];
                return role === "output" || role === "input" ? role : "none";
            }

            function setInternalRole(nodeId, role) {
                const next = Object.assign({}, nodeMetadata);
                next[String(nodeId)] = role;
                nodeMetadata = next;
            }

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

    Component {
        id: protocolBridgeFactory

        PipeWireAudioBridge {
            helperPath: ""
        }
    }
    Component {
        id: easyEffectsStatusServiceFactory

        EasyEffectsStatusService {
            helperPath: ""
        }
    }

    Component {
        id: fakeEasyEffectsStatusFactory

        QtObject {
            property bool ready: true
            property bool refreshing: false
            property bool interested: ownerEpoch > 0
            property real ownerEpoch: 0
            property string outputState: "lastLoaded"
            property string outputName: "Studio"
            property string inputState: "none"
            property string inputName: ""
            property var outputPresets: ["Studio", "Cinema"]
            property string outputPresetsState: "ready"
            property var inputPresets: ["Voice"]
            property string inputPresetsState: "ready"
            property int activationCount: 0
            property int deactivationCount: 0
            property int refreshCount: 0
            property bool loadPending: false
            property string loadPipeline: ""
            property string loadState: "none"
            property var loadRequests: []

            function activate(epoch) {
                ownerEpoch = epoch;
                activationCount += 1;
                return true;
            }

            function deactivate(epoch) {
                if (ownerEpoch !== epoch) {
                    return false;
                }
                ownerEpoch = 0;
                deactivationCount += 1;
                return true;
            }

            function refresh(epoch) {
                if (ownerEpoch !== epoch || refreshing) {
                    return false;
                }
                refreshCount += 1;
                return true;
            }

            function validPresetName(name) {
                return typeof name === "string" && name.length > 0 && name.length <= 100
                        && !/[:/\\\n\r]/u.test(name);
            }

            function loadPreset(epoch, pipeline, name) {
                const candidates = pipeline === "output" ? outputPresets :
                                   pipeline === "input" ? inputPresets : [];
                if (ownerEpoch !== epoch || loadPending || candidates.indexOf(name) === -1) {
                    return false;
                }
                loadPending = true;
                loadPipeline = pipeline;
                loadState = "pending";
                loadRequests = loadRequests.concat([{
                                                       "pipeline": pipeline,
                                                       "name": name
                                                   }]);
                if (pipeline === "output") {
                    outputState = "lastLoaded";
                    outputName = name;
                } else {
                    inputState = "lastLoaded";
                    inputName = name;
                }
                loadPending = false;
                loadState = "confirmed";
                return true;
            }
        }
    }


    Item {
        id: selectionHost
    }

    Component {
        id: selectionViewFactory

        AudioSelectionView {}
    }

    Component {
        id: applicationModelFactory

        QtObject {
            property bool present: true
            property bool available: true
            property var applications: present ? [{
                                                     "id":
                                                     "com.github.wwmm.easyeffects.desktop"
                                                 }] : []
            property var launches: []
            property int nextRequestId: 0

            signal launchAccepted(int requestId, string desktopFileId)
            signal launchRejected(int requestId, string category)

            function eligible(desktopFileId) {
                return present && desktopFileId === "com.github.wwmm.easyeffects.desktop";
            }

            function dispatchLaunch(desktopFileId) {
                if (!eligible(desktopFileId)) {
                    return 0;
                }
                nextRequestId += 1;
                launches = launches.concat([desktopFileId]);
                return nextRequestId;
            }
        }
    }

    Component {
        id: emptySelectionAdapterFactory

        QtObject {
            property bool available: false
            property var outputCandidates: []
            property var inputCandidates: []
            property bool pendingOutputSelection: false
            property bool pendingInputSelection: false
            property string failure: "none"
        }
    }

    function verifyEmptySelectionLayouts(bundle) {
        console.warn("audio: empty selection view geometry");
        const unavailableAdapter = emptySelectionAdapterFactory.createObject(selectionHost);
        const emptyAdapter = emptySelectionAdapterFactory.createObject(selectionHost, {
                                                                           "available": true
                                                                       });
        const cases = [
                  {
                      "adapter": null,
                      "text": "Audio devices unavailable"
                  },
                  {
                      "adapter": unavailableAdapter,
                      "text": "Audio devices unavailable"
                  },
                  {
                      "adapter": emptyAdapter,
                      "text": "No selectable audio devices"
                  }
              ];

        function verifyCase(index) {
            if (index >= cases.length) {
                unavailableAdapter.destroy();
                emptyAdapter.destroy();
                verifySelectionLayout(bundle);
                return;
            }
            const current = cases[index];
            const view = selectionViewFactory.createObject(selectionHost, {
                                                               "adapter": current.adapter,
                                                               "ownerEpoch": index + 1
                                                           });
            require(view !== null, "empty audio selection view is created");
            Qt.callLater(() => {
                view.width = view.implicitWidth;
                view.height = view.implicitHeight;
                Qt.callLater(() => {
                    const contentRoot = findObject(view, "audioContentRoot");
                    const message = findObject(view, "audioEmptyMessage");
                    require(contentRoot !== null && message !== null && message.visible && message.text
                            === current.text, "empty audio state exposes its semantic text");
                    const origin = message.mapToItem(contentRoot, 0, 0);
                    require(view.naturalContentWidth === Theme.size.audioEmptyContentMinimumWidth
                            && contentRoot.implicitWidth
                            === Theme.size.audioEmptyContentMinimumWidth,
                            "empty audio state retains the compact semantic width");
                    require(message.width > 0 && message.paintedWidth <= message.width + 0.5
                            && origin.x >= -0.5 && origin.x + message.width <= contentRoot.width + 0.5,
                            "empty audio text bounds fit the content viewport");
                    view.destroy();
                    Qt.callLater(() => verifyCase(index + 1));
                });
            });
        }

        verifyCase(0);
    }

    Component.onCompleted: Qt.callLater(run)

    function verifySelectionLayout(bundle) {
        console.warn("audio: selection dropdown layout and capability");
        const applications = applicationModelFactory.createObject(selectionHost);
        const easyEffectsStatus = fakeEasyEffectsStatusFactory.createObject(selectionHost);
        const view = selectionViewFactory.createObject(selectionHost, {
                                                           "adapter": bundle.adapter,
                                                           "applicationModel": applications,
                                                           "easyEffectsStatus": easyEffectsStatus,
                                                           "ownerEpoch": 1
                                                       });
        require(view !== null, "audio selection view is created");

        Qt.callLater(() => {
            view.width = view.implicitWidth;
            view.height = view.implicitHeight;
            Qt.callLater(() => {
                const outputSection = findObject(view, "audioOutputSection");
                const inputSection = findObject(view, "audioInputSection");
                const frame = findObject(view, "audioSubviewFrame");
                const contentRoot = findObject(view, "audioContentRoot");
                const pipelineGrid = findObject(view, "audioPipelineGrid");
                const outputDropdown = findObject(view, "audioOutputDropdown");
                const inputDropdown = findObject(view, "audioInputDropdown");
                const outputPopup = findObject(view, "audioOutputPopup");
                const integration = findObject(view, "audioEasyEffectsCapability");
                const openButton = findObject(view, "audioOpenEasyEffects");
                const outputWarning = findObject(view, "audioOutputInternalDefaultWarning");
                const outputPreset = findObject(view, "audioEasyEffectsOutputPreset");
                const inputPreset = findObject(view, "audioEasyEffectsInputPreset");
                const refreshButton = findObject(view, "audioRefreshEasyEffectsStatus");
                const outputPresetDropdown = findObject(view,
                                                        "audioEasyEffectsOutputPresetDropdown");
                const outputPresetPopup = findObject(view, "audioEasyEffectsOutputPresetPopup");
                require(frame !== null && contentRoot !== null && pipelineGrid !== null
                        && outputSection !== null && inputSection !== null && outputDropdown !== null
                        && inputDropdown !== null && outputPopup !== null && outputWarning !== null
                        && outputPreset !== null && inputPreset !== null && refreshButton !== null
                        && outputPresetDropdown !== null && outputPresetPopup !== null,
                        "audio frame exposes device and EasyEffects preset select lists");
                require(inputSection.x > outputSection.x + outputSection.width
                        && Math.abs(inputSection.y - outputSection.y) < 0.5
                        && Math.abs(inputSection.width - outputSection.width) <= 1,
                        "wide audio content uses equal top-aligned pipeline columns");
                require(applications.launches.length === 0 && integration.visible && openButton.visible,
                        "installed EasyEffects exposes one honest affordance without implicit activation");
                require(easyEffectsStatus.activationCount === 1
                        && easyEffectsStatus.ownerEpoch === view.ownerEpoch
                        && outputPreset.statusValue === "Studio"
                        && inputPreset.statusValue === "None reported",
                        "visible exact desktop capability lists presets and labels last-loaded state");
                require(!view.requestPresetLoad("output", "Missing"),
                        "a name absent from the discovered list never crosses the service boundary");
                outputPreset.openPopup(outputPreset.candidates.indexOf("Cinema"));
                require(outputPresetPopup.visible && outputPresetPopup.height > 0,
                        "output preset select list opens with bounded discovered options");
                outputPreset.highlightedIndex = outputPreset.candidates.indexOf("Cinema");
                require(outputPreset.selectHighlighted(),
                        "choosing one listed output preset dispatches immediately");
                require(easyEffectsStatus.loadRequests.length === 1
                        && easyEffectsStatus.loadRequests[0].pipeline === "output"
                        && easyEffectsStatus.loadRequests[0].name === "Cinema"
                        && outputPreset.statusValue === "Cinema",
                        "preset select dispatch publishes confirmed readback");
                require(view.refreshPresetStatus() && easyEffectsStatus.refreshCount === 1,
                        "preset status refresh is explicit and generation-owned");

                outputSection.openPopup(0);
                Qt.callLater(() => {
                    require(outputPopup.visible && outputPopup.height > 0
                            && outputPopup.height <= Theme.size.controlHeightMd * 5
                            + Theme.spacing.xs * 2 + 0.5,
                            "output candidate popup is visible and bounded to five rows");
                    const endEvent = {
                        "accepted": false,
                        "key": Qt.Key_End,
                        "text": ""
                    };
                    outputSection.handlePopupKey(endEvent);
                    require(endEvent.accepted && outputSection.highlightedIndex
                            === bundle.adapter.outputCandidates.length - 1,
                            "popup End navigation reaches the final bounded candidate");
                    const upEvent = {
                        "accepted": false,
                        "key": Qt.Key_Up,
                        "text": ""
                    };
                    outputSection.handlePopupKey(upEvent);
                    require(upEvent.accepted && outputSection.highlightedIndex === 0,
                            "popup arrow navigation moves through eligible candidates");
                    const homeEvent = {
                        "accepted": false,
                        "key": Qt.Key_Home,
                        "text": ""
                    };
                    outputSection.handlePopupKey(homeEvent);
                    require(homeEvent.accepted && outputSection.highlightedIndex === 0,
                            "popup Home navigation reaches the first candidate");
                    const typeEvent = {
                        "accepted": false,
                        "key": 0,
                        "text": "h"
                    };
                    outputSection.handlePopupKey(typeEvent);
                    require(typeEvent.accepted && outputSection.highlightedIndex === 1,
                            "popup type navigation selects the matching bounded label");
                    const enterEvent = {
                        "accepted": false,
                        "key": Qt.Key_Return,
                        "text": ""
                    };
                    outputSection.highlightedIndex = 0;
                    outputSection.handlePopupKey(enterEvent);
                    require(enterEvent.accepted && !bundle.adapter.pendingOutputSelection
                            && !outputPopup.visible,
                            "popup Enter activates the confirmed no-op and closes");
                    outputSection.openPopup(0);
                    const escapeEvent = {
                        "accepted": false,
                        "key": Qt.Key_Escape,
                        "text": ""
                    };
                    outputSection.handlePopupKey(escapeEvent);
                    require(escapeEvent.accepted && !outputPopup.visible && outputDropdown.focus,
                            "popup Escape closes locally and restores dropdown focus intent");

                    const confirmedDescription = outputDropdown.Accessible.description;
                    require(view.requestSelection("output",
                                                  bundle.adapter.outputCandidates[0].endpointKey)
                            && !bundle.adapter.pendingOutputSelection,
                            "reselecting the confirmed device is a bounded no-op");
                    require(view.requestSelection("output",
                                                  bundle.adapter.outputCandidates[1].endpointKey)
                            && bundle.adapter.pendingOutputSelection && !outputDropdown.enabled
                            && !inputDropdown.enabled
                            && outputDropdown.Accessible.description === confirmedDescription,
                            "one pending selection disables both dropdowns and preserves confirmed text");
                    bundle.adapter.selectionDeadlineReached("output");
                    require(findObject(view, "audioSelectionFailure").visible,
                            "selection timeout remains explicit and local to the Audio subview");

                    view.maximumAvailableWidth = view.twoColumnWidth + Theme.spacing.lg * 2 - 1;
                    view.width = view.implicitWidth;
                    Qt.callLater(() => Qt.callLater(() => {
                        require(inputSection.y >= outputSection.y + outputSection.height,
                                "narrow audio content stacks input below output");
                        bundle.adapter.failureDeadlineReached();
                        apply(bundle, () => {
                            bundle.service.defaultAudioSink = bundle.virtualNode;
                        });
                        require(outputWarning.visible && !bundle.adapter.outputAvailable
                                && bundle.adapter.outputEndpointKey === "",
                                "an internal confirmed default shows a bounded warning without an endpoint key");
                        const eligibleOutput = bundle.adapter.outputCandidates[0];
                        require(view.requestSelection("output", eligibleOutput.endpointKey),
                                "the warning state keeps an eligible explicit selection path");
                        apply(bundle, () => {
                            bundle.service.defaultAudioSink = bundle.physicalNode;
                        });
                        bundle.bridge.confirmTracked("output", bundle.outputAudio.volume,
                                                     bundle.outputAudio.muted);
                        require(applications.launches.length === 0 && view.openEasyEffects()
                                && applications.launches.length === 1
                                && applications.launches[0]
                                === "com.github.wwmm.easyeffects.desktop",
                                "only explicit activation launches the exact validated desktop ID");
                        applications.launchAccepted(view.easyEffectsLaunchRequestId,
                                                    "com.github.wwmm.easyeffects.desktop");
                        require(view.openEasyEffects(),
                                "a second explicit Open request is admitted after completion");
                        applications.launchRejected(view.easyEffectsLaunchRequestId, "launch");
                        require(view.easyEffectsLaunchFailure === "EasyEffects could not be opened.",
                                "desktop launch failure stays explicit and local");
                        applications.present = false;
                        Qt.callLater(() => {
                            require(!integration.visible,
                                    "absent EasyEffects desktop metadata removes the affordance");
                            require(easyEffectsStatus.deactivationCount === 1
                                    && easyEffectsStatus.ownerEpoch === 0,
                                    "removing the capability clears visible preset status interest");
                            view.destroy();
                            applications.destroy();
                            easyEffectsStatus.destroy();
                            destroyBundle(bundle);
                            console.warn("audio tests passed");
                            Qt.exit(0);
                        });
                    }));
                });
            });
        });
    }

    function run() {
        console.warn("audio: synchronization and discovery");
        const statusService = easyEffectsStatusServiceFactory.createObject(test);
        require(statusService.activate(9), "status service admits one visible owner");
        statusService.acceptLine(
                    "{\"type\":\"pipeline\",\"generation\":1,\"pipeline\":\"output\",\"state\":\"lastLoaded\",\"name\":\"Studio\"}");
        statusService.acceptLine(
                    "{\"type\":\"pipeline\",\"generation\":1,\"pipeline\":\"input\",\"state\":\"none\"}");
        statusService.acceptLine(
                    "{\"type\":\"presets\",\"generation\":1,\"pipeline\":\"output\",\"state\":\"ready\",\"items\":[\"Cinema\",\"Studio\"]}");
        statusService.acceptLine(
                    "{\"type\":\"presets\",\"generation\":1,\"pipeline\":\"input\",\"state\":\"ready\",\"items\":[\"Voice\"]}");
        require(statusService.outputState === "lastLoaded" && statusService.outputName === "Studio"
                && statusService.inputState === "none" && statusService.inputName === ""
                && statusService.outputPresets.join(",") === "Cinema,Studio"
                && statusService.inputPresets.join(",") === "Voice" && !statusService.refreshing,
                "status service publishes normalized pipeline state and bounded preset models");
        statusService.acceptLine(
                    "{\"type\":\"pipeline\",\"generation\":1,\"pipeline\":\"output\",\"state\":\"lastLoaded\",\"name\":\"private/path\"}");
        require(statusService.outputName === "Studio",
                "status service rejects path-like untrusted preset text");
        statusService.acceptLine(
                    "{\"type\":\"presets\",\"generation\":1,\"pipeline\":\"output\",\"state\":\"ready\",\"items\":[\"Cinema\",\"private/path\"]}");
        require(statusService.outputPresets.join(",") === "Cinema,Studio",
                "status service rejects a malformed preset list atomically");
        statusService.acceptLine(
                    "{\"type\":\"pipeline\",\"generation\":2,\"pipeline\":\"output\",\"state\":\"lastLoaded\",\"name\":\"stale\"}");
        require(statusService.outputName === "Studio",
                "status service rejects a stale helper generation");
        require(statusService.deactivate(9) && !statusService.interested
                && statusService.outputState === "unknown" && statusService.outputName === ""
                && statusService.outputPresets.length === 0 && statusService.inputPresets.length === 0,
                "status service clears names, preset models, and work on close");
        statusService.destroy();
        const protocolBridge = protocolBridgeFactory.createObject(test);
        protocolBridge.acceptLine(
                    "{\"type\":\"node-metadata\",\"nodeId\":20,\"easyEffectsRole\":\"output\"}");
        require(protocolBridge.internalRole(20) === "output" && protocolBridge.knownNodeCount === 1,
                "bridge accepts one normalized internal-node metadata record");
        protocolBridge.acceptLine("{\"type\":\"node-removed\",\"nodeId\":20}");
        require(protocolBridge.internalRole(20) === "none" && protocolBridge.knownNodeCount === 0,
                "bridge removes stale metadata when the PipeWire node disappears");
        protocolBridge.destroy();
        const bundle = makeBundle();
        const outputAudio = own(bundle, makeAudio(1.25, false, [0.5, 1.0]));
        const inputAudio = own(bundle, makeAudio(0.4, false, [0.4]));
        const virtualAudio = own(bundle, makeAudio(0.62, false, [0.62, 0.62]));
        const otherAudio = own(bundle, makeAudio(0.8, false, [0.8, 0.8]));
        const streamAudio = own(bundle, makeAudio(0.3, false, [0.3, 0.3]));
        const alternateInputAudio = own(bundle, makeAudio(0.55, false, [0.55]));
        const otherInputAudio = own(bundle, makeAudio(0.7, false, [0.7]));
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
        const alternateSource = own(bundle, makeNode({
                                                         "pipewireId": 41,
                                                         "name": "usb_input.alternate",
                                                         "description": "USB Microphone",
                                                         "ready": true,
                                                         "isSink": false,
                                                         "audio": alternateInputAudio
                                                     }));
        const otherSource = own(bundle, makeNode({
                                                     "pipewireId": 42,
                                                     "name": "webcam_input.other",
                                                     "description": "Webcam Microphone",
                                                     "ready": true,
                                                     "isSink": false,
                                                     "audio": otherInputAudio
                                                 }));
        const easyEffectsSource = own(bundle, makeNode({
                                                            "pipewireId": 43,
                                                            "name": "easyeffects_source",
                                                            "description": "EasyEffects Source",
                                                            "ready": true,
                                                            "isSink": false,
                                                            "audio": virtualAudio
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
        bundle.bridge.setInternalRole(easyEffectsSource.pipewireId, "input");
        bundle.virtualNode = virtual;
        bundle.physicalNode = physical;
        bundle.outputAudio = outputAudio;

        require(!bundle.adapter.available && bundle.adapter.syncState === "unavailable"
                && bundle.adapter.failure === "unavailable",
                "cold unavailable PipeWire publishes no writable state");
        apply(bundle, () => {
            bundle.model.values = [stream, virtual, source, alternateSource, otherSource,
                                   easyEffectsSource, other, physical];
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
        require(bundle.adapter.inputCandidates.length === 3
                && bundle.adapter.inputCandidates[0].label === "Desk Microphone"
                && bundle.adapter.inputCandidates[0].isDefault,
                "input discovery mirrors output discovery and sorts the confirmed source first");
        require(bundle.adapter.inputCandidates[0].node === undefined,
                "input candidates expose no backend objects");

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
        const concurrentInputCandidate = candidate(bundle, "USB Microphone", "input");
        require(concurrentInputCandidate !== null
                && !bundle.adapter.requestInputSelection(concurrentInputCandidate.endpointKey)
                && bundle.capture.preferredSourceWrites.length === 0,
                "one global mutable slot rejects a concurrent input selection");
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
            bundle.model.values = [stream, virtual, source, alternateSource, otherSource,
                                   easyEffectsSource, other];
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

        console.warn("audio: preferred versus confirmed input");
        const sourceCandidate = candidate(bundle, "Desk Microphone", "input");
        const alternateSourceCandidate = candidate(bundle, "USB Microphone", "input");
        const otherSourceCandidate = candidate(bundle, "Webcam Microphone", "input");
        require(sourceCandidate !== null && alternateSourceCandidate !== null
                && otherSourceCandidate !== null,
                "normalized input candidate keys remain available");
        require(bundle.adapter.requestInputSelection(alternateSourceCandidate.endpointKey)
                && bundle.adapter.pendingInputSelection
                && bundle.capture.preferredSourceWrites.length === 1
                && bundle.capture.preferredSourceWrites[0].node === alternateSource,
                "input selection writes the live candidate as the preferred source");
        require(bundle.adapter.inputLabel === "Desk Microphone",
                "preferred input never replaces confirmed presentation");
        apply(bundle, () => {
            bundle.service.defaultAudioSource = alternateSource;
        });
        bundle.bridge.confirmTracked("input", alternateInputAudio.volume,
                                     alternateInputAudio.muted);
        require(!bundle.adapter.pendingInputSelection && bundle.adapter.inputLabel
                === "USB Microphone",
                "input selection succeeds only after defaultAudioSource confirms it");

        require(bundle.adapter.requestInputSelection(sourceCandidate.endpointKey),
                "second input selection request is accepted");
        apply(bundle, () => {
            bundle.service.defaultAudioSource = otherSource;
        });
        bundle.bridge.confirmTracked("input", otherInputAudio.volume, otherInputAudio.muted);
        require(!bundle.adapter.pendingInputSelection && bundle.adapter.failure === "diverged"
                && bundle.adapter.inputLabel === "Webcam Microphone",
                "divergent confirmed input fails without optimistic presentation");
        bundle.adapter.failureDeadlineReached();

        require(bundle.adapter.requestInputSelection(sourceCandidate.endpointKey),
                "input rejection scenario starts pending");
        bundle.service.preferredDefaultAudioSource = alternateSource;
        require(!bundle.adapter.pendingInputSelection && bundle.adapter.failure === "rejected",
                "divergent preferred input is rejected");
        bundle.adapter.failureDeadlineReached();

        require(bundle.adapter.requestInputSelection(sourceCandidate.endpointKey),
                "input removal scenario starts pending");
        apply(bundle, () => {
            bundle.model.values = [stream, virtual, alternateSource, otherSource, easyEffectsSource,
                                   other];
        });
        require(!bundle.adapter.pendingInputSelection && bundle.adapter.failure === "removed",
                "removed input target clears pending state");
        bundle.adapter.failureDeadlineReached();
        apply(bundle, () => {
            bundle.model.values = [stream, virtual, source, alternateSource, otherSource,
                                   easyEffectsSource, other];
        });
        require(bundle.adapter.requestInputSelection(alternateSourceCandidate.endpointKey),
                "input timeout scenario starts pending");
        bundle.adapter.selectionDeadlineReached("input");
        require(!bundle.adapter.pendingInputSelection && bundle.adapter.failure === "timeout",
                "input selection timeout is bounded");
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
            bundle.model.values = [stream, virtual, source, alternateSource, otherSource,
                                   easyEffectsSource, replacement];
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
                && bundle.adapter.outputCandidates.length === 0
                && bundle.adapter.inputCandidates.length === 0,
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

        console.warn("audio: exact EasyEffects node exclusion");
        require(candidate(bundle, "EasyEffects Source", "input") === null
                && candidate(bundle, "USB Microphone", "input") !== null,
                "exact internal input is filtered while unrelated inputs remain");
        apply(bundle, () => {
            bundle.model.values = [stream, virtual, physical, source, alternateSource, otherSource,
                                   easyEffectsSource, replacement];
        });
        const preferredWritesBeforeFilter = bundle.capture.preferredWrites.length;
        bundle.bridge.setInternalRole(virtual.pipewireId, "output");
        bundle.adapter.processPendingChanges();
        require(candidate(bundle, "EasyEffects Sink") === null
                && candidate(bundle, "Main Output") !== null,
                "exact internal output is filtered while physical devices remain");
        apply(bundle, () => {
            bundle.service.defaultAudioSink = virtual;
        });
        require(bundle.adapter.outputEasyEffectsInternalDefault && !bundle.adapter.outputAvailable
                && bundle.adapter.outputEndpointKey === ""
                && bundle.capture.preferredWrites.length === preferredWritesBeforeFilter,
                "an already-default internal node publishes a warning seam and never auto-routes");
        const physicalAfterFilter = candidate(bundle, "Main Output");
        require(physicalAfterFilter !== null
                && bundle.adapter.requestOutputSelection(physicalAfterFilter.endpointKey)
                && bundle.adapter.pendingOutputSelection,
                "an eligible device remains explicitly selectable from the internal default");
        apply(bundle, () => {
            bundle.service.defaultAudioSink = physical;
        });
        bundle.bridge.confirmTracked("output", outputAudio.volume, outputAudio.muted);
        require(!bundle.adapter.outputEasyEffectsInternalDefault && bundle.adapter.outputAvailable
                && bundle.adapter.outputLabel === "Main Output",
                "a confirmed explicit selection clears the internal-default warning");

        verifyEmptySelectionLayouts(bundle);
    }
}

import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    property int parsedSnapshotCount: 0
    property int confirmedCount: 0
    property int invalidatedCount: 0
    property string confirmedKey: ""
    property int confirmedGeneration: 0
    property int confirmedRevision: 0
    property var confirmedSurfaceToken: null
    property var localSurfaceToken: null

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function display(key, label, isInternal, ratio, pending, failure) {
        return {
            "key": key,
            "label": label,
            "isInternal": isInternal,
            "ratio": ratio,
            "pending": pending,
            "failure": failure
        };
    }

    function state(generation, displays, change, request) {
        return {
            "available": true,
            "supported": displays.length > 0,
            "generation": generation,
            "displays": displays,
            "change": change,
            "request": request
        };
    }

    function run() {
        parser.acceptLine("not json");
        parser.acceptLine("{\"type\":\"state\",\"available\":true}");
        require(parsedSnapshotCount === 0, "malformed helper output leaves parser state intact");
        parser.acceptLine(JSON.stringify({
                                             "type": "state",
                                             "available": true,
                                             "supported": true,
                                             "generation": 1,
                                             "displays": [display("1:display0", "Main", false, 0.4,
                                                                  false, "none")],
                                             "change": null,
                                             "request": null
                                         }));
        require(parsedSnapshotCount === 1, "complete helper state crosses the process boundary");
        parser.acceptLine(JSON.stringify({
                                             "type": "state",
                                             "available": true,
                                             "supported": true,
                                             "generation": 1,
                                             "displays": [display("2:display0", "Main", false, 0.4,
                                                                  false, "none")],
                                             "change": null,
                                             "request": null
                                         }));
        require(parsedSnapshotCount === 1, "generation-mismatched keys are rejected atomically");

        const first = display("1:display0", "Main Display", false, 0.4, false, "none");
        const second = display("1:display1", "Internal Panel", true, 0.6, false, "none");
        fakeBridge.snapshotReceived(state(1, [first, second], null, null));
        require(adapter.available && adapter.supported && adapter.generation === 1
                && adapter.displays.length === 2, "initial coherent display list is exposed");
        require(adapter.displayForKey("1:display1").isInternal && adapter.displayForKey(
                    "1:display1").ratio === 0.6, "normalized display fields remain typed");

        localSurfaceToken = {};
        require(adapter.requestBrightness("1:display0", 0.7, localSurfaceToken),
                "current display accepts one bounded write");
        require(fakeBridge.writeCount === 1 && fakeBridge.lastRequestId === 1
                && fakeBridge.lastDisplayKey === "1:display0" && fakeBridge.lastRatio === 0.7,
                "adapter dispatches only normalized write arguments");
        require(!adapter.requestBrightness("1:display0", 0.8, localSurfaceToken),
                "dispatch gap cannot duplicate a pending display write");
        require(!adapter.requestBrightness("missing", 0.5, localSurfaceToken) &&
                !adapter.requestBrightness("1:display1", -1, localSurfaceToken),
                "stale keys and invalid ratios are rejected locally");

        fakeBridge.snapshotReceived(state(1, [display("1:display0", "Main Display", false, 0.4, true,
                                                      "none"), second], null, {
                                              "requestId": 1,
                                              "outcome": "pending"
                                          }));
        require(adapter.displayForKey("1:display0").ratio === 0.4,
                "pending request never changes the confirmed level");
        fakeBridge.snapshotReceived(state(1, [display("1:display0", "Main Display", false, 0.7,
                                                      false, "none"), second], {
                                              "key": "1:display0",
                                              "ratio": 0.7,
                                              "origin": "self",
                                              "requestId": 1
                                          }, {
                                              "requestId": 1,
                                              "outcome": "confirmed"
                                          }));
        require(confirmedCount === 1 && confirmedKey === "1:display0" && confirmedGeneration === 1
                && confirmedRevision === 1 && confirmedSurfaceToken === localSurfaceToken,
                "matching confirmation retains only the initiating local surface context");
        const firstPresentation = adapter.resolveTransient("1:display0", 1, 1);
        require(firstPresentation !== null && firstPresentation.primary === "Main Display"
                && firstPresentation.detail === "PowerDevil confirmed" && firstPresentation.value
                === "70%" && firstPresentation.progress === 0.7,
                "exact revision resolves a bounded logical-state presentation");
        require(adapter.resolveTransient("1:display0", 1, 2) === null,
                "unconfirmed revision cannot resolve presentation content");

        fakeBridge.snapshotReceived(state(1, [display("1:display0", "Main Display", false, 0.8,
                                                      false, "none"), second], {
                                              "key": "1:display0",
                                              "ratio": 0.8,
                                              "origin": "external",
                                              "requestId": 0
                                          }, null));
        require(confirmedCount === 2 && confirmedRevision === 2 && confirmedSurfaceToken === null,
                "external change reuses the display source without inventing surface identity");
        require(adapter.resolveTransient("1:display0", 1, 1) === null && adapter.resolveTransient(
                    "1:display0", 1, 2).value === "80%",
                "same display retains only its latest backend-confirmed revision");

        fakeBridge.snapshotReceived(state(1, [second], null, null));
        require(invalidatedCount === 1 && adapter.resolveTransient("1:display0", 1, 2) === null,
                "display removal invalidates exact transient identity");
        fakeBridge.snapshotReceived({
                                        "available": false,
                                        "supported": false,
                                        "generation": 0,
                                        "displays": [],
                                        "change": null,
                                        "request": null
                                    });
        require(!adapter.available && !adapter.supported && adapter.displays.length === 0
                && invalidatedCount === 2,
                "service loss exposes unsupported state without a fake zero display");

        fakeBridge.snapshotReceived(state(2, [display("2:display0", "Replacement", false, 0.25,
                                                      false, "none")], null, null));
        require(adapter.generation === 2 && adapter.requestBrightness("2:display0", 0.5, null),
                "replacement generation accepts only its fresh key");
        fakeBridge.snapshotReceived(state(2, [display("2:display0", "Replacement", false, 0.25,
                                                      false, "timeout")], null, {
                                              "requestId": 2,
                                              "outcome": "timeout"
                                          }));
        require(adapter.requestBrightness("2:display0", 0.5, null),
                "terminal timeout clears local dispatch state while preserving confirmation");

        runSoakStage();
    }

    function runSoakStage() {
        console.warn("brightness: 20-cycle helper lifecycle soak");
        fakeBridge.fatalFailure();
        require(!adapter.available && !adapter.supported && adapter.displays.length === 0
                && adapter.activeTimerCount === 0,
                "soak baseline clears the pre-existing pending replacement request");
        const initialParsedSnapshots = parsedSnapshotCount;
        const initialConfirmed = confirmedCount;
        const initialInvalidated = invalidatedCount;
        const initialWrites = fakeBridge.writeCount;

        for (let cycle = 0; cycle < 20; ++cycle) {
            parser.acceptLine("not json " + cycle);
            parser.acceptLine("{\"type\":\"state\",\"generation\":" + cycle + "}");
            require(parsedSnapshotCount === initialParsedSnapshots
                    && parser.maximumDiagnostics === 4 && parser.activeTimerCount === 0,
                    "cycle " + cycle + " keeps malformed helper diagnostics bounded and dormant");

            fakeBridge.ready = false;
            require(!adapter.requestBrightness((cycle + 10) + ":display0", 0.5, null)
                    && fakeBridge.writeCount === initialWrites + cycle * 3,
                    "cycle " + cycle + " rejects writes while the helper is unavailable");
            fakeBridge.ready = true;

            const generation = 10 + cycle * 2;
            const key = generation + ":display0";
            const replacementGeneration = generation + 1;
            const replacementKey = replacementGeneration + ":display0";
            fakeBridge.snapshotReceived(state(generation, [display(key, "Cycle Display", false,
                                                                   0.25, false, "none")], null,
                                                       null));
            require(adapter.available && adapter.supported && adapter.generation === generation
                    && adapter.displays.length === 1 && adapter.activeTimerCount === 0,
                    "cycle " + cycle + " exposes one replacement-owned display and no timer");

            require(adapter.requestBrightness(key, 0.75, null)
                    && !adapter.requestBrightness(key, 0.5, null),
                    "cycle " + cycle + " admits one write and rejects queueing");
            const timeoutRequest = fakeBridge.lastRequestId;
            fakeBridge.snapshotReceived(state(generation, [display(key, "Cycle Display", false,
                                                                   0.25, true, "none")], null, {
                                                   "requestId": timeoutRequest,
                                                   "outcome": "pending"
                                               }));
            fakeBridge.snapshotReceived(state(generation, [display(key, "Cycle Display", false,
                                                                   0.25, false, "timeout")], null, {
                                                   "requestId": timeoutRequest,
                                                   "outcome": "timeout"
                                               }));
            require(adapter.displayForKey(key).ratio === 0.25
                    && adapter.requestBrightness(key, 0.5, null),
                    "cycle " + cycle + " timeout preserves backend state and clears local dispatch");

            fakeBridge.fatalFailure();
            require(!adapter.available && !adapter.supported && adapter.displays.length === 0
                    && adapter.resolveTransient(key, generation, 1) === null
                    && invalidatedCount === initialInvalidated + cycle * 2 + 1,
                    "cycle " + cycle + " owner loss clears models, pending work, and stale projection");

            fakeBridge.snapshotReceived(state(replacementGeneration,
                                               [display(replacementKey, "Replacement Display", false,
                                                        0.55, false, "none")], null, null));
            require(adapter.generation === replacementGeneration && adapter.displays.length === 1
                    && !adapter.requestBrightness(key, 0.6, null)
                    && adapter.requestBrightness(replacementKey, 0.6, null),
                    "cycle " + cycle + " recovery accepts only the replacement generation");
            require(adapter.displayForKey(replacementKey).ratio === 0.55,
                    "cycle " + cycle + " recovery does not speculate backend brightness");

            fakeBridge.snapshotReceived({
                                            "available": false,
                                            "supported": false,
                                            "generation": 0,
                                            "displays": [],
                                            "change": null,
                                            "request": null
                                        });
            require(!adapter.available && !adapter.supported && adapter.generation === 0
                    && adapter.displays.length === 0 && adapter.activeTimerCount === 0
                    && invalidatedCount === initialInvalidated + (cycle + 1) * 2
                    && confirmedCount === initialConfirmed
                    && fakeBridge.writeCount === initialWrites + (cycle + 1) * 3,
                    "cycle " + cycle + " returns to exact model, timer, and request counts");
        }

        require(!adapter.available && !adapter.supported && adapter.generation === 0
                && adapter.displays.length === 0 && adapter.activeTimerCount === 0
                && parsedSnapshotCount === initialParsedSnapshots
                && confirmedCount === initialConfirmed,
                "brightness soak finishes at its pre-cycle clean state");
        console.warn("brightness adapter tests passed");
        Qt.exit(0);
    }

    QtObject {
        id: fakeBridge

        property bool ready: true
        property int writeCount: 0
        property int lastRequestId: 0
        property string lastDisplayKey: ""
        property real lastRatio: -1

        signal snapshotReceived(var snapshot)
        signal fatalFailure

        function setBrightness(requestId, displayKey, ratio) {
            writeCount += 1;
            lastRequestId = requestId;
            lastDisplayKey = displayKey;
            lastRatio = ratio;
            return true;
        }
    }

    BrightnessBridge {
        id: parser

        helperPath: "/usr/bin/true"
        enabled: false
        onSnapshotReceived: snapshot => test.parsedSnapshotCount += 1
    }

    BrightnessAdapter {
        id: adapter

        helperPath: "/usr/bin/true"
        bridge: fakeBridge
        onConfirmedBrightnessChanged: function (sourceToken, sourceGeneration, revision,
                                                initiatingSurfaceToken) {
            test.confirmedCount += 1;
            test.confirmedKey = sourceToken;
            test.confirmedGeneration = sourceGeneration;
            test.confirmedRevision = revision;
            test.confirmedSurfaceToken = initiatingSurfaceToken;
        }
        onConfirmedBrightnessInvalidated: function (sourceToken, sourceGeneration) {
            test.invalidatedCount += 1;
        }
    }

    Component.onCompleted: Qt.callLater(run)
}

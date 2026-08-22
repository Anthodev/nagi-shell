pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

// Stable PowerDevil brightness boundary. Presentation sees only bounded labels,
// normalized logical levels, request state, and opaque generation identities.
Scope {
    id: root

    required property string helperPath

    // Verification seam. Production owns one native BrightnessBridge.
    property var bridge: null

    readonly property bool backendReady: engine.currentBridge !== null && engine.currentBridge.ready
    readonly property bool available: engine.snapshot.available
    readonly property bool supported: engine.snapshot.supported
    readonly property int generation: engine.snapshot.generation
    readonly property var displays: engine.snapshot.displays
    readonly property int activeTimerCount: root.bridge === null ? nativeBridge.activeTimerCount : 0

    signal confirmedBrightnessChanged(string sourceToken, int sourceGeneration, int revision,
                                      var initiatingSurfaceToken)
    signal confirmedBrightnessInvalidated(string sourceToken, int sourceGeneration)
    signal requestFinished(int requestId, string outcome)

    function requestBrightness(displayKey, ratio, initiatingSurfaceToken) {
        return engine.requestBrightness(displayKey, ratio, initiatingSurfaceToken);
    }

    function resolveTransient(sourceToken, sourceGeneration, revision) {
        return engine.resolveTransient(sourceToken, sourceGeneration, revision);
    }

    function displayForKey(displayKey) {
        return engine.displayForKey(displayKey);
    }

    onBridgeChanged: engine.resetSnapshot()
    Component.onDestruction: engine.cleanup()

    BrightnessBridge {
        id: nativeBridge

        helperPath: root.helperPath
        enabled: root.bridge === null
    }

    Connections {
        target: engine.currentBridge
        ignoreUnknownSignals: true

        function onSnapshotReceived(snapshot) {
            engine.acceptSnapshot(snapshot);
        }

        function onFatalFailure() {
            engine.resetSnapshot();
        }
    }

    QtObject {
        id: engine

        property var currentBridge: root.bridge === null ? nativeBridge : root.bridge
        property int nextRequestId: 1
        property var snapshot: unavailableSnapshot()
        property var revisions: ({})
        property var presentations: ({})
        property var localOrigins: ({})
        property var dispatchedKeys: ({})

        function acceptSnapshot(candidate) {
            const previous = snapshot;
            const previousGeneration = previous.generation;
            const currentKeys = {};
            for (let index = 0; index < candidate.displays.length; index += 1) {
                currentKeys["$" + candidate.displays[index].key] = true;
            }
            for (let index = 0; index < previous.displays.length; index += 1) {
                const previousKey = previous.displays[index].key;
                if (previousGeneration !== candidate.generation || currentKeys["$" + previousKey]
                        !== true) {
                    root.confirmedBrightnessInvalidated(previousKey, previousGeneration);
                    delete revisions["$" + previousKey];
                    delete presentations["$" + previousKey];
                }
            }
            if (previousGeneration !== candidate.generation) {
                localOrigins = {};
                dispatchedKeys = {};
            }

            snapshot = candidate;
            if (candidate.change !== null) {
                publishConfirmedChange(candidate.change);
            }
            if (candidate.request !== null) {
                const requestId = candidate.request.requestId;
                const outcome = candidate.request.outcome;
                root.requestFinished(requestId, outcome);
                if (outcome !== "pending") {
                    delete localOrigins["$" + requestId];
                    delete dispatchedKeys["$" + requestId];
                }
            }
        }

        function publishConfirmedChange(change) {
            const display = displayForKey(change.key);
            if (display === null) {
                return;
            }
            const mapKey = "$" + change.key;
            const revision = revisions[mapKey] === undefined ? 1 : revisions[mapKey] + 1;
            revisions[mapKey] = revision;
            presentations[mapKey] = {
                "generation": snapshot.generation,
                "revision": revision,
                "presentation": {
                    "iconName": "display-brightness-symbolic",
                    "primary": display.label.length === 0 ? "Brightness" : display.label,
                    "detail": "PowerDevil confirmed",
                    "value": Math.round(display.ratio * 100) + "%",
                    "progress": display.ratio
                }
            };
            const initiatingSurfaceToken = change.origin === "self" ? localOrigins["$"
                                                                                   + change.requestId] :
                                                                      null;
            root.confirmedBrightnessChanged(change.key, snapshot.generation, revision,
                                            initiatingSurfaceToken === undefined ? null :
                                                                                   initiatingSurfaceToken);
        }

        function requestBrightness(displayKey, ratio, initiatingSurfaceToken) {
            const display = displayForKey(displayKey);
            if (currentBridge === null || !currentBridge.ready || display === null || display.pending
                    || isDispatchPending(displayKey) || typeof ratio !== "number" ||
                    !Number.isFinite(ratio) || ratio < 0 || ratio > 1) {
                return false;
            }
            const requestId = allocateRequestId();
            if (!currentBridge.setBrightness(requestId, displayKey, ratio)) {
                return false;
            }
            localOrigins["$" + requestId] = initiatingSurfaceToken;
            dispatchedKeys["$" + requestId] = displayKey;
            return true;
        }

        function resolveTransient(sourceToken, sourceGeneration, revision) {
            if (typeof sourceToken !== "string" || sourceToken.length === 0 || !Number.isInteger(
                        sourceGeneration) || sourceGeneration <= 0 || !Number.isInteger(revision)
                    || revision <= 0 || sourceGeneration !== snapshot.generation || displayForKey(
                        sourceToken) === null) {
                return null;
            }
            const resolved = presentations["$" + sourceToken];
            if (resolved === undefined || resolved.generation !== sourceGeneration
                    || resolved.revision !== revision) {
                return null;
            }
            return resolved.presentation;
        }

        function displayForKey(displayKey) {
            if (typeof displayKey !== "string" || displayKey.length === 0) {
                return null;
            }
            for (let index = 0; index < snapshot.displays.length; index += 1) {
                if (snapshot.displays[index].key === displayKey) {
                    return snapshot.displays[index];
                }
            }
            return null;
        }

        function isDispatchPending(displayKey) {
            for (const requestKey in dispatchedKeys) {
                if (dispatchedKeys[requestKey] === displayKey) {
                    return true;
                }
            }
            return false;
        }

        function allocateRequestId() {
            const requestId = nextRequestId;
            nextRequestId = nextRequestId >= 2147483647 ? 1 : nextRequestId + 1;
            return requestId;
        }

        function unavailableSnapshot() {
            return {
                "available": false,
                "supported": false,
                "generation": 0,
                "displays": [],
                "change": null,
                "request": null
            };
        }

        function resetSnapshot() {
            const previous = snapshot;
            for (let index = 0; index < previous.displays.length; index += 1) {
                root.confirmedBrightnessInvalidated(previous.displays[index].key,
                                                    previous.generation);
            }
            snapshot = unavailableSnapshot();
            revisions = {};
            presentations = {};
            localOrigins = {};
            dispatchedKeys = {};
        }

        function cleanup() {
            currentBridge = null;
            resetSnapshot();
        }
    }
}

pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

// One process-wide normalized aggregate. Presentation receives only counts,
// availability, opaque versions, and fixed generic status text.
Scope {
    id: root

    required property string helperPath
    property bool enabled: true
    // Verification seam. Production owns one native GamingPerformanceBridge.
    property var bridge: null

    readonly property bool backendReady: engine.currentBridge !== null && engine.currentBridge.ready
    readonly property bool available: engine.snapshot.available
    readonly property bool gameModeAvailable: engine.snapshot.gameModeAvailable
    readonly property bool powerProfilesAvailable: engine.snapshot.powerProfilesAvailable
    readonly property int sourceCount: engine.snapshot.sourceCount
    readonly property bool active: sourceCount > 0
    readonly property int generation: engine.generation
    readonly property int revision: engine.revision
    readonly property int activeTimerCount: root.bridge === null ? nativeBridge.activeTimerCount : 0
    readonly property string sourceToken: "gaming-performance"

    signal feedbackRequested(string sourceToken, int sourceGeneration, int revision)
    signal feedbackInvalidated(string sourceToken, int sourceGeneration)

    function resolveTransient(sourceToken, sourceGeneration, revision) {
        return engine.resolveTransient(sourceToken, sourceGeneration, revision);
    }

    onBridgeChanged: engine.reset()
    onEnabledChanged: {
        if (!enabled) {
            engine.reset();
        }
    }
    Component.onDestruction: engine.reset()

    GamingPerformanceBridge {
        id: nativeBridge

        helperPath: root.helperPath
        enabled: root.enabled && root.bridge === null
    }

    Connections {
        target: engine.currentBridge
        ignoreUnknownSignals: true

        function onSnapshotReceived(snapshot) {
            engine.acceptSnapshot(snapshot);
        }

        function onFatalFailure() {
            engine.reset();
        }
    }

    QtObject {
        id: engine

        property var currentBridge: root.bridge === null ? nativeBridge : root.bridge
        property var snapshot: unavailableSnapshot()
        property bool initialized: false
        property int generation: 0
        property int nextGeneration: 1
        property int revision: 0
        property var presentation: null

        function acceptSnapshot(candidate) {
            if (!root.enabled) {
                return;
            }

            const previous = snapshot;
            const wasInitialized = initialized;
            if (!wasInitialized) {
                generation = nextGeneration;
                nextGeneration = nextGeneration >= 2147483647 ? 1 : nextGeneration + 1;
                initialized = true;
            }
            snapshot = candidate;

            if (!wasInitialized) {
                if (candidate.sourceCount > 0) {
                    publish(qsTr("Gaming performance active"));
                }
                return;
            }

            if (candidate.event === "sourceUnavailable") {
                publish(qsTr("Gaming performance source unavailable"));
                return;
            }
            if (candidate.sourceCount === previous.sourceCount) {
                return;
            }
            if (previous.sourceCount === 0 && candidate.sourceCount > 0) {
                publish(qsTr("Gaming performance active"));
            } else if (candidate.sourceCount > previous.sourceCount) {
                publish(qsTr("Gaming performance requested"));
            } else if (candidate.sourceCount === 0) {
                publish(qsTr("Gaming performance inactive"));
            } else {
                publish(qsTr("Gaming performance request ended"));
            }
        }

        function publish(primary) {
            revision = revision >= 2147483647 ? 1 : revision + 1;
            presentation = {
                "iconName": "gaming-performance-symbolic",
                "primary": primary,
                "detail": qsTr("System status"),
                "value": "",
                "progress": -1
            };
            root.feedbackRequested(root.sourceToken, generation, revision);
        }

        function resolveTransient(candidateToken, candidateGeneration, candidateRevision) {
            if (!root.enabled || presentation === null || candidateToken !== root.sourceToken
                    || candidateGeneration !== generation || candidateRevision !== revision) {
                return null;
            }
            return presentation;
        }

        function reset() {
            if (generation > 0) {
                root.feedbackInvalidated(root.sourceToken, generation);
            }
            snapshot = unavailableSnapshot();
            initialized = false;
            generation = 0;
            revision = 0;
            presentation = null;
        }

        function unavailableSnapshot() {
            return {
                "available": false,
                "gameModeAvailable": false,
                "powerProfilesAvailable": false,
                "gameClientCount": 0,
                "performanceProfile": false,
                "sourceCount": 0,
                "event": "snapshot"
            };
        }
    }
}

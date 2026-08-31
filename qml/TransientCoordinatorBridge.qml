import Quickshell
import QtQuick

// Routes normalized producer identities into the process-wide owner reducer.
// It owns no payload, queue, timer, or backend action.
Scope {
    id: bridge

    required property var coordinator
    required property var surfaceHost
    property var workspaceSource: null
    property var brightnessSource: null
    property var audioSource: null
    property var gamingPerformanceSource: null
    property var notificationSource: null

    Connections {
        target: bridge.workspaceSource
        ignoreUnknownSignals: true

        function onConfirmedWorkspaceChanged(sourceToken, sourceGeneration, revision, outputToken) {
            if (bridge.surfaceHost === null || bridge.surfaceHost === undefined
                    || typeof bridge.surfaceHost.surfaceTokenForOutput !== "function") {
                return;
            }
            const initiatingSurfaceToken = bridge.surfaceHost.surfaceTokenForOutput(outputToken);
            if (initiatingSurfaceToken === null || initiatingSurfaceToken === undefined) {
                return;
            }
            bridge.coordinator.requestWorkspace(sourceToken, sourceGeneration, revision,
                                                initiatingSurfaceToken);
        }

        function onConfirmedWorkspaceInvalidated(sourceToken, sourceGeneration) {
            bridge.coordinator.invalidateTransient(sourceToken, sourceGeneration);
        }
    }

    Connections {
        target: bridge.brightnessSource
        ignoreUnknownSignals: true

        function onConfirmedBrightnessChanged(sourceToken, sourceGeneration, revision,
                                              initiatingSurfaceToken) {
            bridge.coordinator.requestBrightness(sourceToken, sourceGeneration, revision,
                                                 initiatingSurfaceToken);
        }

        function onConfirmedBrightnessInvalidated(sourceToken, sourceGeneration) {
            bridge.coordinator.invalidateTransient(sourceToken, sourceGeneration);
        }
    }

    Connections {
        target: bridge.audioSource
        ignoreUnknownSignals: true

        function onConfirmedOutputChanged(sourceToken, sourceGeneration, revision) {
            bridge.coordinator.requestVolume(sourceToken, sourceGeneration, revision, null);
        }

        function onConfirmedOutputInvalidated(sourceToken, sourceGeneration) {
            bridge.coordinator.invalidateTransient(sourceToken, sourceGeneration);
        }
    }

    Connections {
        target: bridge.gamingPerformanceSource
        ignoreUnknownSignals: true

        function onFeedbackRequested(sourceToken, sourceGeneration, revision) {
            bridge.coordinator.requestGamingPerformance(sourceToken, sourceGeneration, revision,
                                                        null);
        }

        function onFeedbackInvalidated(sourceToken, sourceGeneration) {
            bridge.coordinator.invalidateTransient(sourceToken, sourceGeneration);
        }
    }

    Connections {
        target: bridge.notificationSource
        ignoreUnknownSignals: true

        function onTransientRequested(sourceToken, sourceGeneration, revision) {
            bridge.coordinator.requestNotification(sourceToken, sourceGeneration, revision, null);
        }

        function onTransientInvalidated(sourceToken, sourceGeneration) {
            bridge.coordinator.invalidateTransient(sourceToken, sourceGeneration);
        }
    }
}

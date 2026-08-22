import Quickshell
import QtQuick

// Routes normalized producer identities into the one owner reducer. It owns no
// payload, queue, timer, or backend action.
Scope {
    id: bridge

    required property var coordinator
    required property var surfaceToken
    property var audioSource: null
    property var notificationSource: null

    Connections {
        target: bridge.audioSource
        ignoreUnknownSignals: true

        function onConfirmedOutputChanged(sourceToken, sourceGeneration, revision) {
            bridge.coordinator.requestVolume(sourceToken, sourceGeneration, revision,
                                             bridge.surfaceToken);
        }

        function onConfirmedOutputInvalidated(sourceToken, sourceGeneration) {
            bridge.coordinator.invalidateTransient(sourceToken, sourceGeneration);
        }
    }

    Connections {
        target: bridge.notificationSource
        ignoreUnknownSignals: true

        function onTransientRequested(sourceToken, sourceGeneration, revision) {
            bridge.coordinator.requestNotification(sourceToken, sourceGeneration, revision,
                                                   bridge.surfaceToken);
        }

        function onTransientInvalidated(sourceToken, sourceGeneration) {
            bridge.coordinator.invalidateTransient(sourceToken, sourceGeneration);
        }
    }
}

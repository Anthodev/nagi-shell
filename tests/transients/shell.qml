import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    property real nowMs: 0
    property var surfaceToken: null

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function run() {
        surfaceToken = {};
        require(coordinator.attachSurface(surfaceToken, 1), "transient surface attaches");
        workspace.confirmedWorkspaceChanged("workspace-current", 1, 1);
        require(coordinator.ownerName === "workspace" && coordinator.ownerSourceRevision === 1,
                "confirmed workspace change routes once to the fallback surface");
        const workspaceEpoch = coordinator.ownerEpoch;
        for (let revision = 2; revision <= 20; revision += 1) {
            workspace.confirmedWorkspaceChanged("workspace-current", 1, revision);
        }
        require(coordinator.ownerName === "workspace" && coordinator.ownerEpoch === workspaceEpoch
                && coordinator.ownerSourceRevision === 20 && coordinator.pendingTransientCount === 0,
                "workspace burst coalesces in place without queue growth");

        brightness.confirmedBrightnessChanged("1:display0", 1, 1, null);
        require(coordinator.ownerName === "brightness" && coordinator.restorationDepth === 1,
                "external brightness preempts workspace through fallback routing");
        workspace.confirmedWorkspaceInvalidated("workspace-current", 1);
        require(coordinator.restorationDepth === 0,
                "workspace generation loss removes its suspended feedback");
        const brightnessEpoch = coordinator.ownerEpoch;
        brightness.confirmedBrightnessChanged("1:display0", 1, 2, surfaceToken);
        require(coordinator.ownerEpoch === brightnessEpoch && coordinator.ownerSourceRevision === 2
                && coordinator.pendingTransientCount === 0,
                "local brightness confirmation coalesces without a parallel routing path");
        brightness.confirmedBrightnessInvalidated("1:display0", 1);
        require(coordinator.ownerName === "idle",
                "brightness display removal invalidates visible feedback");

        audio.confirmedOutputChanged("audio-output-1", 1, 1);
        require(coordinator.ownerName === "volume" && coordinator.ownerSourceRevision === 1,
                "confirmed output change enters the volume owner");
        const volumeEpoch = coordinator.ownerEpoch;
        for (let revision = 2; revision <= 20; revision += 1) {
            audio.confirmedOutputChanged("audio-output-1", 1, revision);
        }
        require(coordinator.ownerName === "volume" && coordinator.ownerEpoch === volumeEpoch
                && coordinator.ownerSourceRevision === 20 && coordinator.pendingTransientCount === 0,
                "rapid visible output confirmations coalesce in place without queue growth");

        audio.confirmedInputChanged("audio-input-1", 1, 1);
        require(coordinator.ownerSourceToken === "audio-output-1"
                && coordinator.ownerSourceRevision === 20,
                "default-input confirmation cannot create an output-volume transient");

        notifications.transientRequested("notification-1", 1, 1);
        require(coordinator.ownerName === "notification" && coordinator.restorationDepth === 1,
                "notification priority preempts and suspends confirmed volume");
        audio.confirmedOutputChanged("audio-output-1", 1, 21);
        require(coordinator.restorationDepth === 1 && coordinator.pendingTransientCount === 0,
                "suspended volume source coalesces to one latest revision");
        audio.confirmedOutputInvalidated("audio-output-1", 1);
        require(coordinator.ownerName === "notification" && coordinator.restorationDepth === 0,
                "endpoint removal invalidates the suspended volume without stale restoration");

        notifications.transientRequested("notification-2", 1, 1);
        require(coordinator.pendingTransientCount === 1,
                "independent notification occupies one shared mailbox slot");
        const notificationEpoch = coordinator.ownerEpoch;
        notifications.transientRequested("notification-1", 1, 2);
        require(coordinator.ownerEpoch === notificationEpoch && coordinator.ownerSourceRevision
                === 2 && coordinator.pendingTransientCount === 1,
                "same-notification replacement coalesces without disturbing independent work");
        notifications.transientInvalidated("notification-1", 1);
        require(coordinator.ownerName === "notification" && coordinator.ownerSourceToken
                === "notification-2" && coordinator.pendingTransientCount === 0,
                "notification invalidation restores the next eligible source atomically");
        notifications.transientInvalidated("notification-2", 1);
        require(coordinator.ownerName === "idle", "last notification invalidation restores Idle");

        require(coordinator.setHover(1, true), "expanded baseline enters for pending test");
        for (let revision = 1; revision <= 20; revision += 1) {
            audio.confirmedOutputChanged("audio-output-2", 2, revision);
        }
        require(coordinator.ownerName === "expanded" && coordinator.pendingTransientCount === 1,
                "blocked output burst keeps one replaceable pending transient");
        audio.confirmedOutputInvalidated("audio-output-2", 2);
        require(coordinator.pendingTransientCount === 0,
                "endpoint disappearance drops pending audio before presentation");
        require(coordinator.setHover(1, false) && coordinator.ownerName === "idle",
                "expired pending audio cannot replay after Expanded");

        audio.confirmedOutputChanged("audio-output-3", 3, 1);
        require(coordinator.ownerName === "volume" && coordinator.ownerSourceToken
                === "audio-output-3", "replacement endpoint presents only its fresh generation");
        audio.confirmedOutputInvalidated("audio-output-3", 3);
        require(coordinator.ownerName === "idle",
                "unavailable output cannot leave a stale volume owner");

        console.warn("transient integration tests passed");
        Qt.exit(0);
    }

    QtObject {
        id: workspace

        signal confirmedWorkspaceChanged(string sourceToken, int sourceGeneration, int revision)
        signal confirmedWorkspaceInvalidated(string sourceToken, int sourceGeneration)
    }

    QtObject {
        id: brightness

        signal confirmedBrightnessChanged(string sourceToken, int sourceGeneration, int revision,
                                          var initiatingSurfaceToken)
        signal confirmedBrightnessInvalidated(string sourceToken, int sourceGeneration)
    }

    QtObject {
        id: audio

        signal confirmedOutputChanged(string sourceToken, int sourceGeneration, int revision)
        signal confirmedInputChanged(string sourceToken, int sourceGeneration, int revision)
        signal confirmedOutputInvalidated(string sourceToken, int sourceGeneration)
    }

    QtObject {
        id: notifications

        signal transientRequested(string sourceToken, int sourceGeneration, int revision)
        signal transientInvalidated(string sourceToken, int sourceGeneration)
    }

    IslandStateCoordinator {
        id: coordinator

        monotonicNow: () => test.nowMs
    }

    TransientCoordinatorBridge {
        coordinator: coordinator
        surfaceToken: test.surfaceToken
        workspaceSource: workspace
        brightnessSource: brightness
        audioSource: audio
        notificationSource: notifications
    }

    Component.onCompleted: Qt.callLater(run)
}

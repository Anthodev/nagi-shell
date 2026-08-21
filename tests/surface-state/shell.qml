import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    property int step: 0
    property int launcherEpoch: 0
    property int launcherFocusSerial: 0
    property int modalEpoch: 0
    property int modalRevision: 0
    readonly property int maximumRetryAttempts: 500
    property int retryAttempts: 0

    function advance() {
        Qt.callLater(test.runStep);
    }

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function runStep() {
        if (host.surfaceToken === null || !coordinator.presentationVisible) {
            retryAttempts += 1;
            require(retryAttempts <= maximumRetryAttempts,
                    "actual surface did not acknowledge state within five seconds");
            retry.restart();
            return;
        }
        retryAttempts = 0;

        if (step === 0) {
            require(coordinator.ownerName === "idle", "actual surface acknowledges Idle");
            require(coordinator.openLauncher(null), "shortcut opens Launcher from Idle");
        } else if (step === 1) {
            require(coordinator.ownerName === "launcher" && coordinator.presentationVisible,
                    "actual surface acknowledges Launcher from Idle");
            require(coordinator.focusTarget === coordinator.focusLauncherSearch,
                    "Launcher presentation targets search focus");
            require(coordinator.cancelInteractive(coordinator.ownerEpoch),
                    "Idle Launcher cancellation is routed through coordinator");
        } else if (step === 2) {
            require(coordinator.ownerName === "idle", "Launcher restores Idle");
            require(coordinator.setExpanded(true, host.surfaceToken), "dashboard expands locally");
        } else if (step === 3) {
            require(coordinator.ownerName === "expanded" && coordinator.presentationVisible,
                    "actual surface acknowledges Expanded");
            require(coordinator.openLauncher(null), "shortcut opens Launcher from Expanded");
            launcherEpoch = coordinator.ownerEpoch;
        } else if (step === 4) {
            require(coordinator.ownerName === "launcher" && coordinator.presentationVisible,
                    "actual surface acknowledges Launcher from Expanded");
            launcherFocusSerial = coordinator.focusRequestSerial;
            require(coordinator.openLauncher(null),
                    "shortcut repeats the already-visible Launcher intent");
            require(coordinator.ownerEpoch === launcherEpoch,
                    "repeated shortcut preserves the Launcher owner");
            require(coordinator.focusRequestSerial === launcherFocusSerial + 1,
                    "repeated visible intent refocuses search");
            require(coordinator.cancelInteractive(launcherEpoch),
                    "Expanded Launcher cancellation is routed through coordinator");
        } else if (step === 5) {
            require(coordinator.ownerName === "expanded", "Launcher restores Expanded");
            require(coordinator.setExpanded(false, host.surfaceToken),
                    "dashboard collapses locally");
            require(coordinator.requestVolume("visible-volume", host.surfaceToken),
                    "volume transient enters from Idle");
        } else if (step === 6) {
            require(coordinator.ownerName === "volume" && coordinator.presentationVisible,
                    "actual surface acknowledges Transient");
            require(coordinator.openLauncher(null), "shortcut opens Launcher from Transient");
        } else if (step === 7) {
            require(coordinator.ownerName === "launcher" && coordinator.presentationVisible,
                    "actual surface acknowledges Launcher from Transient");
            require(coordinator.cancelInteractive(coordinator.ownerEpoch),
                    "Transient Launcher cancellation is routed through coordinator");
        } else if (step === 8) {
            require(coordinator.ownerName === "volume" && coordinator.presentationVisible,
                    "Launcher restores fresh Transient predecessor");
            require(coordinator.openLauncher(host.surfaceToken),
                    "dashboard reopens Launcher for Modal predecessor");
        } else if (step === 9) {
            require(coordinator.ownerName === "launcher" && coordinator.presentationVisible,
                    "actual surface acknowledges Modal predecessor");
            require(coordinator.syncPolkitModal(true, true, 1),
                    "existing Polkit flow enters Modal");
            modalEpoch = coordinator.ownerEpoch;
            modalRevision = coordinator.revision;
        } else if (step === 10) {
            require(coordinator.ownerName === "polkitModal" && coordinator.presentationVisible,
                    "actual surface acknowledges Modal");
            require(!coordinator.openLauncher(null), "shortcut is rejected during Modal");
            require(!coordinator.openSession(host.surfaceToken),
                    "session is rejected during Modal");
            require(coordinator.setExpanded(true, host.surfaceToken),
                    "dashboard baseline request is held during Modal");
            require(coordinator.requestNotification("notification", null),
                    "notification remains relevant during Modal");
            require(coordinator.requestVolume("modal-volume", null),
                    "audio remains relevant during Modal");
            require(coordinator.requestBrightness("brightness", null),
                    "brightness remains relevant during Modal");
            require(coordinator.requestWorkspace("workspace", null),
                    "workspace remains relevant during Modal");
            require(coordinator.pendingTransientCount === 4,
                    "all lower transient classes use the bounded mailbox");
            require(coordinator.ownerName === "polkitModal",
                    "lower visible work cannot replace Modal");
            require(coordinator.syncPolkitModal(true, true, 2),
                    "serialized Polkit replacement updates content");
            require(coordinator.ownerEpoch === modalEpoch && coordinator.revision === modalRevision
                    + 1, "serialized replacement preserves Modal ownership");
        } else if (step === 11) {
            require(coordinator.ownerName === "polkitModal" && coordinator.presentationVisible,
                    "replacement Modal content is acknowledged without predecessor flash");
            require(coordinator.syncPolkitModal(false, true, 2),
                    "flow keeps ownership after active clears");
            require(coordinator.ownerName === "polkitModal",
                    "Modal does not restore before flow clears");
            require(coordinator.syncPolkitModal(false, false, 0),
                    "full Polkit cleanup releases Modal");
        } else if (step === 12) {
            require(coordinator.ownerName === "launcher" && coordinator.presentationVisible,
                    "Modal restores the still-relevant Launcher");
            require(coordinator.cancelInteractive(coordinator.ownerEpoch),
                    "Launcher Escape is routed through coordinator");
        } else if (step === 13) {
            require(coordinator.ownerName === "expanded" && coordinator.presentationVisible,
                    "Launcher Escape restores the held dashboard baseline");
            console.log("actual island surface state tests passed");
            Qt.exit(0);
            return;
        }

        step += 1;
        advance();
    }

    IslandStateCoordinator {
        id: coordinator
    }

    IslandSurfaceHost {
        id: host

        coordinator: coordinator
    }

    Timer {
        id: retry

        interval: 10
        onTriggered: test.runStep()
    }

    Component.onCompleted: advance()
}

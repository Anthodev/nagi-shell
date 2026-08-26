import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    property real nowMs: 0
    property var firstToken: null
    property var secondToken: null
    property var thirdToken: null

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function snapshot(token) {
        const ignored = coordinator.stateSerial;
        return coordinator.surfaceSnapshot(token);
    }

    function attachSurfaces() {
        firstToken = {};
        secondToken = {};
        thirdToken = {};
        require(coordinator.attachSurface(firstToken, 1), "first surface attaches");
        require(coordinator.attachSurface(secondToken, 2), "second surface attaches");
        require(coordinator.attachSurface(thirdToken, 3), "third surface attaches");
        require(coordinator.surfaceCount === 3, "one coordinator owns three records");
        require(snapshot(firstToken).ownerName === "idle"
                && snapshot(secondToken).ownerName === "idle"
                && snapshot(thirdToken).ownerName === "idle", "every surface starts Idle");
    }

    function verifyLocalBaselines() {
        require(coordinator.setHover(firstToken, 1, true), "first hover enters");
        require(snapshot(firstToken).ownerName === "expanded", "first surface expands");
        require(snapshot(secondToken).ownerName === "idle", "second surface remains Idle");
        require(!coordinator.setHover(firstToken, 2, false), "stale generation is rejected");
        require(coordinator.setHover(firstToken, 1, false), "first hover clears");
    }

    function verifyInteractiveTransfer() {
        router.preferredToken = secondToken;
        require(coordinator.openLauncher(null), "global launcher routes to preferred surface");
        const firstEpoch = snapshot(secondToken).ownerEpoch;
        require(snapshot(secondToken).ownerName === "launcher"
                && coordinator.interactiveHostToken === secondToken,
                "launcher has one global host");
        require(coordinator.openLauncher(firstToken), "local activation transfers launcher");
        require(snapshot(firstToken).ownerName === "launcher"
                && snapshot(secondToken).ownerName === "idle"
                && coordinator.interactiveHostToken === firstToken,
                "transfer is atomic and leaves previous host Idle");
        require(snapshot(firstToken).ownerEpoch !== firstEpoch, "transfer receives a fresh epoch");

        require(coordinator.openSession(thirdToken), "different island transfers Interactive task");
        const sessionEpoch = snapshot(thirdToken).ownerEpoch;
        require(snapshot(firstToken).ownerName === "idle"
                && snapshot(thirdToken).ownerName === "session",
                "only the transferred Session task survives");
        require(!coordinator.openLauncher(firstToken)
                && snapshot(thirdToken).ownerName === "session",
                "lower-rank Interactive activation cannot preempt Session");
        require(coordinator.cancelInteractive(sessionEpoch), "current Interactive task cancels");
        require(snapshot(thirdToken).ownerName === "idle", "cancellation restores local baseline");
    }

    function verifyDisableAndLoss() {
        require(coordinator.openAudio(firstToken), "Audio opens on first surface");
        const audioEpoch = snapshot(firstToken).ownerEpoch;
        router.preferredToken = secondToken;
        require(coordinator.prepareSurfaceDisable(firstToken), "safe Interactive host transfers");
        require(snapshot(firstToken).ownerName === "idle"
                && snapshot(secondToken).ownerName === "audio"
                && snapshot(secondToken).ownerEpoch === audioEpoch,
                "voluntary disable preserves one safe task owner");

        require(coordinator.syncPolkitModal(true, true, 41), "Modal flow enters");
        require(coordinator.interactiveHostToken === null,
                "Modal admission leaves no competing Interactive focus owner");
        const modalToken = coordinator.modalHostToken;
        require(modalToken !== null && !coordinator.prepareSurfaceDisable(modalToken),
                "voluntary disable is rejected for Modal host");
        router.preferredToken = thirdToken;
        const modalSnapshot = snapshot(modalToken);
        require(coordinator.detachSurface(modalToken, modalSnapshot.generation),
                "involuntary Modal host loss detaches");
        require(coordinator.modalHostToken === thirdToken
                && snapshot(thirdToken).ownerName === "polkitModal"
                && snapshot(thirdToken).restorationDepth === 0,
                "Modal rehomes once without predecessor state");
        require(coordinator.syncPolkitModal(false, false, 0), "Modal flow releases");
        require(snapshot(thirdToken).ownerName === "idle", "rehomed Modal releases to Idle");
        secondToken = {};
        require(coordinator.attachSurface(secondToken, 4),
                "reconnected display receives a fresh session token");
    }

    function verifyTransientProjection() {
        require(coordinator.requestNotification("notification", 1, 1, null),
                "notification enters one global event slot");
        require(coordinator.pendingTransientCount === 1, "broadcast consumes one slot");
        require(snapshot(secondToken).ownerName === "notification"
                && snapshot(thirdToken).ownerName === "notification",
                "notification projects to every eligible island");
        const secondRevision = snapshot(secondToken).revision;
        require(coordinator.requestNotification("notification", 1, 2, null),
                "notification coalesces globally");
        require(coordinator.pendingTransientCount === 1
                && snapshot(secondToken).revision === secondRevision + 1
                && snapshot(thirdToken).ownerSourceRevision === 2,
                "coalescence updates every projection atomically");
        require(coordinator.invalidateTransient("notification", 1),
                "notification invalidates once");
        require(snapshot(secondToken).ownerName === "idle"
                && snapshot(thirdToken).ownerName === "idle"
                && coordinator.pendingTransientCount === 0,
                "invalidation removes every projection atomically");

        require(coordinator.setHover(secondToken, 4, true), "second surface expands");
        require(coordinator.requestVolume("output", 1, 1, null), "volume event broadcasts");
        require(snapshot(secondToken).ownerName === "expanded"
                && snapshot(thirdToken).ownerName === "volume",
                "lower transient respects each surface priority");
        require(coordinator.invalidateTransient("output", 1), "volume event invalidates");
        require(coordinator.setHover(secondToken, 4, false), "second surface returns Idle");

        require(coordinator.requestWorkspace("workspace", 1, 1, thirdToken),
                "workspace event targets action surface");
        require(snapshot(thirdToken).ownerName === "workspace"
                && snapshot(secondToken).ownerName === "idle",
                "workspace never mirrors");
        require(coordinator.invalidateTransient("workspace", 1), "workspace invalidates");
        require(coordinator.requestBrightness("brightness", 1, 1, secondToken),
                "brightness targets initiating surface");
        require(snapshot(secondToken).ownerName === "brightness"
                && snapshot(thirdToken).ownerName === "idle",
                "brightness never guesses another display");
        require(coordinator.invalidateTransient("brightness", 1), "brightness invalidates");
    }

    function verifyTimingAndBounds() {
        require(coordinator.requestVolume("timed", 2, 1, null), "timed volume enters");
        const first = snapshot(firstToken);
        const second = snapshot(secondToken);
        const third = snapshot(thirdToken);
        require(coordinator.acknowledgeVisible(firstToken, first.generation, first.ownerEpoch,
                                               first.revision), "first projection acknowledges");
        require(coordinator.acknowledgeVisible(secondToken, second.generation, second.ownerEpoch,
                                               second.revision), "second projection acknowledges");
        require(coordinator.acknowledgeVisible(thirdToken, third.generation, third.ownerEpoch,
                                               third.revision), "third projection acknowledges");
        nowMs += 1799;
        require(coordinator.setHover(secondToken, 4, false), "pre-boundary dispatch runs");
        require(snapshot(secondToken).ownerName === "volume", "global hold remains before boundary");
        nowMs += 1;
        require(coordinator.setHover(secondToken, 4, false), "hold boundary dispatch runs");
        require(snapshot(secondToken).ownerName === "idle"
                && snapshot(thirdToken).ownerName === "idle",
                "global hold expires atomically");
        coordinator.feedbackDuration = "short";
        require(coordinator.requestVolume("short-timed", 3, 1, null),
                "short feedback preset admits a fresh event");
        const shortFirst = snapshot(firstToken);
        const shortSecond = snapshot(secondToken);
        const shortThird = snapshot(thirdToken);
        require(coordinator.acknowledgeVisible(firstToken, shortFirst.generation,
                                               shortFirst.ownerEpoch, shortFirst.revision)
                && coordinator.acknowledgeVisible(secondToken, shortSecond.generation,
                                                  shortSecond.ownerEpoch, shortSecond.revision)
                && coordinator.acknowledgeVisible(thirdToken, shortThird.generation,
                                                  shortThird.ownerEpoch, shortThird.revision),
                "short feedback starts only after every projection is visible");
        nowMs += 1169;
        coordinator.setHover(secondToken, 4, false);
        require(snapshot(secondToken).ownerName === "volume",
                "short feedback remains before its scaled hold boundary");
        nowMs += 1;
        coordinator.setHover(secondToken, 4, false);
        require(snapshot(secondToken).ownerName === "idle",
                "short feedback expires at its scaled hold boundary");

        coordinator.feedbackDuration = "long";
        require(coordinator.requestWorkspace("long-timed", 3, 1, secondToken),
                "long feedback preset admits a fresh workspace event");
        const longWorkspace = snapshot(secondToken);
        require(coordinator.acknowledgeVisible(secondToken, longWorkspace.generation,
                                               longWorkspace.ownerEpoch, longWorkspace.revision),
                "long workspace feedback begins after visible acknowledgement");
        nowMs += 1799;
        coordinator.setHover(secondToken, 4, false);
        require(snapshot(secondToken).ownerName === "workspace",
                "long workspace feedback remains below its fixed freshness threshold");
        nowMs += 1;
        coordinator.setHover(secondToken, 4, false);
        require(snapshot(secondToken).ownerName === "idle",
                "long workspace hold stays strictly below freshness and expires normally");
        coordinator.feedbackDuration = "normal";


        for (let index = 0; index < 8; index += 1) {
            require(coordinator.requestWorkspace("bounded-" + index, 1, 1, secondToken),
                    "bounded event " + index + " enters");
        }
        require(coordinator.pendingTransientCount === 8, "mailbox remains bounded at eight");
        require(coordinator.requestNotification("higher", 3, 1, null),
                "higher event evicts one bounded candidate");
        require(coordinator.pendingTransientCount === 8, "eviction preserves global bound");
    }

    QtObject {
        id: router

        property var preferredToken: null

        function routeSurfaceToken(excludedToken) {
            if (preferredToken !== null && preferredToken !== excludedToken
                    && test.snapshot(preferredToken).generation > 0) {
                return preferredToken;
            }
            const candidates = [test.firstToken, test.secondToken, test.thirdToken];
            for (let index = 0; index < candidates.length; index += 1) {
                if (candidates[index] !== excludedToken
                        && test.snapshot(candidates[index]).generation > 0) {
                    return candidates[index];
                }
            }
            return null;
        }
    }

    IslandStateCoordinator {
        id: coordinator

        monotonicNow: () => test.nowMs
        surfaceRouter: router
    }

    Timer {
        interval: 1
        running: true
        onTriggered: {
            attachSurfaces();
            verifyLocalBaselines();
            verifyInteractiveTransfer();
            verifyDisableAndLoss();
            verifyTransientProjection();
            verifyTimingAndBounds();
            console.log("coordinator multi-surface tests passed");
            Qt.exit(0);
        }
    }
}

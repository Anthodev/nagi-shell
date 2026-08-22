import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    property int step: 0
    property int retryAttempts: 0
    property int mountedRegionCount: 0
    property int hoverExpandedEpoch: 0
    property int focusSerialBeforeRestore: 0
    property var initialSurfaceToken: null
    property int initialSurfaceGeneration: 0
    readonly property int maximumRetryAttempts: 500

    function advance() {
        Qt.callLater(test.runStep);
    }

    function awaitState(condition, message) {
        if (condition) {
            retryAttempts = 0;
            return true;
        }

        retryAttempts += 1;
        require(retryAttempts <= maximumRetryAttempts, message);
        retry.restart();
        return false;
    }

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function runStep() {
        if (step === 0) {
            if (!awaitState(host.surfaceToken !== null && coordinator.presentationVisible,
                            "actual surface did not acknowledge Idle within five seconds")) {
                return;
            }
            require(coordinator.ownerName === "idle", "actual surface acknowledges Idle");
            require(!host.surfaceFocusable, "Idle never takes keyboard focus");
            initialSurfaceToken = host.surfaceToken;
            initialSurfaceGeneration = host.surfaceGeneration;
            require(coordinator.setHover(host.surfaceGeneration, true),
                    "pointer hover intent expands locally");
        } else if (step === 1) {
            if (!awaitState(coordinator.ownerName === "expanded"
                            && coordinator.presentationVisible
                            && host.loadedDashboardRegionCount === 6,
                            "hover dashboard did not become visible within five seconds")) {
                return;
            }
            require(coordinator.focusTarget === coordinator.focusNone && !host.surfaceFocusable,
                    "hover expansion never steals keyboard focus");
            require(host.surfaceToken === initialSurfaceToken
                    && host.surfaceGeneration === initialSurfaceGeneration,
                    "expansion preserves the one live surface");
            require(host.surfaceWidth <= Theme.size.islandExpandedWidth
                    && host.surfaceHeight <= Theme.size.islandExpandedHeight,
                    "expanded geometry stays within its logical bounds");
            hoverExpandedEpoch = coordinator.ownerEpoch;
            require(coordinator.setExplicitExpanded(host.surfaceGeneration, true),
                    "deliberate keyboard intent joins the visible dashboard");
        } else if (step === 2) {
            if (!awaitState(host.surfaceFocusable && host.dashboardFocused,
                            "deliberate expansion did not receive focus within five seconds")) {
                return;
            }
            require(coordinator.ownerEpoch === hoverExpandedEpoch,
                    "deliberate intent updates the visible dashboard in place");
            require(coordinator.focusTarget === coordinator.focusExpandedDashboard,
                    "coordinator targets dashboard focus only after deliberate intent");
            require(coordinator.openLauncher(host.surfaceToken),
                    "higher-priority interaction interrupts Expanded");
        } else if (step === 3) {
            if (!awaitState(coordinator.ownerName === "launcher"
                            && !coordinator.presentationVisible
                            && !host.surfaceFocusable
                            && host.loadedDashboardRegionCount === 0,
                            "interruption did not hide obsolete dashboard content")) {
                return;
            }
            require(host.surfaceToken === initialSurfaceToken,
                    "interruption still uses the original surface");
            focusSerialBeforeRestore = coordinator.focusRequestSerial;
            require(coordinator.cancelInteractive(coordinator.ownerEpoch),
                    "interrupted interaction cancels through the coordinator");
        } else if (step === 4) {
            if (!awaitState(coordinator.ownerName === "expanded"
                            && coordinator.presentationVisible && host.surfaceFocusable
                            && host.dashboardFocused && host.loadedDashboardRegionCount === 6,
                            "dashboard did not restore visibly with focus")) {
                return;
            }
            require(coordinator.focusRequestSerial === focusSerialBeforeRestore + 1,
                    "restored deliberate dashboard receives one fresh focus request");
            require(host.cancelDashboard(), "keyboard cancellation closes the dashboard");
        } else if (step === 5) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible
                            && !host.surfaceFocusable,
                            "dashboard cancellation did not restore Idle")) {
                return;
            }
            require(!coordinator.hoverIntent && !coordinator.explicitExpandedIntent,
                    "cancellation clears both baseline intents");
            host.reducedMotion = true;
            require(host.requestDeliberateExpansion(),
                    "host exposes deliberate keyboard expansion");
        } else if (step === 6) {
            if (!awaitState(coordinator.ownerName === "expanded"
                            && coordinator.presentationVisible && host.surfaceFocusable
                            && host.surfacePreferredWidth > Theme.size.islandIdleWidth
                            && host.surfacePreferredHeight > Theme.size.islandIdleHeight,
                            "reduced-motion dashboard did not become usable")) {
                return;
            }
            require(host.geometryAnimationDuration === 0,
                    "reduced motion removes geometry interpolation");
            require(host.cancelDashboard(), "Close remains functional with reduced motion");
        } else if (step === 7) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible,
                            "reduced-motion collapse did not restore Idle")) {
                return;
            }
            require(mountedRegionCount >= 12,
                    "all six real region components remount after interruption");
            require(!coordinator.setHover(host.surfaceGeneration + 1, true),
                    "stale surface intent cannot reopen the dashboard");
            console.warn("actual island dashboard surface tests passed");
            Qt.exit(0);
            return;
        }

        step += 1;
        advance();
    }

    component TestRegion: Item {
        implicitWidth: 120
        implicitHeight: 72
        Component.onCompleted: test.mountedRegionCount += 1
    }

    Component {
        id: mediaRegion
        TestRegion {}
    }

    Component {
        id: clockRegion
        TestRegion {}
    }

    Component {
        id: quickControlsRegion
        TestRegion {}
    }

    Component {
        id: audioRegion
        TestRegion {}
    }

    Component {
        id: notificationsRegion
        TestRegion {}
    }

    Component {
        id: navigationRegion
        TestRegion {}
    }

    IslandStateCoordinator {
        id: coordinator
    }

    IslandSurfaceHost {
        id: host

        coordinator: coordinator
        dashboardMediaContent: mediaRegion
        dashboardClockContent: clockRegion
        dashboardQuickControlsContent: quickControlsRegion
        dashboardAudioContent: audioRegion
        dashboardNotificationsContent: notificationsRegion
        dashboardNavigationContent: navigationRegion
    }

    Timer {
        id: retry

        interval: 10
        onTriggered: test.runStep()
    }

    Component.onCompleted: advance()
}

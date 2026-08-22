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
    property real sessionEpoch: 0
    property real historyEpoch: 0
    property var initialSurfaceToken: null
    property int initialSurfaceGeneration: 0
    property int compactTransientWidth: 0
    property int compactTransientHeight: 0
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
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible
                            && host.loadedDashboardRegionCount === 6,
                            "hover dashboard did not become visible within five seconds")) {
                return;
            }
            require(coordinator.focusTarget === coordinator.focusNone && !host.surfaceFocusable,
                    "hover expansion never steals keyboard focus");
            require(host.surfaceToken === initialSurfaceToken && host.surfaceGeneration
                    === initialSurfaceGeneration, "expansion preserves the one live surface");
            require(host.surfaceWidth <= Theme.size.islandExpandedWidth && host.surfaceHeight
                    <= Theme.size.islandExpandedHeight,
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
            if (!awaitState(coordinator.ownerName === "launcher" &&
                            !coordinator.presentationVisible && !host.surfaceFocusable
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
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible
                            && host.surfaceFocusable && host.dashboardFocused
                            && host.loadedDashboardRegionCount === 6,
                            "dashboard did not restore visibly with focus")) {
                return;
            }
            require(coordinator.focusRequestSerial === focusSerialBeforeRestore + 1,
                    "restored deliberate dashboard receives one fresh focus request");
            require(host.cancelDashboard(), "keyboard cancellation closes the dashboard");
        } else if (step === 5) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible &&
                            !host.surfaceFocusable,
                            "dashboard cancellation did not restore Idle")) {
                return;
            }
            require(!coordinator.hoverIntent && !coordinator.explicitExpandedIntent,
                    "cancellation clears both baseline intents");
            host.reducedMotion = true;
            require(host.requestDeliberateExpansion(),
                    "host exposes deliberate keyboard expansion");
        } else if (step === 6) {
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible
                            && host.surfaceFocusable && host.surfacePreferredWidth
                            > Theme.size.islandIdleWidth && host.surfacePreferredHeight
                            > Theme.size.islandIdleHeight,
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
            require(host.requestDeliberateExpansion(),
                    "session entry can originate from a deliberate dashboard");
        } else if (step === 8) {
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible,
                            "dashboard did not reopen for session entry")) {
                return;
            }
            require(coordinator.openSession(host.surfaceToken),
                    "visible dashboard session entry is admitted");
            sessionEpoch = coordinator.ownerEpoch;
        } else if (step === 9) {
            if (!awaitState(coordinator.ownerName === "session" && coordinator.presentationVisible
                            && host.surfaceFocusable && host.sessionFocused,
                            "session focus state: owner=" + coordinator.ownerName + " visible="
                            + coordinator.presentationVisible + " focusable="
                            + host.surfaceFocusable + " focused=" + host.sessionFocused
                            + " target=" + coordinator.focusTarget + " serial="
                            + coordinator.focusRequestSerial)) {
                return;
            }
            require(coordinator.focusTarget === coordinator.focusSessionActions,
                    "session presentation receives the action-grid focus target");
            require(host.surfaceToken === initialSurfaceToken,
                    "session interaction preserves the one live surface");
            require(!coordinator.cancelInteractive(sessionEpoch - 1),
                    "stale session cancellation cannot close the current owner");
            require(coordinator.cancelInteractive(sessionEpoch),
                    "session cancellation accepts the current owner epoch");
        } else if (step === 10) {
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible
                            && host.dashboardFocused,
                            "session cancellation did not restore the deliberate dashboard")) {
                return;
            }
            require(coordinator.openHistory(host.surfaceToken),
                    "visible dashboard history entry is admitted");
            historyEpoch = coordinator.ownerEpoch;
        } else if (step === 11) {
            if (!awaitState(coordinator.ownerName === "history" && coordinator.presentationVisible
                            && host.surfaceFocusable && host.historyFocused && host.historyRowCount
                            === 2, "history view did not render and receive focus in the actual surface")) {
                return;
            }
            require(coordinator.focusTarget === coordinator.focusNotificationHistory,
                    "history presentation receives the list focus target");
            require(!coordinator.cancelInteractive(historyEpoch - 1),
                    "stale history Back cannot close the current owner");
            require(coordinator.cancelInteractive(historyEpoch),
                    "history Back accepts the current owner epoch");
        } else if (step === 12) {
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible
                            && host.dashboardFocused,
                            "history Back did not restore the deliberate dashboard")) {
                return;
            }
            require(host.cancelDashboard(), "restored dashboard remains cancellable");
        } else if (step === 13) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible,
                            "final dashboard cancellation did not restore Idle")) {
                return;
            }
            host.reducedMotion = false;
            require(coordinator.requestVolume("surface-volume", 1, 1, host.surfaceToken),
                    "actual surface accepts a compact value transient");
            require(!coordinator.presentationVisible,
                    "visible hold waits for compact entry completion");
        } else if (step === 14) {
            if (!awaitState(coordinator.ownerName === "volume" && coordinator.presentationVisible
                            && host.transientCommitted,
                            "compact value transient did not commit visibly")) {
                return;
            }
            require(host.transientPrimaryText === "Built-in Audio" && host.transientDetailText
                    === "Output volume", "compact transient resolves the exact normalized payload");
            require(host.surfacePreferredWidth === Theme.size.islandTransientCompactWidth
                    && host.surfacePreferredHeight === Theme.size.islandTransientCompactHeight,
                    "compact transient uses representative OSD geometry");
            require(!host.transientEntryAnimationRunning && !host.surfaceFocusable,
                    "settled transient suspends animation and never steals focus");
            compactTransientWidth = host.surfacePreferredWidth;
            compactTransientHeight = host.surfacePreferredHeight;
            require(coordinator.requestNotification("surface-notification", 2, 1, host.surfaceToken),
                    "notification preempts the compact transient");
            require(!coordinator.presentationVisible,
                    "notification hold waits for its taller entry completion");
        } else if (step === 15) {
            if (!awaitState(coordinator.ownerName === "notification"
                            && coordinator.presentationVisible && host.transientCommitted,
                            "notification transient did not commit visibly")) {
                return;
            }
            require(host.transientPrimaryText === "Messages" && host.transientDetailText
                    === "Review requested",
                    "notification transient replaces compact content without stale text");
            require(host.surfacePreferredWidth > compactTransientWidth
                    && host.surfacePreferredHeight > compactTransientHeight,
                    "notification content receives taller representative geometry");
            require(coordinator.invalidateTransient("surface-notification", 2),
                    "notification source invalidation releases current ownership");
        } else if (step === 16) {
            if (!awaitState(coordinator.ownerName === "volume" && coordinator.presentationVisible
                            && host.transientPrimaryText === "Built-in Audio",
                            "fresh compact predecessor did not restore visibly")) {
                return;
            }
            require(coordinator.invalidateTransient("surface-volume", 1),
                    "restored compact source invalidates cleanly");
        } else if (step === 17) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible,
                            "transient invalidation did not restore Idle")) {
                return;
            }
            host.reducedMotion = true;
            require(coordinator.requestWorkspace("surface-workspace", 3, 1, host.surfaceToken),
                    "reduced-motion workspace transient enters");
        } else if (step === 18) {
            if (!awaitState(coordinator.ownerName === "workspace"
                            && coordinator.presentationVisible && host.transientCommitted,
                            "reduced-motion transient did not commit")) {
                return;
            }
            require(host.transientPrimaryText === "Development" && host.transientDetailText
                    === "Desktop 2 of 4", "reduced motion preserves transient state meaning");
            require(host.geometryAnimationDuration === 0 && !host.transientEntryAnimationRunning,
                    "reduced motion removes geometry and entry animation work");
            require(coordinator.invalidateTransient("surface-workspace", 3),
                    "reduced-motion source invalidates");
        } else if (step === 19) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible,
                            "final transient cleanup did not restore Idle")) {
                return;
            }
            require(mountedRegionCount >= 18,
                    "all six real region components remount across Interactive interruptions");
            require(!coordinator.setHover(host.surfaceGeneration + 1, true),
                    "stale surface intent cannot reopen the dashboard");
            console.warn("actual island transient, dashboard, history, and session tests passed");
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

    ListModel {
        id: fakeHistoryModel

        ListElement {
            firstAdmissionSequence: "2"
            state: "expired"
            appName: "Mail"
            summary: "Build finished"
            body: "The controlled verification run completed."
        }

        ListElement {
            firstAdmissionSequence: "1"
            state: "live"
            appName: "Messages"
            summary: "Review requested"
            body: "Please check the latest changes."
        }
    }

    QtObject {
        id: fakeNotificationService

        readonly property var historyModel: fakeHistoryModel
        readonly property bool serverOwned: true

        function dismiss(recordKey) {
            const index = historyIndex(recordKey);
            if (index < 0) {
                return false;
            }
            fakeHistoryModel.remove(index);
            return true;
        }

        function historyIndex(recordKey) {
            const key = String(recordKey);
            for (let index = 0; index < fakeHistoryModel.count; index += 1) {
                if (String(fakeHistoryModel.get(index).firstAdmissionSequence) === key) {
                    return index;
                }
            }
            return -1;
        }
    }

    QtObject {
        id: fakeSessionService

        readonly property bool backendReady: true
        readonly property bool pending: false
        readonly property string pendingAction: "none"
        readonly property string failure: "none"

        signal operationFinished(int requestId, string action, string outcome)

        function clearFailure() {
        }
        function requestAction(action) {
            return 0;
        }
    }
    QtObject {
        id: fakeTransientSource

        function resolveTransient(sourceToken, sourceGeneration, sourceRevision) {
            if (sourceToken === "surface-volume" && sourceGeneration === 1 && sourceRevision
                    === 1) {
                return {
                    "detail": "Output volume",
                    "iconName": "audio-volume-high-symbolic",
                    "primary": "Built-in Audio",
                    "progress": 0.64,
                    "value": "64%"
                };
            }
            if (sourceToken === "surface-notification" && sourceGeneration === 2 && sourceRevision
                    === 1) {
                return {
                    "detail": "Review requested",
                    "iconName": "preferences-desktop-notification-symbolic",
                    "primary": "Messages",
                    "value": ""
                };
            }
            if (sourceToken === "surface-workspace" && sourceGeneration === 3 && sourceRevision
                    === 1) {
                return {
                    "detail": "Desktop 2 of 4",
                    "iconName": "preferences-desktop-virtual-symbolic",
                    "primary": "Development",
                    "value": "2 / 4"
                };
            }
            return null;
        }
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
        sessionService: fakeSessionService
        notificationService: fakeNotificationService
        workspaceTransientSource: fakeTransientSource
        brightnessTransientSource: fakeTransientSource
        volumeTransientSource: fakeTransientSource
        notificationTransientSource: fakeTransientSource
    }

    Timer {
        id: retry

        interval: 10
        onTriggered: test.runStep()
    }

    Component.onCompleted: advance()
}

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
    property real modalRevisionBeforeReplacement: 0
    readonly property int maximumRetryAttempts: 500
    readonly property string polkitVisualState: Quickshell.env("NAGI_POLKIT_VISUAL_STATE") ?? ""

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

    function configurePolkitVisualState() {
        const supported = ["hidden-multiple", "single", "visible", "pending", "failure",
                           "cancellation"];
        require(supported.indexOf(polkitVisualState) >= 0,
                "unknown Polkit visual state: " + polkitVisualState);
        fakePolkitController.available = true;
        fakePolkitController.terminal = false;
        fakePolkitController.responseRequired = true;
        fakePolkitController.responseVisible = polkitVisualState === "visible";
        fakePolkitController.submissionPending = polkitVisualState === "pending";
        fakePolkitController.cancellationPending = polkitVisualState === "cancellation";
        fakePolkitController.supplementaryMessage = polkitVisualState === "failure"
                ? "Authentication failed. Check the response and try again." : "";
        fakePolkitController.supplementaryIsError = polkitVisualState === "failure";
        fakePolkitController.identities = polkitVisualState === "hidden-multiple"
                ? [modalIdentity, alternateModalIdentity] : [modalIdentity];
        fakePolkitController.selectedIdentity = modalIdentity;
    }

    function runPolkitVisualStep() {
        if (step === 0) {
            if (!awaitState(host.surfaceToken !== null && coordinator.presentationVisible,
                            "visual surface did not acknowledge Idle")) {
                return;
            }
            configurePolkitVisualState();
            require(coordinator.syncPolkitModal(true, true, 1),
                    "visual Modal snapshot enters");
            step = 1;
            advance();
            return;
        }
        if (!awaitState(coordinator.ownerName === "polkitModal"
                        && coordinator.presentationVisible && host.polkitLoaded,
                        "visual Polkit state did not render")) {
            return;
        }
        console.warn("holding Polkit visual state " + polkitVisualState);
    }

    function runStep() {
        if (polkitVisualState !== "") {
            runPolkitVisualStep();
            return;
        }
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
            if (!awaitState(coordinator.ownerName === "launcher"
                            && coordinator.presentationVisible && host.surfaceFocusable
                            && host.launcherFocused && host.launcherResultCount === 1
                            && host.loadedDashboardRegionCount === 0,
                            "launcher state: owner=" + coordinator.ownerName + " visible="
                            + coordinator.presentationVisible + " focusable="
                            + host.surfaceFocusable + " focused=" + host.launcherFocused
                            + " results=" + host.launcherResultCount + " regions="
                            + host.loadedDashboardRegionCount + " target=" + coordinator.focusTarget
                            + " serial=" + coordinator.focusRequestSerial)) {
                return;
            }
            require(host.launcherSelectedId === "fixture.desktop"
                    && host.surfaceToken === initialSurfaceToken,
                    "launcher selection did not remain on the original surface");
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
            host.reducedMotion = true;
            require(host.requestDeliberateExpansion(),
                    "Modal predecessor opens through deliberate surface intent");
        } else if (step === 20) {
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible
                            && host.dashboardFocused,
                            "Modal predecessor did not become focused")) {
                return;
            }
            require(coordinator.syncPolkitModal(true, true, 1),
                    "controlled Modal snapshot enters");
        } else if (step === 21) {
            if (!awaitState(coordinator.ownerName === "polkitModal"
                            && coordinator.presentationVisible && host.surfaceFocusable
                            && host.polkitLoaded && host.polkitFocused,
                            "Polkit presentation did not load, acknowledge, and focus")) {
                return;
            }
            require(host.surfacePreferredWidth === Theme.size.islandExpandedWidth
                    && host.surfacePreferredHeight === Theme.size.islandExpandedHeight
                    && host.geometryAnimationDuration === 0,
                    "Polkit Modal uses bounded reduced-motion geometry");
            require(host.polkitIdentityCount === 2 && host.polkitResponseFieldVisible,
                    "normalized identities and the live prompt reach the Modal view");
            require(!coordinator.openLauncher(host.surfaceToken)
                    && !coordinator.openSession(host.surfaceToken),
                    "Modal rejects lower-priority Interactive requests");
            fakePolkitController.promptGeneration += 1;
        } else if (step === 22) {
            if (!awaitState(host.polkitResponseFocused,
                            "new prompt generation did not focus the response field")) {
                return;
            }
            fakePolkitController.available = false;
        } else if (step === 23) {
            if (!awaitState(!host.polkitLoaded && !host.polkitResponseFieldVisible,
                            "unavailable controller did not destroy the credential view")) {
                return;
            }
            fakePolkitController.available = true;
        } else if (step === 24) {
            if (!awaitState(host.polkitLoaded && coordinator.presentationVisible
                            && host.surfaceFocusable,
                            "restored controller did not recreate the current Modal view")) {
                return;
            }
            modalRevisionBeforeReplacement = coordinator.revision;
            fakePolkitController.flowGeneration = 2;
            fakePolkitController.promptGeneration += 1;
            require(coordinator.syncPolkitModal(true, true, 2),
                    "serialized flow replacement updates Modal in place");
            require(!coordinator.presentationVisible,
                    "flow replacement waits for its matching presentation acknowledgement");
        } else if (step === 25) {
            if (!awaitState(coordinator.ownerName === "polkitModal"
                            && coordinator.presentationVisible && host.polkitLoaded
                            && host.polkitResponseFocused,
                            "replacement flow did not acknowledge and refocus")) {
                return;
            }
            require(coordinator.revision === modalRevisionBeforeReplacement + 1,
                    "flow replacement increments one Modal revision without a second frame");
            require(coordinator.syncPolkitModal(false, false, 0),
                    "terminal absent snapshot releases Modal");
        } else if (step === 26) {
            if (!awaitState(coordinator.ownerName === "expanded" && coordinator.presentationVisible
                            && host.dashboardFocused && !host.polkitLoaded,
                            "Modal completion did not restore its focused predecessor")) {
                return;
            }
            require(host.cancelDashboard(), "restored predecessor remains cancellable");
        } else if (step === 27) {
            if (!awaitState(coordinator.ownerName === "idle" && coordinator.presentationVisible
                            && !host.surfaceFocusable,
                            "final Modal predecessor cleanup did not restore Idle")) {
                return;
            }
            console.warn("actual island launcher, transient, dashboard, history, session, and Polkit UI tests passed");
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
        id: modalIdentity

        readonly property string id: "unix-user:1000"
        readonly property string string: "unix-user:developer"
        readonly property string displayName: "Developer"
        readonly property bool isGroup: false
    }

    QtObject {
        id: alternateModalIdentity

        readonly property string id: "unix-user:0"
        readonly property string string: "unix-user:root"
        readonly property string displayName: "Administrator"
        readonly property bool isGroup: false
    }

    QtObject {
        id: fakePolkitController

        property bool available: true
        property bool terminal: false
        property bool responseRequired: true
        property bool responseVisible: false
        property bool submissionPending: false
        property bool cancellationPending: false
        property int flowGeneration: 1
        property int promptGeneration: 1
        property int failureGeneration: 0
        property string message: "Authentication is required to change system settings."
        property string actionId: "org.example.settings.modify"
        property string inputPrompt: "Password"
        property string supplementaryMessage: ""
        property bool supplementaryIsError: false
        property string iconName: "object-locked-symbolic"
        property var identities: [modalIdentity, alternateModalIdentity]
        property var selectedIdentity: modalIdentity

        function cancel() {
            cancellationPending = true;
        }
        function selectIdentity(identity) {
            selectedIdentity = identity;
        }
        function submitResponse(response, generation) {
            submissionPending = true;
            responseRequired = false;
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

    QtObject {
        id: fakeApplicationModel

        readonly property bool initialized: true
        readonly property bool available: true
        readonly property bool pinMutationPending: false
        readonly property string pinFailure: "none"
        readonly property var pinIds: []
        readonly property var recencyIds: ["fixture.desktop"]
        readonly property var applications: [{
                "id": "fixture.desktop",
                "name": "Fixture Application",
                "keywords": ["fixture"],
                "icon": "",
                "nameOrder": 0,
                "idOrder": 0
            }]
        readonly property var pinnedApplications: []
        readonly property var recentApplications: applications

        signal launchAccepted(int requestId, string desktopFileId)
        signal launchRejected(int requestId, string category)
        signal pinCommitted(string desktopFileId)
        signal pinRemoved(string desktopFileId)
        signal pinReordered(string desktopFileId)
        signal pinMutationFailed(string category)

        function captureDiscoveryGeneration() {
        }
        function dispatchLaunch(desktopFileId) {
            return 1;
        }
        function movePin(desktopFileId, newIndex) {
            return false;
        }
        function pin(desktopFileId) {
            return true;
        }
        function unpin(desktopFileId) {
            return false;
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
        polkitController: fakePolkitController
        notificationService: fakeNotificationService
        applicationModel: fakeApplicationModel
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

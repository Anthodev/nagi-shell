import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    property real nowMs: 0
    property var token: null
    property int generation: 0
    property bool fakePolkitActive: true
    property bool fakePolkitFlowPresent: true
    property int fakePolkitFlowGeneration: 77

    function attachFreshSurface() {
        if (token !== null) {
            require(coordinator.detachSurface(token, generation), "current surface detaches");
        }
        token = {};
        generation += 1;
        require(coordinator.attachSurface(token, generation), "fresh surface attaches");
        require(coordinator.ownerName === "idle", "fresh surface starts idle");
    }

    function exerciseFreshness(request, owner, freshness) {
        require(request(), owner + " freshness request enters");
        require(coordinator.ownerName === owner, owner + " owns before freshness boundary");
        nowMs += freshness - 1;
        require(coordinator.setHover(generation, false), owner + " pre-boundary dispatch succeeds");
        require(coordinator.ownerName === owner, owner + " remains fresh before boundary");
        nowMs += 1;
        require(coordinator.setHover(generation, false), owner
                + " freshness boundary dispatch succeeds");
        require(coordinator.ownerName === "idle", owner + " expires at freshness boundary");
    }

    function exerciseVisibleHold(request, owner, hold) {
        require(request(), owner + " hold request enters");
        require(coordinator.ownerName === owner, owner + " owns before acknowledgement");
        require(coordinator.acknowledgeVisible(generation, coordinator.ownerEpoch,
                                               coordinator.revision), owner
                + " presentation is acknowledged");
        nowMs += hold - 1;
        require(coordinator.setHover(generation, false), owner
                + " hold pre-boundary dispatch succeeds");
        require(coordinator.ownerName === owner, owner + " remains visible before hold boundary");
        nowMs += 1;
        require(coordinator.setHover(generation, false), owner
                + " hold boundary dispatch succeeds");
        require(coordinator.ownerName === "idle", owner + " releases at hold boundary");
    }

    function syncFakePolkitSnapshot(target) {
        return target.syncPolkitModal(fakePolkitActive, fakePolkitFlowPresent,
                                      fakePolkitFlowGeneration);
    }

    function verifyReloadReattachment() {
        const first = coordinatorFactory.createObject(test);
        require(first !== null, "pre-reload coordinator is created");
        const firstToken = {};
        require(first.attachSurface(firstToken, 1), "pre-reload surface attaches");
        require(first.setHover(1, true), "pre-reload predecessor enters");
        require(syncFakePolkitSnapshot(first), "pre-reload Modal snapshot enters");
        require(first.ownerName === "polkitModal", "pre-reload Modal owns the island");
        first.destroy();

        const replacement = coordinatorFactory.createObject(test);
        require(replacement !== null, "replacement coordinator is created");
        require(syncFakePolkitSnapshot(replacement),
                "replacement coordinator reads the existing snapshot");
        const replacementToken = {};
        require(replacement.attachSurface(replacementToken, 1),
                "replacement surface attaches after snapshot synchronization");
        require(replacement.ownerName === "polkitModal" && replacement.restorationDepth === 0,
                "reload reattaches Modal without old predecessor state");
        require(replacement.acknowledgeVisible(1, replacement.ownerEpoch, replacement.revision),
                "reattached Modal presentation is acknowledged");
        require(replacement.focusTarget === replacement.focusPolkitModal
                && replacement.focusRequestSerial === 1,
                "reattached Modal retains a valid focus path");

        fakePolkitActive = false;
        fakePolkitFlowPresent = false;
        fakePolkitFlowGeneration = 0;
        require(syncFakePolkitSnapshot(replacement),
                "registration loss publishes an absent authoritative snapshot");
        require(replacement.ownerName === "idle",
                "registration loss restores only the replacement baseline");
        replacement.destroy();
    }

    function verifyExpandedIntents() {
        attachFreshSurface();
        require(!coordinator.setHover(generation + 1, true), "stale hover generation is rejected");
        require(coordinator.setHover(generation, true), "current hover expands the baseline");
        require(coordinator.ownerName === "expanded" && coordinator.focusTarget
                === coordinator.focusNone, "hover expansion never requests keyboard focus");
        const hoverFocusSerial = coordinator.focusRequestSerial;
        require(coordinator.acknowledgeVisible(generation, coordinator.ownerEpoch,
                                               coordinator.revision),
                "hover dashboard presentation is acknowledged");
        require(coordinator.focusRequestSerial === hoverFocusSerial,
                "hover acknowledgement does not issue focus");

        require(coordinator.setExplicitExpanded(generation, true),
                "deliberate intent joins the expanded baseline");
        require(coordinator.ownerName === "expanded" && coordinator.focusTarget
                === coordinator.focusExpandedDashboard && coordinator.focusRequestSerial
                === hoverFocusSerial + 1,
                "visible deliberate expansion receives dashboard focus intent");
        require(coordinator.setExplicitExpanded(generation, false),
                "deliberate intent can clear independently");
        require(coordinator.ownerName === "expanded" && coordinator.hoverIntent
                && coordinator.focusTarget === coordinator.focusNone,
                "current hover keeps Expanded visible without retaining focus");
        require(coordinator.setHover(generation, false), "pointer exit clears hover intent");
        require(coordinator.ownerName === "idle", "clearing both intents restores Idle");

        const deliberateFocusSerial = coordinator.focusRequestSerial;
        require(coordinator.openDashboard(null),
                "surface-independent dashboard activation enters from Idle");
        require(coordinator.focusRequestSerial === deliberateFocusSerial && coordinator.focusTarget
                === coordinator.focusExpandedDashboard,
                "focus waits for the deliberate dashboard presentation");
        require(coordinator.acknowledgeVisible(generation, coordinator.ownerEpoch,
                                               coordinator.revision),
                "deliberate dashboard presentation is acknowledged");
        require(coordinator.focusRequestSerial === deliberateFocusSerial + 1,
                "matching visibility acknowledgement issues focus once");
        require(coordinator.setExplicitExpanded(generation, false),
                "keyboard cancellation clears deliberate intent");
        require(coordinator.ownerName === "idle" && coordinator.focusTarget
                === coordinator.focusNone, "keyboard cancellation restores Idle focus policy");
    }

    function verifyExternalReset() {
        attachFreshSurface();
        require(coordinator.setHover(generation, true)
                && coordinator.setExplicitExpanded(generation, true),
                "external-reset baseline expands with focus intent");
        require(coordinator.openTray(token), "external-reset tray interaction opens");
        require(coordinator.requestNotification("external-reset-notification", 1, 1, token),
                "external-reset scenario retains pending transient work");
        require(coordinator.resetToIdle(token), "matching external reset is accepted");
        require(coordinator.ownerName === "idle" && !coordinator.hoverIntent
                && !coordinator.explicitExpandedIntent && coordinator.pendingTransientCount === 0
                && coordinator.restorationDepth === 0 && coordinator.focusTarget
                === coordinator.focusNone,
                "external reset clears every non-modal owner, intent, pending item, and predecessor");
        require(!coordinator.resetToIdle({}), "foreign surface reset is rejected");

        require(coordinator.syncPolkitModal(true, true, 90), "Modal opens for reset guard");
        require(!coordinator.resetToIdle(token) && coordinator.ownerName === "polkitModal",
                "external reset cannot abandon Modal ownership");
        require(coordinator.syncPolkitModal(false, false, 0),
                "Modal reset guard releases through its authoritative snapshot");
        require(coordinator.ownerName === "idle", "Modal cleanup returns to Idle");
    }

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function run() {
        attachFreshSurface();
        require(coordinator.requestWorkspace("workspace", 1, 1, token),
                "workspace request is accepted");
        require(coordinator.ownerName === "workspace", "workspace owns idle");
        require(coordinator.requestBrightness("brightness", 1, 1, token),
                "brightness request is accepted");
        require(coordinator.ownerName === "brightness",
                "higher transient preempts lower transient");
        require(coordinator.requestWorkspace("other-workspace", 1, 1, token),
                "lower transient enters mailbox");
        require(coordinator.ownerName === "brightness",
                "lower transient cannot replace higher transient");
        require(coordinator.setHover(generation, true), "expanded baseline is accepted");
        require(coordinator.ownerName === "expanded", "expanded preempts transients");
        require(coordinator.requestNotification("notification", 1, 1, token),
                "notification is held while expanded");
        require(coordinator.ownerName === "expanded", "transient cannot replace expanded");
        require(coordinator.openLauncher(token), "local launcher intent is accepted");
        require(coordinator.ownerName === "launcher", "launcher preempts expanded");
        require(coordinator.openSession(token), "session intent is accepted");
        const suspendedSessionEpoch = coordinator.ownerEpoch;
        require(coordinator.ownerName === "session", "session preempts launcher");
        require(coordinator.syncPolkitModal(true, true, 1), "Polkit snapshot is accepted");
        require(coordinator.ownerName === "polkitModal", "Modal preempts session");
        require(coordinator.restorationDepth <= coordinator.maximumRestorationDepth,
                "restoration chain remains bounded");
        require(coordinator.completeInteractive(suspendedSessionEpoch),
                "matching completion invalidates a Modal-suspended session");
        require(coordinator.ownerName === "polkitModal",
                "suspended completion cannot close the current Modal");
        require(!coordinator.completeInteractive(suspendedSessionEpoch),
                "repeated suspended completion is stale");
        require(coordinator.syncPolkitModal(false, false, 0), "Polkit cleanup is accepted");
        require(coordinator.ownerName === "launcher",
                "Modal cleanup skips the completed session and restores its predecessor");
        require(coordinator.cancelInteractive(coordinator.ownerEpoch), "launcher cancels");
        require(coordinator.ownerName === "expanded", "launcher restores expanded");

        attachFreshSurface();
        require(coordinator.setHover(generation, true), "expanded predecessor is set");
        require(coordinator.openLauncher(token), "dashboard launcher intent opens");
        const launcherEpoch = coordinator.ownerEpoch;
        const launcherRevision = coordinator.revision;
        require(coordinator.acknowledgeVisible(generation, launcherEpoch, launcherRevision),
                "matching launcher presentation is acknowledged");
        const firstFocus = coordinator.focusRequestSerial;
        require(firstFocus > 0 && coordinator.focusTarget === coordinator.focusLauncherSearch,
                "visible launcher requests search focus");
        require(coordinator.openLauncher(null), "global launcher intent is idempotently accepted");
        require(coordinator.ownerEpoch === launcherEpoch,
                "repeated launcher preserves owner epoch");
        require(coordinator.focusRequestSerial === firstFocus + 1,
                "repeated visible launcher requests search focus again");
        require(!coordinator.completeInteractive(launcherEpoch - 1),
                "stale completion is rejected");
        require(coordinator.cancelInteractive(launcherEpoch), "Escape cancels current launcher");
        require(coordinator.ownerName === "expanded", "Escape restores the predecessor");
        require(coordinator.openTray(null),
                "global tray intent opens through the attached surface");
        require(coordinator.openTray(token), "visible dashboard tray intent renews focus");
        const trayEpoch = coordinator.ownerEpoch;
        require(coordinator.ownerName === "tray", "tray owns the island as an Interactive task");
        require(coordinator.acknowledgeVisible(generation, trayEpoch, coordinator.revision),
                "matching tray presentation is acknowledged");
        const trayFocus = coordinator.focusRequestSerial;
        require(trayFocus > 0 && coordinator.focusTarget === coordinator.focusTray,
                "visible tray requests item focus");
        require(coordinator.openTray(token) && coordinator.ownerEpoch === trayEpoch
                && coordinator.focusRequestSerial === trayFocus + 1,
                "repeated tray intent preserves its epoch and renews focus");
        require(!coordinator.openHistory(token),
                "equal-rank history cannot replace active tray");
        require(coordinator.cancelInteractive(trayEpoch),
                "tray Back accepts its current owner epoch");
        require(coordinator.ownerName === "expanded",
                "tray Back atomically restores its dashboard predecessor");

        require(coordinator.openAudio(null),
                "global audio intent opens through the attached surface");
        require(coordinator.openAudio(token), "visible dashboard audio intent renews focus");
        const audioEpoch = coordinator.ownerEpoch;
        require(coordinator.ownerName === "audio"
                && coordinator.focusTarget === coordinator.focusAudio,
                "audio mirrors tray ownership and focus rank");
        require(coordinator.acknowledgeVisible(generation, audioEpoch, coordinator.revision),
                "matching audio presentation is acknowledged");
        const audioFocus = coordinator.focusRequestSerial;
        require(coordinator.openAudio(token) && coordinator.ownerEpoch === audioEpoch
                && coordinator.focusRequestSerial === audioFocus + 1,
                "repeated audio intent preserves its epoch and renews focus");
        require(!coordinator.openTray(token),
                "equal-rank tray cannot replace active audio");
        const audioRevisionBeforeModal = coordinator.revision;
        require(coordinator.syncPolkitModal(true, true, 2),
                "Modal can suspend the active audio task");
        require(!coordinator.openAudio(token), "audio is rejected during Modal");
        require(coordinator.syncPolkitModal(false, false, 0),
                "Modal cleanup restores the audio task");
        require(coordinator.ownerName === "audio" && coordinator.ownerEpoch === audioEpoch
                && coordinator.revision > audioRevisionBeforeModal,
                "audio restoration preserves epoch and advances revision");
        require(coordinator.cancelInteractive(audioEpoch),
                "audio Back accepts its restored owner epoch");
        require(coordinator.ownerName === "expanded",
                "audio Back atomically restores its dashboard predecessor");


        require(coordinator.openHistory(null),
                "global history intent opens through the attached surface");
        require(coordinator.openHistory(token), "visible dashboard history intent renews focus");
        const historyEpoch = coordinator.ownerEpoch;
        require(coordinator.ownerName === "history",
                "history owns the island as an Interactive task");
        require(coordinator.acknowledgeVisible(generation, historyEpoch, coordinator.revision),
                "matching history presentation is acknowledged");
        const historyFocus = coordinator.focusRequestSerial;
        require(historyFocus > 0 && coordinator.focusTarget === coordinator.focusNotificationHistory,
                "visible history requests list focus");
        require(coordinator.openHistory(token) && coordinator.ownerEpoch === historyEpoch
                && coordinator.focusRequestSerial === historyFocus + 1,
                "repeated history intent preserves its epoch and renews focus");
        require(!coordinator.openLauncher(token),
                "equal-rank launcher cannot replace active history");

        require(coordinator.openSession(null), "global session intent preempts visible history");
        const sessionEpoch = coordinator.ownerEpoch;
        require(coordinator.acknowledgeVisible(generation, sessionEpoch, coordinator.revision),
                "matching session presentation is acknowledged");
        require(coordinator.focusTarget === coordinator.focusSessionActions,
                "visible session interaction requests action-grid focus");
        const sessionRevisionBeforeModal = coordinator.revision;
        require(coordinator.syncPolkitModal(true, true, 2),
                "Modal can suspend the active session task");
        require(coordinator.syncPolkitModal(false, false, 0),
                "Modal cleanup restores an unfinished session task");
        require(coordinator.ownerName === "session" && coordinator.ownerEpoch === sessionEpoch
                && coordinator.revision > sessionRevisionBeforeModal,
                "restoration preserves the session task epoch with a fresh presentation revision");
        require(coordinator.acknowledgeVisible(generation, sessionEpoch, coordinator.revision),
                "restored session presentation is acknowledged");
        require(!coordinator.cancelInteractive(sessionEpoch + 100),
                "stale session cancellation is rejected");
        require(coordinator.cancelInteractive(sessionEpoch),
                "current session cancellation is accepted");
        require(coordinator.ownerName === "history" && coordinator.ownerEpoch === historyEpoch,
                "session cancellation restores the suspended history task");
        require(coordinator.acknowledgeVisible(generation, historyEpoch, coordinator.revision),
                "restored history presentation is acknowledged");
        require(coordinator.cancelInteractive(historyEpoch),
                "history Back accepts its current owner epoch");
        require(coordinator.ownerName === "expanded",
                "history Back atomically restores its dashboard predecessor");
        require(coordinator.openLauncher(null), "shortcut launcher intent opens");
        require(coordinator.ownerName === "launcher",
                "global and local origins share launcher behavior");
        require(coordinator.cancelInteractive(coordinator.ownerEpoch), "global launcher completes");
        require(coordinator.ownerName === "expanded", "global launcher restores identically");

        attachFreshSurface();
        require(coordinator.syncPolkitModal(true, true, 10), "Modal enters from current snapshot");
        const modalEpoch = coordinator.ownerEpoch;
        const modalRevision = coordinator.revision;
        require(coordinator.acknowledgeVisible(generation, modalEpoch, modalRevision),
                "matching Modal presentation is acknowledged");
        const modalFocus = coordinator.focusRequestSerial;
        require(!coordinator.openLauncher(null), "launcher is rejected during Modal");
        require(!coordinator.openHistory(token), "history is rejected during Modal");
        require(!coordinator.openTray(token), "tray is rejected during Modal");
        require(!coordinator.openAudio(token), "audio is rejected during Modal");
        require(!coordinator.openSession(token), "session is rejected during Modal");
        require(coordinator.ownerName === "polkitModal" && coordinator.focusRequestSerial
                === modalFocus, "lower requests cannot steal Modal ownership or focus");
        require(coordinator.requestNotification("held", 1, 1, null),
                "fresh notification is held during Modal");
        require(coordinator.pendingTransientCount === 1,
                "held transient occupies one bounded slot");
        require(coordinator.syncPolkitModal(true, true, 11),
                "serialized flow replacement is accepted");
        require(coordinator.ownerName === "polkitModal" && coordinator.ownerEpoch === modalEpoch
                && coordinator.revision === modalRevision + 1,
                "flow replacement updates Modal in place");
        require(coordinator.syncPolkitModal(false, true, 11),
                "inactive agent with flow stays Modal");
        require(coordinator.ownerName === "polkitModal",
                "flow presence prevents early restoration");
        nowMs += 6000;
        require(coordinator.syncPolkitModal(false, false, 0), "full cleanup releases Modal");
        require(coordinator.ownerName === "idle",
                "expired held work and rejected launcher do not replay");

        require(coordinator.syncPolkitModal(true, true, 12), "another Modal enters");
        const oldModalEpoch = coordinator.ownerEpoch;
        require(coordinator.detachSurface(token, generation), "surface loss detaches Modal host");
        token = {};
        generation += 1;
        require(coordinator.attachSurface(token, generation), "replacement surface attaches");
        require(coordinator.ownerName === "polkitModal" && coordinator.ownerEpoch !== oldModalEpoch,
                "existing flow reattaches as a new Modal owner");
        require(coordinator.restorationDepth === 0, "surface loss drops old restoration state");
        require(coordinator.syncPolkitModal(false, false, 0), "reattached Modal cleans up");
        require(coordinator.ownerName === "idle", "reattached Modal restores new baseline only");

        attachFreshSurface();
        require(coordinator.requestNotification("timeout", 1, 1, token), "notification enters");
        const notificationEpoch = coordinator.ownerEpoch;
        require(coordinator.acknowledgeVisible(generation, notificationEpoch, coordinator.revision),
                "notification presentation is acknowledged");
        nowMs += 2999;
        require(coordinator.setHover(generation, false), "dispatch processes elapsed time");
        require(coordinator.ownerName === "notification", "hold remains before exact boundary");
        nowMs += 1;
        require(coordinator.setHover(generation, false), "exact hold boundary is processed");
        require(coordinator.ownerName === "idle", "visible hold starts at acknowledgement");
        require(!coordinator.acknowledgeVisible(generation, notificationEpoch, 1),
                "stale visible acknowledgement is ignored");

        require(coordinator.requestVolume("visible-coalescing", 1, 1, token),
                "visible value event enters");
        const coalescedEpoch = coordinator.ownerEpoch;
        const supersededRevision = coordinator.revision;
        require(coordinator.requestVolume("visible-coalescing", 1, 2, token),
                "superseding value event coalesces in place");
        require(coordinator.ownerEpoch === coalescedEpoch && coordinator.revision
                === supersededRevision + 1,
                "coalescing preserves owner and advances content revision");
        require(coordinator.ownerSourceGeneration === 1 && coordinator.ownerSourceRevision === 2,
                "coalescing exposes the exact latest source version");
        require(!coordinator.requestVolume("visible-coalescing", 1, 2, token),
                "duplicate source revision cannot restart the visible hold");
        require(!coordinator.requestVolume("visible-coalescing", 1, 1, token),
                "older source revision is rejected");
        require(coordinator.requestVolume("visible-coalescing", 2, 1, token),
                "a new source generation receives an independent pending slot");
        require(coordinator.pendingTransientCount === 1,
                "generation-scoped coalescing does not merge distinct sources");
        require(coordinator.invalidateTransient("visible-coalescing", 2)
                && coordinator.pendingTransientCount === 0,
                "source invalidation removes matching pending work");
        require(!coordinator.acknowledgeVisible(generation, coalescedEpoch, supersededRevision),
                "superseded presentation acknowledgement is rejected");
        require(coordinator.acknowledgeVisible(generation, coalescedEpoch, coordinator.revision),
                "current coalesced presentation is acknowledged");
        nowMs += 1800;
        require(coordinator.setHover(generation, false), "coalesced hold boundary is processed");
        require(coordinator.ownerName === "idle", "coalesced value releases once");

        require(!coordinator.requestNotification("x".repeat(129), 1, 1, token),
                "oversized source token is rejected");
        require(!coordinator.requestNotification({}, 1, 1, token),
                "object source token is rejected");
        require(!coordinator.requestNotification("bounded-version",
                                                 coordinator.maximumSourceVersion + 1, 1, token),
                "oversized source generation is rejected");
        require(!coordinator.requestNotification("bounded-version", 1,
                                                 coordinator.maximumSourceVersion + 1, token),
                "oversized source revision is rejected");
        require(!coordinator.invalidateTransient("bounded-version",
                                                 coordinator.maximumSourceVersion + 1),
                "oversized invalidation generation is rejected");

        exerciseVisibleHold(() => coordinator.requestVolume("volume-hold", 1, 1, token), "volume",
        1800);
        exerciseVisibleHold(() => coordinator.requestBrightness("brightness-hold", 1, 1, token),
        "brightness", 1800);
        exerciseVisibleHold(() => coordinator.requestWorkspace("workspace-hold", 1, 1, token),
        "workspace", 1200);

        require(coordinator.requestWorkspace("freshness", 1, 1, token),
                "workspace enters without acknowledgement");
        nowMs += 2000;
        require(coordinator.setHover(generation, false), "freshness boundary is processed");
        require(coordinator.ownerName === "idle",
                "freshness expires even before visibility acknowledgement");

        exerciseFreshness(() => coordinator.requestBrightness("brightness-freshness", 1, 1, token),
        "brightness", 3000);
        exerciseFreshness(() => coordinator.requestVolume("volume-freshness", 1, 1, token), "volume",
        3000);
        exerciseFreshness(() => coordinator.requestNotification("notification-freshness", 1, 1,
                                                                token), "notification", 6000);

        require(coordinator.requestNotification("remaining-hold", 1, 1, token),
                "notification enters for hold resumption");
        require(coordinator.acknowledgeVisible(generation, coordinator.ownerEpoch,
                                               coordinator.revision),
                "notification hold starts after visibility");
        nowMs += 500;
        require(coordinator.setHover(generation, true), "Expanded preempts visible notification");
        require(coordinator.ownerName === "expanded", "Expanded owns during preemption");
        require(coordinator.setHover(generation, false), "Expanded releases notification");
        require(coordinator.ownerName === "notification", "fresh predecessor is restored");
        require(coordinator.acknowledgeVisible(generation, coordinator.ownerEpoch,
                                               coordinator.revision),
                "restored notification is acknowledged");
        nowMs += 2499;
        require(coordinator.setHover(generation, false),
                "remaining hold pre-boundary is processed");
        require(coordinator.ownerName === "notification",
                "restored notification keeps only its remaining hold");
        nowMs += 1;
        require(coordinator.setHover(generation, false), "remaining hold boundary is processed");
        require(coordinator.ownerName === "idle",
                "remaining hold does not restart from full duration");
        require(coordinator.requestVolume("invalidation", 7, 1, token),
                "value source enters for invalidation");
        require(coordinator.requestNotification("invalidation-notification", 8, 1, token),
                "higher transient suspends the value source");
        require(coordinator.ownerName === "notification" && coordinator.restorationDepth === 1,
                "strict transient preemption captures one predecessor");
        require(!coordinator.invalidateTransient("invalidation", 6),
                "stale source generation cannot remove a live predecessor");
        require(coordinator.invalidateTransient("invalidation-notification", 8),
                "current source invalidation is accepted");
        require(coordinator.ownerName === "volume" && coordinator.ownerSourceGeneration === 7,
                "current invalidation atomically restores the relevant predecessor");
        require(coordinator.invalidateTransient("invalidation", 7) && coordinator.ownerName
                === "idle", "restored source invalidation removes it without stale content");

        require(coordinator.syncPolkitModal(true, true, 20), "Modal opens for mailbox test");
        require(coordinator.requestWorkspace("pending-invalidation", 9, 1, null),
                "Modal admits a pending source for invalidation");
        require(coordinator.invalidateTransient("pending-invalidation", 9)
                && coordinator.pendingTransientCount === 0,
                "source invalidation removes matching Modal-held work");
        for (let index = 1; index <= 8; index += 1) {
            require(coordinator.requestNotification("notification-" + index, 1, 1, null),
                    "mailbox accepts bounded notification " + index);
        }
        require(coordinator.pendingTransientCount === 8, "mailbox reaches its fixed capacity");
        require(coordinator.requestNotification("notification-4", 1, 2, null),
                "coalesced update is accepted");
        require(coordinator.pendingTransientCount === 8, "coalescing retains admission slot");
        require(!coordinator.requestWorkspace("overflow-low", 1, 1, null),
                "lower-rank overflow is rejected");
        require(coordinator.pendingTransientCount === 8, "rejected overflow does not grow mailbox");
        require(coordinator.requestNotification("notification-9", 1, 1, null),
                "equal-rank overflow evicts oldest lowest-rank slot");
        require(coordinator.pendingTransientCount === 8, "accepted overflow remains bounded");
        require(coordinator.syncPolkitModal(false, false, 0), "mailbox Modal releases");
        require(coordinator.ownerName === "notification" && coordinator.ownerSourceToken
                === "notification-2",
                "highest-rank oldest remaining transient is selected deterministically");


        verifyExpandedIntents();
        verifyExternalReset();

        verifyReloadReattachment();

        console.log("island state coordinator tests passed");
        Qt.exit(0);
    }

    Component {
        id: coordinatorFactory

        IslandStateCoordinator {}
    }

    IslandStateCoordinator {
        id: coordinator

        monotonicNow: () => test.nowMs
    }


    Component.onCompleted: Qt.callLater(test.run)
}

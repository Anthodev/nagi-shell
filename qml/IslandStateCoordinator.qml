import Quickshell
import QtQuick

Scope {
    id: root

    readonly property int maximumPendingTransients: 8
    readonly property int maximumRestorationDepth: 8

    readonly property int ownerNone: 0
    readonly property int ownerIdle: 1
    readonly property int ownerWorkspace: 2
    readonly property int ownerBrightness: 3
    readonly property int ownerVolume: 4
    readonly property int ownerNotification: 5
    readonly property int ownerExpanded: 6
    readonly property int ownerLauncher: 7
    readonly property int ownerSession: 8
    readonly property int ownerPolkitModal: 9

    readonly property int focusNone: 0
    readonly property int focusLauncherSearch: 1
    readonly property int focusPolkitModal: 2
    readonly property int focusExpandedDashboard: 3

    readonly property int surfaceGeneration: reducer.surfaceGeneration
    readonly property var surfaceToken: reducer.surfaceToken
    readonly property int ownerKind: reducer.ownerKind
    readonly property string ownerName: reducer.ownerName(reducer.ownerKind)
    readonly property int ownerRank: reducer.ownerRank
    readonly property real ownerEpoch: reducer.ownerEpoch
    readonly property real revision: reducer.revision
    readonly property var ownerSourceToken: reducer.ownerSourceToken
    readonly property bool presentationVisible: reducer.presentationVisible
    readonly property int focusTarget: reducer.focusTarget
    readonly property real focusRequestSerial: reducer.focusRequestSerial
    readonly property bool hoverIntent: reducer.hoverIntent
    readonly property bool explicitExpandedIntent: reducer.explicitExpandedIntent
    readonly property int pendingTransientCount: reducer.pending.length
    readonly property int restorationDepth: reducer.restoration.length
    readonly property bool modalPresent: reducer.modalPresent
    readonly property int modalFlowGeneration: reducer.modalFlowGeneration

    // Tests may inject a monotonic millisecond source. Production uses Quickshell's
    // QElapsedTimer-backed clock and one relative one-shot scheduler.
    property var monotonicNow: null

    function acknowledgeVisible(generation, epoch, contentRevision) {
        return reducer.acknowledgeVisible(generation, epoch, contentRevision);
    }

    function attachSurface(token, generation) {
        return reducer.attachSurface(token, generation);
    }

    function cancelInteractive(epoch) {
        return reducer.finishInteractive(epoch);
    }

    function completeInteractive(epoch) {
        return reducer.finishInteractive(epoch);
    }

    function detachSurface(token, generation) {
        return reducer.detachSurface(token, generation);
    }

    function openLauncher(initiatingSurfaceToken) {
        return reducer.openLauncher(initiatingSurfaceToken);
    }

    function openSession(initiatingSurfaceToken) {
        return reducer.openSession(initiatingSurfaceToken);
    }

    function requestBrightness(sourceToken, initiatingSurfaceToken) {
        return reducer.requestTransient(root.ownerBrightness, sourceToken, initiatingSurfaceToken);
    }

    function requestNotification(sourceToken, initiatingSurfaceToken) {
        return reducer.requestTransient(root.ownerNotification, sourceToken,
                                        initiatingSurfaceToken);
    }

    function requestVolume(sourceToken, initiatingSurfaceToken) {
        return reducer.requestTransient(root.ownerVolume, sourceToken, initiatingSurfaceToken);
    }

    function requestWorkspace(sourceToken, initiatingSurfaceToken) {
        return reducer.requestTransient(root.ownerWorkspace, sourceToken, initiatingSurfaceToken);
    }

    function setExplicitExpanded(generation, expanded) {
        return reducer.setExplicitExpanded(generation, expanded);
    }

    function setHover(generation, hovered) {
        return reducer.setHover(generation, hovered);
    }

    function syncPolkitModal(isActive, flowPresent, flowGeneration) {
        return reducer.syncPolkitModal(isActive, flowPresent, flowGeneration);
    }

    QtObject {
        id: reducer

        property int surfaceGeneration: 0
        property var surfaceToken: null
        property bool hoverIntent: false
        property bool explicitExpandedIntent: false
        readonly property bool baselineExpanded: hoverIntent || explicitExpandedIntent

        property int ownerKind: root.ownerNone
        property int ownerRank: -1
        property real ownerEpoch: 0
        property real revision: 0
        property var ownerSourceToken: null
        property real ownerAdmission: 0
        property real ownerFreshUntil: -1
        property real ownerHoldDuration: 0
        property real ownerHoldUntil: -1
        property bool presentationVisible: false
        property bool focusPending: false

        property var pending: []
        property var restoration: []
        property real nextAdmission: 0
        property real nextOwnerEpoch: 0

        property bool modalIsActive: false
        property bool modalFlowPresent: false
        property int modalFlowGeneration: 0
        readonly property bool modalPresent: modalIsActive || modalFlowPresent

        property int focusTarget: root.focusNone
        property real focusRequestSerial: 0

        property real lastNow: -1
        property real scheduleSerial: 0
        property int scheduledSurfaceGeneration: 0
        property real scheduledOwnerEpoch: 0
        property real scheduledRevision: 0
        property real armedScheduleSerial: 0

        function acknowledgeVisible(generation, epoch, contentRevision) {
            const now = currentTime();
            expireDue(now);

            if (generation !== surfaceGeneration || epoch !== ownerEpoch || contentRevision
                    !== revision || ownerKind === root.ownerNone) {
                schedule(now);
                return false;
            }

            if (!presentationVisible) {
                presentationVisible = true;
                if (isTransient(ownerKind)) {
                    ownerHoldUntil = now + ownerHoldDuration;
                }
            }

            if (focusPending) {
                focusPending = false;
                focusRequestSerial += 1;
            }

            schedule(now);
            return true;
        }

        function attachSurface(token, generation) {
            if (token === null || token === undefined || !Number.isInteger(generation) || generation
                    <= 0) {
                return false;
            }

            const now = currentTime();
            expireDue(now);

            if (surfaceToken === token && surfaceGeneration === generation) {
                schedule(now);
                return true;
            }

            clearLocalState();
            surfaceToken = token;
            surfaceGeneration = generation;
            enterOwner(baselineExpanded ? root.ownerExpanded : root.ownerIdle, null, null, now);

            if (modalPresent) {
                captureCurrent(now);
                enterOwner(root.ownerPolkitModal, null, null, now);
            }

            schedule(now);
            return true;
        }

        function captureCurrent(now) {
            if (ownerKind === root.ownerNone || ownerKind === root.ownerIdle || ownerKind
                    === root.ownerPolkitModal) {
                return;
            }

            if (restoration.length >= root.maximumRestorationDepth) {
                return;
            }

            if (restoration.length > 0 && restoration[restoration.length - 1].rank >= ownerRank) {
                return;
            }

            let holdRemaining = ownerHoldDuration;
            if (isTransient(ownerKind) && presentationVisible) {
                holdRemaining = Math.max(0, ownerHoldUntil - now);
            }

            const frames = restoration.slice();
            frames.push({
                            "admission": ownerAdmission,
                            "freshUntil": ownerFreshUntil,
                            "holdDuration": holdRemaining,
                            "kind": ownerKind,
                            "rank": ownerRank,
                            "sourceToken": ownerSourceToken,
                            "surfaceGeneration": surfaceGeneration
                        });
            restoration = frames;
        }

        function clearLocalState() {
            scheduler.stop();
            surfaceToken = null;
            surfaceGeneration = 0;
            hoverIntent = false;
            explicitExpandedIntent = false;
            ownerKind = root.ownerNone;
            ownerRank = -1;
            ownerEpoch = 0;
            revision = 0;
            ownerSourceToken = null;
            ownerAdmission = 0;
            ownerFreshUntil = -1;
            ownerHoldDuration = 0;
            ownerHoldUntil = -1;
            presentationVisible = false;
            focusPending = false;
            focusTarget = root.focusNone;
            pending = [];
            restoration = [];
        }

        function currentTime() {
            let value = root.monotonicNow === null ? monotonicClock.elapsed() * 1000 :
                                                     root.monotonicNow();
            if (typeof value !== "number" || !Number.isFinite(value)) {
                value = lastNow < 0 ? 0 : lastNow;
            }
            value = Math.max(0, value);
            if (lastNow >= 0 && value < lastNow) {
                value = lastNow;
            }
            lastNow = value;
            return value;
        }

        function detachSurface(token, generation) {
            if (surfaceToken !== token || surfaceGeneration !== generation) {
                return false;
            }

            clearLocalState();
            return true;
        }

        function enterOwner(kind, sourceToken, record, now) {
            nextOwnerEpoch += 1;
            ownerKind = kind;
            ownerRank = rankFor(kind);
            ownerEpoch = nextOwnerEpoch;
            revision = 1;
            ownerSourceToken = sourceToken;
            ownerAdmission = record === null ? 0 : record.admission;
            ownerFreshUntil = record === null ? -1 : record.freshUntil;
            ownerHoldDuration = record === null ? holdFor(kind) : record.holdDuration;
            ownerHoldUntil = -1;
            presentationVisible = false;
            focusPending = kind === root.ownerLauncher || kind === root.ownerPolkitModal || (kind
                                                                                             === root.ownerExpanded
                                                                                             && explicitExpandedIntent);
            focusTarget = focusFor(kind);
        }

        function expireDue(now) {
            if (surfaceToken === null) {
                return;
            }

            let pendingExpired = false;
            for (let index = 0; index < pending.length; index += 1) {
                if (pending[index].freshUntil <= now) {
                    pendingExpired = true;
                    break;
                }
            }
            if (pendingExpired) {
                const nextPending = [];
                for (let index = 0; index < pending.length; index += 1) {
                    if (pending[index].freshUntil > now) {
                        nextPending.push(pending[index]);
                    }
                }
                pending = nextPending;
            }

            let restorationExpired = false;
            for (let index = 0; index < restoration.length; index += 1) {
                const frame = restoration[index];
                if (isTransient(frame.kind) && frame.freshUntil <= now) {
                    restorationExpired = true;
                    break;
                }
            }
            if (restorationExpired) {
                const nextRestoration = [];
                for (let index = 0; index < restoration.length; index += 1) {
                    const frame = restoration[index];
                    if (!isTransient(frame.kind) || frame.freshUntil > now) {
                        nextRestoration.push(frame);
                    }
                }
                restoration = nextRestoration;
            }

            if (isTransient(ownerKind) && (ownerFreshUntil <= now || (presentationVisible
                                                                      && ownerHoldUntil <= now))) {
                restoreNext(now);
            }
        }

        function finishInteractive(epoch) {
            const now = currentTime();
            expireDue(now);

            if ((ownerKind !== root.ownerLauncher && ownerKind !== root.ownerSession) || ownerEpoch
                    !== epoch) {
                schedule(now);
                return false;
            }

            restoreNext(now);
            schedule(now);
            return true;
        }

        function focusFor(kind) {
            if (kind === root.ownerLauncher) {
                return root.focusLauncherSearch;
            }
            if (kind === root.ownerPolkitModal) {
                return root.focusPolkitModal;
            }
            if (kind === root.ownerExpanded && explicitExpandedIntent) {
                return root.focusExpandedDashboard;
            }
            return root.focusNone;
        }

        function freshnessFor(kind) {
            if (kind === root.ownerNotification) {
                return 6000;
            }
            if (kind === root.ownerVolume || kind === root.ownerBrightness) {
                return 3000;
            }
            if (kind === root.ownerWorkspace) {
                return 2000;
            }
            return 0;
        }

        function holdFor(kind) {
            if (kind === root.ownerNotification) {
                return 3000;
            }
            if (kind === root.ownerVolume || kind === root.ownerBrightness) {
                return 1800;
            }
            if (kind === root.ownerWorkspace) {
                return 1200;
            }
            return 0;
        }

        function isRelevantFrame(frame, now) {
            if (frame.surfaceGeneration !== surfaceGeneration) {
                return false;
            }
            if (isTransient(frame.kind)) {
                return frame.freshUntil > now && frame.holdDuration > 0;
            }
            if (frame.kind === root.ownerExpanded) {
                return baselineExpanded;
            }
            return frame.kind === root.ownerLauncher || frame.kind === root.ownerSession;
        }

        function isSourceToken(token) {
            return (typeof token === "string" && token.length > 0 && token.length <= 128) || (
                        typeof token === "number" && Number.isSafeInteger(token));
        }

        function isTransient(kind) {
            return kind === root.ownerWorkspace || kind === root.ownerBrightness || kind === root.ownerVolume || kind
                    === root.ownerNotification;
        }

        function matchingSurface(initiatingSurfaceToken) {
            if (surfaceToken === null) {
                return false;
            }
            return initiatingSurfaceToken === null || initiatingSurfaceToken === undefined
                    || initiatingSurfaceToken === surfaceToken;
        }

        function nextPendingIndex(now) {
            let selected = -1;
            for (let index = 0; index < pending.length; index += 1) {
                const candidate = pending[index];
                if (candidate.freshUntil <= now) {
                    continue;
                }
                if (selected < 0 || candidate.rank > pending[selected].rank || (candidate.rank
                                                                                === pending[selected].rank
                                                                                && candidate.admission
                                                                                < pending[selected].admission)) {
                    selected = index;
                }
            }
            return selected;
        }

        function openLauncher(initiatingSurfaceToken) {
            const now = currentTime();
            expireDue(now);

            if (!matchingSurface(initiatingSurfaceToken) || ownerKind === root.ownerPolkitModal
                    || ownerRank > 6) {
                schedule(now);
                return false;
            }

            if (ownerKind === root.ownerLauncher) {
                if (presentationVisible) {
                    focusRequestSerial += 1;
                } else {
                    focusPending = true;
                }
                schedule(now);
                return true;
            }

            captureCurrent(now);
            enterOwner(root.ownerLauncher, null, null, now);
            schedule(now);
            return true;
        }

        function openSession(initiatingSurfaceToken) {
            const now = currentTime();
            expireDue(now);

            if (!matchingSurface(initiatingSurfaceToken) || ownerKind === root.ownerPolkitModal) {
                schedule(now);
                return false;
            }

            if (ownerKind === root.ownerSession) {
                schedule(now);
                return true;
            }

            captureCurrent(now);
            enterOwner(root.ownerSession, null, null, now);
            schedule(now);
            return true;
        }

        function ownerName(kind) {
            if (kind === root.ownerIdle) {
                return "idle";
            }
            if (kind === root.ownerWorkspace) {
                return "workspace";
            }
            if (kind === root.ownerBrightness) {
                return "brightness";
            }
            if (kind === root.ownerVolume) {
                return "volume";
            }
            if (kind === root.ownerNotification) {
                return "notification";
            }
            if (kind === root.ownerExpanded) {
                return "expanded";
            }
            if (kind === root.ownerLauncher) {
                return "launcher";
            }
            if (kind === root.ownerSession) {
                return "session";
            }
            if (kind === root.ownerPolkitModal) {
                return "polkitModal";
            }
            return "none";
        }

        function queueTransient(record) {
            let eviction = -1;
            if (pending.length >= root.maximumPendingTransients) {
                eviction = 0;
                for (let index = 1; index < pending.length; index += 1) {
                    if (pending[index].rank < pending[eviction].rank || (pending[index].rank
                                                                         === pending[eviction].rank
                                                                         && pending[index].admission
                                                                         < pending[eviction].admission)) {
                        eviction = index;
                    }
                }

                if (record.rank < pending[eviction].rank) {
                    return false;
                }
            }

            const records = pending.slice();
            if (eviction >= 0) {
                records.splice(eviction, 1);
            }
            records.push(record);
            pending = records;
            return true;
        }

        function rankFor(kind) {
            if (kind === root.ownerIdle) {
                return 0;
            }
            if (kind === root.ownerWorkspace) {
                return 1;
            }
            if (kind === root.ownerBrightness) {
                return 2;
            }
            if (kind === root.ownerVolume) {
                return 3;
            }
            if (kind === root.ownerNotification) {
                return 4;
            }
            if (kind === root.ownerExpanded) {
                return 5;
            }
            if (kind === root.ownerLauncher) {
                return 6;
            }
            if (kind === root.ownerSession) {
                return 7;
            }
            if (kind === root.ownerPolkitModal) {
                return 8;
            }
            return -1;
        }

        function transientRecord(kind, sourceToken, admission, freshUntil) {
            return {
                "admission": admission,
                "freshUntil": freshUntil,
                "holdDuration": holdFor(kind),
                "kind": kind,
                "rank": rankFor(kind),
                "sourceToken": sourceToken,
                "surfaceGeneration": surfaceGeneration
            };
        }

        function requestTransient(kind, sourceToken, initiatingSurfaceToken) {
            const now = currentTime();
            expireDue(now);

            if (!matchingSurface(initiatingSurfaceToken) || !isSourceToken(sourceToken)) {
                schedule(now);
                return false;
            }

            const freshUntil = now + freshnessFor(kind);
            if (ownerKind === kind && ownerSourceToken === sourceToken) {
                revision += 1;
                ownerFreshUntil = freshUntil;
                ownerHoldDuration = holdFor(kind);
                ownerHoldUntil = -1;
                presentationVisible = false;
                schedule(now);
                return true;
            }

            for (let index = restoration.length - 1; index >= 0; index -= 1) {
                if (restoration[index].kind === kind && restoration[index].sourceToken
                        === sourceToken) {
                    const frames = restoration.slice();
                    frames[index] = transientRecord(kind, sourceToken, restoration[index].admission,
                                                    freshUntil);
                    restoration = frames;
                    schedule(now);
                    return true;
                }
            }

            for (let index = 0; index < pending.length; index += 1) {
                if (pending[index].kind === kind && pending[index].sourceToken === sourceToken) {
                    const records = pending.slice();
                    records[index] = transientRecord(kind, sourceToken, pending[index].admission,
                                                     freshUntil);
                    pending = records;
                    schedule(now);
                    return true;
                }
            }

            nextAdmission += 1;
            const record = transientRecord(kind, sourceToken, nextAdmission, freshUntil);

            if (record.rank > ownerRank) {
                captureCurrent(now);
                enterOwner(kind, sourceToken, record, now);
                schedule(now);
                return true;
            }

            const accepted = queueTransient(record);
            schedule(now);
            return accepted;
        }

        function restoreNext(now) {
            let frames = restoration.slice();
            while (frames.length > 0 && !isRelevantFrame(frames[frames.length - 1], now)) {
                frames.pop();
            }
            restoration = frames;

            const predecessor = frames.length === 0 ? null : frames[frames.length - 1];
            const pendingIndex = nextPendingIndex(now);
            const pendingRecord = pendingIndex < 0 ? null : pending[pendingIndex];
            const baselineKind = baselineExpanded ? root.ownerExpanded : root.ownerIdle;
            const baselineRank = rankFor(baselineKind);
            const predecessorRank = predecessor === null ? -1 : predecessor.rank;
            const pendingRank = pendingRecord === null ? -1 : pendingRecord.rank;

            if (predecessor !== null && predecessorRank >= pendingRank && predecessorRank
                    >= baselineRank) {
                frames.pop();
                restoration = frames;
                enterOwner(predecessor.kind, predecessor.sourceToken, predecessor, now);
                return;
            }

            if (pendingRecord !== null && pendingRank > baselineRank) {
                const records = pending.slice();
                records.splice(pendingIndex, 1);
                pending = records;
                enterOwner(pendingRecord.kind, pendingRecord.sourceToken, pendingRecord, now);
                return;
            }

            restoration = [];
            enterOwner(baselineKind, null, null, now);
        }

        function schedule(now) {
            if (surfaceToken === null) {
                scheduler.stop();
                return;
            }

            let deadline = -1;
            if (isTransient(ownerKind)) {
                deadline = ownerFreshUntil;
                if (presentationVisible) {
                    deadline = Math.min(deadline, ownerHoldUntil);
                }
            }

            for (let index = 0; index < pending.length; index += 1) {
                if (deadline < 0 || pending[index].freshUntil < deadline) {
                    deadline = pending[index].freshUntil;
                }
            }
            for (let index = 0; index < restoration.length; index += 1) {
                if (isTransient(restoration[index].kind) && (deadline < 0
                                                             || restoration[index].freshUntil
                                                             < deadline)) {
                    deadline = restoration[index].freshUntil;
                }
            }

            if (deadline < 0) {
                scheduler.stop();
                return;
            }

            scheduleSerial += 1;
            armedScheduleSerial = scheduleSerial;
            scheduledSurfaceGeneration = surfaceGeneration;
            scheduledOwnerEpoch = ownerEpoch;
            scheduledRevision = revision;
            scheduler.interval = Math.max(1, Math.min(2147483647, Math.ceil(deadline - now)));
            scheduler.restart();
        }

        function schedulerTriggered(generation, epoch, contentRevision, serial) {
            if (generation !== surfaceGeneration || epoch !== ownerEpoch || contentRevision
                    !== revision || serial !== armedScheduleSerial) {
                return;
            }

            const now = currentTime();
            expireDue(now);
            schedule(now);
        }

        function setBaselineIntent(generation, value, explicitIntent) {
            const now = currentTime();
            expireDue(now);

            if (typeof value !== "boolean" || generation !== surfaceGeneration || surfaceToken
                    === null) {
                schedule(now);
                return false;
            }

            const wasExpanded = baselineExpanded;
            const wasExplicit = explicitExpandedIntent;
            if (explicitIntent) {
                explicitExpandedIntent = value;
            } else {
                hoverIntent = value;
            }

            if (!wasExpanded && baselineExpanded && ownerRank < rankFor(root.ownerExpanded)) {
                captureCurrent(now);
                enterOwner(root.ownerExpanded, null, null, now);
            } else if (wasExpanded && !baselineExpanded && ownerKind === root.ownerExpanded) {
                restoreNext(now);
            } else if (explicitIntent && value && ownerKind === root.ownerExpanded) {
                focusTarget = root.focusExpandedDashboard;
                if (presentationVisible) {
                    focusRequestSerial += 1;
                } else {
                    focusPending = true;
                }
            } else if (explicitIntent && wasExplicit && !value && ownerKind
                       === root.ownerExpanded) {
                focusPending = false;
                focusTarget = root.focusNone;
            }

            schedule(now);
            return true;
        }

        function setExplicitExpanded(generation, expanded) {
            return setBaselineIntent(generation, expanded, true);
        }

        function setHover(generation, hovered) {
            return setBaselineIntent(generation, hovered, false);
        }

        function syncPolkitModal(isActive, flowPresent, flowGeneration) {
            if (typeof isActive !== "boolean" || typeof flowPresent !== "boolean" ||
                    !Number.isInteger(flowGeneration) || flowGeneration < 0) {
                return false;
            }

            const now = currentTime();
            expireDue(now);
            const wasPresent = modalPresent;
            const snapshotChanged = modalIsActive !== isActive || modalFlowPresent !== flowPresent
                  || modalFlowGeneration !== flowGeneration;

            modalIsActive = isActive;
            modalFlowPresent = flowPresent;
            modalFlowGeneration = flowGeneration;

            if (!wasPresent && modalPresent) {
                if (surfaceToken !== null) {
                    captureCurrent(now);
                    enterOwner(root.ownerPolkitModal, null, null, now);
                }
            } else if (wasPresent && modalPresent && snapshotChanged && ownerKind
                       === root.ownerPolkitModal) {
                revision += 1;
                presentationVisible = false;
                focusPending = true;
            } else if (wasPresent && !modalPresent && ownerKind === root.ownerPolkitModal) {
                restoreNext(now);
            }

            schedule(now);
            return true;
        }
    }

    ElapsedTimer {
        id: monotonicClock
    }

    Timer {
        id: scheduler

        repeat: false
        onTriggered: reducer.schedulerTriggered(reducer.scheduledSurfaceGeneration,
                                                reducer.scheduledOwnerEpoch,
                                                reducer.scheduledRevision,
                                                reducer.armedScheduleSerial)
    }
}

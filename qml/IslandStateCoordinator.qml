import Quickshell
import QtQuick

Scope {
    id: root

    readonly property int maximumPendingTransients: 8
    readonly property int maximumRestorationDepth: 8
    readonly property int maximumSourceVersion: 2147483647

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
    readonly property int ownerHistory: 10
    readonly property int ownerTray: 11
    readonly property int ownerAudio: 12
    readonly property int ownerWeather: 13

    readonly property int focusNone: 0
    readonly property int focusLauncherSearch: 1
    readonly property int focusPolkitModal: 2
    readonly property int focusExpandedDashboard: 3
    readonly property int focusSessionActions: 4
    readonly property int focusNotificationHistory: 5
    readonly property int focusTray: 6
    readonly property int focusAudio: 7
    readonly property int focusWeather: 8

    readonly property int stateSerial: state.serial
    readonly property int surfaceCount: state.surfaces.length
    readonly property int pendingTransientCount: state.transients.length
    readonly property bool modalPresent: state.modalIsActive || state.modalFlowPresent
    readonly property int modalFlowGeneration: state.modalFlowGeneration
    readonly property var modalHostToken: state.modalHostToken
    readonly property var interactiveHostToken: state.interactiveHostToken()
    readonly property bool anyExpanded: state.anyOwner(root.ownerExpanded)

    // IslandSurfaceHost implements routeSurfaceToken(excludedToken) using only
    // live surface tokens, QWindow->QScreen equality, and configured fallback.
    property var surfaceRouter: null
    property var monotonicNow: null
    property string feedbackDuration: "normal"

    function acknowledgeVisible(token, generation, epoch, contentRevision) {
        return state.acknowledgeVisible(token, generation, epoch, contentRevision);
    }

    function attachSurface(token, generation) {
        return state.attachSurface(token, generation);
    }

    function cancelInteractive(epoch) {
        return state.finishInteractive(epoch);
    }

    function completeInteractive(epoch) {
        return state.finishInteractive(epoch);
    }

    function detachSurface(token, generation) {
        return state.detachSurface(token, generation);
    }

    function invalidateTransient(sourceToken, sourceGeneration) {
        return state.invalidateTransient(sourceToken, sourceGeneration);
    }

    function openAudio(initiatingSurfaceToken) {
        return state.openInteractive(root.ownerAudio, initiatingSurfaceToken);
    }

    function openWeather(initiatingSurfaceToken) {
        return state.openInteractive(root.ownerWeather, initiatingSurfaceToken);
    }

    function openDashboard(initiatingSurfaceToken) {
        const token = state.routedToken(initiatingSurfaceToken, null);
        const record = state.recordForToken(token);
        return record !== null && state.setBaselineIntent(record.token, record.generation, true,
                                                          true);
    }

    function openHistory(initiatingSurfaceToken) {
        return state.openInteractive(root.ownerHistory, initiatingSurfaceToken);
    }

    function openLauncher(initiatingSurfaceToken) {
        return state.openInteractive(root.ownerLauncher, initiatingSurfaceToken);
    }

    function openSession(initiatingSurfaceToken) {
        return state.openInteractive(root.ownerSession, initiatingSurfaceToken);
    }

    function openTray(initiatingSurfaceToken) {
        return state.openInteractive(root.ownerTray, initiatingSurfaceToken);
    }

    function ownerNameFor(kind) {
        return state.ownerName(kind);
    }

    function prepareSurfaceDisable(token) {
        return state.prepareSurfaceDisable(token);
    }

    function requestBrightness(sourceToken, sourceGeneration, sourceRevision,
                               initiatingSurfaceToken) {
        return state.requestTransient(root.ownerBrightness, sourceToken, sourceGeneration,
                                      sourceRevision, initiatingSurfaceToken, false);
    }

    function requestNotification(sourceToken, sourceGeneration, sourceRevision,
                                 initiatingSurfaceToken) {
        return state.requestTransient(root.ownerNotification, sourceToken, sourceGeneration,
                                      sourceRevision, initiatingSurfaceToken, true);
    }

    function requestVolume(sourceToken, sourceGeneration, sourceRevision, initiatingSurfaceToken) {
        return state.requestTransient(root.ownerVolume, sourceToken, sourceGeneration,
                                      sourceRevision, initiatingSurfaceToken, true);
    }

    function requestWorkspace(sourceToken, sourceGeneration, sourceRevision,
                              initiatingSurfaceToken) {
        return state.requestTransient(root.ownerWorkspace, sourceToken, sourceGeneration,
                                      sourceRevision, initiatingSurfaceToken, false);
    }

    function resetToIdle(initiatingSurfaceToken) {
        return state.resetToIdle(initiatingSurfaceToken);
    }

    function setExplicitExpanded(token, generation, expanded) {
        return state.setBaselineIntent(token, generation, expanded, true);
    }

    function setHover(token, generation, hovered) {
        return state.setBaselineIntent(token, generation, hovered, false);
    }

    function surfaceSnapshot(token) {
        return state.surfaceSnapshot(token);
    }

    function syncPolkitModal(isActive, flowPresent, flowGeneration) {
        return state.syncPolkitModal(isActive, flowPresent, flowGeneration);
    }

    QtObject {
        id: state

        property var surfaces: []
        property var transients: []
        property real nextAdmission: 0
        property real nextOwnerEpoch: 0
        property real lastNow: -1
        property int serial: 0

        property bool modalIsActive: false
        property bool modalFlowPresent: false
        property int modalFlowGeneration: 0
        property var modalHostToken: null

        function acknowledgeVisible(token, generation, epoch, contentRevision) {
            const now = currentTime();
            expireDue(now);
            const record = recordForToken(token);
            if (record === null || record.generation !== generation || record.owner.epoch !== epoch
                    || record.owner.revision !== contentRevision || record.owner.kind
                    === root.ownerNone) {
                schedule(now);
                return false;
            }

            record.owner.presentationVisible = true;
            if (record.owner.focusPending) {
                record.owner.focusPending = false;
                record.focusRequestSerial += 1;
            }
            if (isTransient(record.owner.kind)) {
                const event = eventForId(record.owner.eventId);
                if (event !== null && event.visibleTokens.indexOf(token) < 0) {
                    event.visibleTokens.push(token);
                    let everyProjectionVisible = true;
                    for (let index = 0; index < surfaces.length; index += 1) {
                        const candidate = surfaces[index];
                        if (candidate.owner.eventId === event.id && event.visibleTokens.indexOf(
                                    candidate.token) < 0) {
                            everyProjectionVisible = false;
                            break;
                        }
                    }
                    if (everyProjectionVisible) {
                        event.holdUntil = now + event.holdDuration;
                    }
                }
            }
            publish();
            schedule(now);
            return true;
        }

        function anyOwner(kind) {
            for (let index = 0; index < surfaces.length; index += 1) {
                if (surfaces[index].owner.kind === kind) {
                    return true;
                }
            }
            return false;
        }

        function attachSurface(token, generation) {
            if (token === null || token === undefined || !Number.isInteger(generation) || generation
                    <= 0 || recordForToken(token) !== null) {
                return false;
            }
            surfaces.push({
                              "explicitExpanded": false,
                              "focusRequestSerial": 0,
                              "generation": generation,
                              "hover": false,
                              "owner": baselineOwner(false),
                              "restoration": [],
                              "token": token
                          });
            if (root.modalPresent && modalHostToken === null) {
                rehomeModal(null, false);
            }
            publish();
            schedule(currentTime());
            return true;
        }

        function baselineKind(record) {
            return record.hover || record.explicitExpanded ? root.ownerExpanded : root.ownerIdle;
        }

        function baselineOwner(expanded) {
            return ownerRecord(expanded ? root.ownerExpanded : root.ownerIdle, null, null, false);
        }

        function captureCurrent(record) {
            if (record.owner.kind === root.ownerNone || record.owner.kind === root.ownerIdle
                    || record.owner.kind === root.ownerPolkitModal || record.restoration.length
                    >= root.maximumRestorationDepth) {
                return;
            }
            const frames = record.restoration.slice();
            frames.push(Object.assign({}, record.owner));
            record.restoration = frames;
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
            const record = recordForToken(token);
            if (record === null || record.generation !== generation) {
                return false;
            }
            const modalLost = modalHostToken === token;
            const interactiveLost = isInteractiveKind(record.owner.kind);
            const interactiveKind = interactiveLost ? record.owner.kind : root.ownerNone;
            const interactiveEpoch = interactiveLost ? record.owner.epoch : 0;
            const next = [];
            for (let index = 0; index < surfaces.length; index += 1) {
                if (surfaces[index] !== record) {
                    next.push(surfaces[index]);
                }
            }
            surfaces = next;
            removeTargetFromEvents(token);
            if (modalLost) {
                modalHostToken = null;
                rehomeModal(token, false);
            } else if (interactiveLost) {
                transferInteractiveAfterLoss(interactiveKind, interactiveEpoch, token);
            }
            publish();
            schedule(currentTime());
            return true;
        }

        function enterOwner(record, kind, event, preservedEpoch, preservedRevision) {
            const epoch = preservedEpoch > 0 ? preservedEpoch : ++nextOwnerEpoch;
            const revision = preservedRevision > 0 ? preservedRevision : 1;
            record.owner = ownerRecord(kind, event, epoch, true);
            record.owner.revision = revision;
        }

        function eventForId(id) {
            if (id === 0) {
                return null;
            }
            for (let index = 0; index < transients.length; index += 1) {
                if (transients[index].id === id) {
                    return transients[index];
                }
            }
            return null;
        }

        function eventMatches(event, kind, sourceToken, sourceGeneration) {
            return event.kind === kind && event.sourceToken === sourceToken
                    && event.sourceGeneration === sourceGeneration;
        }

        function expireDue(now) {
            const expired = [];
            for (let index = 0; index < transients.length; index += 1) {
                const event = transients[index];
                if (event.freshUntil <= now || (event.holdUntil >= 0 && event.holdUntil <= now)) {
                    expired.push(event.id);
                }
            }
            for (let index = 0; index < expired.length; index += 1) {
                removeEvent(expired[index], now);
            }
        }

        function finishInteractive(epoch) {
            const now = currentTime();
            expireDue(now);
            for (let index = 0; index < surfaces.length; index += 1) {
                const record = surfaces[index];
                if (isInteractiveKind(record.owner.kind) && record.owner.epoch === epoch) {
                    restoreNext(record, now);
                    publish();
                    schedule(now);
                    return true;
                }
                for (let frameIndex = record.restoration.length - 1; frameIndex >= 0; frameIndex
                     -= 1) {
                    if (isInteractiveKind(record.restoration[frameIndex].kind)
                            && record.restoration[frameIndex].epoch === epoch) {
                        const frames = record.restoration.slice();
                        frames.splice(frameIndex, 1);
                        record.restoration = frames;
                        publish();
                        schedule(now);
                        return true;
                    }
                }
            }
            schedule(now);
            return false;
        }

        function focusFor(kind) {
            if (kind === root.ownerLauncher) {
                return root.focusLauncherSearch;
            }
            if (kind === root.ownerHistory) {
                return root.focusNotificationHistory;
            }
            if (kind === root.ownerTray) {
                return root.focusTray;
            }
            if (kind === root.ownerAudio) {
                return root.focusAudio;
            }
            if (kind === root.ownerWeather) {
                return root.focusWeather;
            }
            if (kind === root.ownerSession) {
                return root.focusSessionActions;
            }
            if (kind === root.ownerPolkitModal) {
                return root.focusPolkitModal;
            }
            if (kind === root.ownerExpanded) {
                return root.focusExpandedDashboard;
            }
            return root.focusNone;
        }

        function forceIdle(record) {
            record.hover = false;
            record.explicitExpanded = false;
            record.restoration = [];
            record.owner = baselineOwner(false);
        }

        function freshnessFor(kind) {
            if (kind === root.ownerNotification) {
                return 6000;
            }
            if (kind === root.ownerVolume || kind === root.ownerBrightness) {
                return 3000;
            }
            return kind === root.ownerWorkspace ? 2000 : 0;
        }

        function holdFor(kind) {
            let baseline = 0;
            if (kind === root.ownerNotification) {
                baseline = 3000;
            } else if (kind === root.ownerVolume || kind === root.ownerBrightness) {
                baseline = 1800;
            } else if (kind === root.ownerWorkspace) {
                baseline = 1200;
            }
            const factor = root.feedbackDuration === "short" ? 0.65 : root.feedbackDuration
                                                               === "long" ? 1.5 : 1;
            return Math.min(Math.round(baseline * factor), Math.max(0, freshnessFor(kind) - 1));
        }

        function interactiveHostToken() {
            for (let index = 0; index < surfaces.length; index += 1) {
                if (isInteractiveKind(surfaces[index].owner.kind)) {
                    return surfaces[index].token;
                }
            }
            return null;
        }

        function isInteractiveKind(kind) {
            return kind === root.ownerLauncher || kind === root.ownerHistory || kind === root.ownerTray || kind
                    === root.ownerAudio || kind === root.ownerWeather || kind === root.ownerSession;
        }

        function isRelevantFrame(frame, record, now) {
            if (isTransient(frame.kind)) {
                const event = eventForId(frame.eventId);
                return event !== null && event.freshUntil > now && event.targets.indexOf(
                            record.token) >= 0;
            }
            if (frame.kind === root.ownerExpanded) {
                return record.hover || record.explicitExpanded;
            }
            return isInteractiveKind(frame.kind);
        }

        function isSourceToken(token) {
            return (typeof token === "string" && token.length > 0 && token.length <= 128) || (
                        typeof token === "number" && Number.isSafeInteger(token));
        }

        function isSourceVersion(sourceGeneration, sourceRevision) {
            return Number.isInteger(sourceGeneration) && sourceGeneration > 0 && sourceGeneration
                    <= root.maximumSourceVersion && Number.isInteger(sourceRevision)
                    && sourceRevision > 0 && sourceRevision <= root.maximumSourceVersion;
        }

        function invalidateTransient(sourceToken, sourceGeneration) {
            if (!isSourceToken(sourceToken) || !Number.isInteger(sourceGeneration)
                    || sourceGeneration <= 0) {
                return false;
            }
            const now = currentTime();
            const matches = [];
            for (let index = 0; index < transients.length; index += 1) {
                if (transients[index].sourceToken === sourceToken
                        && transients[index].sourceGeneration === sourceGeneration) {
                    matches.push(transients[index].id);
                }
            }
            for (let index = 0; index < matches.length; index += 1) {
                removeEvent(matches[index], now);
            }
            if (matches.length > 0) {
                publish();
            }
            schedule(now);
            return matches.length > 0;
        }

        function isTransient(kind) {
            return kind === root.ownerWorkspace || kind === root.ownerBrightness || kind === root.ownerVolume || kind
                    === root.ownerNotification;
        }

        function openInteractive(kind, initiatingSurfaceToken) {
            if (!isInteractiveKind(kind) || root.modalPresent) {
                return false;
            }
            const token = routedToken(initiatingSurfaceToken, null);
            const target = recordForToken(token);
            if (target === null) {
                return false;
            }

            for (let index = 0; index < surfaces.length; index += 1) {
                const current = surfaces[index];
                if (!isInteractiveKind(current.owner.kind)) {
                    continue;
                }
                if (rankFor(kind) < current.owner.rank) {
                    return false;
                }
                if (current === target && current.owner.kind === kind) {
                    if (current.owner.presentationVisible) {
                        current.focusRequestSerial += 1;
                    } else {
                        current.owner.focusPending = true;
                    }
                    publish();
                    return true;
                }
                forceIdle(current);
            }

            captureCurrent(target);
            enterOwner(target, kind, null, 0, 0);
            publish();
            schedule(currentTime());
            return true;
        }

        function ownerName(kind) {
            if (kind === root.ownerIdle)
                return "idle";
            if (kind === root.ownerWorkspace)
                return "workspace";
            if (kind === root.ownerBrightness)
                return "brightness";
            if (kind === root.ownerVolume)
                return "volume";
            if (kind === root.ownerNotification)
                return "notification";
            if (kind === root.ownerExpanded)
                return "expanded";
            if (kind === root.ownerLauncher)
                return "launcher";
            if (kind === root.ownerSession)
                return "session";
            if (kind === root.ownerHistory)
                return "history";
            if (kind === root.ownerTray)
                return "tray";
            if (kind === root.ownerAudio)
                return "audio";
            if (kind === root.ownerWeather)
                return "weather";
            if (kind === root.ownerPolkitModal)
                return "polkitModal";
            return "none";
        }

        function ownerRecord(kind, event, epoch, focusPending) {
            return {
                "epoch": epoch === null || epoch === undefined ? 0 : epoch,
                "eventId": event === null ? 0 : event.id,
                "focusPending": focusPending === true && (isInteractiveKind(kind) || kind
                                                          === root.ownerPolkitModal || kind
                                                          === root.ownerExpanded),
                "focusTarget": focusFor(kind),
                "kind": kind,
                "presentationVisible": false,
                "rank": rankFor(kind),
                "revision": 1,
                "sourceGeneration": event === null ? 0 : event.sourceGeneration,
                "sourceRevision": event === null ? 0 : event.sourceRevision,
                "sourceToken": event === null ? null : event.sourceToken
            };
        }

        function prepareSurfaceDisable(token) {
            const record = recordForToken(token);
            if (record === null || modalHostToken === token) {
                return false;
            }
            if (!isInteractiveKind(record.owner.kind)) {
                return true;
            }
            const replacementToken = routedToken(null, token);
            const replacement = recordForToken(replacementToken);
            if (replacement === null) {
                return false;
            }
            const kind = record.owner.kind;
            const epoch = record.owner.epoch;
            const revision = record.owner.revision;
            forceIdle(record);
            captureCurrent(replacement);
            enterOwner(replacement, kind, null, epoch, revision + 1);
            publish();
            return true;
        }

        function projectEvent(event, now) {
            for (let index = 0; index < event.targets.length; index += 1) {
                const record = recordForToken(event.targets[index]);
                if (record === null || record.owner.eventId === event.id) {
                    continue;
                }
                if (event.rank > record.owner.rank) {
                    captureCurrent(record);
                    enterOwner(record, event.kind, event, 0, 0);
                }
            }
        }

        function publish() {
            surfaces = surfaces.slice();
            transients = transients.slice();
            serial += 1;
        }

        function rankFor(kind) {
            if (kind === root.ownerIdle)
                return 0;
            if (kind === root.ownerWorkspace)
                return 1;
            if (kind === root.ownerBrightness)
                return 2;
            if (kind === root.ownerVolume)
                return 3;
            if (kind === root.ownerNotification)
                return 4;
            if (kind === root.ownerExpanded)
                return 5;
            if (kind === root.ownerLauncher || kind === root.ownerHistory || kind === root.ownerTray
                    || kind === root.ownerAudio || kind === root.ownerWeather)
                return 6;
            if (kind === root.ownerSession)
                return 7;
            if (kind === root.ownerPolkitModal)
                return 8;
            return -1;
        }

        function recordForToken(token) {
            if (token === null || token === undefined) {
                return null;
            }
            for (let index = 0; index < surfaces.length; index += 1) {
                if (surfaces[index].token === token) {
                    return surfaces[index];
                }
            }
            return null;
        }

        function rehomeModal(excludedToken, capturePredecessor) {
            if (!(modalIsActive || modalFlowPresent) || modalHostToken !== null) {
                return;
            }
            const token = routedToken(null, excludedToken);
            const record = recordForToken(token);
            if (record === null) {
                return;
            }
            if (capturePredecessor) {
                for (let index = 0; index < surfaces.length; index += 1) {
                    const current = surfaces[index];
                    if (current !== record && isInteractiveKind(current.owner.kind)) {
                        forceIdle(current);
                    }
                }
            }
            if (capturePredecessor) {
                captureCurrent(record);
            } else {
                forceIdle(record);
            }
            enterOwner(record, root.ownerPolkitModal, null, 0, 0);
            modalHostToken = token;
        }

        function removeEvent(eventId, now) {
            const next = [];
            for (let index = 0; index < transients.length; index += 1) {
                if (transients[index].id !== eventId) {
                    next.push(transients[index]);
                }
            }
            transients = next;
            for (let index = 0; index < surfaces.length; index += 1) {
                const record = surfaces[index];
                const frames = [];
                for (let frameIndex = 0; frameIndex < record.restoration.length; frameIndex += 1) {
                    if (record.restoration[frameIndex].eventId !== eventId) {
                        frames.push(record.restoration[frameIndex]);
                    }
                }
                record.restoration = frames;
                if (record.owner.eventId === eventId) {
                    restoreNext(record, now);
                }
            }
        }

        function removeTargetFromEvents(token) {
            const now = currentTime();
            const emptyEvents = [];
            for (let index = 0; index < transients.length; index += 1) {
                const event = transients[index];
                event.targets = event.targets.filter(candidate => candidate !== token);
                event.visibleTokens = event.visibleTokens.filter(candidate => candidate !== token);
                if (event.targets.length === 0) {
                    emptyEvents.push(event.id);
                }
            }
            for (let index = 0; index < emptyEvents.length; index += 1) {
                removeEvent(emptyEvents[index], now);
            }
        }

        function requestTransient(kind, sourceToken, sourceGeneration, sourceRevision,
                                  initiatingSurfaceToken, broadcast) {
            const now = currentTime();
            expireDue(now);
            if (!isTransient(kind) || !isSourceToken(sourceToken) || !isSourceVersion(
                        sourceGeneration, sourceRevision)) {
                return false;
            }

            let event = null;
            for (let index = 0; index < transients.length; index += 1) {
                if (eventMatches(transients[index], kind, sourceToken, sourceGeneration)) {
                    event = transients[index];
                    break;
                }
            }
            if (event !== null) {
                if (sourceRevision <= event.sourceRevision) {
                    schedule(now);
                    return false;
                }
                event.sourceRevision = sourceRevision;
                event.freshUntil = now + freshnessFor(kind);
                event.holdDuration = holdFor(kind);
                event.holdUntil = -1;
                event.visibleTokens = [];
                for (let index = 0; index < surfaces.length; index += 1) {
                    const record = surfaces[index];
                    if (record.owner.eventId === event.id) {
                        record.owner.revision += 1;
                        record.owner.sourceRevision = sourceRevision;
                        record.owner.presentationVisible = false;
                    }
                }
                projectEvent(event, now);
                publish();
                schedule(now);
                return true;
            }

            let targets = [];
            if (broadcast) {
                for (let index = 0; index < surfaces.length; index += 1) {
                    targets.push(surfaces[index].token);
                }
            } else {
                const token = routedToken(initiatingSurfaceToken, null);
                if (token !== null) {
                    targets.push(token);
                }
            }
            if (targets.length === 0) {
                return false;
            }

            nextAdmission += 1;
            event = {
                "admission": nextAdmission,
                "freshUntil": now + freshnessFor(kind),
                "holdDuration": holdFor(kind),
                "holdUntil": -1,
                "id": nextAdmission,
                "kind": kind,
                "rank": rankFor(kind),
                "sourceGeneration": sourceGeneration,
                "sourceRevision": sourceRevision,
                "sourceToken": sourceToken,
                "targets": targets,
                "visibleTokens": []
            };
            if (transients.length >= root.maximumPendingTransients) {
                let eviction = 0;
                for (let index = 1; index < transients.length; index += 1) {
                    if (transients[index].rank < transients[eviction].rank || (
                                transients[index].rank === transients[eviction].rank
                                && transients[index].admission < transients[eviction].admission)) {
                        eviction = index;
                    }
                }
                if (event.rank < transients[eviction].rank) {
                    return false;
                }
                removeEvent(transients[eviction].id, now);
            }
            transients.push(event);
            projectEvent(event, now);
            publish();
            schedule(now);
            return true;
        }

        function resetToIdle(initiatingSurfaceToken) {
            const record = recordForToken(initiatingSurfaceToken);
            if (record === null || modalHostToken === record.token) {
                return false;
            }
            forceIdle(record);
            publish();
            schedule(currentTime());
            return true;
        }

        function restoreNext(record, now) {
            let predecessor = null;
            while (record.restoration.length > 0) {
                const candidate = record.restoration[record.restoration.length - 1];
                record.restoration = record.restoration.slice(0, -1);
                if (isRelevantFrame(candidate, record, now)) {
                    predecessor = candidate;
                    break;
                }
            }
            let pendingEvent = null;
            for (let index = 0; index < transients.length; index += 1) {
                const candidate = transients[index];
                if (candidate.freshUntil <= now || candidate.targets.indexOf(record.token) < 0
                        || record.owner.eventId === candidate.id) {
                    continue;
                }
                if (pendingEvent === null || candidate.rank > pendingEvent.rank || (candidate.rank
                                                                                    === pendingEvent.rank
                                                                                    && candidate.admission
                                                                                    < pendingEvent.admission)) {
                    pendingEvent = candidate;
                }
            }
            const baseline = baselineKind(record);
            const predecessorRank = predecessor === null ? -1 : predecessor.rank;
            const pendingRank = pendingEvent === null ? -1 : pendingEvent.rank;
            const baselineRank = rankFor(baseline);
            if (predecessor !== null && predecessorRank >= pendingRank && predecessorRank
                    >= baselineRank) {
                record.owner = predecessor;
                record.owner.revision += 1;
                record.owner.presentationVisible = false;
                record.owner.focusPending = isInteractiveKind(record.owner.kind) || (
                            record.owner.kind === root.ownerExpanded && record.explicitExpanded);
                record.owner.focusTarget = record.owner.focusPending ? focusFor(record.owner.kind) :
                                                                       root.focusNone;
                return;
            }
            if (pendingEvent !== null && pendingRank > baselineRank) {
                enterOwner(record, pendingEvent.kind, pendingEvent, 0, 0);
                return;
            }
            record.restoration = [];
            record.owner = baselineOwner(baseline === root.ownerExpanded);
            if (baseline === root.ownerExpanded && record.explicitExpanded) {
                record.owner.focusPending = true;
            }
        }

        function routedToken(initiatingSurfaceToken, excludedToken) {
            const initiated = recordForToken(initiatingSurfaceToken);
            if (initiated !== null && initiated.token !== excludedToken) {
                return initiated.token;
            }
            if (root.surfaceRouter !== null && root.surfaceRouter !== undefined
                    && typeof root.surfaceRouter.routeSurfaceToken === "function") {
                const routed = root.surfaceRouter.routeSurfaceToken(excludedToken);
                if (recordForToken(routed) !== null && routed !== excludedToken) {
                    return routed;
                }
            }
            for (let index = 0; index < surfaces.length; index += 1) {
                if (surfaces[index].token !== excludedToken) {
                    return surfaces[index].token;
                }
            }
            return null;
        }

        function schedule(now) {
            let deadline = -1;
            for (let index = 0; index < transients.length; index += 1) {
                const event = transients[index];
                const candidate = event.holdUntil >= 0 ? Math.min(event.freshUntil,
                                                                  event.holdUntil) :
                                                         event.freshUntil;
                if (deadline < 0 || candidate < deadline) {
                    deadline = candidate;
                }
            }
            if (deadline < 0) {
                scheduler.stop();
                return;
            }
            scheduler.interval = Math.max(1, Math.min(2147483647, Math.ceil(deadline - now)));
            scheduler.restart();
        }

        function setBaselineIntent(token, generation, value, explicitIntent) {
            const now = currentTime();
            expireDue(now);
            const record = recordForToken(token);
            if (record === null || record.generation !== generation || typeof value !== "boolean") {
                return false;
            }
            const wasExpanded = record.hover || record.explicitExpanded;
            if (explicitIntent) {
                record.explicitExpanded = value;
            } else {
                record.hover = value;
            }
            const expanded = record.hover || record.explicitExpanded;
            if (!wasExpanded && expanded && record.owner.rank < rankFor(root.ownerExpanded)) {
                captureCurrent(record);
                enterOwner(record, root.ownerExpanded, null, 0, 0);
                record.owner.focusPending = record.explicitExpanded;
                record.owner.focusTarget = record.explicitExpanded ? root.focusExpandedDashboard :
                                                                     root.focusNone;
            } else if (wasExpanded && !expanded && record.owner.kind === root.ownerExpanded) {
                restoreNext(record, now);
            } else if (explicitIntent && value && record.owner.kind === root.ownerExpanded) {
                record.owner.focusTarget = root.focusExpandedDashboard;
                if (record.owner.presentationVisible) {
                    record.focusRequestSerial += 1;
                } else {
                    record.owner.focusPending = true;
                }
            } else if (explicitIntent && !value && record.owner.kind === root.ownerExpanded) {
                record.owner.focusPending = false;
                record.owner.focusTarget = root.focusNone;
            }
            publish();
            schedule(now);
            return true;
        }

        function surfaceSnapshot(token) {
            const ignored = serial;
            const record = recordForToken(token);
            if (record === null) {
                return Object.freeze({
                                         "explicitExpandedIntent": false,
                                         "focusRequestSerial": 0,
                                         "focusTarget": root.focusNone,
                                         "generation": 0,
                                         "hoverIntent": false,
                                         "ownerEpoch": 0,
                                         "ownerKind": root.ownerNone,
                                         "ownerName": "none",
                                         "ownerSourceGeneration": 0,
                                         "ownerSourceRevision": 0,
                                         "ownerSourceToken": null,
                                         "presentationVisible": false,
                                         "restorationDepth": 0,
                                         "revision": 0
                                     });
            }
            return Object.freeze({
                                     "explicitExpandedIntent": record.explicitExpanded,
                                     "focusRequestSerial": record.focusRequestSerial,
                                     "focusTarget": record.owner.focusTarget,
                                     "generation": record.generation,
                                     "hoverIntent": record.hover,
                                     "ownerEpoch": record.owner.epoch,
                                     "ownerKind": record.owner.kind,
                                     "ownerName": ownerName(record.owner.kind),
                                     "ownerSourceGeneration": record.owner.sourceGeneration,
                                     "ownerSourceRevision": record.owner.sourceRevision,
                                     "ownerSourceToken": record.owner.sourceToken,
                                     "presentationVisible": record.owner.presentationVisible,
                                     "restorationDepth": record.restoration.length,
                                     "revision": record.owner.revision
                                 });
        }

        function syncPolkitModal(isActive, flowPresent, flowGeneration) {
            if (typeof isActive !== "boolean" || typeof flowPresent !== "boolean" ||
                    !Number.isInteger(flowGeneration) || flowGeneration < 0) {
                return false;
            }
            const wasPresent = modalIsActive || modalFlowPresent;
            const snapshotChanged = modalIsActive !== isActive || modalFlowPresent !== flowPresent
                  || modalFlowGeneration !== flowGeneration;
            modalIsActive = isActive;
            modalFlowPresent = flowPresent;
            modalFlowGeneration = flowGeneration;
            const present = modalIsActive || modalFlowPresent;
            if (!wasPresent && present) {
                rehomeModal(null, true);
            } else if (wasPresent && present && snapshotChanged) {
                const record = recordForToken(modalHostToken);
                if (record !== null && record.owner.kind === root.ownerPolkitModal) {
                    record.owner.revision += 1;
                    record.owner.presentationVisible = false;
                    record.owner.focusPending = true;
                }
            } else if (wasPresent && !present) {
                const record = recordForToken(modalHostToken);
                modalHostToken = null;
                if (record !== null && record.owner.kind === root.ownerPolkitModal) {
                    restoreNext(record, currentTime());
                }
            }
            publish();
            schedule(currentTime());
            return true;
        }

        function transferInteractiveAfterLoss(kind, epoch, excludedToken) {
            const token = routedToken(null, excludedToken);
            const target = recordForToken(token);
            if (target === null) {
                return;
            }
            captureCurrent(target);
            enterOwner(target, kind, null, epoch, 1);
        }
    }

    ElapsedTimer {
        id: monotonicClock
    }

    Timer {
        id: scheduler

        repeat: false
        onTriggered: {
            const now = state.currentTime();
            state.expireDue(now);
            state.publish();
            state.schedule(now);
        }
    }
}

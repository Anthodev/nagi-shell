pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: root

    required property string helperPath
    property string pinsPathOverride: ""
    property string recencyPathOverride: ""

    readonly property bool available: state.discoveryAvailable
    readonly property bool initialized: state.readyForUse
    readonly property var applications: state.applications
    readonly property var pinnedApplications: state.pinnedApplications
    readonly property var recentApplications: state.recentApplications
    readonly property var pinIds: state.committedPins
    readonly property var recencyIds: state.recencyIds
    readonly property bool pinMutationPending: state.pinsWritePhase !== "idle" || state.pendingPins
                                               !== null
    readonly property bool launchPending: state.pendingLaunch !== null
    readonly property string pinFailure: state.pinFailure
    readonly property string recencyFailure: state.recencyFailure
    readonly property string pinsPath: state.pinsPath
    readonly property string recencyPath: state.recencyPath
    readonly property int maximumPins: 8
    readonly property int maximumRecency: 20
    readonly property int maximumRecentRows: 8
    readonly property int maximumStoreBytes: 128 * 1024
    readonly property int maximumDiagnosticsPerStore: 4

    signal pinCommitted(string desktopFileId)
    signal pinRemoved(string desktopFileId)
    signal pinReordered(string desktopFileId)
    signal pinMutationFailed(string category)
    signal recencyPersisted
    signal launchAccepted(int requestId, string desktopFileId)
    signal launchRejected(int requestId, string category)

    function pin(desktopFileId) {
        if (!state.pinStoreAvailable || !bridge.ready) {
            state.pinFailure = "unavailable";
            return false;
        }
        if (!eligible(desktopFileId)) {
            return false;
        }
        const target = state.desiredPins.slice();
        if (target.indexOf(desktopFileId) !== -1) {
            return false;
        }
        if (target.length >= root.maximumPins) {
            state.pinFailure = "limit";
            return false;
        }
        target.push(desktopFileId);
        state.pinFailure = "none";
        schedulePins(target, "pin", desktopFileId);
        return true;
    }

    function unpin(desktopFileId) {
        if (!state.pinStoreAvailable || !bridge.ready) {
            state.pinFailure = "unavailable";
            return false;
        }
        const target = state.desiredPins.slice();
        const index = target.indexOf(desktopFileId);
        if (index === -1) {
            return false;
        }
        target.splice(index, 1);
        state.pinFailure = "none";
        schedulePins(target, "unpin", desktopFileId);
        return true;
    }

    function movePin(desktopFileId, newIndex) {
        if (!state.pinStoreAvailable || !bridge.ready || !Number.isInteger(newIndex)) {
            state.pinFailure = state.pinStoreAvailable && bridge.ready ? "none" : "unavailable";
            return false;
        }
        const target = state.desiredPins.slice();
        const oldIndex = target.indexOf(desktopFileId);
        if (oldIndex === -1 || newIndex < 0 || newIndex >= target.length || newIndex === oldIndex) {
            return false;
        }
        target.splice(oldIndex, 1);
        target.splice(newIndex, 0, desktopFileId);
        state.pinFailure = "none";
        schedulePins(target, "reorder", desktopFileId);
        return true;
    }

    function dispatchLaunch(desktopFileId) {
        if (state.pendingLaunch !== null || !eligible(desktopFileId) || !bridge.ready) {
            return 0;
        }
        state.nextLaunchRequestId = state.nextLaunchRequestId >= 2147483647 ? 1 :
                                                                              state.nextLaunchRequestId
                                                                              + 1;
        const requestId = state.nextLaunchRequestId;
        state.pendingLaunch = {
            "requestId": requestId,
            "desktopFileId": desktopFileId
        };
        if (!bridge.launch(requestId, desktopFileId)) {
            state.pendingLaunch = null;
            return 0;
        }
        return requestId;
    }

    function acceptLaunchResult(requestId, accepted, category) {
        const pending = state.pendingLaunch;
        if (pending === null || pending.requestId !== requestId) {
            return;
        }
        state.pendingLaunch = null;
        if (!accepted) {
            root.launchRejected(requestId, category);
            captureDiscoveryGeneration();
            return;
        }
        commitAcceptedLaunch(pending.desktopFileId);
        root.launchAccepted(requestId, pending.desktopFileId);
    }

    function recordAcceptedLaunch(desktopFileId) {
        return eligible(desktopFileId) && commitAcceptedLaunch(desktopFileId);
    }

    function commitAcceptedLaunch(desktopFileId) {
        if (!validDesktopId(desktopFileId)) {
            return false;
        }
        const target = state.recencyIds.slice();
        const previous = target.indexOf(desktopFileId);
        if (previous !== -1) {
            target.splice(previous, 1);
        }
        target.unshift(desktopFileId);
        if (target.length > root.maximumRecency) {
            target.length = root.maximumRecency;
        }
        if (arraysEqual(target, state.recencyIds)) {
            return true;
        }
        state.recencyIds = target;
        rebuildSections();
        if (state.recencyStoreAvailable && bridge.ready) {
            state.recencyFailure = "none";
            scheduleRecency(target);
        } else {
            state.recencyFailure = "unavailable";
        }
        return true;
    }

    function eligible(desktopFileId) {
        return validDesktopId(desktopFileId) && state.entryById[desktopFileId] !== undefined;
    }

    function markDiscoveryIncomplete(category) {
        state.discoveryAvailable = false;
        warnBounded("discovery", category);
    }

    function captureDiscoveryGeneration() {
        const values = DesktopEntries.applications.values;
        const snapshot = [];
        if (values !== null && typeof values === "object" && typeof values.length === "number") {
            for (let index = 0; index < values.length; ++index) {
                snapshot.push(values[index]);
            }
        }
        state.nextDiscoveryGeneration += 1;
        state.pendingDiscoveryGeneration = state.nextDiscoveryGeneration;
        state.pendingDiscoveryEntries = snapshot;
        startDiscoveryScan();
    }

    function startDiscoveryScan() {
        if (!bridge.ready || state.scanInFlight || state.pendingDiscoveryGeneration === 0) {
            return;
        }
        const generation = state.pendingDiscoveryGeneration;
        const entries = state.pendingDiscoveryEntries;
        if (!bridge.scan(generation)) {
            return;
        }
        state.pendingDiscoveryGeneration = 0;
        state.pendingDiscoveryEntries = [];
        state.scanInFlight = true;
        state.inFlightDiscoveryGeneration = generation;
        state.inFlightDiscoveryEntries = entries;
    }

    function acceptDiscoveryGeneration(generation) {
        if (!state.scanInFlight || generation.generation !== state.inFlightDiscoveryGeneration) {
            return;
        }
        const sourceEntries = state.inFlightDiscoveryEntries;
        state.scanInFlight = false;
        state.inFlightDiscoveryGeneration = 0;
        state.inFlightDiscoveryEntries = [];

        if (generation.complete) {
            const quickshellById = {};
            let complete = (sourceEntries.length === 0) === (generation.entries.length === 0);
            for (let index = 0; index < sourceEntries.length; ++index) {
                const entry = sourceEntries[index];
                if (entry === null || typeof entry !== "object" || typeof entry.id !== "string"
                        || entry.id.length === 0 || quickshellById[entry.id] !== undefined) {
                    complete = false;
                    break;
                }
                quickshellById[entry.id] = entry;
            }

            const map = {};
            const applications = [];
            if (complete) {
                for (let index = 0; index < generation.entries.length; ++index) {
                    const validated = generation.entries[index];
                    const entry = quickshellById[validated.quickshellId]
                          ?? quickshellById[validated.id];
                    if (entry === undefined) {
                        continue;
                    }
                    const row = normalizedEntry(validated.id, entry);
                    if (row === null || map[row.id] !== undefined) {
                        complete = false;
                        break;
                    }
                    row.idOrder = index;
                    map[row.id] = row;
                    applications.push(row);
                }
            }

            if (complete) {
                applications.sort(compareApplications);
                for (let index = 0; index < applications.length; ++index) {
                    applications[index].nameOrder = index;
                }
                state.entryById = map;
                state.applications = applications;
                state.discoveryAvailable = true;
                state.hasCompleteDiscovery = true;
                reconcileCompleteGeneration();
            } else {
                markDiscoveryIncomplete("inconsistent complete generation");
            }
        } else {
            markDiscoveryIncomplete("incomplete generation");
        }
        startDiscoveryScan();
    }

    function normalizedEntry(desktopFileId, entry) {
        if (!validDesktopId(desktopFileId) || typeof entry.name !== "string") {
            return null;
        }
        const name = entry.name.trim();
        if (name.length === 0) {
            return null;
        }
        const keywords = [];
        const seenKeywords = {};
        const sourceKeywords = entry.keywords;
        if (sourceKeywords !== null && typeof sourceKeywords === "object"
                && typeof sourceKeywords.length === "number") {
            for (let index = 0; index < sourceKeywords.length; ++index) {
                if (typeof sourceKeywords[index] !== "string") {
                    continue;
                }
                const keyword = sourceKeywords[index].trim();
                if (keyword.length > 0 && seenKeywords[keyword] !== true) {
                    seenKeywords[keyword] = true;
                    keywords.push(keyword);
                }
            }
        }
        return {
            "id": desktopFileId,
            "name": name,
            "keywords": keywords,
            "icon": typeof entry.icon === "string" ? entry.icon.trim() : "",
            "desktopEntry": entry
        };
    }

    function compareApplications(left, right) {
        const byName = left.name.localeCompare(right.name);
        return byName !== 0 ? byName : left.id < right.id ? -1 : left.id > right.id ? 1 : 0;
    }

    function reconcileCompleteGeneration() {
        if (!state.storageInitialized || !state.hasCompleteDiscovery) {
            return;
        }
        const pruned = [];
        for (let index = 0; index < state.recencyIds.length; ++index) {
            const id = state.recencyIds[index];
            if (eligible(id)) {
                pruned.push(id);
            }
        }
        const changed = !arraysEqual(pruned, state.recencyIds);
        if (changed) {
            state.recencyIds = pruned;
            if (state.recencyStoreAvailable) {
                scheduleRecency(pruned);
            } else {
                state.recencyFailure = "unavailable";
            }
        }
        rebuildSections();
        state.readyForUse = true;
    }

    function rebuildSections() {
        const pins = [];
        const pinned = {};
        for (let index = 0; index < state.committedPins.length; ++index) {
            const id = state.committedPins[index];
            const entry = state.entryById[id];
            if (entry !== undefined) {
                pins.push(entry);
                pinned[id] = true;
            }
        }

        const recents = [];
        for (let index = 0; index < state.recencyIds.length && recents.length
             < root.maximumRecentRows; ++index) {
            const id = state.recencyIds[index];
            const entry = state.entryById[id];
            if (entry !== undefined && pinned[id] !== true) {
                recents.push(entry);
            }
        }
        state.pinnedApplications = pins;
        state.recentApplications = recents;
    }

    function acceptStores(stores) {
        if (state.storageInitialized) {
            startDiscoveryScan();
            startStoreWrite("pins");
            startStoreWrite("recency");
            return;
        }
        const pins = parseStore("pins", stores.pins, root.maximumPins);
        const recency = parseStore("recency", stores.recency, root.maximumRecency);
        state.pinStoreAvailable = stores.pins.available;
        state.recencyStoreAvailable = stores.recency.available;
        state.committedPins = pins;
        state.desiredPins = pins.slice();
        state.recencyIds = recency;
        state.storageInitialized = true;
        state.pinFailure = stores.pins.available ? "none" : "unavailable";
        state.recencyFailure = stores.recency.available ? "none" : "unavailable";
        reconcileCompleteGeneration();
        startDiscoveryScan();
    }

    function parseStore(kind, store, limit) {
        if (!store.available || store.category === "missing" || store.category === "empty") {
            return [];
        }
        if (store.category !== "loaded") {
            warnBounded(kind, store.category);
            return [];
        }
        let document;
        try {
            document = JSON.parse(store.text);
        } catch (error) {
            warnBounded(kind, "malformed");
            return [];
        }
        if (document === null || typeof document !== "object" || Array.isArray(document) || !Number.isInteger(
                    document.version) || document.version !== 1 || !Array.isArray(
                    document.desktopFileIds)) {
            warnBounded(kind, Number.isInteger(document?.version) && document.version !== 1
                        ? "version" : "schema");
            return [];
        }
        return normalizeIds(document.desktopFileIds, limit);
    }

    function normalizeIds(values, limit) {
        const result = [];
        const seen = {};
        for (let index = 0; index < values.length && result.length < limit; ++index) {
            const value = values[index];
            if (validDesktopId(value) && seen[value] !== true) {
                seen[value] = true;
                result.push(value);
            }
        }
        return result;
    }

    function validDesktopId(value) {
        if (typeof value !== "string" || value.length <= 8 || !value.endsWith(".desktop")
                || value.indexOf("\u0000") !== -1) {
            return false;
        }
        try {
            return unescape(encodeURIComponent(value)).length <= 4096;
        } catch (error) {
            return false;
        }
    }

    function schedulePins(ids, operation, desktopFileId) {
        state.desiredPins = ids.slice();
        state.pendingPins = {
            "ids": ids.slice(),
            "operation": operation,
            "desktopFileId": desktopFileId
        };
        startStoreWrite("pins");
    }

    function scheduleRecency(ids) {
        state.pendingRecency = ids.slice();
        startStoreWrite("recency");
    }

    function startStoreWrite(store) {
        if (!bridge.ready) {
            return;
        }
        if (store === "pins") {
            if (state.pinsWritePhase !== "idle" || state.pendingPins === null) {
                return;
            }
            state.currentPinsWrite = state.pendingPins;
            state.pendingPins = null;
            state.pinsWriteSerial += 1;
            state.pinsWritePhase = "preparing";
            if (!bridge.prepareWrite("pins", state.pinsWriteSerial)) {
                failStoreWrite("pins", "unavailable");
            }
            return;
        }
        if (state.recencyWritePhase !== "idle" || state.pendingRecency === null) {
            return;
        }
        state.currentRecencyWrite = state.pendingRecency;
        state.pendingRecency = null;
        state.recencyWriteSerial += 1;
        state.recencyWritePhase = "preparing";
        if (!bridge.prepareWrite("recency", state.recencyWriteSerial)) {
            failStoreWrite("recency", "unavailable");
        }
    }

    function acceptWriteReady(store, serial, success, category) {
        if (store === "pins") {
            if (state.pinsWritePhase !== "preparing" || serial !== state.pinsWriteSerial) {
                return;
            }
            if (!success) {
                failStoreWrite("pins", category);
                return;
            }
            state.pinsWritePhase = "saving";
            pinsWriter.setText(serialize(state.currentPinsWrite.ids));
            return;
        }
        if (state.recencyWritePhase !== "preparing" || serial !== state.recencyWriteSerial) {
            return;
        }
        if (!success) {
            failStoreWrite("recency", category);
            return;
        }
        state.recencyWritePhase = "saving";
        recencyWriter.setText(serialize(state.currentRecencyWrite));
    }

    function fileSaved(store) {
        if (store === "pins" && state.pinsWritePhase === "saving") {
            state.pinsWritePhase = "verifying";
            if (!bridge.verifyWrite("pins", state.pinsWriteSerial)) {
                failStoreWrite("pins", "unavailable");
            }
        } else if (store === "recency" && state.recencyWritePhase === "saving") {
            state.recencyWritePhase = "verifying";
            if (!bridge.verifyWrite("recency", state.recencyWriteSerial)) {
                failStoreWrite("recency", "unavailable");
            }
        }
    }

    function acceptWriteVerified(store, serial, success, category) {
        if (store === "pins") {
            if (state.pinsWritePhase !== "verifying" || serial !== state.pinsWriteSerial) {
                return;
            }
            if (!success) {
                failStoreWrite("pins", category);
                return;
            }
            const mutation = state.currentPinsWrite;
            state.committedPins = mutation.ids.slice();
            state.currentPinsWrite = null;
            state.pinsWritePhase = "idle";
            state.pinFailure = "none";
            rebuildSections();
            if (mutation.operation === "pin") {
                root.pinCommitted(mutation.desktopFileId);
            } else if (mutation.operation === "unpin") {
                root.pinRemoved(mutation.desktopFileId);
            } else {
                root.pinReordered(mutation.desktopFileId);
            }
            startStoreWrite("pins");
            return;
        }
        if (state.recencyWritePhase !== "verifying" || serial !== state.recencyWriteSerial) {
            return;
        }
        if (!success) {
            failStoreWrite("recency", category);
            return;
        }
        state.currentRecencyWrite = null;
        state.recencyWritePhase = "idle";
        state.recencyFailure = "none";
        root.recencyPersisted();
        startStoreWrite("recency");
    }

    function failStoreWrite(store, category) {
        if (store === "pins") {
            state.currentPinsWrite = null;
            state.pendingPins = null;
            state.pinsWritePhase = "idle";
            state.desiredPins = state.committedPins.slice();
            state.pinFailure = "write";
            root.pinMutationFailed(category === "none" ? "write" : category);
            return;
        }
        state.currentRecencyWrite = null;
        state.recencyWritePhase = "idle";
        state.recencyFailure = "write";
        startStoreWrite("recency");
    }

    function serialize(ids) {
        return JSON.stringify({
                                  "version": 1,
                                  "desktopFileIds": ids
                              }, null, 2) + "\n";
    }

    function arraysEqual(left, right) {
        if (left.length !== right.length) {
            return false;
        }
        for (let index = 0; index < left.length; ++index) {
            if (left[index] !== right[index]) {
                return false;
            }
        }
        return true;
    }

    function resolveStorePath(environmentName, fallbackSuffix, fileName) {
        const configured = Quickshell.env(environmentName);
        let base = typeof configured === "string" ? configured : "";
        if (!base.startsWith("/")) {
            const home = Quickshell.env("HOME");
            if (typeof home !== "string" || !home.startsWith("/")) {
                return "";
            }
            base = home.replace(/\/+$/, "") + fallbackSuffix;
        }
        base = base.replace(/\/+$/, "");
        return base + "/nagi-shell/" + fileName;
    }

    function warnBounded(store, category) {
        const key = store === "pins" ? "pinDiagnosticCount" : store === "recency"
                                       ? "recencyDiagnosticCount" : "discoveryDiagnosticCount";
        if (state[key] >= root.maximumDiagnosticsPerStore) {
            return;
        }
        state[key] += 1;
        console.warn("Application model: " + store + " " + String(category).slice(0, 64));
    }

    Connections {
        target: DesktopEntries

        function onApplicationsChanged() {
            root.captureDiscoveryGeneration();
        }
    }

    ApplicationBridge {
        id: bridge

        helperPath: root.helperPath
        pinsPath: state.pinsPath
        recencyPath: state.recencyPath
        enabled: state.pathsInitialized

        onInitialized: stores => root.acceptStores(stores)
        onGenerationReceived: generation => root.acceptDiscoveryGeneration(generation)
        onLaunchResult: (requestId, accepted, category) => root.acceptLaunchResult(requestId,
                                                                                   accepted, category)
        onWriteReady: (store, serial, success, category) => root.acceptWriteReady(store, serial, success,
                                                                                  category)
        onWriteVerified: (store, serial, success, category) => root.acceptWriteVerified(store,
                                                                                        serial, success,
                                                                                        category)
        onFatalFailure: {
            if (state.pendingLaunch !== null) {
                const requestId = state.pendingLaunch.requestId;
                state.pendingLaunch = null;
                root.launchRejected(requestId, "unavailable");
            }
            root.markDiscoveryIncomplete("helper unavailable");
            state.scanInFlight = false;
            if (state.inFlightDiscoveryGeneration !== 0) {
                state.pendingDiscoveryGeneration = state.inFlightDiscoveryGeneration;
                state.pendingDiscoveryEntries = state.inFlightDiscoveryEntries;
            }
            state.inFlightDiscoveryGeneration = 0;
            state.inFlightDiscoveryEntries = [];
            if (state.pinsWritePhase !== "idle") {
                root.failStoreWrite("pins", "unavailable");
            }
            if (state.recencyWritePhase !== "idle") {
                root.failStoreWrite("recency", "unavailable");
            }
        }
    }

    FileView {
        id: pinsWriter

        path: state.pinStoreAvailable ? state.pinsPath : ""
        atomicWrites: true
        preload: false
        printErrors: false
        onSaved: root.fileSaved("pins")
        onSaveFailed: error => root.failStoreWrite("pins", "write")
    }

    FileView {
        id: recencyWriter

        path: state.recencyStoreAvailable ? state.recencyPath : ""
        atomicWrites: true
        preload: false
        printErrors: false
        onSaved: root.fileSaved("recency")
        onSaveFailed: error => root.failStoreWrite("recency", "write")
    }

    QtObject {
        id: state

        property string pinsPath: ""
        property string recencyPath: ""
        property bool pathsInitialized: false
        property bool storageInitialized: false
        property bool readyForUse: false
        property bool pinStoreAvailable: false
        property bool recencyStoreAvailable: false
        property bool discoveryAvailable: false
        property bool hasCompleteDiscovery: false
        property var entryById: ({})
        property var applications: []
        property var pinnedApplications: []
        property var recentApplications: []
        property var committedPins: []
        property var desiredPins: []
        property var recencyIds: []
        property string pinFailure: "none"
        property string recencyFailure: "none"
        property int nextDiscoveryGeneration: 0
        property int pendingDiscoveryGeneration: 0
        property var pendingDiscoveryEntries: []
        property bool scanInFlight: false
        property int inFlightDiscoveryGeneration: 0
        property var inFlightDiscoveryEntries: []
        property int nextLaunchRequestId: 0
        property var pendingLaunch: null
        property string pinsWritePhase: "idle"
        property int pinsWriteSerial: 0
        property var currentPinsWrite: null
        property var pendingPins: null
        property string recencyWritePhase: "idle"
        property int recencyWriteSerial: 0
        property var currentRecencyWrite: null
        property var pendingRecency: null
        property int pinDiagnosticCount: 0
        property int recencyDiagnosticCount: 0
        property int discoveryDiagnosticCount: 0
    }

    Component.onCompleted: {
        state.pinsPath = root.pinsPathOverride !== "" ? root.pinsPathOverride :
                                                        root.resolveStorePath("XDG_CONFIG_HOME",
                                                                              "/.config",
                                                                              "application-pins.json");
        state.recencyPath = root.recencyPathOverride !== "" ? root.recencyPathOverride :
                                                              root.resolveStorePath("XDG_STATE_HOME",
                                                                                    "/.local/state",
                                                                                    "application-recency.json");
        state.pathsInitialized = true;
        if (DesktopEntries.applications.values.length > 0) {
            root.captureDiscoveryGeneration();
        }
    }
}

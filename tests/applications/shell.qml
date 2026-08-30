import Quickshell
import Quickshell.Io
import QtQuick
import "qml"

ShellRoot {
    id: test

    property string phase: Quickshell.env("NAGI_APPLICATION_TEST_PHASE")
    property string stage: "startup"
    property bool started: false
    property string configuredHelperPath: Quickshell.env("NAGI_APPLICATION_HELPER")
    property string activeHelperPath: configuredHelperPath
    property int soakCycle: 0
    property int soakRejectedCount: 0
    property var soakApplicationIds: []
    property var soakPinIds: []
    property var soakRecencyIds: []

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            return false;
        }
        return true;
    }

    function ids(rows) {
        const result = [];
        for (let index = 0; index < rows.length; ++index) {
            result.push(rows[index].id);
        }
        return result;
    }

    function equal(left, right) {
        return JSON.stringify(left) === JSON.stringify(right);
    }

    function runInitialAssertions() {
        if (started || !applications.initialized) {
            return;
        }
        started = true;
        if (phase === "defaults") {
            const home = Quickshell.env("HOME");
            if (!require(applications.pinsPath === home
                         + "/.config/nagi-shell/application-pins.json",
                         "relative config base did not use the XDG default") || !require(
                        applications.recencyPath === home
                        + "/.local/state/nagi-shell/application-recency.json",
                        "relative state base did not use the XDG default") || !require(
                        applications.pinIds.length === 0 && applications.recencyIds.length === 0,
                        "missing default stores were not clean first-run state") || !require(
                        applications.pinFailure === "none" && applications.recencyFailure === "none",
                        "missing default store directories were not initialized")) {
                return;
            }
            console.log("application model XDG default tests passed");
            Qt.exit(0);
            return;
        }
        if (phase === "unsafe") {
            if (!require(applications.pinFailure === "unavailable",
                         "unsafe pin store was not disabled") || !require(
                        applications.pinIds.length === 0, "unsafe pin store content was read") ||
                    !require(!applications.pin("app0.desktop"),
                             "unsafe pin store accepted a mutation") || !require(
                        applications.recordAcceptedLaunch("app7.desktop"),
                        "independent recency store was blocked")) {
                return;
            }
            stage = "unsafe-launch";
            return;
        }
        if (phase === "restart") {
            if (!require(equal(applications.pinIds, ["app6.desktop", "dormant.desktop",
                                                     "app1.desktop", "app2.desktop", "app3.desktop",
                                                     "app4.desktop", "app5.desktop"]),
                         "pins did not survive restart") || !require(equal(applications.recencyIds,
                                                                           ["app9.desktop",
                                                                            "app8.desktop"]),
                                                                     "recency did not survive restart")
                    || !require(equal(ids(applications.pinnedApplications), ["app6.desktop",
                                                                             "app1.desktop",
                                                                             "app2.desktop",
                                                                             "app3.desktop",
                                                                             "app4.desktop",
                                                                             "app5.desktop"]),
                                "dormant pin was not hidden after restart") || !require(equal(ids(
                                                                                                  applications.recentApplications),
                                                                                              ["app9.desktop",
                                                                                               "app8.desktop"]),
                                                                                        "restart recent rows are incorrect")) {
                return;
            }
            console.log("application model restart tests passed");
            Qt.exit(0);
            return;
        }

        const many = [];
        for (let index = 0; index < 25; ++index) {
            many.push("bounded" + index + ".desktop");
        }
        many.splice(2, 0, "bounded0.desktop", "bad", 3);
        if (!require(applications.applications.length === 10,
                     "eligible fixtures did not appear exactly once") || !require(
                    applications.applications[0].name === "Fixture 0",
                    "current display metadata was not exposed") || !require(equal(
                                                                                applications.applications[0].keywords,
                                                                                ["zero", "fixture"]),
                                                                            "current keywords were not normalized")
                || !require(equal(applications.pinIds, ["dormant.desktop", "app0.desktop"]),
                            "pin startup normalization changed order") || !require(equal(ids(
                                                                                             applications.pinnedApplications),
                                                                                         ["app0.desktop"]),
                                                                                   "dormant pin was not hidden")
                || !require(equal(applications.recencyIds, ["app8.desktop", "app0.desktop"]),
                            "MRU was not deduplicated and pruned") || !require(equal(ids(
                                                                                         applications.recentApplications),
                                                                                     ["app8.desktop"]),
                                                                               "pinned ID was not excluded from recents")
                || !require(applications.normalizeIds(many, 20).length === 20,
                            "ID normalization did not enforce the MRU bound") || !require(
                    applications.parseStore("pins", {
                                                "available": true,
                                                "category": "loaded",
                                                "text": "{\"version\":2,\"desktopFileIds\":[\"app0.desktop\"]}"
                                            }, 8).length === 0,
                    "unknown store version was partially recovered") || !require(
                    applications.parseStore("pins", {
                                                "available": true,
                                                "category": "loaded",
                                                "text": "not json"
                                            }, 8).length === 0,
                    "malformed store was partially recovered")) {
            return;
        }

        const retainedApplications = ids(applications.applications);
        const retainedPins = applications.pinIds.slice();
        const retainedRecency = applications.recencyIds.slice();
        applications.markDiscoveryIncomplete("controlled incomplete generation");
        if (!require(!applications.available, "incomplete generation remained available") ||
                !require(equal(ids(applications.applications), retainedApplications),
                         "incomplete generation replaced the last complete model") || !require(equal(
                                                                                                   applications.pinIds,
                                                                                                   retainedPins),
                                                                                               "incomplete generation rewrote pins")
                || !require(equal(applications.recencyIds, retainedRecency),
                            "incomplete generation rewrote MRU")) {
            return;
        }
        stage = "restore-discovery";
        applications.captureDiscoveryGeneration();
    }

    function beginLifecycle() {
        stage = "hidden-write";
        appWriter.setText(
                    "[Desktop Entry]\nType=Application\nName=Fixture 0\nHidden=true\nExec=/usr/bin/true\n");
        renamedWriter.setText(
                    "[Desktop Entry]\nType=Application\nName=Renamed Fixture\nExec=/usr/bin/true\n");
    }

    function checkLifecycle() {
        if (stage === "hidden-wait" && ids(applications.pinnedApplications).indexOf("app0.desktop")
                === -1 && ids(applications.applications).indexOf("renamed.desktop") !== -1) {
            if (!require(applications.pinIds.indexOf("app0.desktop") !== -1,
                         "missing pin was not kept dormant") || !require(ids(
                                                                             applications.pinnedApplications).indexOf(
                                                                             "renamed.desktop") ===
                                                                         -1, "pin migrated to a changed desktop ID")) {
                return;
            }
            stage = "restore-write";
            appWriter.setText(
                        "[Desktop Entry]\nType=Application\nName=Fixture 0 Restored\nExec=/usr/bin/true\nIcon=restored\nKeywords=restored;\n");
        } else if (stage === "restore-wait" && ids(applications.pinnedApplications).indexOf(
                       "app0.desktop") !== -1) {
            if (!require(applications.entryById === undefined,
                         "private exact-ID map leaked through the public API") || !require(
                        applications.recencyIds.indexOf("app0.desktop") === -1,
                        "pruned MRU returned after same-ID reinstall")) {
                return;
            }
            beginPinMutations();
        }
    }

    function beginPinMutations() {
        stage = "pinning";
        for (let index = 1; index <= 6; ++index) {
            if (!require(applications.pin("app" + index + ".desktop"),
                         "eligible pin request was rejected")) {
                return;
            }
        }
    }

    function beginApplicationSoak() {
        stage = "soak-ready";
        soakCycle = 0;
        soakRejectedCount = 0;
        soakApplicationIds = ids(applications.applications);
        soakPinIds = applications.pinIds.slice();
        soakRecencyIds = applications.recencyIds.slice();
        if (!require(applications.available && applications.initialized
                     && !applications.pinMutationPending && !applications.launchPending,
                     "application soak starts from an available idle model")) {
            return;
        }
        Qt.callLater(runApplicationSoakCycle);
    }

    function runApplicationSoakCycle() {
        if (soakCycle >= 20) {
            if (!require(activeHelperPath === configuredHelperPath && applications.available
                         && applications.initialized && !applications.pinMutationPending
                         && !applications.launchPending
                         && equal(ids(applications.applications), soakApplicationIds)
                         && equal(applications.pinIds, soakPinIds)
                         && equal(applications.recencyIds, soakRecencyIds),
                         "application soak finishes at its pre-cycle helper, model, store, and queue counts")) {
                return;
            }
            console.log("application model mutation and lifecycle soak tests passed");
            Qt.exit(0);
            return;
        }

        const cycle = soakCycle;
        if (!require(stage === "soak-ready" && applications.available
                     && applications.initialized && !applications.pinMutationPending
                     && !applications.launchPending
                     && equal(ids(applications.applications), soakApplicationIds)
                     && equal(applications.pinIds, soakPinIds)
                     && equal(applications.recencyIds, soakRecencyIds),
                     "cycle " + cycle + " starts from exact model, store, and queue counts")) {
            return;
        }

        const malformedPins = applications.parseStore("pins", {
                                                           "available": true,
                                                           "category": "loaded",
                                                           "text": "not json " + cycle
                                                       }, applications.maximumPins);
        const malformedRecency = applications.parseStore("recency", {
                                                               "available": true,
                                                               "category": "loaded",
                                                               "text": "{\"version\":1}"
                                                           }, applications.maximumRecency);
        const oversizedIds = [];
        for (let index = 0; index < 64; ++index) {
            oversizedIds.push("cycle-" + cycle + "-" + index + ".desktop");
        }
        if (!require(malformedPins.length === 0 && malformedRecency.length === 0
                     && applications.normalizeIds(oversizedIds,
                                                  applications.maximumRecency).length
                     === applications.maximumRecency
                     && applications.maximumDiagnosticsPerStore === 4
                     && equal(ids(applications.applications), soakApplicationIds)
                     && equal(applications.pinIds, soakPinIds)
                     && equal(applications.recencyIds, soakRecencyIds),
                     "cycle " + cycle + " bounds malformed stores, diagnostics, and records")) {
            return;
        }

        stage = "soak-denial";
        const requestId = applications.dispatchLaunch("app9.desktop");
        if (!require(requestId > 0 && applications.launchPending
                     && applications.dispatchLaunch("app8.desktop") === 0,
                     "cycle " + cycle + " admits one launch and rejects queueing")) {
            return;
        }
        applications.acceptLaunchResult(requestId + 1, false, "launch");
        if (!require(applications.launchPending,
                     "cycle " + cycle + " ignores a stale launch completion")) {
            return;
        }
        applications.acceptLaunchResult(requestId, false, "launch");
        if (!require(!applications.launchPending && soakRejectedCount === cycle + 1
                     && equal(applications.recencyIds, soakRecencyIds)
                     && equal(applications.pinIds, soakPinIds),
                     "cycle " + cycle + " denial leaves backend-owned stores unchanged")) {
            return;
        }

        stage = "soak-losing";
        activeHelperPath = "";
    }

    function restartApplicationSoakHelper() {
        if (stage !== "soak-restarting") {
            return;
        }
        stage = "soak-recovering";
        activeHelperPath = configuredHelperPath;
        applications.captureDiscoveryGeneration();
    }

    function completeApplicationSoakCycle() {
        if (!require(stage === "soak-validating" && applications.available
                     && applications.initialized && activeHelperPath === configuredHelperPath
                     && !applications.pinMutationPending && !applications.launchPending
                     && equal(ids(applications.applications), soakApplicationIds)
                     && equal(applications.pinIds, soakPinIds)
                     && equal(applications.recencyIds, soakRecencyIds),
                     "cycle " + soakCycle + " replacement recovers exact records and clean queues")) {
            return;
        }
        soakCycle += 1;
        stage = "soak-ready";
        Qt.callLater(runApplicationSoakCycle);
    }

    ApplicationModel {
        id: applications

        helperPath: test.activeHelperPath

        onInitializedChanged: test.runInitialAssertions()
        onAvailableChanged: {
            if (test.stage === "restore-discovery" && applications.available) {
                test.beginLifecycle();
                return;
            }
            if (test.stage === "soak-losing" && !applications.available) {
                if (!test.require(!applications.pinMutationPending && !applications.launchPending
                                  && test.equal(test.ids(applications.applications),
                                                test.soakApplicationIds)
                                  && test.equal(applications.pinIds, test.soakPinIds)
                                  && test.equal(applications.recencyIds, test.soakRecencyIds),
                                  "cycle " + test.soakCycle
                                  + " owner loss retains bounded records and clears queued work")) {
                    return;
                }
                test.stage = "soak-restarting";
                Qt.callLater(test.restartApplicationSoakHelper);
                return;
            }
            if (test.stage === "soak-recovering" && applications.available) {
                test.stage = "soak-validating";
                Qt.callLater(test.completeApplicationSoakCycle);
            }
        }
        onApplicationsChanged: test.checkLifecycle()
        onPinnedApplicationsChanged: test.checkLifecycle()
        onPinCommitted: desktopFileId => {
            if (test.stage === "pinning" && applications.pinIds.length === 8) {
                if (!test.require(!applications.pin("app7.desktop"), "ninth pin was not rejected")
                        || !test.require(applications.pinFailure === "limit",
                                         "pin limit failure was not exposed")) {
                    return;
                }
                test.stage = "moving";
                test.require(applications.movePin("app6.desktop", 0),
                             "pin reorder request was rejected");
            }
        }
        onPinReordered: desktopFileId => {
            if (test.stage !== "moving") {
                return;
            }
            if (!test.require(applications.pinIds[0] === "app6.desktop",
                              "pin order did not commit after save")) {
                return;
            }
            test.stage = "unpinning";
            test.require(applications.unpin("app0.desktop"), "unpin request was rejected");
        }
        onPinRemoved: desktopFileId => {
            if (test.stage !== "unpinning") {
                return;
            }
            test.stage = "launching";
            test.require(applications.dispatchLaunch("app9.desktop") > 0,
                         "eligible launch dispatch was rejected");
        }
        onLaunchAccepted: (requestId, desktopFileId) => {
            if (test.stage === "launching" && desktopFileId === "app9.desktop") {
                test.stage = "launched-persisting";
            }
        }
        onLaunchRejected: (requestId, category) => {
            if (test.stage === "soak-denial" && category === "launch") {
                test.soakRejectedCount += 1;
                return;
            }
            test.require(false, "structured launch was rejected: " + category);
        }
        onRecencyPersisted: {
            if (test.stage === "unsafe-launch" && applications.recencyIds[0] === "app7.desktop") {
                console.log("application model isolated-store failure tests passed");
                Qt.exit(0);
                return;
            }
            if (test.stage !== "launched-persisting"
                    || applications.recencyIds[0] !== "app9.desktop") {
                return;
            }
            if (!test.require(equal(applications.recencyIds, ["app9.desktop", "app8.desktop"]),
                              "accepted launch did not move to MRU front") || !test.require(equal(
                                                                                                ids(applications.recentApplications),
                                                                                                ["app9.desktop",
                                                                                                 "app8.desktop"]),
                                                                                            "recent rows do not follow MRU order")) {
                return;
            }
            test.beginApplicationSoak();
            return;
        }
    }

    FileView {
        id: appWriter

        path: Quickshell.env("XDG_DATA_HOME") + "/applications/app0.desktop"
        atomicWrites: true
        printErrors: false
        onSaved: {
            if (test.stage === "hidden-write") {
                test.stage = "hidden-wait";
            } else if (test.stage === "restore-write") {
                test.stage = "restore-wait";
            }
        }
    }

    FileView {
        id: renamedWriter

        path: Quickshell.env("XDG_DATA_HOME") + "/applications/renamed.desktop"
        atomicWrites: true
        preload: false
        printErrors: false
    }

    Timer {
        interval: 15000
        running: true
        onTriggered: {
            console.error("FAIL: application model tests timed out at " + test.stage);
            Qt.exit(1);
        }
    }

    Component.onCompleted: Qt.callLater(test.runInitialAssertions)
}

import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    id: test

    property string helperPath: Quickshell.env("NAGI_WORKSPACE_HELPER")
    property string controllerPath: Quickshell.env("NAGI_WORKSPACE_CONTROLLER")
    property int expectedOutputs: Number(Quickshell.env("KWIN_TEST_OUTPUTS") || "1")
    property string pluginName: "nagi-workspace-consensus-test-controller"
    property string helperEpoch: ""
    property string firstId: ""
    property string switchedId: ""
    property int controllerScriptId: -1
    property bool controllerStarted: false
    property bool listReady: false
    property bool sawDivergence: false
    property bool sawReconvergence: false
    property bool sawSharedSwitch: false
    property bool sawReorder: false
    property bool sawCurrentRename: false
    property bool sawNonCurrentRename: false
    property bool sawRemoval: false
    property bool sawReplacement: false
    property int desktopCountBeforeRemoval: 0
    property string replacementId: ""
    readonly property string currentRename: "Nagi Current Renamed"
    readonly property string nonCurrentRename: "Nagi Non-current Renamed"
    readonly property string retiredRename: "Nagi Retired Renamed"
    readonly property string replacementName: "Nagi Replacement"
    readonly property string replacementRename: "Nagi Replacement Renamed"
    property bool finishing: false

    function fail(message) {
        console.error("FAIL: " + message);
        if (helper.running) {
            helper.write("{\"op\":\"shutdown\"}\n");
        }
        Qt.exit(1);
    }

    function require(condition, message) {
        if (!condition) {
            fail(message);
            return false;
        }
        return true;
    }

    function exactKeys(object, expected) {
        return Object.keys(object).sort().join("|") === expected.slice().sort().join("|");
    }

    function desktopById(snapshot, id) {
        for (var index = 0; index < snapshot.desktops.length; ++index) {
            if (snapshot.desktops[index].id === id) {
                return snapshot.desktops[index];
            }
        }
        return null;
    }

    function desktopByName(snapshot, name) {
        for (var index = 0; index < snapshot.desktops.length; ++index) {
            if (snapshot.desktops[index].name === name) {
                return snapshot.desktops[index];
            }
        }
        return null;
    }

    function validateSnapshot(snapshot) {
        if (!require(exactKeys(snapshot, ["version", "helperEpoch", "available", "currentId",
                                          "showTransient", "desktops"]),
                     "helper wire has exact top-level keys") || !require(snapshot.version === 1,
                                                                         "helper wire version is one")
                || !require(typeof snapshot.helperEpoch === "string" && /^[0-9a-f]{32}$/.test(
                                snapshot.helperEpoch), "helper epoch is 32 lowercase hex") ||
                !require(typeof snapshot.available === "boolean" && typeof snapshot.showTransient
                         === "boolean" && Array.isArray(snapshot.desktops),
                         "helper wire types are exact")) {
            return false;
        }
        if (helperEpoch === "") {
            helperEpoch = snapshot.helperEpoch;
        } else if (!require(snapshot.helperEpoch === helperEpoch,
                            "helper epoch is stable for the process")) {
            return false;
        }

        if (!snapshot.available) {
            return require(snapshot.currentId === null && !snapshot.showTransient
                           && snapshot.desktops.length === 0, "unavailable snapshot is canonical");
        }
        if (!require(typeof snapshot.currentId === "string" && snapshot.currentId.length > 0
                     && snapshot.desktops.length > 0, "available snapshot has a current desktop")) {
            return false;
        }

        var foundCurrent = false;
        for (var index = 0; index < snapshot.desktops.length; ++index) {
            var desktop = snapshot.desktops[index];
            if (!require(exactKeys(desktop, ["id", "name", "position"]),
                         "desktop wire has exact keys") || !require(typeof desktop.id === "string"
                                                                    && desktop.id.length > 0
                                                                    && typeof desktop.name
                                                                    === "string"
                                                                    && desktop.position === index,
                                                                    "desktop wire is dense and ordered")) {
                return false;
            }
            foundCurrent = foundCurrent || desktop.id === snapshot.currentId;
        }
        return require(foundCurrent, "current desktop resolves in the wire list");
    }

    function acceptLine(line) {
        var snapshot;
        try {
            snapshot = JSON.parse(line);
        } catch (error) {
            fail("helper emitted malformed JSON");
            return;
        }
        if (!validateSnapshot(snapshot)) {
            return;
        }

        if (firstId === "" && snapshot.available) {
            firstId = snapshot.currentId;
            loadController.running = true;
            return;
        }
        if (!controllerStarted) {
            return;
        }

        if (snapshot.available && snapshot.desktops.length >= 2) {
            listReady = true;
        }
        if (!snapshot.available && expectedOutputs > 1 && listReady) {
            if (!require(!snapshot.showTransient, "divergence suppresses transient feedback")) {
                return;
            }
            sawDivergence = true;
            return;
        }
        if (snapshot.available && snapshot.currentId === firstId && expectedOutputs > 1
                && sawDivergence) {
            if (!require(!snapshot.showTransient,
                         "reconvergence never invents transient feedback")) {
                return;
            }
            sawReconvergence = true;
            return;
        }
        if (snapshot.available && snapshot.currentId !== firstId && snapshot.showTransient) {
            if (!require(expectedOutputs === 1 || sawReconvergence,
                         "shared switch follows tested reconvergence")) {
                return;
            }
            switchedId = snapshot.currentId;
            sawSharedSwitch = true;
            return;
        }
        if (sawSharedSwitch && !sawReorder && snapshot.available
                && snapshot.currentId === switchedId && !snapshot.showTransient
                && snapshot.desktops.length >= 2 && snapshot.desktops[0].id === switchedId) {
            var reorderedCurrent = desktopById(snapshot, switchedId);
            if (!require(reorderedCurrent !== null && reorderedCurrent.name !== currentRename,
                         "desktop reorder publishes before rename mutations")) {
                return;
            }
            sawReorder = true;
            return;
        }
        if (!sawReorder) {
            return;
        }

        var currentDesktop = desktopById(snapshot, switchedId);
        var originalDesktop = desktopById(snapshot, firstId);
        if (!sawCurrentRename) {
            if (!require(snapshot.available && snapshot.currentId === switchedId
                         && !snapshot.showTransient && currentDesktop !== null
                         && currentDesktop.name === currentRename && originalDesktop !== null
                         && originalDesktop.name !== nonCurrentRename,
                         "current desktop rename publishes exactly once before the next mutation")) {
                return;
            }
            sawCurrentRename = true;
            return;
        }
        if (!sawNonCurrentRename) {
            if (!require(snapshot.available && snapshot.currentId === switchedId
                         && !snapshot.showTransient && currentDesktop !== null
                         && currentDesktop.name === currentRename && originalDesktop !== null
                         && originalDesktop.name === nonCurrentRename,
                         "non-current desktop rename publishes exactly once before removal")) {
                return;
            }
            desktopCountBeforeRemoval = snapshot.desktops.length;
            sawNonCurrentRename = true;
            return;
        }
        if (!sawRemoval) {
            if (!require(snapshot.available && snapshot.currentId === switchedId
                         && !snapshot.showTransient && currentDesktop !== null
                         && currentDesktop.name === currentRename && originalDesktop === null
                         && desktopByName(snapshot, retiredRename) === null
                         && snapshot.desktops.length === desktopCountBeforeRemoval - 1,
                         "removed desktop and its retired rename cannot mutate the snapshot")) {
                return;
            }
            sawRemoval = true;
            return;
        }
        if (!sawReplacement) {
            var replacementDesktop = desktopByName(snapshot, replacementName);
            if (!require(snapshot.available && snapshot.currentId === switchedId
                         && !snapshot.showTransient && currentDesktop !== null
                         && currentDesktop.name === currentRename && originalDesktop === null
                         && replacementDesktop !== null
                         && snapshot.desktops.length === desktopCountBeforeRemoval,
                         "replacement desktop publishes without a stale removal callback")) {
                return;
            }
            replacementId = replacementDesktop.id;
            sawReplacement = true;
            return;
        }

        var renamedReplacement = desktopById(snapshot, replacementId);
        if (!require(snapshot.available && snapshot.currentId === switchedId
                     && !snapshot.showTransient && currentDesktop !== null
                     && currentDesktop.name === currentRename && originalDesktop === null
                     && renamedReplacement !== null
                     && renamedReplacement.name === replacementRename
                     && snapshot.desktops.length === desktopCountBeforeRemoval,
                     "replacement rename publishes exactly once from its current subscription")) {
            return;
        }
        finishing = true;
        helper.write("{\"op\":\"shutdown\"}\n");
    }

    Process {
        id: helper
        command: [test.helperPath]
        stdinEnabled: true
        running: true
        stdout: SplitParser {
            onRead: data => test.acceptLine(data)
        }
        onExited: function (exitCode) {
            if (!test.finishing) {
                test.fail("workspace helper exited unexpectedly");
                return;
            }
            if (!test.require(exitCode === 0, "workspace helper shuts down cleanly")) {
                return;
            }
            unloadController.running = true;
        }
    }

    Process {
        id: loadController
        command: ["busctl", "--user", "call", "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting",
            "loadScript", "ss", test.controllerPath, test.pluginName]
        stdout: StdioCollector {
            id: loadOutput
        }
        onExited: function (exitCode) {
            if (!test.require(exitCode === 0, "controller script loads")) {
                return;
            }
            var match = /^i\s+(-?\d+)/.exec(loadOutput.text.trim());
            if (!test.require(match !== null && Number(match[1]) >= 0,
                              "controller returns a valid KWin script ID")) {
                return;
            }
            test.controllerScriptId = Number(match[1]);
            test.controllerStarted = true;
            runController.command = ["busctl", "--user", "call", "org.kde.KWin",
                                     "/Scripting/Script" + test.controllerScriptId,
                                     "org.kde.kwin.Script", "run"];
            runController.running = true;
        }
    }

    Process {
        id: runController
        onExited: function (exitCode) {
            test.require(exitCode === 0, "controller script runs");
        }
    }

    Process {
        id: unloadController
        command: ["busctl", "--user", "call", "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting",
            "unloadScript", "s", test.pluginName]
        onExited: function (exitCode) {
            if (!test.require(exitCode === 0, "controller script unloads")) {
                return;
            }
            console.warn("workspace consensus virtual-KWin tests passed");
            Qt.exit(0);
        }
    }

    Timer {
        interval: 15000
        running: true
        onTriggered: test.fail("workspace consensus virtual-KWin test timed out")
    }

    Component.onCompleted: {
        if (helperPath === "" || controllerPath === "" || expectedOutputs < 1) {
            fail("workspace consensus test environment is incomplete");
        }
    }
}

pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

// Issue #70 gate 5: settings writer/watch path probe. Proves private atomic
// replacement, migration backup, own-write reload without generation churn,
// last-good retention on malformed external content, and the filesystem
// effect of atomicWrites over a symlink.
ShellRoot {
    id: root

    readonly property string configHome: {
        const xdgHome = Quickshell.env("XDG_CONFIG_HOME") ?? "";
        return xdgHome !== "" ? xdgHome : (Quickshell.env("HOME") ?? "") + "/.config";
    }
    readonly property string settingsPath: configHome + "/settings.conf"
    readonly property string legacyPath: configHome + "/legacy.conf"
    readonly property string backupPath: configHome + "/settings.conf.bak"
    readonly property string linkPath: configHome + "/link.conf"
    readonly property int maximumRetryAttempts: 600

    property int retryAttempts: 0
    property int stepIndex: 0
    property int generation: 0
    property string normalized: ""
    property int selfWriteEvents: 0

    function advance() {
        Qt.callLater(root.runStep);
    }

    function awaitState(condition, message) {
        if (condition) {
            root.retryAttempts = 0;
            return true;
        }
        root.retryAttempts += 1;
        if (root.retryAttempts > root.maximumRetryAttempts) {
            root.fail(message);
        }
        retry.restart();
        return false;
    }

    function fail(message) {
        console.error("SETTINGS FAIL: " + message);
        Qt.exit(1);
    }

    function emit(text) {
        console.warn("SETTINGS " + text);
    }

    function parse(content) {
        // Strict bounded parser: exactly one [theme] section with one key.
        const lines = content.replace(/\r?\n$/, "").split(/\r?\n/);
        if (lines.length !== 2 || lines[0] !== "[theme]" || !lines[1].startsWith("mode=")) {
            return null;
        }
        return lines[1].slice(5).trim() === "wallpaper" ? "wallpaper" : null;
    }

    function publish(candidate) {
        if (candidate === null) {
            return false;
        }
        if (candidate === root.normalized) {
            return true;
        }
        root.normalized = candidate;
        root.generation += 1;
        return true;
    }

    Timer {
        id: retry

        interval: 50
        onTriggered: root.runStep()
    }

    Timer {
        id: quietWindow

        interval: 800
        onTriggered: root.advance()
    }

    Component.onCompleted: root.advance()

    function runStep() {
        switch (root.stepIndex) {
        case 0:
            if (!root.awaitState(legacyLoader.loaded || !legacyLoader.path,
                                 "legacy file was never inspected")) {
                return;
            }
            root.emit("MIGRATION legacy_present=" + legacyLoader.loaded);
            if (legacyLoader.loaded) {
                backupWriter.setText(legacyLoader.text());
                return;
            }
            root.stepIndex = 1;
            root.advance();
            return;
        case 1:
            mainFile.path = root.settingsPath;
            root.stepIndex = 2;
            root.advance();
            return;
        case 2:
            if (!root.awaitState(mainFile.loaded || root.loadFailed,
                                 "settings path was never resolved")) {
                return;
            }
            root.selfWriteEvents = 0;
            mainFile.setText("[theme]\nmode=wallpaper\n");
            root.stepIndex = 3;
            root.advance();
            return;
        case 3:
            if (!root.awaitState(root.normalized === "wallpaper" && root.generation === 1,
                                 "first write did not normalize")) {
                return;
            }
            root.stepIndex = 4;
            quietWindow.restart();
            return;
        case 4:
            root.emit("LOOPQUIET selfWriteEvents=" + root.selfWriteEvents
                          + " generation=" + root.generation);
            root.emit("MARKER READY-FOR-MALFORMED");
            root.stepIndex = 5;
            root.advance();
            return;
        case 5:
            if (!root.awaitState(mainFile.loaded && root.normalized === "wallpaper"
                                     && root.generation === 1
                                     && parse(mainFile.text()) === null,
                                 "malformed replacement was not observed")) {
                return;
            }
            root.emit("LASTGOOD kept=true generation=" + root.generation);
            root.emit("MARKER READY-FOR-SYMLINK");
            symlinkProbe.path = root.linkPath;
            root.stepIndex = 6;
            root.advance();
            return;
        case 6:
            if (!root.awaitState(symlinkProbe.path === root.linkPath,
                                 "symlink probe never attached")) {
                return;
            }
            symlinkProbe.setText("escaped-content\n");
            root.stepIndex = 7;
            return;
        case 7:
            if (!root.awaitState(symlinkResult !== "",
                                 "symlink write never completed")) {
                return;
            }
            root.emit("SERVICE generation=" + root.generation);
            root.emit("DONE");
            return;
        default:
            root.fail("unknown step " + root.stepIndex);
        }
    }

    property string symlinkResult: ""

    FileView {
        id: legacyLoader

        path: root.legacyPath
        preload: true
        printErrors: false
    }

    FileView {
        id: backupWriter

        path: root.backupPath
        atomicWrites: true
        printErrors: false

        onSaved: {
            root.emit("MIGRATION backed_up=true");
            root.stepIndex = 1;
            root.advance();
        }
        onSaveFailed: root.fail("migration backup write failed")
    }

    FileView {
        id: mainFile

        path: ""
        watchChanges: true
        atomicWrites: true
        printErrors: false

        onFileChanged: {
            root.selfWriteEvents += 1;
            console.warn("SETTINGS EVENT fileChanged=" + root.selfWriteEvents);
            reload();
        }
        onLoaded: {
            const candidate = parse(text());
            root.publish(candidate);
            console.warn("SETTINGS LOADED parsed=" + (candidate ?? "null"));
        }
        onSaved: {
            const candidate = parse(text());
            root.publish(candidate);
            console.warn("SETTINGS SAVED parsed=" + (candidate ?? "null"));
        }
        onLoadFailed: function (error) {
            root.loadFailed = true;
            console.warn("SETTINGS LOADFAILED error=" + error);
        }
    }

    FileView {
        id: symlinkProbe

        path: ""
        atomicWrites: true
        printErrors: false

        onSaved: {
            root.symlinkResult = "saved";
            root.advance();
        }
        onSaveFailed: {
            root.symlinkResult = "failed";
            root.advance();
        }
    }
    property bool loadFailed: false
}


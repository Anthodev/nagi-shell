pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

// Issue #70 gate 4: event-first KDE appearance observation probe. Watches a
// synthetic kdeglobals through Quickshell FileView and re-derives color
// scheme, accent, and animation factor after every change event, including
// atomic-rename replacement and deletion.
ShellRoot {
    id: root

    readonly property string configHome: {
        const xdgHome = Quickshell.env("XDG_CONFIG_HOME") ?? "";
        return xdgHome !== "" ? xdgHome : (Quickshell.env("HOME") ?? "") + "/.config";
    }
    readonly property string kdeGlobalsPath: configHome + "/kdeglobals"

    property int changeEvents: 0
    property var debounce: null

    function canonicalAccent(value) {
        if (/^#[0-9a-fA-F]{6}$/.test(value)) {
            return value.toUpperCase();
        }
        const rgb = value.split(",");
        if (rgb.length === 3 || rgb.length === 4) {
            let ok = true;
            let hex = "#";
            for (let index = 0; index < 3; index += 1) {
                const channel = Number(rgb[index].trim());
                if (!Number.isInteger(channel) || channel < 0 || channel > 255) {
                    ok = false;
                    break;
                }
                hex += channel.toString(16).padStart(2, "0").toUpperCase();
            }
            if (ok) {
                return hex;
            }
        }
        return "invalid";
    }

    function emit(scheme, accent, motion) {
        console.warn("APPEARANCE scheme=" + scheme + " accent=" + accent + " motion=" + motion);
    }

    function publish() {
        const content = watcher.loaded ? watcher.text() : "";
        if (content === "" && !watcher.loaded) {
            root.emit("null", "null", "null");
            return;
        }
        let section = "";
        let scheme = "null";
        let accent = "null";
        let motion = "null";
        const lines = content.split(/\r?\n/);
        for (let index = 0; index < lines.length; index += 1) {
            const line = lines[index].trim();
            if (line === "" || line.startsWith("#")) {
                continue;
            }
            if (line.startsWith("[") && line.endsWith("]")) {
                section = line.slice(1, -1);
                continue;
            }
            const split = line.indexOf("=");
            if (split <= 0) {
                continue;
            }
            const key = line.slice(0, split).trim();
            const value = line.slice(split + 1).trim();
            if (section === "General" && key === "ColorScheme") {
                scheme = value;
            } else if (section === "General" && key === "AccentColor") {
                accent = root.canonicalAccent(value);
            } else if (section === "KDE" && key === "AnimationDurationFactor") {
                const number = Number(value);
                motion = Number.isFinite(number) && number >= 0 ? String(number) : "invalid";
            }
        }
        root.emit(scheme, accent, motion);
    }

    Timer {
        id: settle

        interval: 80
        onTriggered: root.publish()
    }

    FileView {
        id: watcher

        path: root.kdeGlobalsPath
        watchChanges: true
        preload: true
        printErrors: false

        onFileChanged: {
            root.changeEvents += 1;
            reload();
        }
        onLoaded: settle.restart()
        onLoadFailed: function (error) {
            if (error === FileViewError.FileNotFound) {
                settle.restart();
            } else {
                console.warn("APPEARANCE error=" + error);
            }
        }
    }

    Component.onCompleted: console.warn("PROBE READY path=" + root.kdeGlobalsPath)
}

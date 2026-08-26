pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

// One event-first KDE appearance boundary. Raw kdeglobals syntax and Qt palette
// types stay here; Theme receives one normalized immutable snapshot.
Scope {
    id: root

    property string configPath: ""
    readonly property string resolvedPath: configPath !== "" ? configPath : (Quickshell.env(
                                                                                 "XDG_CONFIG_HOME")
                                                                             ?? "") !== ""
                                                               ? Quickshell.env("XDG_CONFIG_HOME")
                                                                 + "/kdeglobals" : Quickshell.env(
                                                                     "HOME") + "/.config/kdeglobals"
    readonly property var snapshot: root._snapshot
    readonly property bool minimalMotion: snapshot.animationFactor <= 0
    property int _generation: 0
    property var _snapshot: Object.freeze({
                                              "accent": "#3DAEE9",
                                              "animationFactor": 1,
                                              "colorScheme": "light",
                                              "generation": 0,
                                              "schemeName": "BreezeLight",
                                              "surface": "#EFF0F1",
                                              "text": "#232629"
                                          })

    function canonicalColor(value) {
        const text = String(value);
        const match = text.match(/^#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$/);
        if (match === null || (match[2] !== undefined && match[2].toUpperCase() === "00")) {
            return null;
        }
        return "#" + match[1].toUpperCase();
    }

    function kConfigColor(value) {
        const text = String(value);
        if (/^#[0-9a-fA-F]{6}$/.test(text)) {
            return text.toUpperCase();
        }
        const channels = String(value).split(",");
        if (channels.length !== 3 && channels.length !== 4) {
            return null;
        }
        const values = [];
        for (let index = 0; index < channels.length; index += 1) {
            const channel = Number(channels[index].trim());
            if (!Number.isInteger(channel) || channel < 0 || channel > 255) {
                return null;
            }
            values.push(channel);
        }
        const alpha = values.length === 4 ? values[3] : 255;
        if (alpha === 0) {
            return null;
        }
        const rgb = values.slice(0, 3).map(channel => channel.toString(16).padStart(2,
                                                                                    "0").toUpperCase(
                                                          )).join("");
        return alpha === 255 ? "#" + rgb : "#" + alpha.toString(16).padStart(2, "0").toUpperCase()
                               + rgb;
    }

    function parse(content) {
        const result = {
            "accent": null,
            "animationFactor": 1,
            "schemeName": ""
        };
        if (typeof content !== "string" || content.length > 1048576) {
            return result;
        }
        let section = "";
        const lines = content.split(/\r?\n/);
        for (let index = 0; index < lines.length; index += 1) {
            const line = lines[index].trim();
            if (line === "" || line.startsWith("#") || line.startsWith(";")) {
                continue;
            }
            if (line.startsWith("[") && line.endsWith("]")) {
                section = line.slice(1, -1);
                continue;
            }
            const separator = line.indexOf("=");
            if (separator <= 0) {
                continue;
            }
            const key = line.slice(0, separator).trim();
            const value = line.slice(separator + 1).trim();
            if (section === "General" && key === "ColorScheme" && value.length <= 128 && !/[\x00-\x1F\x7F]/.test(
                        value)) {
                result.schemeName = value;
            } else if (section === "General" && key === "AccentColor") {
                result.accent = kConfigColor(value);
            } else if (section === "KDE" && key === "AnimationDurationFactor") {
                const factor = Number(value);
                if (value !== "" && Number.isFinite(factor)) {
                    result.animationFactor = factor;
                }
            }
        }
        return result;
    }

    function relativeLuminance(value) {
        function linear(channel) {
            const normalized = channel / 255;
            return normalized <= 0.04045 ? normalized / 12.92 : Math.pow((normalized + 0.055)
                                                                         / 1.055, 2.4);
        }
        const color = canonicalColor(value) ?? "#000000";
        return 0.2126 * linear(parseInt(color.slice(1, 3), 16)) + 0.7152 * linear(parseInt(color.slice(
                                                                                               3, 5), 16))
                + 0.0722 * linear(parseInt(color.slice(5, 7), 16));
    }

    function publish() {
        const parsed = parse(settings.loaded ? settings.text() : "");
        const surface = canonicalColor(systemPalette.window) ?? "#EFF0F1";
        const text = canonicalColor(systemPalette.windowText) ?? "#232629";
        const paletteAccent = canonicalColor(systemPalette.highlight) ?? "#3DAEE9";
        const candidate = {
            "accent": parsed.accent ?? paletteAccent,
            "animationFactor": parsed.animationFactor,
            "colorScheme": relativeLuminance(surface) < 0.45 ? "dark" : "light",
            "generation": root._generation + 1,
            "schemeName": parsed.schemeName,
            "surface": surface,
            "text": text
        };
        const current = Object.assign({}, root._snapshot);
        delete current.generation;
        const comparison = Object.assign({}, candidate);
        delete comparison.generation;
        if (JSON.stringify(current) === JSON.stringify(comparison)) {
            return;
        }
        root._generation += 1;
        candidate.generation = root._generation;
        root._snapshot = Object.freeze(candidate);
    }

    function schedulePublish() {
        publishTimer.restart();
    }

    SystemPalette {
        id: systemPalette

        colorGroup: SystemPalette.Active
        onHighlightChanged: root.schedulePublish()
        onWindowChanged: root.schedulePublish()
        onWindowTextChanged: root.schedulePublish()
    }

    Timer {
        id: publishTimer

        interval: 80
        onTriggered: root.publish()
    }

    FileView {
        id: settings

        path: root.resolvedPath
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.schedulePublish()
        onLoadFailed: root.schedulePublish()
    }

    Component.onCompleted: schedulePublish()
}

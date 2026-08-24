pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Strict, bounded user-configuration boundary. Consumers receive one frozen
// normalized snapshot and never parse theme.conf independently.
Singleton {
    id: root

    readonly property string configHome: {
        const xdgHome = Quickshell.env("XDG_CONFIG_HOME") ?? "";
        return xdgHome !== "" ? xdgHome : (Quickshell.env("HOME") ?? "") + "/.config";
    }
    readonly property string configDirectoryPath: configHome + "/nagi-shell"
    readonly property string configPath: configDirectoryPath + "/theme.conf"
    readonly property string defaultStagingPath: configDirectoryPath + "/.theme.conf.default-"
                                                 + Quickshell.processId
    readonly property int maximumConfigBytes: 4096
    readonly property int maximumFontFamilyBytes: 128
    readonly property int maximumDateFormatBytes: 64
    readonly property real minimumSurfaceOpacity: 0.85
    readonly property real maximumSurfaceOpacity: 1.0
    readonly property int minimumOuterRadius: 8
    readonly property int maximumOuterRadius: 32
    readonly property string defaultContent:
    "[theme]\nmode=wallpaper\naccent=#5B6FF5\nsurface_opacity=0.96\nfont_family=Inter\nouter_radius=16\n\n[media]\nenabled=true\n\n[weather]\nenabled=false\n; Find a city's coordinates:\n; https://nominatim.openstreetmap.org/ui/search.html\n; latitude=48.85\n; longitude=2.35\n\n[clock]\nformat=24h\ndate_format=dddd, d MMMM\nshow_idle_date=false\n"
    // Verification-only seam for unrelated harnesses that assert zero XDG writes.
    readonly property bool defaultCreationEnabled: Quickshell.env(
                                                       "NAGI_SKIP_DEFAULT_CONFIG_CREATION") !== "1"

    readonly property var snapshot: root._snapshot
    property var _snapshot: defaultSnapshot(1)
    property int _generation: 1
    property bool _initialLoadSettled: false
    property bool _defaultCreationPending: false
    property var _loggedFailures: ({})
    property bool _defaultDirectoryReady: false
    property bool _defaultCreationAttempted: false

    signal defaultCandidateStaged
    property bool _hasLoadedConfiguration: false

    function defaultSnapshot(generation) {
        return Object.freeze({
                                 "generation": generation,
                                 "theme": Object.freeze({
                                                            "mode": "wallpaper",
                                                            "configuredAccent": null,
                                                            "surfaceOpacity": 0.96,
                                                            "fontFamily": "Inter",
                                                            "outerRadius": 16
                                                        }),
                                 "media": Object.freeze({
                                                            "enabled": true
                                                        }),
                                 "weather": Object.freeze({
                                                              "enabled": false,
                                                              "latitude": null,
                                                              "longitude": null
                                                          }),
                                 "clock": Object.freeze({
                                                            "format": "24h",
                                                            "dateFormat": "dddd, d MMMM",
                                                            "showIdleDate": false
                                                        })
                             });
    }

    function utf8Length(value) {
        return unescape(encodeURIComponent(value)).length;
    }

    function canonicalHex(value) {
        return typeof value === "string" && /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(value)
                ? value.toUpperCase() : null;
    }

    function strictNumber(value) {
        if (typeof value !== "string" || !/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$/.test(value)) {
            return null;
        }
        const number = Number(value);
        return Number.isFinite(number) ? number : null;
    }

    function strictBoolean(value) {
        if (value === "true") {
            return true;
        }
        if (value === "false") {
            return false;
        }
        return null;
    }

    function parseConfiguration(content, byteLength) {
        if (typeof content !== "string" || !Number.isInteger(byteLength) || byteLength < 0 || byteLength
                > maximumConfigBytes || content.indexOf("\0") !== -1) {
            return null;
        }

        const allowed = {
            "theme": ["mode", "accent", "surface_opacity", "font_family", "outer_radius"],
            "media": ["enabled"],
            "weather": ["enabled", "latitude", "longitude"],
            "clock": ["format", "date_format", "show_idle_date"]
        };
        const sections = {};
        let currentSection = "";
        const lines = content.split(/\r?\n/);
        for (let index = 0; index < lines.length; index += 1) {
            const line = lines[index].trim();
            if (line === "" || line.startsWith(";")) {
                continue;
            }
            if (line.startsWith("[") && line.endsWith("]")) {
                const section = line.slice(1, -1);
                if (!Object.prototype.hasOwnProperty.call(allowed, section)
                        || Object.prototype.hasOwnProperty.call(sections, section)) {
                    return null;
                }
                sections[section] = {};
                currentSection = section;
                continue;
            }
            const separator = line.indexOf("=");
            if (currentSection === "" || separator <= 0) {
                return null;
            }
            const key = line.slice(0, separator).trim();
            const value = line.slice(separator + 1).trim();
            if (allowed[currentSection].indexOf(key) === -1 || value === ""
                    || Object.prototype.hasOwnProperty.call(sections[currentSection], key)) {
                return null;
            }
            sections[currentSection][key] = value;
        }

        if (!Object.prototype.hasOwnProperty.call(sections, "theme")) {
            return null;
        }
        const theme = sections.theme;
        if (theme.mode !== "wallpaper" && theme.mode !== "accent") {
            return null;
        }
        const accent = theme.accent === undefined ? null : canonicalHex(theme.accent);
        if ((theme.accent !== undefined && accent === null) || (theme.mode === "accent" && accent
                                                                === null)) {
            return null;
        }

        const opacity = theme.surface_opacity === undefined ? 0.96 : strictNumber(
                                                                  theme.surface_opacity);
        const radius = theme.outer_radius === undefined ? 16 : strictNumber(theme.outer_radius);
        const family = theme.font_family === undefined ? "Inter" : theme.font_family;
        if (opacity === null || opacity < minimumSurfaceOpacity || opacity > maximumSurfaceOpacity
                || radius === null || !Number.isInteger(radius) || radius < minimumOuterRadius
                || radius > maximumOuterRadius || family.length === 0 || utf8Length(family)
                > maximumFontFamilyBytes || /[\x00-\x1F\x7F]/.test(family)) {
            return null;
        }

        const mediaSection = sections.media ?? {};
        const mediaEnabled = mediaSection.enabled === undefined ? true : strictBoolean(
                                                                      mediaSection.enabled);
        const weatherSection = sections.weather ?? {};
        const weatherEnabled = weatherSection.enabled === undefined ? false : strictBoolean(
                                                                          weatherSection.enabled);
        const latitude = weatherSection.latitude === undefined ? null : strictNumber(
                                                                     weatherSection.latitude);
        const longitude = weatherSection.longitude === undefined ? null : strictNumber(
                                                                       weatherSection.longitude);
        if (mediaEnabled === null || weatherEnabled === null || (weatherSection.latitude
                                                                 !== undefined && latitude
                                                                 === null) || (
                    weatherSection.longitude !== undefined && longitude === null) || (latitude
                                                                                      !== null && (
                                                                                          latitude
                                                                                          < -90 || latitude
                                                                                          > 90)) || (
                    longitude !== null && (longitude < -180 || longitude > 180)) || (weatherEnabled
                                                                                     && (latitude
                                                                                         === null
                                                                                         || longitude
                                                                                         === null))) {
            return null;
        }

        const clockSection = sections.clock ?? {};
        const clockFormat = clockSection.format === undefined ? "24h" : clockSection.format;
        const dateFormat = clockSection.date_format === undefined ? "dddd, d MMMM" :
                                                                    clockSection.date_format;
        const showIdleDate = clockSection.show_idle_date === undefined ? false : strictBoolean(
                                                                             clockSection.show_idle_date);
        if ((clockFormat !== "12h" && clockFormat !== "24h") || dateFormat.length === 0 || utf8Length(
                    dateFormat) > maximumDateFormatBytes || /[\x00-\x1F\x7F]/.test(dateFormat)
                || showIdleDate === null) {
            return null;
        }

        return Object.freeze({
                                 "generation": 0,
                                 "theme": Object.freeze({
                                                            "mode": theme.mode,
                                                            "configuredAccent": accent,
                                                            "surfaceOpacity": opacity,
                                                            "fontFamily": family,
                                                            "outerRadius": radius
                                                        }),
                                 "media": Object.freeze({
                                                            "enabled": mediaEnabled
                                                        }),
                                 "weather": Object.freeze({
                                                              "enabled": weatherEnabled,
                                                              "latitude": latitude,
                                                              "longitude": longitude
                                                          }),
                                 "clock": Object.freeze({
                                                            "format": clockFormat,
                                                            "dateFormat": dateFormat,
                                                            "showIdleDate": showIdleDate
                                                        })
                             });
    }

    function publish(candidate) {
        if (candidate === null) {
            return false;
        }
        const currentKey = JSON.stringify(root._snapshot, function (key, value) {
            return key === "generation" ? undefined : value;
        });
        const candidateKey = JSON.stringify(candidate, function (key, value) {
            return key === "generation" ? undefined : value;
        });
        if (candidateKey === currentKey) {
            return true;
        }
        root._generation += 1;
        root._snapshot = Object.freeze(Object.assign({}, candidate, {
                                                         "generation": root._generation
                                                     }));
        return true;
    }

    function applyLoadedConfiguration() {
        root._defaultCreationPending = false;
        const data = configFile.data();
        const byteLength = data !== null && typeof data.byteLength === "number" ? data.byteLength :
                                                                                  utf8Length(
                                                                                      configFile.text(
                                                                                          ));
        const candidate = parseConfiguration(configFile.text(), byteLength);
        root._initialLoadSettled = true;
        if (candidate === null) {
            warnOnce(byteLength > maximumConfigBytes ? "oversized" : "malformed", byteLength
                     > maximumConfigBytes ? "configuration exceeds 4 KiB" :
                                            "configuration is malformed");
            return;
        }
        publish(candidate);
        root._hasLoadedConfiguration = true;
    }

    function createDefault() {
        if (_defaultCreationPending || _defaultCreationAttempted || configDirectoryPath === "") {
            return;
        }
        _defaultCreationAttempted = true;
        _defaultCreationPending = true;
        if (_defaultDirectoryReady) {
            defaultStagingFile.setText(defaultContent);
        } else {
            directoryCreator.running = true;
        }
    }
    function warnOnce(kind, message) {
        if (_loggedFailures[kind] === true) {
            return;
        }
        _loggedFailures[kind] = true;
        console.warn("Nagi configuration: " + message + "; preserving the last valid snapshot");
    }

    FileView {
        id: configFile
        path: root.configPath
        watchChanges: true
        preload: true
        atomicWrites: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.applyLoadedConfiguration()
        onLoadFailed: function (error) {
            root._initialLoadSettled = true;
            if (error === FileViewError.FileNotFound) {
                if (root.defaultCreationEnabled && !root._hasLoadedConfiguration &&
                        !root._defaultCreationAttempted) {
                    root.createDefault();
                } else if (!root._defaultCreationPending) {
                    root.warnOnce("unavailable", "configuration is unavailable");
                }
            } else {
                root.warnOnce("unavailable", "configuration is unavailable");
            }
        }
    }

    FileView {
        id: defaultStagingFile

        path: root.defaultStagingPath
        atomicWrites: true
        printErrors: false
        onSaved: {
            root.defaultCandidateStaged();
            if (root._defaultCreationPending) {
                defaultInstaller.running = true;
            } else {
                defaultCleanup.running = true;
            }
        }
        onSaveFailed: function (error) {
            root._defaultCreationPending = false;
            root.warnOnce("create", "default configuration candidate could not be written");
        }
    }

    FileView {
        id: configDirectoryWatcher
        path: root.configDirectoryPath
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: {
            configFile.watchChanges = false;
            configFile.watchChanges = true;
            configFile.reload();
        }
    }

    Process {
        id: directoryCreator
        command: ["mkdir", "-p", "--", root.configDirectoryPath]
        onExited: function (exitCode) {
            if (!root._defaultCreationPending) {
                return;
            }
            if (exitCode === 0) {
                root._defaultDirectoryReady = true;
                defaultStagingFile.setText(root.defaultContent);
            } else {
                root._defaultCreationPending = false;
                root.warnOnce("create", "default configuration directory could not be created");
            }
        }
    }

    Process {
        id: defaultInstaller
        command: ["ln", "--", root.defaultStagingPath, root.configPath]
        onExited: function (exitCode) {
            defaultCleanup.running = true;
        }
    }

    Process {
        id: defaultCleanup
        command: ["rm", "-f", "--", root.defaultStagingPath]
        onExited: function (exitCode) {
            root._defaultCreationPending = false;
            configFile.reload();
        }
    }
}

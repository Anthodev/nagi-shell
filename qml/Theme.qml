pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The presentation-wide design-system boundary. Configuration and palette
// changes publish one frozen snapshot so consumers never observe half-derived
// colors. Fixed semantic roles remain independent from the accent source.
Singleton {
    id: root

    readonly property string configHome: {
        const xdgHome = Quickshell.env("XDG_CONFIG_HOME") ?? "";
        return xdgHome !== "" ? xdgHome : (Quickshell.env("HOME") ?? "") + "/.config";
    }
    readonly property string configDirectoryPath: configHome + "/nagi-shell"
    readonly property string configPath: configDirectoryPath + "/theme.conf"
    // Strict, bounded INI contract:
    //   [theme]
    //   mode=wallpaper|accent
    //   accent=#RRGGBB|#AARRGGBB
    // Accent is required in fixed mode and optional as wallpaper-mode fallback.
    // The injected wallpaper adapter publishes { accent: "#RRGGBB" } here only
    // for a validated Ready snapshot and clears the seam on every failure state.
    property var wallpaperPalette: null
    readonly property var snapshot: root._snapshot

    readonly property int maximumConfigBytes: 4096
    readonly property string officialAccent: "#5B6FF5"
    property var _configuration: Object.freeze({
                                                   "mode": "wallpaper",
                                                   "configuredAccent": null
                                               })
    property int _generation: 1
    property var _snapshot: buildSnapshot(_configuration)
    property string _snapshotKey: ""
    property bool _initialized: false
    property var _loggedFailures: ({})

    function canonicalHex(value) {
        if (typeof value !== "string" || !/^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(value)) {
            return null;
        }
        return value.toUpperCase();
    }

    function rgb(hex) {
        const canonical = canonicalHex(hex);
        if (canonical === null) {
            return null;
        }
        const hasAlpha = canonical.length === 9;
        const offset = hasAlpha ? 3 : 1;
        const alpha = hasAlpha ? parseInt(canonical.slice(1, 3), 16) / 255 : 1;
        const foreground = {
            "r": parseInt(canonical.slice(offset, offset + 2), 16),
            "g": parseInt(canonical.slice(offset + 2, offset + 4), 16),
            "b": parseInt(canonical.slice(offset + 4, offset + 6), 16)
        };
        if (alpha === 1) {
            return foreground;
        }
        const background = {
            "r": 8,
            "g": 13,
            "b": 22
        };
        return {
            "r": Math.round(foreground.r * alpha + background.r * (1 - alpha)),
            "g": Math.round(foreground.g * alpha + background.g * (1 - alpha)),
            "b": Math.round(foreground.b * alpha + background.b * (1 - alpha))
        };
    }

    function hexByte(value) {
        return Math.max(0, Math.min(255, Math.round(value))).toString(16).padStart(2,
                                                                                   "0").toUpperCase(
                    );
    }

    function hex(value) {
        return "#" + hexByte(value.r) + hexByte(value.g) + hexByte(value.b);
    }

    function mix(first, second, amount) {
        const a = typeof first === "string" ? rgb(first) : first;
        const b = typeof second === "string" ? rgb(second) : second;
        return {
            "r": a.r + (b.r - a.r) * amount,
            "g": a.g + (b.g - a.g) * amount,
            "b": a.b + (b.b - a.b) * amount
        };
    }

    function linearChannel(channel) {
        const value = channel / 255;
        return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
    }

    function luminance(value) {
        const color = typeof value === "string" ? rgb(value) : value;
        return 0.2126 * linearChannel(color.r) + 0.7152 * linearChannel(color.g) + 0.0722
                * linearChannel(color.b);
    }

    function contrast(first, second) {
        const firstLuminance = luminance(first);
        const secondLuminance = luminance(second);
        return (Math.max(firstLuminance, secondLuminance) + 0.05) / (Math.min(firstLuminance,
                                                                              secondLuminance)
                                                                     + 0.05);
    }

    function ensureContrast(candidate, background, floor, toward) {
        let result = typeof candidate === "string" ? rgb(candidate) : candidate;
        if (contrast(result, background) >= floor) {
            return result;
        }
        const target = typeof toward === "string" ? rgb(toward) : toward;
        for (let step = 1; step <= 32; step += 1) {
            const adjusted = mix(result, target, step / 32);
            if (contrast(adjusted, background) >= floor) {
                return adjusted;
            }
        }
        return target;
    }

    function chooseForeground(backgrounds) {
        const dark = "#080D16";
        const light = "#F1F5FA";
        let darkFloor = Number.POSITIVE_INFINITY;
        let lightFloor = Number.POSITIVE_INFINITY;
        for (let index = 0; index < backgrounds.length; index += 1) {
            darkFloor = Math.min(darkFloor, contrast(dark, backgrounds[index]));
            lightFloor = Math.min(lightFloor, contrast(light, backgrounds[index]));
        }
        return darkFloor >= lightFloor ? dark : light;
    }

    function validWallpaperAccent() {
        if (root.wallpaperPalette === null || typeof root.wallpaperPalette !== "object") {
            return null;
        }
        return canonicalHex(root.wallpaperPalette.accent);
    }

    function buildSnapshot(configuration) {
        const wallpaperAccent = configuration.mode === "wallpaper" ? validWallpaperAccent() : null;
        const candidates = [];
        if (wallpaperAccent !== null) {
            candidates.push({
                                "accent": wallpaperAccent,
                                "source": "wallpaper"
                            });
        }
        if (configuration.configuredAccent !== null) {
            candidates.push({
                                "accent": configuration.configuredAccent,
                                "source": "configured"
                            });
        }
        candidates.push({
                            "accent": root.officialAccent,
                            "source": "fallback"
                        });

        for (let index = 0; index < candidates.length; index += 1) {
            const snapshot = deriveSnapshot(configuration, candidates[index].accent,
                                            candidates[index].source, wallpaperAccent);
            if (snapshot !== null) {
                return snapshot;
            }
        }
        return null;
    }

    function deriveSnapshot(configuration, selected, source, wallpaperAccent) {
        const surfaceBase = "#080D16";
        const progressTrack = "#1C2836";
        const primaryRgb = ensureContrast(rgb(selected), surfaceBase, 4.5, "#FFFFFF");
        const primary = hex(primaryRgb);
        const hover = hex(ensureContrast(mix(primaryRgb, "#FFFFFF", 0.18), surfaceBase, 4.5,
                                         "#FFFFFF"));

        const pressed = hex(ensureContrast(mix(primaryRgb, surfaceBase, 0.10), surfaceBase, 4.5,
                                           "#FFFFFF"));
        const focusRing = hex(ensureContrast(mix(primaryRgb, "#FFFFFF", 0.24), surfaceBase, 3,
                                             "#FFFFFF"));
        const progressFill = hex(ensureContrast(primaryRgb, progressTrack, 3, "#FFFFFF"));
        const foreground = chooseForeground([primary, hover, pressed]);
        const surfaceHover = hex(ensureContrast(mix(surfaceBase, primaryRgb, 0.10), surfaceBase,
                                                1.08, primaryRgb));
        const surfaceActive = hex(ensureContrast(mix(surfaceBase, primaryRgb, 0.18), surfaceBase,
                                                 1.16, primaryRgb));
        const controlFill = "#16222F";
        const controlFillHover = hex(mix(controlFill, primaryRgb, 0.12));
        const controlFillPressed = hex(mix(controlFill, primaryRgb, 0.20));
        const border = "#263448";
        const borderHover = hex(ensureContrast(mix(border, primaryRgb, 0.28), surfaceBase, 3,
                                               "#FFFFFF"));
        const borderPressed = hex(ensureContrast(mix(border, primaryRgb, 0.42), surfaceBase, 3,
                                                 "#FFFFFF"));
        const ratios = Object.freeze({
                                         "accentOnSurface": contrast(primary, surfaceBase),
                                         "accentForeground": Math.min(contrast(foreground, primary),
                                                                      contrast(foreground, hover),
                                                                      contrast(foreground, pressed)),
                                         "focusRingOnSurface": contrast(focusRing, surfaceBase),
                                         "progressOnTrack": contrast(progressFill, progressTrack),
                                         "surfaceHoverOnBase": contrast(surfaceHover, surfaceBase),
                                         "surfaceActiveOnBase": contrast(surfaceActive, surfaceBase)
                                     });
        if (ratios.accentOnSurface < 3 || ratios.accentForeground < 4.5
                || ratios.focusRingOnSurface < 3 || ratios.progressOnTrack < 3
                || ratios.surfaceHoverOnBase < 1.08 || ratios.surfaceActiveOnBase < 1.16) {
            return null;
        }
        return Object.freeze({
                                 "generation": root._generation,
                                 "mode": configuration.mode,
                                 "source": source,
                                 "configuredAccent": configuration.configuredAccent,
                                 "wallpaperAccent": wallpaperAccent,
                                 "accent": primary,
                                 "accentHover": hover,
                                 "accentPressed": pressed,
                                 "accentForeground": foreground,
                                 "focusRing": focusRing,
                                 "progressFill": progressFill,
                                 "surfaceHover": surfaceHover,
                                 "surfaceActive": surfaceActive,
                                 "controlFillHover": controlFillHover,
                                 "controlFillPressed": controlFillPressed,
                                 "surfaceBorderHover": borderHover,
                                 "surfaceBorderPressed": borderPressed,
                                 "contrast": ratios
                             });
    }

    function snapshotKey(candidate) {
        if (candidate === null) {
            return "";
        }
        const copy = {};
        for (const key in candidate) {
            if (key !== "generation") {
                copy[key] = candidate[key];
            }
        }
        return JSON.stringify(copy);
    }

    function publish(configuration) {
        const candidate = buildSnapshot(configuration);
        if (candidate === null) {
            warnOnce("derived-contrast", "derived palette did not meet contrast floors");
            return false;
        }
        const key = snapshotKey(candidate);
        if (key === root._snapshotKey) {
            return true;
        }
        root._generation += 1;
        const published = Object.assign({}, candidate, {
                                            "generation": root._generation
                                        });
        root._snapshot = Object.freeze(published);
        root._snapshotKey = key;
        return true;
    }

    function parseConfiguration(content, byteLength) {
        if (typeof content !== "string" || byteLength > root.maximumConfigBytes || content.indexOf(
                    "\0") !== -1) {
            return null;
        }
        let inTheme = false;
        let sawTheme = false;
        const values = {};
        const lines = content.split(/\r?\n/);
        for (let index = 0; index < lines.length; index += 1) {
            const line = lines[index].trim();
            if (line === "" || line.startsWith(";")) {
                continue;
            }
            if (line.startsWith("[") && line.endsWith("]")) {
                if (line !== "[theme]" || sawTheme) {
                    return null;
                }
                inTheme = true;
                sawTheme = true;
                continue;
            }
            const separator = line.indexOf("=");
            if (!inTheme || separator <= 0) {
                return null;
            }
            const key = line.slice(0, separator).trim();
            const value = line.slice(separator + 1).trim();
            if ((key !== "mode" && key !== "accent") || Object.prototype.hasOwnProperty.call(values,
                                                                                             key) || value
                    === "") {
                return null;
            }
            values[key] = value;
        }
        if (!sawTheme || (values.mode !== "wallpaper" && values.mode !== "accent")) {
            return null;
        }
        const configuredAccent = values.accent === undefined ? null : canonicalHex(values.accent);
        if ((values.accent !== undefined && configuredAccent === null) || (values.mode === "accent"
                                                                           && configuredAccent
                                                                           === null)) {
            return null;
        }
        return Object.freeze({
                                 "mode": values.mode,
                                 "configuredAccent": configuredAccent
                             });
    }

    function applyLoadedConfiguration() {
        const data = configFile.data();
        const byteLength = data !== null && typeof data.byteLength === "number" ? data.byteLength :
                                                                                  configFile.text(
                                                                                      ).length;
        const configuration = parseConfiguration(configFile.text(), byteLength);
        if (configuration === null) {
            warnOnce(byteLength > root.maximumConfigBytes ? "oversized" : "malformed", byteLength
                     > root.maximumConfigBytes ? "theme configuration exceeds 4 KiB" :
                                                 "theme configuration is malformed");
            return;
        }
        root._configuration = configuration;
        publish(configuration);
    }

    function warnOnce(kind, message) {
        if (root._loggedFailures[kind] === true) {
            return;
        }
        root._loggedFailures[kind] = true;
        console.warn("Nagi Theme: " + message + "; preserving the last valid snapshot");
    }

    Component.onCompleted: {
        // Break the initial QML bindings: subsequent updates are imperative,
        // validated publications rather than dependency-by-dependency churn.
        const initial = root._snapshot;
        root._snapshot = initial;
        root._snapshotKey = snapshotKey(initial);
        root._initialized = true;
    }

    onWallpaperPaletteChanged: {
        if (root._initialized) {
            publish(root._configuration);
        }
    }

    FileView {
        id: configFile

        path: root.configPath
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.applyLoadedConfiguration()
        onLoadFailed: function (error) {
            root.warnOnce("unavailable", "theme configuration is unavailable");
        }
    }

    // FileView watches a missing file only when its parent exists. This
    // one-shot parent watcher covers first-time creation of nagi-shell/ and
    // then retires; steady-state changes remain owned by configFile.
    FileView {
        id: configDirectoryWatcher

        path: root.configDirectoryPath
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: {
            path = "";
            configFile.watchChanges = false;
            configFile.watchChanges = true;
            configFile.reload();
        }
        onLoadFailed: function (error) {
            if (error === FileViewError.NotAFile) {
                path = "";
            }
        }
    }

    readonly property QtObject color: QtObject {
        readonly property color surface: "#F5080D16"
        readonly property color surfaceBorder: "#263448"
        readonly property color controlFill: "#16222F"
        readonly property color textPrimary: "#EFF3F8"
        readonly property color textSecondary: "#B9C4D2"
        readonly property color textMuted: "#8494A6"
        readonly property color danger: "#F26D7E"
        readonly property color dangerFill: "#21171B"
        readonly property color dangerFillHover: "#321B22"
        readonly property color dangerFillPressed: "#43202A"
        readonly property color success: "#7BD88F"
        readonly property color warning: "#E8C268"
        readonly property color progressTrack: "#1C2836"
        readonly property color surfaceHover: root.snapshot.surfaceHover
        readonly property color surfaceActive: root.snapshot.surfaceActive
        readonly property color progressFill: root.snapshot.progressFill
    }

    readonly property QtObject spacing: QtObject {
        readonly property int xs: 4
        readonly property int sm: 8
        readonly property int md: 12
        readonly property int lg: 16
        readonly property int xl: 24
        readonly property int xxl: 32
    }

    readonly property QtObject radius: QtObject {
        // A 16 px outer radius reads as softly rectangular at both compact and
        // expanded scales. Inner radii subtract optical insets, not percentages.
        readonly property int outer: 16
        readonly property int sm: 6
        readonly property int md: 10
        readonly property int lg: 12
        readonly property int xl: 16
    }

    // Locked from the live issue-63 matrix. QML sets the primary family; the
    // deployment fallback chain is "Inter" -> "Noto Sans" -> "DejaVu Sans" -> sans-serif.
    // Fontconfig resolves unavailable faces and scripts.
    readonly property QtObject type: QtObject {
        readonly property string family: "Inter"
        readonly property int caption: 11
        readonly property int display: 48
        readonly property int body: 13
        readonly property int title: 15
        readonly property int weightRegular: Font.Normal
        readonly property int weightMedium: Font.Medium
        readonly property int weightSemibold: Font.DemiBold
    }

    readonly property QtObject size: QtObject {
        readonly property int islandIdleWidth: 120
        readonly property int islandIdleHeight: 46
        readonly property int islandWorkspaceIndicatorWidth: 28
        readonly property int islandWorkspaceIndicatorHeight: 22
        readonly property int islandSeparatorHeight: 18
        readonly property int audioEmptyContentMinimumWidth: 192
        readonly property int islandIdleMediaMaximumWidth: 220
        readonly property int islandTransientCompactWidth: 340
        // 288 px gives 13 px Inter labels and the icon/value/bar composition
        // a stable 256 px inner lane while retaining the 340 px compact cap.
        readonly property int islandTransientCompactMinimumWidth: 288
        readonly property int islandTransientCompactHeight: 56
        readonly property int islandTransientNotificationWidth: 420
        readonly property int islandTransientNotificationHeight: 72
        readonly property int islandTransientValueMaximumWidth: 96
        readonly property int controlHeightSm: 26
        readonly property int controlHeightMd: 32
        readonly property int controlHeightLg: 38
        readonly property int iconSizeSm: 14
        readonly property int iconSizeMd: 18
        readonly property int iconSizeLg: 22
        readonly property int progressBarHeight: 4
        readonly property real progressIndeterminateSpan: 0.28
        readonly property int focusRingWidth: 2
        readonly property int focusRingGap: 2
        readonly property int hairlineWidth: 1
    }

    readonly property QtObject opacity: QtObject {
        readonly property real surface: 0.96
        readonly property real disabled: 0.45
        readonly property real shadow: 0.28
    }

    readonly property QtObject elevation: QtObject {
        readonly property color shadowColor: "#000000"
        readonly property int shadowRadius: 22
        readonly property int shadowVerticalOffset: 8
        readonly property int shadowSamples: 17
    }

    readonly property QtObject motion: QtObject {
        readonly property int durationFast: 100
        readonly property int durationNormal: 180
        readonly property int durationSlow: 280
        readonly property int durationExpansion: 300
        readonly property int expansionAnchor: Qt.AlignTop
        readonly property int easingStandard: Easing.OutCubic
        readonly property int easingExpansion: Easing.OutCubic
    }
}

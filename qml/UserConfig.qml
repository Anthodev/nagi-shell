pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// One strict, versioned settings boundary. Presentation and services consume
// immutable normalized snapshots; filesystem content never leaks past here.
Singleton {
    id: root

    readonly property int schemaVersion: 2
    readonly property int maximumConfigBytes: 32768
    readonly property int maximumFontFamilyBytes: 128
    readonly property int maximumDateFormatBytes: 64
    readonly property int maximumPreferredApplicationBytes: 256
    readonly property var allowedDateFormats: Object.freeze(["dddd, d MMMM", "ddd, d MMM",
                                                             "yyyy-MM-dd", "MM/dd/yyyy",
                                                             "dd/MM/yyyy"])
    readonly property int maximumLocationLabelBytes: 128
    readonly property int maximumWallpaperRoots: 8
    readonly property int maximumWallpaperRootBytes: 1024
    readonly property real minimumSurfaceOpacity: 0.85
    readonly property real maximumSurfaceOpacity: 1.0
    readonly property int minimumOuterRadius: 8
    readonly property int maximumOuterRadius: 32

    readonly property string configHome: {
        const xdgHome = Quickshell.env("XDG_CONFIG_HOME") ?? "";
        return xdgHome !== "" ? xdgHome : (Quickshell.env("HOME") ?? "") + "/.config";
    }
    readonly property string configDirectoryPath: configHome + "/nagi-shell"
    readonly property string configPath: configDirectoryPath + "/settings.conf"
    readonly property string lastGoodPath: configDirectoryPath + "/settings.conf.last-good"
    readonly property string legacyPath: configDirectoryPath + "/theme.conf"
    readonly property string migrationBackupPath: configDirectoryPath + "/settings.conf.bak"
    readonly property string invalidBackupPath: configDirectoryPath + "/settings.conf.invalid"
    readonly property string helperPath: Quickshell.env("NAGI_SETTINGS_HELPER")
                                         ?? Quickshell.shellPath("build/nagi-settings")
    // Verification-only seam for harnesses that assert zero XDG writes.
    readonly property bool defaultCreationEnabled: Quickshell.env(
                                                       "NAGI_SKIP_DEFAULT_CONFIG_CREATION") !== "1"

    readonly property var snapshot: root._snapshot
    readonly property bool writable: root._writerReady && !root.readOnly && (root.status === "ready"
                                                                             || root.status
                                                                             === "write-failed")
    readonly property bool recoveryRequired: root.status === "recovery"
    property string status: "loading"
    property string recoveryKind: ""
    property string errorMessage: ""
    property bool readOnly: false

    property var _snapshot: defaultSnapshot(1)
    property var _persistedSnapshot: defaultSnapshot(1)
    property var _lastGoodSnapshot: null
    property var _writeCandidate: null
    property var _inFlightCandidate: null
    property var _pendingLastGoodSnapshot: null
    property string _writePurpose: ""
    property string _pendingOperation: ""
    property string _pendingPayload: ""
    property string _ownWriteCanonical: ""
    property bool _writeInProgress: false
    property bool _writerReady: false
    property int _generation: 1
    property bool _initializing: true
    property bool _hasLoadedConfiguration: false
    property bool _hasPersistedConfiguration: false
    property var _loggedFailures: ({})

    readonly property string defaultContent: serializeConfiguration(defaultSnapshot(0))

    function defaultSnapshot(generation) {
        return freezeSnapshot({
                                  "generation": generation,
                                  "schemaVersion": schemaVersion,
                                  "appearance": {
                                      "scheme": "nagi-dark",
                                      "accentMode": "wallpaper",
                                      "customSurface": "#080D16",
                                      "customText": "#EFF3F8",
                                      "customAccent": "#5B6FF5",
                                      "surfaceOpacity": 0.96,
                                      "borderIntensity": 0,
                                      "blurEnabled": false,
                                      "motion": "full",
                                      "fontFamily": "Inter",
                                      "outerRadius": 16
                                  },
                                  "island": {
                                      "compactHeight": 46,
                                      "compactPadding": 24,
                                      "expandedWidthPercent": 1,
                                      "expandedHeightPercent": 1,
                                      "showWorkspace": true,
                                      "showWeather": true,
                                      "showMedia": true,
                                      "feedbackDuration": "normal",
                                      "gamingIndicator": true
                                  },
                                  "clock": {
                                      "format": "24h",
                                      "showSeconds": false,
                                      "dateFormat": "dddd, d MMMM",
                                      "showIdleDate": false
                                  },
                                  "media": {
                                      "enabled": true,
                                      "compactVisible": true,
                                      "dashboardVisible": true,
                                      "playerPolicy": "automatic",
                                      "preferredApplication": ""
                                  },
                                  "notifications": {
                                      "popupsEnabled": true,
                                      "doNotDisturb": false,
                                      "criticalMode": "bypass",
                                      "dashboardVisible": true,
                                      "historyVisible": true
                                  },
                                  "weather": {
                                      "enabled": false,
                                      "consent": false,
                                      "locationLabel": "",
                                      "latitude": null,
                                      "longitude": null,
                                      "temperatureUnit": "auto",
                                      "windUnit": "auto",
                                      "refreshPreset": "1h"
                                  },
                                  "wallpaper": {
                                      "roots": []
                                  }
                              });
    }

    function freezeSnapshot(candidate) {
        const result = {
            "generation": candidate.generation ?? 0,
            "schemaVersion": schemaVersion,
            "appearance": Object.freeze(Object.assign({}, candidate.appearance)),
            "island": Object.freeze(Object.assign({}, candidate.island)),
            "clock": Object.freeze(Object.assign({}, candidate.clock)),
            "media": Object.freeze(Object.assign({}, candidate.media)),
            "notifications": Object.freeze(Object.assign({}, candidate.notifications)),
            "weather": Object.freeze(Object.assign({}, candidate.weather)),
            "wallpaper": Object.freeze({
                                           "roots": Object.freeze(candidate.wallpaper.roots.slice())
                                       })
        };
        return Object.freeze(result);
    }

    function mutableSnapshot(source) {
        return {
            "generation": 0,
            "schemaVersion": schemaVersion,
            "appearance": Object.assign({}, source.appearance),
            "island": Object.assign({}, source.island),
            "clock": Object.assign({}, source.clock),
            "media": Object.assign({}, source.media),
            "notifications": Object.assign({}, source.notifications),
            "weather": Object.assign({}, source.weather),
            "wallpaper": {
                "roots": source.wallpaper.roots.slice()
            }
        };
    }

    function utf8Length(value) {
        return unescape(encodeURIComponent(value)).length;
    }

    function canonicalHex(value, allowAlpha) {
        const pattern = allowAlpha ? /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/ : /^#[0-9a-fA-F]{6}$/;
        return typeof value === "string" && pattern.test(value) ? value.toUpperCase() : null;
    }
    function colorChannels(value, background) {
        const canonical = canonicalHex(value, true);
        if (canonical === null) {
            return null;
        }
        const hasAlpha = canonical.length === 9;
        const offset = hasAlpha ? 3 : 1;
        const foreground = {
            "r": parseInt(canonical.slice(offset, offset + 2), 16),
            "g": parseInt(canonical.slice(offset + 2, offset + 4), 16),
            "b": parseInt(canonical.slice(offset + 4, offset + 6), 16)
        };
        if (!hasAlpha) {
            return foreground;
        }
        const base = colorChannels(background, "#080D16");
        const alpha = parseInt(canonical.slice(1, 3), 16) / 255;
        return {
            "r": foreground.r * alpha + base.r * (1 - alpha),
            "g": foreground.g * alpha + base.g * (1 - alpha),
            "b": foreground.b * alpha + base.b * (1 - alpha)
        };
    }

    function colorLuminance(value, background) {
        function linear(channel) {
            const normalized = channel / 255;
            return normalized <= 0.04045 ? normalized / 12.92 : Math.pow((normalized + 0.055)
                                                                         / 1.055, 2.4);
        }
        const color = colorChannels(value, background);
        return color === null ? Number.NaN : 0.2126 * linear(color.r) + 0.7152 * linear(color.g)
                                + 0.0722 * linear(color.b);
    }

    function colorContrast(first, second) {
        const firstLuminance = colorLuminance(first, second);
        const secondLuminance = colorLuminance(second, first);
        return (Math.max(firstLuminance, secondLuminance) + 0.05) / (Math.min(firstLuminance,
                                                                              secondLuminance)
                                                                     + 0.05);
    }

    function appearanceValidationError(appearance) {
        if (appearance.scheme === "custom" && colorContrast(appearance.customText,
                                                            appearance.customSurface) < 4.5) {
            return "Primary text must keep at least 4.5:1 contrast with the custom surface.";
        }
        return "";
    }

    function strictNumber(value) {
        if (typeof value !== "string" || !/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$/.test(value)) {
            return null;
        }
        const number = Number(value);
        return Number.isFinite(number) ? number : null;
    }

    function strictBoolean(value) {
        return value === "true" ? true : value === "false" ? false : null;
    }

    function boundedString(value, maximumBytes, allowEmpty) {
        return typeof value === "string" && (allowEmpty || value.length > 0) && utf8Length(value)
                <= maximumBytes && !/[\x00-\x1F\x7F]/.test(value);
    }

    function oneOf(value, values) {
        return values.indexOf(value) !== -1;
    }

    function validateCandidate(candidate) {
        if (candidate === null || typeof candidate !== "object") {
            return null;
        }
        const appearance = candidate.appearance;
        const island = candidate.island;
        const clock = candidate.clock;
        const media = candidate.media;
        const notifications = candidate.notifications;
        const weather = candidate.weather;
        const wallpaper = candidate.wallpaper;
        if (!appearance || !island || !clock || !media || !notifications || !weather ||
                !wallpaper) {

            return null;
        }

        const customSurface = canonicalHex(appearance.customSurface, false);
        const customText = canonicalHex(appearance.customText, false);
        const customAccent = canonicalHex(appearance.customAccent, true);
        if (customSurface === null || customText === null || customAccent === null) {
            return null;
        }
        appearance.customSurface = customSurface;
        appearance.customText = customText;
        appearance.customAccent = customAccent;
        if (appearanceValidationError(appearance) !== "") {
            return null;
        }
        if (!oneOf(appearance.scheme, ["nagi-dark", "nagi-oled", "nagi-light", "system", "custom"])
                || !oneOf(appearance.accentMode, ["nagi", "system", "wallpaper", "custom"])
                || typeof appearance.surfaceOpacity !== "number" || !Number.isFinite(
                    appearance.surfaceOpacity) || appearance.surfaceOpacity < minimumSurfaceOpacity
                || appearance.surfaceOpacity > maximumSurfaceOpacity
                || typeof appearance.borderIntensity !== "number" || !Number.isFinite(
                    appearance.borderIntensity) || appearance.borderIntensity < 0
                || appearance.borderIntensity > 1 || typeof appearance.blurEnabled !== "boolean" ||
                !oneOf(appearance.motion, ["full", "reduced", "minimal"]) || !boundedString(
                    appearance.fontFamily, maximumFontFamilyBytes, false) || !Number.isInteger(
                    appearance.outerRadius) || appearance.outerRadius < minimumOuterRadius
                || appearance.outerRadius > maximumOuterRadius) {
            return null;
        }

        if (!Number.isInteger(island.compactHeight) || island.compactHeight < 44
                || island.compactHeight > 48 || !Number.isInteger(island.compactPadding)
                || island.compactPadding < 16 || island.compactPadding > 32
                || typeof island.expandedWidthPercent !== "number" || !Number.isFinite(
                    island.expandedWidthPercent) || island.expandedWidthPercent < 0.6
                || island.expandedWidthPercent > 1 || typeof island.expandedHeightPercent
                !== "number" || !Number.isFinite(island.expandedHeightPercent)
                || island.expandedHeightPercent < 0.6 || island.expandedHeightPercent > 1
                || typeof island.showWorkspace !== "boolean" || typeof island.showWeather
                !== "boolean" || typeof island.showMedia !== "boolean" || !oneOf(
                    island.feedbackDuration, ["short", "normal", "long"])
                || typeof island.gamingIndicator !== "boolean") {
            return null;
        }

        if (!oneOf(clock.format, ["auto", "12h", "24h"]) || typeof clock.showSeconds !== "boolean"
                || !boundedString(clock.dateFormat, maximumDateFormatBytes, false) || !oneOf(
                    clock.dateFormat, allowedDateFormats) || typeof clock.showIdleDate
                !== "boolean") {
            return null;
        }
        if (typeof media.enabled !== "boolean" || typeof media.compactVisible !== "boolean"
                || typeof media.dashboardVisible !== "boolean" || !oneOf(media.playerPolicy,
                                                                         ["automatic",
                                                                          "preferred"]) ||
                !boundedString(media.preferredApplication, maximumPreferredApplicationBytes, true)
                || (media.playerPolicy === "preferred" && media.preferredApplication === "")) {
            return null;
        }
        if (typeof notifications.popupsEnabled !== "boolean" || typeof notifications.doNotDisturb
                !== "boolean" || !oneOf(notifications.criticalMode, ["bypass", "silence"])
                || typeof notifications.dashboardVisible !== "boolean"
                || typeof notifications.historyVisible !== "boolean") {
            return null;
        }
        const latitudeValid = weather.latitude === null || (typeof weather.latitude === "number"
                                                            && Number.isFinite(weather.latitude)
                                                            && weather.latitude >= -90
                                                            && weather.latitude <= 90);
        const longitudeValid = weather.longitude === null || (typeof weather.longitude === "number"
                                                              && Number.isFinite(weather.longitude)
                                                              && weather.longitude >= -180
                                                              && weather.longitude <= 180);
        if (typeof weather.enabled !== "boolean" || typeof weather.consent !== "boolean" ||
                !boundedString(weather.locationLabel, maximumLocationLabelBytes, true) ||
                !latitudeValid || !longitudeValid || !oneOf(weather.temperatureUnit, ["auto",
                                                                                      "celsius",
                                                                                      "fahrenheit"])
                || !oneOf(weather.windUnit, ["auto", "kmh", "mph", "ms"]) || !oneOf(weather.refreshPreset,
                                                                                    ["15m", "30m",
                                                                                     "1h", "3h"])
                || (weather.enabled && (!weather.consent || weather.locationLabel === ""
                                        || weather.latitude === null || weather.longitude
                                        === null))) {
            return null;
        }
        if (!Array.isArray(wallpaper.roots) || wallpaper.roots.length > maximumWallpaperRoots) {
            return null;
        }
        const seenRoots = {};
        for (let index = 0; index < wallpaper.roots.length; index += 1) {
            const path = wallpaper.roots[index];
            if (!boundedString(path, maximumWallpaperRootBytes, false) || !path.startsWith("/")
                    || seenRoots[path] === true) {
                return null;
            }
            seenRoots[path] = true;
        }
        return freezeSnapshot(candidate);
    }

    function parseIni(content, byteLength, allowFuture) {
        if (typeof content !== "string" || !Number.isInteger(byteLength) || byteLength < 0 || byteLength
                > maximumConfigBytes || content.indexOf("\0") !== -1) {
            return null;
        }
        const allowed = {
            "settings": ["schema_version"],
            "appearance": ["scheme", "accent_mode", "custom_surface", "custom_text", "custom_accent",
                "surface_opacity", "border_intensity", "blur_enabled", "motion", "font_family",
                "outer_radius"],
            "island": ["compact_height", "compact_padding", "expanded_width_percent",
                "expanded_height_percent", "show_workspace", "show_weather", "show_media",
                "feedback_duration", "gaming_indicator"],
            "clock": ["format", "show_seconds", "date_format", "show_idle_date"],
            "media": ["enabled", "compact_visible", "dashboard_visible", "player_policy",
                "preferred_application"],
            "notifications": ["popups_enabled", "do_not_disturb", "critical_mode",
                "dashboard_visible", "history_visible"],
            "weather": ["enabled", "consent", "location_label", "latitude", "longitude",
                "temperature_unit", "wind_unit", "refresh_preset"],
            "wallpaper": ["roots"]
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
                if (Object.prototype.hasOwnProperty.call(sections, section)) {
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
            if (value === "" || Object.prototype.hasOwnProperty.call(sections[currentSection],
                                                                     key)) {
                return null;
            }
            sections[currentSection][key] = value;
        }
        const metadata = sections.settings;
        if (!metadata || !/^\d+$/.test(metadata.schema_version ?? "")) {
            return null;
        }
        const version = Number(metadata.schema_version);
        if (!Number.isSafeInteger(version) || version < 1) {
            return null;
        }
        if (version > schemaVersion && allowFuture) {
            return Object.freeze({
                                     "futureVersion": version
                                 });
        }
        if (version !== schemaVersion) {
            return null;
        }
        const sectionNames = Object.keys(sections);
        for (let index = 0; index < sectionNames.length; index += 1) {
            const section = sectionNames[index];
            if (!Object.prototype.hasOwnProperty.call(allowed, section)) {
                return null;
            }
            const keys = Object.keys(sections[section]);
            for (let keyIndex = 0; keyIndex < keys.length; keyIndex += 1) {
                if (allowed[section].indexOf(keys[keyIndex]) === -1) {
                    return null;
                }
            }
        }
        const requiredSections = Object.keys(allowed);
        if (sectionNames.length !== requiredSections.length) {
            return null;
        }
        for (let index = 0; index < requiredSections.length; index += 1) {
            const section = requiredSections[index];
            if (!Object.prototype.hasOwnProperty.call(sections, section) || Object.keys(
                        sections[section]).length !== allowed[section].length) {
                return null;
            }
        }
        return sections;
    }

    function parseConfiguration(content, byteLength) {
        const sections = parseIni(content, byteLength, true);
        if (sections === null || sections.futureVersion !== undefined) {
            return sections;
        }
        const candidate = mutableSnapshot(defaultSnapshot(0));
        const appearance = sections.appearance ?? {};
        const island = sections.island ?? {};
        const clock = sections.clock ?? {};
        const media = sections.media ?? {};
        const notifications = sections.notifications ?? {};
        const weather = sections.weather ?? {};
        const wallpaper = sections.wallpaper ?? {};

        function numberValue(section, key, fallback) {
            return section[key] === undefined ? fallback : strictNumber(section[key]);
        }
        function booleanValue(section, key, fallback) {
            return section[key] === undefined ? fallback : strictBoolean(section[key]);
        }

        candidate.appearance.scheme = appearance.scheme ?? candidate.appearance.scheme;
        candidate.appearance.accentMode = appearance.accent_mode ?? candidate.appearance.accentMode;
        candidate.appearance.customSurface = appearance.custom_surface
                ?? candidate.appearance.customSurface;
        candidate.appearance.customText = appearance.custom_text ?? candidate.appearance.customText;
        candidate.appearance.customAccent = appearance.custom_accent
                ?? candidate.appearance.customAccent;
        candidate.appearance.surfaceOpacity = numberValue(appearance, "surface_opacity",
                                                          candidate.appearance.surfaceOpacity);
        candidate.appearance.borderIntensity = numberValue(appearance, "border_intensity",
                                                           candidate.appearance.borderIntensity);
        candidate.appearance.blurEnabled = booleanValue(appearance, "blur_enabled",
                                                        candidate.appearance.blurEnabled);
        candidate.appearance.motion = appearance.motion ?? candidate.appearance.motion;
        candidate.appearance.fontFamily = appearance.font_family ?? candidate.appearance.fontFamily;
        candidate.appearance.outerRadius = numberValue(appearance, "outer_radius",
                                                       candidate.appearance.outerRadius);

        candidate.island.compactHeight = numberValue(island, "compact_height",
                                                     candidate.island.compactHeight);
        candidate.island.compactPadding = numberValue(island, "compact_padding",
                                                      candidate.island.compactPadding);
        candidate.island.expandedWidthPercent = numberValue(island, "expanded_width_percent",
                                                            candidate.island.expandedWidthPercent);
        candidate.island.expandedHeightPercent = numberValue(island, "expanded_height_percent",
                                                             candidate.island.expandedHeightPercent);
        candidate.island.showWorkspace = booleanValue(island, "show_workspace",
                                                      candidate.island.showWorkspace);
        candidate.island.showWeather = booleanValue(island, "show_weather",
                                                    candidate.island.showWeather);
        candidate.island.showMedia = booleanValue(island, "show_media", candidate.island.showMedia);
        candidate.island.feedbackDuration = island.feedback_duration
                ?? candidate.island.feedbackDuration;
        candidate.island.gamingIndicator = booleanValue(island, "gaming_indicator",
                                                        candidate.island.gamingIndicator);

        candidate.clock.format = clock.format ?? candidate.clock.format;
        candidate.clock.showSeconds = booleanValue(clock, "show_seconds",
                                                   candidate.clock.showSeconds);
        candidate.clock.dateFormat = clock.date_format ?? candidate.clock.dateFormat;
        candidate.clock.showIdleDate = booleanValue(clock, "show_idle_date",
                                                    candidate.clock.showIdleDate);

        candidate.media.enabled = booleanValue(media, "enabled", candidate.media.enabled);
        candidate.media.compactVisible = booleanValue(media, "compact_visible",
                                                      candidate.media.compactVisible);
        candidate.media.dashboardVisible = booleanValue(media, "dashboard_visible",
                                                        candidate.media.dashboardVisible);
        candidate.media.playerPolicy = media.player_policy ?? candidate.media.playerPolicy;
        if (media.preferred_application !== undefined) {
            try {
                candidate.media.preferredApplication = JSON.parse(media.preferred_application);
            } catch (error) {
                return null;
            }
        }

        candidate.notifications.popupsEnabled = booleanValue(notifications, "popups_enabled",
                                                             candidate.notifications.popupsEnabled);
        candidate.notifications.doNotDisturb = booleanValue(notifications, "do_not_disturb",
                                                            candidate.notifications.doNotDisturb);
        candidate.notifications.criticalMode = notifications.critical_mode
                ?? candidate.notifications.criticalMode;
        candidate.notifications.dashboardVisible = booleanValue(notifications, "dashboard_visible",
                                                                candidate.notifications.dashboardVisible);
        candidate.notifications.historyVisible = booleanValue(notifications, "history_visible",
                                                              candidate.notifications.historyVisible);

        candidate.weather.enabled = booleanValue(weather, "enabled", candidate.weather.enabled);
        candidate.weather.consent = booleanValue(weather, "consent", candidate.weather.consent);
        if (weather.location_label !== undefined) {
            try {
                candidate.weather.locationLabel = JSON.parse(weather.location_label);
            } catch (error) {
                return null;
            }
        }
        candidate.weather.latitude = numberValue(weather, "latitude", candidate.weather.latitude);
        candidate.weather.longitude = numberValue(weather, "longitude",
                                                  candidate.weather.longitude);
        candidate.weather.temperatureUnit = weather.temperature_unit
                ?? candidate.weather.temperatureUnit;
        candidate.weather.windUnit = weather.wind_unit ?? candidate.weather.windUnit;
        candidate.weather.refreshPreset = weather.refresh_preset ?? candidate.weather.refreshPreset;

        if (wallpaper.roots !== undefined) {
            try {
                candidate.wallpaper.roots = JSON.parse(wallpaper.roots);
            } catch (error) {
                return null;
            }
        }
        return validateCandidate(candidate);
    }

    function parseLegacyConfiguration(content, byteLength) {
        if (typeof content !== "string" || !Number.isInteger(byteLength) || byteLength < 0 || byteLength
                > 4096 || content.indexOf("\0") !== -1) {
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
                if (!allowed[section] || sections[section]) {
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
                    || sections[currentSection][key] !== undefined) {
                return null;
            }
            sections[currentSection][key] = value;
        }
        if (!sections.theme || !oneOf(sections.theme.mode, ["wallpaper", "accent"])) {
            return null;
        }
        const candidate = mutableSnapshot(defaultSnapshot(0));
        const theme = sections.theme;
        const accent = theme.accent === undefined ? "#5B6FF5" : canonicalHex(theme.accent, true);
        if (theme.mode === "accent" && theme.accent === undefined) {
            return null;
        }
        candidate.appearance.accentMode = theme.mode === "accent" ? "custom" : "wallpaper";
        candidate.appearance.customAccent = accent;
        candidate.appearance.surfaceOpacity = theme.surface_opacity === undefined ? 0.96 :
                                                                                    strictNumber(
                                                                                        theme.surface_opacity);
        candidate.appearance.fontFamily = theme.font_family ?? "Inter";
        candidate.appearance.outerRadius = theme.outer_radius === undefined ? 16 : strictNumber(
                                                                                  theme.outer_radius);
        const media = sections.media ?? {};
        candidate.media.enabled = media.enabled === undefined ? true : strictBoolean(media.enabled);
        const weather = sections.weather ?? {};
        candidate.weather.enabled = weather.enabled === undefined ? false : strictBoolean(
                                                                        weather.enabled);
        candidate.weather.latitude = weather.latitude === undefined ? null : strictNumber(
                                                                          weather.latitude);
        candidate.weather.longitude = weather.longitude === undefined ? null : strictNumber(
                                                                            weather.longitude);
        if (candidate.weather.enabled) {
            candidate.weather.consent = true;
            candidate.weather.locationLabel = "Configured location";
        }
        const clock = sections.clock ?? {};
        candidate.clock.format = clock.format ?? "24h";
        candidate.clock.dateFormat = clock.date_format ?? "dddd, d MMMM";
        candidate.clock.showIdleDate = clock.show_idle_date === undefined ? false : strictBoolean(
                                                                                clock.show_idle_date);
        return validateCandidate(candidate);
    }

    function serializeConfiguration(candidate) {
        const value = validateCandidate(mutableSnapshot(candidate));
        if (value === null) {
            return "";
        }
        function booleanText(flag) {
            return flag ? "true" : "false";
        }
        const a = value.appearance;
        const i = value.island;
        const c = value.clock;
        const m = value.media;
        const n = value.notifications;
        const w = value.weather;
        return "[settings]\nschema_version=" + schemaVersion + "\n\n[appearance]\nscheme="
                + a.scheme + "\naccent_mode=" + a.accentMode + "\ncustom_surface="
                + a.customSurface + "\ncustom_text=" + a.customText + "\ncustom_accent="
                + a.customAccent + "\nsurface_opacity=" + a.surfaceOpacity + "\nborder_intensity="
                + a.borderIntensity + "\nblur_enabled=" + booleanText(a.blurEnabled) + "\nmotion="
                + a.motion + "\nfont_family=" + a.fontFamily + "\nouter_radius=" + a.outerRadius
                + "\n\n[island]\ncompact_height=" + i.compactHeight + "\ncompact_padding="
                + i.compactPadding + "\nexpanded_width_percent=" + i.expandedWidthPercent
                + "\nexpanded_height_percent=" + i.expandedHeightPercent + "\nshow_workspace="
                + booleanText(i.showWorkspace) + "\nshow_weather=" + booleanText(i.showWeather)
                + "\nshow_media=" + booleanText(i.showMedia) + "\nfeedback_duration="
                + i.feedbackDuration + "\ngaming_indicator=" + booleanText(i.gamingIndicator)
                + "\n\n[clock]\nformat=" + c.format + "\nshow_seconds=" + booleanText(
                    c.showSeconds) + "\ndate_format=" + c.dateFormat + "\nshow_idle_date="
                + booleanText(c.showIdleDate) + "\n\n[media]\nenabled=" + booleanText(m.enabled)
                + "\ncompact_visible=" + booleanText(m.compactVisible) + "\ndashboard_visible="
                + booleanText(m.dashboardVisible) + "\nplayer_policy=" + m.playerPolicy
                + "\npreferred_application=" + JSON.stringify(m.preferredApplication)
                + "\n\n[notifications]\npopups_enabled=" + booleanText(n.popupsEnabled)
                + "\ndo_not_disturb=" + booleanText(n.doNotDisturb) + "\ncritical_mode="
                + n.criticalMode + "\ndashboard_visible=" + booleanText(n.dashboardVisible)
                + "\nhistory_visible=" + booleanText(n.historyVisible) + "\n\n[weather]\nenabled="
                + booleanText(w.enabled) + "\nconsent=" + booleanText(w.consent)
                + "\nlocation_label=" + JSON.stringify(w.locationLabel) + "\nlatitude=" + (
                    w.latitude === null ? "-" : w.latitude) + "\nlongitude=" + (w.longitude === null
                                                                                ? "-" : w.longitude)
                + "\ntemperature_unit=" + w.temperatureUnit + "\nwind_unit=" + w.windUnit
                + "\nrefresh_preset=" + w.refreshPreset + "\n\n[wallpaper]\nroots=" + JSON.stringify(
                    value.wallpaper.roots) + "\n";
    }

    function normalizeDiskPlaceholders(candidate) {
        return candidate === null || candidate.futureVersion !== undefined ? candidate :
                                                                             validateCandidate(
                                                                                 mutableSnapshot(
                                                                                     candidate));
    }

    function snapshotKey(candidate) {
        return JSON.stringify(candidate, function (key, value) {
            return key === "generation" ? undefined : value;
        });
    }

    function publish(candidate) {
        if (candidate === null) {
            return false;
        }
        if (snapshotKey(candidate) === snapshotKey(root._snapshot)) {
            return true;
        }
        root._generation += 1;
        const mutable = mutableSnapshot(candidate);
        mutable.generation = root._generation;
        root._snapshot = freezeSnapshot(mutable);
        return true;
    }

    function warnOnce(kind, message) {
        if (_loggedFailures[kind] === true) {
            return;
        }
        _loggedFailures[kind] = true;
        console.warn("Nagi settings: " + message);
    }

    function enterRecovery(kind, message, unsafe) {
        status = "recovery";
        recoveryKind = kind;
        errorMessage = message;
        readOnly = unsafe;
        const fallback = _lastGoodSnapshot ?? defaultSnapshot(0);
        _persistedSnapshot = fallback;
        publish(fallback);
        warnOnce(kind, message);
    }

    function loadCandidate(view, allowFuture) {
        if (!view.loaded) {
            return null;
        }
        const data = view.data();
        const bytes = data !== null && typeof data.byteLength === "number" ? data.byteLength :
                                                                             utf8Length(view.text(
                                                                                            ));
        const parsed = parseConfiguration(view.text(), bytes);
        return allowFuture ? normalizeDiskPlaceholders(parsed) : parsed !== null
                             && parsed.futureVersion === undefined ? normalizeDiskPlaceholders(
                                                                         parsed) : null;
    }

    function sendPendingOperation() {
        if (_writerReady && _writeInProgress) {
            writer.write(_pendingOperation + " " + encodeURIComponent(_pendingPayload) + "\n");
        }
    }

    function beginHelper(operation, candidate, purpose) {
        if (_writeInProgress || candidate === null) {
            return false;
        }
        const payload = serializeConfiguration(candidate);
        if (payload === "" || utf8Length(payload) > maximumConfigBytes) {
            return false;
        }
        _pendingOperation = operation;
        _pendingPayload = payload;
        _inFlightCandidate = candidate;
        _writePurpose = purpose;
        _writeInProgress = true;
        if (purpose === "persist") {
            _ownWriteCanonical = payload;
        }
        sendPendingOperation();
        return true;
    }

    function finishWriter(success) {
        if (!_writeInProgress) {
            return;
        }
        const purpose = _writePurpose;
        const candidate = _inFlightCandidate;
        _pendingOperation = "";
        _pendingPayload = "";
        _writePurpose = "";
        _ownWriteCanonical = "";
        _writeInProgress = false;
        _inFlightCandidate = null;
        if (!success) {
            if (purpose === "persist") {
                publish(_persistedSnapshot);
            }
            status = purpose === "migration" ? "recovery" : "write-failed";
            recoveryKind = purpose === "migration" ? "migration" : "write";
            errorMessage
                    = "Settings could not be saved. Check the configuration directory and try again.";
            warnOnce("write", errorMessage);
            _pendingLastGoodSnapshot = null;
            _writeCandidate = null;
            return;
        }
        if (purpose !== "last-good") {
            _persistedSnapshot = candidate;
        }
        _lastGoodSnapshot = candidate;
        _hasPersistedConfiguration = true;
        _hasLoadedConfiguration = true;
        status = "ready";
        recoveryKind = "";
        errorMessage = "";
        readOnly = false;
        if (purpose !== "last-good") {
            if (settingsFile.path === "") {
                settingsFile.path = configPath;
            } else if (!settingsFile.loaded) {
                settingsFile.reload();
            }
        }
        if (lastGoodFile.path === "") {
            lastGoodFile.path = lastGoodPath;
        }
        if (_writeCandidate !== null) {
            Qt.callLater(root.persistDesiredSnapshot);
        } else {
            Qt.callLater(root.syncPendingLastGood);
        }
    }

    function schedulePersistence(candidate, continuous) {
        _writeCandidate = candidate;
        if (continuous) {
            persistenceDebounce.restart();
        } else {
            persistenceDebounce.stop();
            Qt.callLater(root.persistDesiredSnapshot);
        }
    }

    function persistDesiredSnapshot() {
        if (_writeInProgress || _writeCandidate === null || !writable) {
            return;
        }
        const desired = _writeCandidate;
        _writeCandidate = null;
        if (!beginHelper("write", desired, "persist")) {
            _writeCandidate = desired;
        }
    }

    function syncPendingLastGood() {
        if (_writeInProgress || _pendingLastGoodSnapshot === null) {
            return;
        }
        const candidate = _pendingLastGoodSnapshot;
        _pendingLastGoodSnapshot = null;
        if (!beginHelper("last-good", candidate, "last-good")) {
            _pendingLastGoodSnapshot = candidate;
        }
    }

    function updatePage(page, changes, continuous) {
        if (!writable || typeof changes !== "object" || changes === null) {
            return false;
        }
        const allowedPages = ["appearance", "island", "clock", "media", "notifications", "weather",
                              "wallpaper"];
        if (allowedPages.indexOf(page) === -1) {
            return false;
        }
        const candidate = mutableSnapshot(_snapshot);
        const keys = Object.keys(changes);
        for (let index = 0; index < keys.length; index += 1) {
            if (!Object.prototype.hasOwnProperty.call(candidate[page], keys[index])) {
                return false;
            }
            candidate[page][keys[index]] = changes[keys[index]];
        }
        const normalized = validateCandidate(candidate);
        if (normalized === null) {
            return false;
        }
        publish(normalized);
        schedulePersistence(normalized, continuous === true);
        return true;
    }

    function resetPage(page) {
        const defaults = defaultSnapshot(0);
        if (!Object.prototype.hasOwnProperty.call(defaults, page) || page === "generation" || page
                === "schemaVersion") {
            return false;
        }
        const changes = page === "wallpaper" ? {
                                                   "roots": defaults.wallpaper.roots.slice()
                                               } : Object.assign({}, defaults[page]);
        return updatePage(page, changes, false);
    }

    function resetAll() {
        if (status === "future" || readOnly) {
            return false;
        }
        const defaults = defaultSnapshot(0);
        publish(defaults);
        if (recoveryRequired) {
            return beginHelper(recoveryKind === "missing" ? "create" : "recover", defaults,
                               "recovery");
        }
        schedulePersistence(defaults, false);
        return true;
    }

    function restoreLastGood() {
        if (!recoveryRequired || readOnly || _lastGoodSnapshot === null) {
            return false;
        }
        publish(_lastGoodSnapshot);
        return beginHelper(recoveryKind === "missing" ? "create" : "recover", _lastGoodSnapshot,
                           "recovery");
    }

    function applyExternalConfiguration() {
        if (_initializing) {
            return;
        }
        const candidate = loadCandidate(settingsFile, true);
        if (candidate !== null && candidate.futureVersion !== undefined) {
            status = "future";
            readOnly = true;
            recoveryKind = "future";
            errorMessage
                    = "Settings were created by a newer Nagi version. Update Nagi to edit them.";
            publish(_lastGoodSnapshot ?? defaultSnapshot(0));
            return;
        }
        if (candidate === null) {
            enterRecovery("invalid",
                          "Settings are invalid. Restore the last-good copy or reset defaults.",
                          false);
            return;
        }
        if (snapshotKey(candidate) === snapshotKey(_persistedSnapshot) && _lastGoodSnapshot
                !== null && snapshotKey(candidate) === snapshotKey(_lastGoodSnapshot)) {
            status = "ready";
            recoveryKind = "";
            errorMessage = "";
            readOnly = false;
            return;
        }
        const canonical = serializeConfiguration(candidate);
        if (_writeInProgress && canonical === _ownWriteCanonical) {
            return;
        }
        _persistedSnapshot = candidate;
        _hasPersistedConfiguration = true;
        status = "ready";
        recoveryKind = "";
        errorMessage = "";
        readOnly = false;
        publish(candidate);
        if (!beginHelper("last-good", candidate, "last-good")) {
            _pendingLastGoodSnapshot = candidate;
        }
    }

    function finishInspection(result) {
        let paths;
        try {
            paths = JSON.parse(result);
        } catch (error) {
            enterRecovery("path", "The settings path could not be verified safely.", true);
            _initializing = false;
            return;
        }
        if (paths.settings === "unsafe" || paths.lastGood === "unsafe" || paths.legacy === "unsafe"
                || paths.backup === "unsafe" || paths.invalid === "unsafe") {
            enterRecovery("path",
                          "A settings path is a symlink or non-regular file and was rejected.",
                          true);
            _initializing = false;
            return;
        }

        if (paths.lastGood === "regular") {
            lastGoodFile.path = lastGoodPath;
            lastGoodFile.waitForJob();
            _lastGoodSnapshot = loadCandidate(lastGoodFile, false);
        }
        if (paths.settings === "regular") {
            settingsFile.path = configPath;
            settingsFile.waitForJob();
            const candidate = loadCandidate(settingsFile, true);
            _initializing = false;
            if (candidate !== null && candidate.futureVersion !== undefined) {
                status = "future";
                readOnly = true;
                recoveryKind = "future";
                errorMessage
                        = "Settings were created by a newer Nagi version. Update Nagi to edit them.";
                publish(_lastGoodSnapshot ?? defaultSnapshot(0));
                return;
            }
            if (candidate === null) {
                enterRecovery("invalid",
                              "Settings are invalid. Restore the last-good copy or reset defaults.",
                              false);
                return;
            }
            _persistedSnapshot = candidate;
            _hasPersistedConfiguration = true;
            _hasLoadedConfiguration = true;
            status = "ready";
            publish(candidate);
            const canonical = serializeConfiguration(candidate);
            if (_lastGoodSnapshot === null || snapshotKey(_lastGoodSnapshot) !== snapshotKey(
                        candidate) || settingsFile.text() !== canonical) {
                beginHelper("write", candidate, "canonicalize");
            }
            return;
        }
        if (paths.legacy === "regular") {
            legacyFile.path = legacyPath;
            legacyFile.waitForJob();
            const data = legacyFile.data();
            const bytes = data !== null && typeof data.byteLength === "number" ? data.byteLength :
                                                                                 utf8Length(
                                                                                     legacyFile.text(
                                                                                         ));
            const candidate = parseLegacyConfiguration(legacyFile.text(), bytes);
            _initializing = false;
            if (candidate === null) {
                enterRecovery("migration", "The legacy theme file is invalid and was not migrated.",
                              false);
                return;
            }
            publish(candidate);
            beginHelper("migrate", candidate, "migration");
            return;
        }

        _initializing = false;
        const defaults = defaultSnapshot(0);
        _persistedSnapshot = defaults;
        publish(defaults);
        if (defaultCreationEnabled) {
            beginHelper("create", defaults, "create");
        } else {
            status = "ready";
        }
    }

    Component.onCompleted: inspection.running = true

    Process {
        id: inspection

        command: [root.helperPath, "inspect", root.configDirectoryPath]
        stdout: StdioCollector {
            id: inspectionOutput
        }
        onExited: function (exitCode) {
            if (exitCode !== 0) {
                root.enterRecovery("path", "The settings directory could not be verified safely.",
                                   true);
                root._initializing = false;
                return;
            }
            root.finishInspection(inspectionOutput.text.trim());
        }
    }

    Process {
        id: writer

        command: [root.helperPath, "serve", root.configDirectoryPath]
        stdinEnabled: true
        running: true
        stdout: SplitParser {
            onRead: data => root.finishWriter(data === "OK")
        }
        stderr: SplitParser {
            onRead: data => root.warnOnce("helper",
                                          "The settings writer reported a bounded failure.")
        }
        onStarted: {
            root._writerReady = true;
            root.sendPendingOperation();
        }
        onExited: function (exitCode) {
            root._writerReady = false;
            if (root._writeInProgress) {
                root.finishWriter(false);
            } else if (root.status === "ready") {
                root.status = "write-failed";
                root.recoveryKind = "write";
                root.errorMessage = "Settings cannot be saved because the private writer stopped.";
            }
        }
    }

    FileView {
        id: settingsFile

        path: ""
        watchChanges: true
        preload: true
        atomicWrites: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.applyExternalConfiguration()
        onLoadFailed: function (error) {
            if (!root._initializing && root._hasPersistedConfiguration) {
                root.enterRecovery(error === FileViewError.FileNotFound ? "missing" : "unreadable",
                                   error === FileViewError.FileNotFound
                                   ? "Settings were removed. Restore the last-good copy or reset defaults." :
                                     "Settings cannot be read. Fix permissions, then restore or reset.",
                                   false);
            }
        }
    }

    FileView {
        id: lastGoodFile

        path: ""
        preload: true
        atomicWrites: true
        printErrors: false
    }

    FileView {
        id: legacyFile

        path: ""
        preload: true
        printErrors: false
    }

    Timer {
        id: persistenceDebounce

        interval: 180
        onTriggered: root.persistDesiredSnapshot()
    }
}

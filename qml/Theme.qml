pragma Singleton

import Quickshell
import QtQuick

// The presentation-wide design-system boundary. Configuration and palette
// changes publish one frozen snapshot so consumers never observe half-derived
// colors. Fixed semantic roles remain independent from the accent source.
Singleton {
    id: root

    readonly property string configHome: UserConfig.configHome
    readonly property string configDirectoryPath: UserConfig.configDirectoryPath
    readonly property string configPath: UserConfig.configPath
    // The injected wallpaper adapter publishes { accent: "#RRGGBB" } here only
    // for a validated Ready snapshot and clears the seam on every failure state.
    property var wallpaperPalette: null
    // Normalized by KdeAppearanceAdapter. Tests may inject an immutable snapshot.
    property var systemAppearance: Object.freeze({
                                                     "accent": "#3DAEE9",
                                                     "animationFactor": 1,
                                                     "colorScheme": "light",
                                                     "generation": 0,
                                                     "schemeName": "BreezeLight",
                                                     "surface": "#EFF0F1",
                                                     "text": "#232629"
                                                 })
    readonly property var snapshot: root._snapshot

    readonly property string officialAccent: "#5B6FF5"
    property var _configuration: visualConfiguration(UserConfig.snapshot.appearance)
    property int _generation: 1
    property var _snapshot: buildSnapshot(_configuration)
    property string _snapshotKey: ""
    property bool _initialized: false
    property var _loggedFailures: ({})

    function visualConfiguration(appearance) {
        return Object.freeze({
                                 "accentMode": appearance.accentMode,
                                 "borderIntensity": appearance.borderIntensity,
                                 "blurEnabled": appearance.blurEnabled,
                                 "controlCenterBaseFontSize": appearance.controlCenterBaseFontSize,
                                 "controlCenterFontFamily": appearance.controlCenterFontFamily,
                                 "customAccent": appearance.customAccent,
                                 "customSurface": appearance.customSurface,
                                 "customText": appearance.customText,
                                 "expandedBaseFontSize": appearance.expandedBaseFontSize,
                                 "expandedFontFamily": appearance.expandedFontFamily,
                                 "idleBaseFontSize": appearance.idleBaseFontSize,
                                 "idleFontFamily": appearance.idleFontFamily,
                                 "motion": appearance.motion,
                                 "outerRadius": appearance.outerRadius,
                                 "scheme": appearance.scheme,
                                 "surfaceOpacity": appearance.surfaceOpacity
                             });
    }

    function canonicalHex(value) {
        if (typeof value !== "string" || !/^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(value)) {
            return null;
        }
        return value.toUpperCase();
    }

    function rgb(value, background) {
        const canonical = canonicalHex(value);
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
        const base = rgb(background ?? "#080D16");
        return {
            "r": Math.round(foreground.r * alpha + base.r * (1 - alpha)),
            "g": Math.round(foreground.g * alpha + base.g * (1 - alpha)),
            "b": Math.round(foreground.b * alpha + base.b * (1 - alpha))
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
    function ensureContrastAgainst(candidate, backgrounds, floor, toward) {
        const original = typeof candidate === "string" ? rgb(candidate) : candidate;
        const target = typeof toward === "string" ? rgb(toward) : toward;
        for (let step = 0; step <= 32; step += 1) {
            const adjusted = step === 0 ? original : mix(original, target, step / 32);
            let valid = true;
            for (let index = 0; index < backgrounds.length; index += 1) {
                if (contrast(adjusted, backgrounds[index]) < floor) {
                    valid = false;
                    break;
                }
            }
            if (valid) {
                return adjusted;
            }
        }
        return target;
    }

    function validWallpaperAccent() {
        if (root.wallpaperPalette === null || typeof root.wallpaperPalette !== "object") {
            return null;
        }
        return canonicalHex(root.wallpaperPalette.accent);
    }

    function maintainedPalette(scheme, configuration) {
        const dark = {
            "danger": "#F26D7E",
            "progressTrack": "#1C2836",
            "success": "#7BD88F",
            "surface": "#080D16",
            "surfaceBorder": "#263448",
            "text": "#EFF3F8",
            "warning": "#E8C268"
        };
        const oled = Object.assign({}, dark, {
                                       "progressTrack": "#1A1D24",
                                       "surface": "#000000",
                                       "surfaceBorder": "#303641",
                                       "text": "#F5F7FA"
                                   });
        const light = {
            "danger": "#A12B3D",
            "progressTrack": "#D5DBE2",
            "success": "#19723A",
            "surface": "#F4F6F8",
            "surfaceBorder": "#AAB4C0",
            "text": "#151A21",
            "warning": "#805E00"
        };
        if (scheme === "nagi-oled") {
            return oled;
        }
        if (scheme === "nagi-light") {
            return light;
        }
        if (scheme === "system") {
            const base = systemAppearance.colorScheme === "dark" ? dark : light;
            return Object.assign({}, base, {
                                     "surface": canonicalHex(systemAppearance.surface)
                                                ?? base.surface,
                                     "text": canonicalHex(systemAppearance.text) ?? base.text
                                 });
        }
        if (scheme === "custom") {
            const surface = configuration.customSurface;
            const text = configuration.customText;
            const base = luminance(surface) > 0.45 ? light : dark;
            return Object.assign({}, base, {
                                     "surface": surface,
                                     "surfaceBorder": hex(mix(surface, text, 0.24)),
                                     "text": text
                                 });
        }
        return dark;
    }

    function buildSnapshot(configuration) {
        const palette = maintainedPalette(configuration.scheme, configuration);
        const wallpaperAccent = configuration.accentMode === "wallpaper" ? validWallpaperAccent() :
                                                                           null;
        const candidates = [];
        if (configuration.accentMode === "wallpaper" && wallpaperAccent !== null) {
            candidates.push({
                                "accent": wallpaperAccent,
                                "source": "wallpaper"
                            });
        } else if (configuration.accentMode === "system") {
            candidates.push({
                                "accent": systemAppearance.accent,
                                "source": "system"
                            });
        } else if (configuration.accentMode === "custom") {
            candidates.push({
                                "accent": configuration.customAccent,
                                "source": "custom"
                            });
        } else if (configuration.accentMode === "nagi") {
            candidates.push({
                                "accent": root.officialAccent,
                                "source": "nagi"
                            });
        }
        if (configuration.accentMode === "wallpaper") {
            candidates.push({
                                "accent": configuration.customAccent,
                                "source": "configured"
                            });
        }
        candidates.push({
                            "accent": root.officialAccent,
                            "source": "fallback"
                        });

        for (let index = 0; index < candidates.length; index += 1) {
            const snapshot = deriveSnapshot(configuration, palette, candidates[index].accent,
                                            candidates[index].source, wallpaperAccent);
            if (snapshot !== null) {
                return snapshot;
            }
        }
        return null;
    }

    function deriveSnapshot(configuration, palette, selected, source, wallpaperAccent) {
        const surfaceBase = palette.surface;
        const textPrimary = palette.text;
        if (contrast(textPrimary, surfaceBase) < 4.5) {
            return null;
        }
        const selectedRgb = rgb(selected, surfaceBase);
        if (selectedRgb === null) {
            return null;
        }
        const toward = luminance(surfaceBase) > 0.45 ? "#000000" : "#FFFFFF";
        const foreground = luminance(surfaceBase) > 0.45 ? "#F1F5FA" : "#080D16";
        const primaryRgb = ensureContrastAgainst(selectedRgb, [surfaceBase, foreground], 4.5,
                                                 toward);
        const primary = hex(primaryRgb);
        const hover = hex(ensureContrastAgainst(mix(primaryRgb, toward, 0.18), [surfaceBase,
                                                                                foreground], 4.5,
                                                toward));
        const pressed = hex(ensureContrastAgainst(mix(primaryRgb, toward, 0.08), [surfaceBase,
                                                                                  foreground], 4.5,
                                                  toward));
        const focusRing = hex(ensureContrast(mix(primaryRgb, toward, 0.24), surfaceBase, 3,
                                             toward));
        const progressFill = hex(ensureContrast(primaryRgb, palette.progressTrack, 3, toward));
        const surfaceHover = hex(ensureContrast(mix(surfaceBase, primaryRgb, 0.10), surfaceBase,
                                                1.08, primaryRgb));
        const surfaceActive = hex(ensureContrast(mix(surfaceBase, primaryRgb, 0.18), surfaceBase,
                                                 1.16, primaryRgb));
        const controlFill = hex(mix(surfaceBase, textPrimary, 0.08));
        const controlFillHover = hex(mix(controlFill, primaryRgb, 0.12));
        const controlFillPressed = hex(mix(controlFill, primaryRgb, 0.20));
        const borderHover = hex(ensureContrast(mix(palette.surfaceBorder, primaryRgb, 0.28),
                                               surfaceBase, 3, toward));
        const borderPressed = hex(ensureContrast(mix(palette.surfaceBorder, primaryRgb, 0.42),
                                                 surfaceBase, 3, toward));
        const textSecondary = hex(ensureContrast(mix(textPrimary, surfaceBase, 0.24), surfaceBase,
                                                 4.5, textPrimary));
        const textMuted = hex(ensureContrast(mix(textPrimary, surfaceBase, 0.43), surfaceBase, 4.5,
                                             textPrimary));
        let dangerRgb = ensureContrast(palette.danger, surfaceBase, 4.5, toward);
        let dangerFill = hex(mix(surfaceBase, dangerRgb, 0.06));
        let dangerFillHover = hex(mix(surfaceBase, dangerRgb, 0.10));
        let dangerFillPressed = hex(mix(surfaceBase, dangerRgb, 0.14));
        dangerRgb = ensureContrastAgainst(dangerRgb, [surfaceBase, dangerFill, dangerFillHover,
                                                      dangerFillPressed], 4.5, toward);
        const danger = hex(dangerRgb);
        dangerFill = hex(mix(surfaceBase, dangerRgb, 0.06));
        dangerFillHover = hex(mix(surfaceBase, dangerRgb, 0.10));
        dangerFillPressed = hex(mix(surfaceBase, dangerRgb, 0.14));
        const warning = hex(ensureContrast(palette.warning, surfaceBase, 4.5, toward));
        const success = hex(ensureContrast(palette.success, surfaceBase, 4.5, toward));
        const ratios = Object.freeze({
                                         "accentOnSurface": contrast(primary, surfaceBase),
                                         "accentForeground": Math.min(contrast(foreground, primary),
                                                                      contrast(foreground, hover),
                                                                      contrast(foreground, pressed)),
                                         "focusRingOnSurface": contrast(focusRing, surfaceBase),
                                         "progressOnTrack": contrast(progressFill,
                                                                     palette.progressTrack),
                                         "surfaceHoverOnBase": contrast(surfaceHover, surfaceBase),
                                         "surfaceActiveOnBase": contrast(surfaceActive, surfaceBase),
                                         "statusOnSurface": Math.min(contrast(danger, surfaceBase),
                                                                     contrast(warning, surfaceBase),
                                                                     contrast(success, surfaceBase)),
                                         "dangerOnFills": Math.min(contrast(danger, dangerFill),
                                                                   contrast(danger, dangerFillHover),
                                                                   contrast(danger,
                                                                            dangerFillPressed)),
                                         "textOnSurface": contrast(textPrimary, surfaceBase),
                                         "textSecondaryOnSurface": contrast(textSecondary,
                                                                            surfaceBase),
                                         "textMutedOnSurface": contrast(textMuted, surfaceBase)
                                     });
        if (ratios.accentOnSurface < 3 || ratios.accentForeground < 4.5
                || ratios.focusRingOnSurface < 3 || ratios.progressOnTrack < 3
                || ratios.surfaceHoverOnBase < 1.08 || ratios.surfaceActiveOnBase < 1.16
                || ratios.statusOnSurface < 4.5 || ratios.dangerOnFills < 4.5
                || ratios.textOnSurface < 4.5 || ratios.textSecondaryOnSurface < 4.5
                || ratios.textMutedOnSurface < 4.5) {
            return null;
        }
        return Object.freeze({
                                 "accent": primary,
                                 "accentForeground": foreground,
                                 "accentHover": hover,
                                 "accentPressed": pressed,
                                 "borderIntensity": configuration.borderIntensity,
                                 "blurEnabled": configuration.blurEnabled,
                                 "configuredAccent": configuration.customAccent,
                                 "contrast": ratios,
                                 "controlFill": controlFill,
                                 "controlFillHover": controlFillHover,
                                 "controlFillPressed": controlFillPressed,
                                 "danger": danger,
                                 "dangerFill": dangerFill,
                                 "dangerFillHover": dangerFillHover,
                                 "dangerFillPressed": dangerFillPressed,
                                 "focusRing": focusRing,
                                 "generation": root._generation,
                                 "mode": configuration.accentMode,
                                 "progressFill": progressFill,
                                 "progressTrack": palette.progressTrack,
                                 "scheme": configuration.scheme,
                                 "source": source,
                                 "success": success,
                                 "surface": surfaceBase,
                                 "surfaceActive": surfaceActive,
                                 "surfaceBorder": palette.surfaceBorder,
                                 "surfaceBorderHover": borderHover,
                                 "surfaceBorderPressed": borderPressed,
                                 "surfaceHover": surfaceHover,
                                 "textMuted": textMuted,
                                 "textPrimary": textPrimary,
                                 "textSecondary": textSecondary,
                                 "wallpaperAccent": wallpaperAccent,
                                 "warning": warning
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

    function syncUserConfiguration() {
        root._configuration = visualConfiguration(UserConfig.snapshot.appearance);
        publish(root._configuration);
    }

    Component.onCompleted: {
        // Break the initial QML bindings: subsequent updates are imperative,
        // validated publications rather than dependency-by-dependency churn.
        const initial = root._snapshot;
        root._snapshot = initial;
        root._snapshotKey = snapshotKey(initial);
        root._initialized = true;
        syncUserConfiguration();
    }

    onWallpaperPaletteChanged: {
        if (root._initialized) {
            publish(root._configuration);
        }
    }
    onSystemAppearanceChanged: {
        if (root._initialized) {
            publish(root._configuration);
        }
    }

    Connections {
        target: UserConfig

        function onSnapshotChanged() {
            root.syncUserConfiguration();
        }
    }
    function effectiveMotionScale(userMode, animationFactor) {
        const userScale = userMode === "minimal" ? 0 : userMode === "reduced" ? 0.5 : 1;
        const kdeScale = animationFactor <= 0 ? 0 : Math.min(1, animationFactor);
        return Math.min(userScale, kdeScale);
    }

    function motionMode(scale) {
        return scale <= 0 ? "minimal" : scale < 1 ? "reduced" : "full";
    }

    readonly property QtObject color: QtObject {
        readonly property color surface: root.snapshot.surface
        readonly property color surfaceOpaque: root.snapshot.surface
        readonly property color surfaceBorder: root.snapshot.surfaceBorder
        readonly property color controlFill: root.snapshot.controlFill
        readonly property color textPrimary: root.snapshot.textPrimary
        readonly property color textSecondary: root.snapshot.textSecondary
        readonly property color textMuted: root.snapshot.textMuted
        readonly property color danger: root.snapshot.danger
        readonly property color dangerFill: root.snapshot.dangerFill
        readonly property color dangerFillHover: root.snapshot.dangerFillHover
        readonly property color dangerFillPressed: root.snapshot.dangerFillPressed
        readonly property color success: root.snapshot.success
        readonly property color warning: root.snapshot.warning
        readonly property color progressTrack: root.snapshot.progressTrack
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
        readonly property int outer: UserConfig.snapshot.appearance.outerRadius
        readonly property int sm: 6
        readonly property int md: 10
        readonly property int lg: 12
        readonly property int xl: 16
    }

    // Each surface resolves one typography scope. Semantic roles keep their
    // established ratios to the user-selected body size instead of collapsing
    // to that base value.
    readonly property QtObject type: QtObject {
        function scopeFor(item) {
            let current = item;
            while (current !== null && current !== undefined) {
                if (current.nagiTypographyScope === "idle" || current.nagiTypographyScope
                        === "expanded" || current.nagiTypographyScope === "controlCenter") {
                    return current.nagiTypographyScope;
                }
                current = current.parent;
            }
            return "expanded";
        }
        function familyFor(scope) {
            return scope === "idle" ? UserConfig.snapshot.appearance.idleFontFamily : scope
                                      === "controlCenter"
                                      ? UserConfig.snapshot.appearance.controlCenterFontFamily :
                                        UserConfig.snapshot.appearance.expandedFontFamily;
        }
        function baseSizeFor(scope) {
            return scope === "idle" ? UserConfig.snapshot.appearance.idleBaseFontSize : scope
                                      === "controlCenter"
                                      ? UserConfig.snapshot.appearance.controlCenterBaseFontSize :
                                        UserConfig.snapshot.appearance.expandedBaseFontSize;
        }
        function sizeFor(scope, role) {
            const base = baseSizeFor(scope);
            if (role === "caption" || role === "muted") {
                return Math.max(1, Math.round(base * 11 / 13));
            }
            if (role === "title" || role === "heading") {
                return Math.max(1, Math.round(base * 15 / 13));
            }
            if (role === "display") {
                return Math.max(1, Math.round(base * 48 / 13));
            }
            return base;
        }

        function familyForItem(item) {
            return familyFor(scopeFor(item));
        }
        function sizeForItem(item, role) {
            return sizeFor(scopeFor(item), role);
        }

        readonly property string family: familyFor("expanded")
        readonly property int caption: sizeFor("expanded", "caption")
        readonly property int display: sizeFor("expanded", "display")
        readonly property int body: sizeFor("expanded", "body")
        readonly property int title: sizeFor("expanded", "title")
        readonly property int weightRegular: Font.Normal
        readonly property int weightMedium: Font.Medium
        readonly property int weightSemibold: Font.DemiBold
    }

    readonly property QtObject size: QtObject {
        readonly property int islandIdleWidth: 120
        readonly property int islandIdleHeight: UserConfig.snapshot.island.compactHeight
        readonly property int islandCompactPadding: UserConfig.snapshot.island.compactPadding
        // A 288 px floor keeps every focused subview under the pointer while
        // the outer surface morphs, without replacing content-driven sizing.
        readonly property int islandSubviewMinimumWidth: 288
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
        readonly property int onboardingWidth: 520
        readonly property int onboardingMinimumWidth: 420
        readonly property int onboardingMaximumWidth: 640
        readonly property int controlCenterMinimumWidth: 640
        readonly property int controlCenterMinimumHeight: 480
        readonly property int controlCenterPreferredWidth: 920
        readonly property int controlCenterPreferredHeight: 660
        readonly property int controlCenterResponsiveBreakpoint: 760
        readonly property int controlCenterSidebarWidth: 196
        readonly property int controlCenterContentMaximumWidth: 880
        readonly property int controlCenterRowStackBreakpoint: 720
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
        readonly property real surface: UserConfig.snapshot.appearance.surfaceOpacity
        readonly property real disabled: 0.62
        readonly property real shadow: 0.28
        readonly property real border: UserConfig.snapshot.appearance.borderIntensity
    }

    readonly property QtObject elevation: QtObject {
        readonly property color shadowColor: "#000000"
        readonly property int shadowRadius: 22
        readonly property int shadowVerticalOffset: 8
        readonly property int shadowSamples: 17
    }

    readonly property QtObject motion: QtObject {
        readonly property real scale: root.effectiveMotionScale(
                                          UserConfig.snapshot.appearance.motion,
                                          root.systemAppearance.animationFactor)
        readonly property string effectiveMode: root.motionMode(scale)

        readonly property int durationFast: scale <= 0 ? 0 : Math.max(1, Math.round(70 * scale))
        readonly property int durationNormal: scale <= 0 ? 0 : Math.max(1, Math.round(120 * scale))
        readonly property int durationSlow: scale <= 0 ? 0 : Math.max(1, Math.round(170 * scale))
        readonly property int durationExpansion: scale <= 0 ? 0 : Math.max(1, Math.round(190
                                                                                         * scale))
        readonly property int expansionAnchor: Qt.AlignTop
        readonly property int easingStandard: Easing.OutCubic
        readonly property int easingExpansion: Easing.OutCubic
    }
}

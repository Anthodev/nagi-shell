import Quickshell
import Quickshell.Io
import QtQuick
import "qml"

ShellRoot {
    id: test

    readonly property string phase: Quickshell.env("NAGI_SETTINGS_TEST_PHASE") ?? "normal"
    property string stage: "startup"
    property var preservedSnapshot: null
    property int preservedGeneration: 0
    property int writeEvents: 0
    property int baselineWriteEvents: 0
    property int attempts: 0
    property bool schemaValidated: false

    function fail(message) {
        console.error("FAIL: " + message + " (phase=" + phase + ", stage=" + stage + ")");
        Qt.exit(1);
        throw new Error(message);
    }

    function require(condition, message) {
        if (!condition) {
            fail(message);
        }
    }

    function awaitState(condition, message) {
        if (condition) {
            attempts = 0;
            return true;
        }
        attempts += 1;
        if (attempts > 200) {
            fail(message);
        }
        poll.restart();
        return false;
    }

    function validateSnapshot(snapshot) {
        require(snapshot !== null && Object.isFrozen(snapshot), "snapshot is frozen");
        require(Object.isFrozen(snapshot.appearance) && Object.isFrozen(snapshot.wallpaper.roots),
                "nested settings are frozen");
        require(snapshot.schemaVersion === 3, "schema version is independent and exact");
        require(snapshot.appearance.surfaceOpacity >= 0.85 && snapshot.appearance.surfaceOpacity
                <= 1, "opacity is bounded");
        require(snapshot.island.compactHeight >= 44 && snapshot.island.compactHeight <= 48,
                "compact height is bounded");
    }

    function validateSchemaContract() {
        const full = UserConfig.mutableSnapshot(UserConfig.defaultSnapshot(0));
        full.appearance = {
            "scheme": "custom",
            "accentMode": "custom",
            "customSurface": "#101010",
            "customText": "#F0F0F0",
            "customAccent": "#8090FF",
            "surfaceOpacity": 0.85,
            "borderIntensity": 1,
            "blurEnabled": true,
            "motion": "minimal",
            "idleFontFamily": "Noto Sans",
            "idleBaseFontSize": 11,
            "expandedFontFamily": "Source Sans 3",
            "expandedBaseFontSize": 18,
            "controlCenterFontFamily": "Inter",
            "controlCenterBaseFontSize": 16,
            "outerRadius": 32
        };
        full.island = {
            "compactHeight": 48,
            "compactPadding": 32,
            "expandedWidthPercent": 0.6,
            "expandedHeightPercent": 0.6,
            "showWorkspace": false,
            "showWeather": false,
            "showMedia": false,
            "feedbackDuration": "long",
            "gamingIndicator": false
        };
        full.clock = {
            "format": "auto",
            "showSeconds": true,
            "dateFormat": "yyyy-MM-dd",
            "showIdleDate": true
        };
        full.media = {
            "enabled": false,
            "compactVisible": false,
            "dashboardVisible": false,
            "playerPolicy": "preferred",
            "preferredApplication": "org.example.Player.desktop"
        };
        full.notifications = {
            "popupsEnabled": false,
            "doNotDisturb": true,
            "criticalMode": "silence",
            "dashboardVisible": false,
            "historyVisible": false
        };
        full.weather = {
            "enabled": true,
            "consent": true,
            "locationLabel": "Bounded city",
            "latitude": -90,
            "longitude": 180,
            "temperatureUnit": "fahrenheit",
            "windUnit": "mph",
            "refreshPreset": "15m"
        };
        full.wallpaper = {
            "roots": ["/one", "/two"]
        };
        const normalized = UserConfig.validateCandidate(full);
        require(normalized !== null, "every non-default schema field is accepted");
        const serialized = UserConfig.serializeConfiguration(normalized);
        const parsed = UserConfig.parseConfiguration(serialized, UserConfig.utf8Length(serialized));
        require(parsed !== null && parsed.futureVersion === undefined && UserConfig.snapshotKey(
                    parsed) === UserConfig.snapshotKey(normalized),
                "every schema field round-trips canonically");
        const invalidDate = UserConfig.mutableSnapshot(normalized);
        invalidDate.clock.dateFormat = "yyyy qqq unsafe";
        require(UserConfig.validateCandidate(invalidDate) === null,
                "unregistered date patterns are rejected at the settings boundary");
        const tooSmallTypography = UserConfig.mutableSnapshot(normalized);
        tooSmallTypography.appearance.idleBaseFontSize = UserConfig.minimumBaseFontSize - 1;
        require(UserConfig.validateCandidate(tooSmallTypography) === null,
                "base typography size rejects values below the safe partition");
        const tooLargeTypography = UserConfig.mutableSnapshot(normalized);
        tooLargeTypography.appearance.controlCenterBaseFontSize = UserConfig.maximumBaseFontSize
                + 1;
        require(UserConfig.validateCandidate(tooLargeTypography) === null,
                "base typography size rejects values above the safe partition");
        const oversizedFamily = UserConfig.mutableSnapshot(normalized);
        oversizedFamily.appearance.expandedFontFamily = "x".repeat(
                    UserConfig.maximumFontFamilyBytes + 1);
        require(UserConfig.validateCandidate(oversizedFamily) === null,
                "scoped font families retain the bounded string contract");
        const continuousPartitions = [
                  {
                      "page": "appearance",
                      "key": "surfaceOpacity",
                      "values": [0.85, 0.9, 0.96, 1]
                  },
                  {
                      "page": "appearance",
                      "key": "borderIntensity",
                      "values": [0, 0.25, 0.5, 0.75, 1]
                  },
                  {
                      "page": "appearance",
                      "key": "outerRadius",
                      "values": [8, 12, 16, 24, 32]
                  },
                  {
                      "page": "appearance",
                      "key": "idleBaseFontSize",
                      "values": [11, 13, 18]
                  },
                  {
                      "page": "appearance",
                      "key": "expandedBaseFontSize",
                      "values": [11, 13, 18]
                  },
                  {
                      "page": "appearance",
                      "key": "controlCenterBaseFontSize",
                      "values": [11, 13, 18]
                  },
                  {
                      "page": "island",
                      "key": "compactHeight",
                      "values": [44, 45, 46, 47, 48]
                  },
                  {
                      "page": "island",
                      "key": "compactPadding",
                      "values": [16, 20, 24, 28, 32]
                  },
                  {
                      "page": "island",
                      "key": "expandedWidthPercent",
                      "values": [0.6, 0.7, 0.8, 0.9, 1]
                  },
                  {
                      "page": "island",
                      "key": "expandedHeightPercent",
                      "values": [0.6, 0.7, 0.8, 0.9, 1]
                  }
              ];
        for (let partition = 0; partition < continuousPartitions.length; partition += 1) {
            const entry = continuousPartitions[partition];
            for (let valueIndex = 0; valueIndex < entry.values.length; valueIndex += 1) {
                const candidate = UserConfig.mutableSnapshot(UserConfig.defaultSnapshot(0));
                candidate[entry.page][entry.key] = entry.values[valueIndex];
                require(UserConfig.validateCandidate(candidate) !== null, entry.page + "."
                        + entry.key + " partition " + entry.values[valueIndex]
                        + " stays inside the complete schema invariants");
            }
        }

        const legacyAlphaContent = "[theme]\nmode=accent\naccent=#CC24C78A\n";
        const legacyAlpha = UserConfig.parseLegacyConfiguration(legacyAlphaContent,
                                                                UserConfig.utf8Length(
                                                                    legacyAlphaContent));
        require(legacyAlpha !== null && legacyAlpha.appearance.customAccent === "#CC24C78A",
                "valid V1 alpha accent migrates without loss");

        const invalid = ["[settings]\nschema_version=2\n[unknown]\nvalue=x\n",
                         "[settings]\nschema_version=2\n",
                         "[settings]\nschema_version=2\n[settings]\nschema_version=2\n",
                         "[settings]\nschema_version=2\n[media]\nenabled=\n",
                         "[settings]\nschema_version=2\n[appearance]\nsurface_opacity=Infinity\n",
                         "[settings]\nschema_version=2\n[island]\ncompact_height=43\n",
                         "[settings]\nschema_version=2\n[clock]\nformat=locale\n",
                         "[settings]\nschema_version=2\n[media]\nplayer_policy=preferred\n",
                         "[settings]\nschema_version=2\n[notifications]\ncritical_mode=all\n",
                         "[settings]\nschema_version=2\n[weather]\nenabled=true\n",
                         "[settings]\nschema_version=2\n[wallpaper]\nroots=[\"relative\"]\n",
                         "[settings]\nschema_version=2\n[wallpaper]\nroots=[\"/same\",\"/same\"]\n",
                         "[settings]\nschema_version=2\u0000\n"];
        for (let index = 0; index < invalid.length; index += 1) {
            require(UserConfig.parseConfiguration(invalid[index], UserConfig.utf8Length(
                                                      invalid[index])) === null,
                    "invalid schema fixture " + index + " is rejected");
        }
        require(UserConfig.parseConfiguration("x".repeat(UserConfig.maximumConfigBytes + 1),
                                              UserConfig.maximumConfigBytes + 1) === null,
                "oversized settings are rejected before parsing");
        const futureContent = "[settings]\nschema_version=4\n[x]\ny=z\n";
        const future = UserConfig.parseConfiguration(futureContent, UserConfig.utf8Length(
                                                         futureContent));
        require(future !== null && future.futureVersion === 4,
                "future schema detection ignores unknown future fields safely");
    }
    function requireTextFillContrast(snapshot, label) {
        require(snapshot !== null, label + " publishes a theme snapshot");
        const statePairs = [
                  ["surface hover", snapshot.surfaceHoverForeground, snapshot.surfaceHover],
                  ["surface active", snapshot.surfaceActiveForeground, snapshot.surfaceActive],
                  ["control fill", snapshot.controlFillForeground, snapshot.controlFill],
                  ["control fill hover", snapshot.controlFillHoverForeground,
                   snapshot.controlFillHover],
                  ["control fill pressed", snapshot.controlFillPressedForeground,
                   snapshot.controlFillPressed],
                  ["rail", snapshot.controlCenterRailForeground,
                   snapshot.controlCenterRailSurface],
                  ["selected rail", snapshot.controlCenterRailSelectedForeground,
                   snapshot.controlCenterRailSelectedSurface]
              ];
        for (let index = 0; index < statePairs.length; index += 1) {
            const pair = statePairs[index];
            const ratio = Theme.contrast(pair[1], pair[2]);
            require(Theme.canonicalHex(pair[1]) !== null && ratio >= 4.5,
                    label + " keeps " + pair[0] + " foreground at 4.5:1 ("
                    + ratio.toFixed(3) + ")");
            if (Theme.contrast(snapshot.textPrimary, pair[2]) >= 4.5) {
                require(pair[1] === snapshot.textPrimary,
                        label + " preserves primary text for safe " + pair[0]);
            }
        }

        const accentPairs = [
                  ["surface hover", snapshot.surfaceHoverAccent, snapshot.surfaceHover],
                  ["surface active", snapshot.surfaceActiveAccent, snapshot.surfaceActive],
                  ["rail", snapshot.controlCenterRailAccent, snapshot.controlCenterRailSurface],
                  ["selected rail", snapshot.controlCenterRailSelectedAccent,
                   snapshot.controlCenterRailSelectedSurface]
              ];
        for (let index = 0; index < accentPairs.length; index += 1) {
            const pair = accentPairs[index];
            const ratio = Theme.contrast(pair[1], pair[2]);
            require(Theme.canonicalHex(pair[1]) !== null && ratio >= 3,
                    label + " keeps " + pair[0] + " accent at 3:1 ("
                    + ratio.toFixed(3) + ")");
            if (Theme.contrast(snapshot.accent, pair[2]) >= 3) {
                require(pair[1] === snapshot.accent,
                        label + " preserves the accent for safe " + pair[0]);
            }
        }

        const controlFillAccentRatio = Theme.contrast(snapshot.controlFillAccent,
                                                      snapshot.controlFill);
        require(Theme.canonicalHex(snapshot.controlFillAccent) !== null
                && controlFillAccentRatio >= 4.5,
                label + " keeps accent status text on control fill at 4.5:1 ("
                + controlFillAccentRatio.toFixed(3) + ")");
        if (Theme.contrast(snapshot.accent, snapshot.controlFill) >= 4.5) {
            require(snapshot.controlFillAccent === snapshot.accent,
                    label + " preserves the accent for safe control-fill status text");
        }
        const surfaceActiveAccentTextRatio = Theme.contrast(snapshot.surfaceActiveAccentText,
                                                            snapshot.surfaceActive);
        require(Theme.canonicalHex(snapshot.surfaceActiveAccentText) !== null
                && surfaceActiveAccentTextRatio >= 4.5,
                label + " keeps accent text on surface active at 4.5:1 ("
                + surfaceActiveAccentTextRatio.toFixed(3) + ")");
        if (Theme.contrast(snapshot.accent, snapshot.surfaceActive) >= 4.5) {
            require(snapshot.surfaceActiveAccentText === snapshot.accent,
                    label + " preserves accent text when it is safe on surface active");
        }
        const surfaceHoverWarningRatio = Theme.contrast(snapshot.surfaceHoverWarning,
                                                        snapshot.surfaceHover);
        require(Theme.canonicalHex(snapshot.surfaceHoverWarning) !== null
                && surfaceHoverWarningRatio >= 3,
                label + " keeps warning graphics on surface hover at 3:1 ("
                + surfaceHoverWarningRatio.toFixed(3) + ")");
        if (Theme.contrast(snapshot.warning, snapshot.surfaceHover) >= 3) {
            require(snapshot.surfaceHoverWarning === snapshot.warning,
                    label + " preserves warning color when it is safe on surface hover");
        }
        const surfaceActiveWarningRatio = Theme.contrast(snapshot.surfaceActiveWarning,
                                                         snapshot.surfaceActive);
        require(Theme.canonicalHex(snapshot.surfaceActiveWarning) !== null
                && surfaceActiveWarningRatio >= 3,
                label + " keeps warning graphics on surface active at 3:1 ("
                + surfaceActiveWarningRatio.toFixed(3) + ")");
        if (Theme.contrast(snapshot.warning, snapshot.surfaceActive) >= 3) {
            require(snapshot.surfaceActiveWarning === snapshot.warning,
                    label + " preserves warning color when it is safe on surface active");
        }

        const pairs = [
                  ["accent foreground on accent", snapshot.accentForeground, snapshot.accent],
                  ["accent foreground on accent hover", snapshot.accentForeground,
                   snapshot.accentHover],
                  ["accent foreground on accent pressed", snapshot.accentForeground,
                   snapshot.accentPressed],
                  ["primary text on surface", snapshot.textPrimary, snapshot.surface],
                  ["primary text on danger fill", snapshot.textPrimary, snapshot.dangerFill],
                  ["secondary text on surface", snapshot.textSecondary, snapshot.surface],
                  ["secondary text on control fill", snapshot.textSecondary,
                   snapshot.controlFill],
                  ["secondary text on danger fill", snapshot.textSecondary, snapshot.dangerFill],
                  ["muted text on surface", snapshot.textMuted, snapshot.surface],
                  ["muted text on control fill", snapshot.textMuted, snapshot.controlFill],
                  ["danger text on surface", snapshot.danger, snapshot.surface],
                  ["danger text on control fill", snapshot.danger, snapshot.controlFill],
                  ["danger text on danger fill", snapshot.danger, snapshot.dangerFill],
                  ["danger text on danger hover fill", snapshot.danger, snapshot.dangerFillHover],
                  ["danger text on danger pressed fill", snapshot.danger,
                   snapshot.dangerFillPressed],
                  ["warning text on surface", snapshot.warning, snapshot.surface],
                  ["warning text on control fill", snapshot.warning, snapshot.controlFill],
                  ["success text on surface", snapshot.success, snapshot.surface],
                  ["success text on control fill", snapshot.success, snapshot.controlFill]
              ];
        for (let index = 0; index < pairs.length; index += 1) {
            const ratio = Theme.contrast(pairs[index][1], pairs[index][2]);
            require(ratio >= 4.5, label + " keeps " + pairs[index][0] + " at 4.5:1 ("
                    + ratio.toFixed(3) + ")");
        }

        require(snapshot.contrast.surfaceHoverOnBase >= 1.08
                && snapshot.contrast.surfaceActiveOnBase >= 1.16
                && snapshot.contrast.controlCenterRailOnSurface >= 1.08
                && snapshot.contrast.controlCenterRailOnSurface < 2
                && snapshot.contrast.controlCenterRailSelectedOnRail >= 1.16,
                label + " retains every tonal state-distinction floor");
    }

    function validateAppearanceContract() {
        const defaults = UserConfig.defaultSnapshot(0).appearance;
        const schemes = ["nagi-dark", "nagi-oled", "nagi-light", "system", "custom"];
        Theme.systemAppearance = Object.freeze({
                                                   "accent": "#3DAEE9",
                                                   "animationFactor": 1,
                                                   "colorScheme": "light",
                                                   "generation": 1,
                                                   "schemeName": "BreezeLight",
                                                   "surface": "#EFF0F1",
                                                   "text": "#232629"
                                               });
        for (let index = 0; index < schemes.length; index += 1) {
            const appearance = Object.assign({}, defaults, {
                                                 "accentMode": "nagi",
                                                 "customAccent": "#8090FF",
                                                 "customSurface": "#101010",
                                                 "customText": "#F0F0F0",
                                                 "scheme": schemes[index]
                                             });
            const snapshot = Theme.buildSnapshot(Theme.visualConfiguration(appearance));
            require(snapshot !== null && snapshot.scheme === schemes[index]
                    && snapshot.contrast.textOnSurface >= 4.5
                    && snapshot.contrast.textSecondaryOnSurface >= 4.5
                    && snapshot.contrast.textMutedOnSurface >= 4.5
                    && snapshot.contrast.statusOnSurface >= 4.5 && snapshot.contrast.dangerOnFills
                    >= 4.5 && snapshot.contrast.focusRingOnSurface >= 3, "maintained scheme "
                    + schemes[index] + " publishes a complete safe palette: " + JSON.stringify(
                        snapshot));
            requireTextFillContrast(snapshot, "maintained scheme " + schemes[index]);
            const railSurface = snapshot.controlCenterRailSurface;
            require(Theme.canonicalHex(railSurface) !== null, "maintained scheme "
                    + schemes[index] + " publishes a canonical Control Center rail surface");
            const railContrast = Theme.contrast(railSurface, snapshot.surface);
            require(railContrast >= 1.08 && railContrast < 2, "maintained scheme "
                    + schemes[index] + " keeps the rail surface distinct and low-contrast ("
                    + railContrast.toFixed(3) + ")");
            require(snapshot.contrast.surfaceHoverOnBase >= 1.08
                    && snapshot.contrast.surfaceActiveOnBase >= 1.16
                    && snapshot.contrast.controlCenterRailSelectedOnRail >= 1.16,
                    "maintained scheme " + schemes[index]
                    + " retains differentiated hover, active, and selected-rail fills");
        }
        const typographyScopes = ["idle", "expanded", "controlCenter"];
        for (let scopeIndex = 0; scopeIndex < typographyScopes.length; scopeIndex += 1) {
            const scope = typographyScopes[scopeIndex];
            const pageTitleSize = Theme.type.sizeFor(scope, "pageTitle");
            require(pageTitleSize > Theme.type.sizeFor(scope, "title")
                    && pageTitleSize < Theme.type.sizeFor(scope, "display"), scope
                    + " typography resolves a pageTitle role between section-title and display scale");
        }

        const accentModes = ["nagi", "system", "wallpaper", "custom"];
        Theme.wallpaperPalette = Object.freeze({
                                                   "accent": "#D06BFF"
                                               });
        for (let index = 0; index < accentModes.length; index += 1) {
            const appearance = Object.assign({}, defaults, {
                                                 "accentMode": accentModes[index],
                                                 "customAccent": "#8090FF"
                                             });
            const snapshot = Theme.buildSnapshot(Theme.visualConfiguration(appearance));
            require(snapshot !== null && snapshot.mode === accentModes[index]
                    && snapshot.contrast.accentForeground >= 4.5, "accent mode "
                    + accentModes[index] + " derives readable state roles");
            requireTextFillContrast(snapshot, "accent mode " + accentModes[index]);
        }
        Theme.wallpaperPalette = null;

        const legacyPalette = UserConfig.mutableSnapshot(UserConfig.defaultSnapshot(0));
        legacyPalette.appearance.scheme = "custom";
        legacyPalette.appearance.accentMode = "custom";
        legacyPalette.appearance.customSurface = "#000000";
        legacyPalette.appearance.customText = "#7A7A7A";
        legacyPalette.appearance.customAccent = "#FFFFFF";
        const normalizedLegacyPalette = UserConfig.validateCandidate(legacyPalette);
        require(UserConfig.appearanceValidationError(legacyPalette.appearance) === ""
                && normalizedLegacyPalette !== null,
                "the established 4.5:1 custom-palette boundary remains parser-valid");

        const version3Content = UserConfig.serializeConfiguration(normalizedLegacyPalette);
        const scopedTypography = "idle_font_family=Inter\nidle_base_font_size=13\n"
                + "expanded_font_family=Inter\nexpanded_base_font_size=13\n"
                + "control_center_font_family=Inter\ncontrol_center_base_font_size=13\n";
        const version2Content = version3Content.replace("schema_version=3", "schema_version=2").replace(
                    scopedTypography, "font_family=Inter\n");
        const versionedPalettes = [{
                                         "label": "V2",
                                         "content": version2Content
                                     }, {
                                         "label": "V3",
                                         "content": version3Content
                                     }];
        for (let index = 0; index < versionedPalettes.length; index += 1) {
            const fixture = versionedPalettes[index];
            const parsed = UserConfig.parseConfiguration(fixture.content, UserConfig.utf8Length(
                                                               fixture.content));
            require(parsed !== null && parsed.schemaVersion === 3 && parsed.appearance.scheme
                    === "custom" && parsed.appearance.customSurface === "#000000"
                    && parsed.appearance.customText === "#7A7A7A",
                    fixture.label + " keeps a previously valid custom palette loadable");
            const derived = Theme.buildSnapshot(Theme.visualConfiguration(parsed.appearance));
            require(derived !== null && derived.source === "custom",
                    fixture.label + " derives its configured extreme accent without fallback");
            requireTextFillContrast(derived, fixture.label + " legacy custom palette");
        }

        const previousSettings = UserConfig.snapshot;
        const previousThemeKey = Theme.snapshotKey(Theme.snapshot);
        const previousThemeGeneration = Theme.snapshot.generation;
        require(UserConfig.publish(normalizedLegacyPalette) && Theme.snapshot.generation
                > previousThemeGeneration && Theme.snapshot.surface === "#000000"
                && Theme.snapshot.textPrimary === "#7A7A7A" && Theme.snapshot.source === "custom",
                "legacy custom settings publish immediately instead of retaining a stale theme");
        requireTextFillContrast(Theme.snapshot, "published legacy custom palette");
        require(UserConfig.publish(previousSettings)
                && Theme.snapshotKey(Theme.snapshot) === previousThemeKey,
                "theme contract probe restores the prior settings snapshot");

        const extremeAccents = ["#000000", "#FFFFFF"];
        for (let index = 0; index < extremeAccents.length; index += 1) {
            const extremePalette = UserConfig.mutableSnapshot(normalizedLegacyPalette);
            extremePalette.appearance.customAccent = extremeAccents[index];
            const normalizedExtreme = UserConfig.validateCandidate(extremePalette);
            const derivedExtreme = normalizedExtreme === null ? null : Theme.buildSnapshot(
                                                                        Theme.visualConfiguration(
                                                                            normalizedExtreme.appearance));
            require(normalizedExtreme !== null && derivedExtreme !== null
                    && derivedExtreme.source === "custom",
                    extremeAccents[index] + " extreme accent derives a total custom palette");
            require(derivedExtreme.contrast.textOnSurfaceActive >= 4.5
                    && derivedExtreme.contrast.textOnControlFillHover >= 4.5
                    && derivedExtreme.contrast.textOnControlFillPressed >= 4.5,
                    extremeAccents[index]
                    + " extreme accent keeps selected, hover, and pressed text readable");
            requireTextFillContrast(derivedExtreme, extremeAccents[index] + " extreme accent");
        }
        const midtonePalette = UserConfig.mutableSnapshot(UserConfig.defaultSnapshot(0));
        midtonePalette.appearance.scheme = "custom";
        midtonePalette.appearance.accentMode = "custom";
        midtonePalette.appearance.customSurface = "#777777";
        midtonePalette.appearance.customText = "#000000";
        midtonePalette.appearance.customAccent = "#000000";
        const normalizedMidtone = UserConfig.validateCandidate(midtonePalette);
        const derivedMidtone = normalizedMidtone === null ? null : Theme.buildSnapshot(
                                                                    Theme.visualConfiguration(
                                                                        normalizedMidtone.appearance));
        require(normalizedMidtone !== null && derivedMidtone !== null
                && derivedMidtone.source === "custom"
                && derivedMidtone.surfaceActiveForeground !== derivedMidtone.textPrimary
                && derivedMidtone.contrast.surfaceActiveOnBase >= 1.16
                && derivedMidtone.contrast.accentOnSurfaceActive >= 3,
                "midtone boundary derives distinct active fill with dedicated safe foregrounds");
        requireTextFillContrast(derivedMidtone, "midtone boundary");
        const midtoneThemeGeneration = Theme.snapshot.generation;
        require(UserConfig.publish(normalizedMidtone) && Theme.snapshot.generation
                > midtoneThemeGeneration && Theme.snapshot.surface === "#777777"
                && Theme.snapshot.textPrimary === "#000000" && Theme.snapshot.source === "custom",
                "midtone parser-valid settings publish without retaining a stale theme");
        requireTextFillContrast(Theme.snapshot, "published midtone boundary");
        require(UserConfig.publish(previousSettings)
                && Theme.snapshotKey(Theme.snapshot) === previousThemeKey,
                "midtone theme probe restores the prior settings snapshot");
        require(Theme.effectiveMotionScale("full", 1) === 1 && Theme.motionMode(
                    Theme.effectiveMotionScale("full", 1)) === "full" && Theme.effectiveMotionScale(
                    "reduced", 1) === 0.5 && Theme.motionMode(Theme.effectiveMotionScale("reduced",
                                                                                         1)) === "reduced"
                && Theme.effectiveMotionScale("minimal", 1) === 0 && Theme.effectiveMotionScale(
                    "full", 0) === 0,
                "effective motion always chooses the most restrictive Nagi or KDE preference");
    }

    function runNormal() {
        switch (stage) {
        case "startup":
        {
            if (!schemaValidated) {
                validateSchemaContract();
                validateAppearanceContract();
                schemaValidated = true;
            }
            if (!awaitState(UserConfig.status === "ready" && configReader.loaded,
                            "default settings did not become ready")) {
                return;
            }
            validateSnapshot(UserConfig.snapshot);
            require(UserConfig.configPath.endsWith("/nagi-shell/settings.conf"),
                    "settings.conf is canonical");
            require(configReader.text().indexOf("[settings]\nschema_version=3") === 0,
                    "default file is canonical V3");
            require(UserConfig.snapshot.appearance.accentMode === "wallpaper"
                    && UserConfig.snapshot.media.enabled && !UserConfig.snapshot.weather.enabled,
                    "V1 visible defaults are preserved");
            baselineWriteEvents = writeEvents;
            preservedGeneration = UserConfig.snapshot.generation;
            require(UserConfig.updatePage("appearance", {
                                              "surfaceOpacity": 0.91
                                          }, true), "first continuous update is accepted");
            require(UserConfig.updatePage("appearance", {
                                              "surfaceOpacity": 0.92
                                          }, true), "second continuous update is accepted");
            require(UserConfig.updatePage("appearance", {
                                              "surfaceOpacity": 0.93
                                          }, true), "third continuous update is accepted");
            require(UserConfig.snapshot.appearance.surfaceOpacity === 0.93
                    && UserConfig.snapshot.generation === preservedGeneration + 3,
                    "safe UI changes publish immediately");
            stage = "debounced";
            poll.restart();
            return;
        }
        case "debounced":
        {
            if (!awaitState(UserConfig.status === "ready" && !UserConfig._writeInProgress
                            && configReader.text().indexOf("surface_opacity=0.93") !== -1,
                            "debounced settings were not persisted: status=" + UserConfig.status
                            + " pending=" + (UserConfig._writeCandidate !== null) + " file="
                            + configReader.text().indexOf("surface_opacity=0.93"))) {
                return;
            }
            require(writeEvents - baselineWriteEvents === 1,
                    "continuous changes produce one settings write");
            const first = UserConfig.mutableSnapshot(UserConfig.snapshot);
            first.appearance.surfaceOpacity = 0.9;
            const normalizedFirst = UserConfig.validateCandidate(first);
            UserConfig.publish(normalizedFirst);
            require(UserConfig.beginHelper("write", normalizedFirst, "persist"),
                    "first queued write starts");
            require(UserConfig.updatePage("appearance", {
                                              "surfaceOpacity": 0.89
                                          }, false), "newer update queues during persistence");
            stage = "queued-write";
            poll.restart();
            return;
        }
        case "queued-write":
        {
            if (!awaitState(UserConfig.status === "ready"
                            && UserConfig.snapshot.appearance.surfaceOpacity === 0.89
                            && configReader.text().indexOf("surface_opacity=0.89") !== -1,
                            "latest in-flight update was not persisted")) {
                return;
            }
            const external = UserConfig.mutableSnapshot(UserConfig.snapshot);
            external.clock.format = "12h";
            stage = "external-valid";
            fixtureWriter.setText(UserConfig.serializeConfiguration(external));
            return;
        }
        case "external-valid":
        {
            if (!awaitState(UserConfig.snapshot.clock.format === "12h",
                            "valid external edit did not win atomically")) {
                return;
            }
            preservedSnapshot = UserConfig.snapshot;
            stage = "external-invalid";
            fixtureWriter.setText("[broken\npartial=true\n");
            return;
        }
        case "external-invalid":
        {
            if (!awaitState(UserConfig.recoveryRequired, "invalid edit did not require recovery")) {
                return;
            }
            require(UserConfig.snapshot === preservedSnapshot,
                    "invalid content keeps the exact last-good snapshot");
            require(!UserConfig.updatePage("clock", {
                                               "format": "24h"
                                           }, false), "ordinary writes are blocked in recovery");
            require(UserConfig.restoreLastGood(), "explicit restore is accepted");
            stage = "restored";
            poll.restart();
            return;
        }
        case "restored":
        {
            if (!awaitState(UserConfig.status === "ready" && invalidReader.loaded,
                            "last-good restore did not complete")) {
                return;
            }
            require(invalidReader.text() === "[broken\npartial=true\n",
                    "invalid input is retained byte-for-byte");
            require(UserConfig.resetPage("clock"), "page reset is accepted");
            stage = "page-reset";
            poll.restart();
            return;
        }
        case "page-reset":
        {
            if (!awaitState(UserConfig.status === "ready" && UserConfig.snapshot.clock.format
                            === "24h", "page reset did not persist defaults")) {
                return;
            }
            require(UserConfig.updatePage("media", {
                                              "enabled": false
                                          }, false), "media update is accepted");
            stage = "media-off";
            poll.restart();
            return;
        }
        case "media-off":
        {
            if (!awaitState(UserConfig.status === "ready" && !UserConfig.snapshot.media.enabled,
                            "media disable did not persist")) {
                return;
            }
            require(UserConfig.resetAll(), "global reset is accepted");
            stage = "reset-all";
            poll.restart();
            return;
        }
        case "reset-all":
        {
            if (!awaitState(UserConfig.status === "ready" && UserConfig.snapshot.media.enabled
                            && UserConfig.snapshot.appearance.surfaceOpacity === 0.96,
                            "global reset did not restore versioned defaults")) {
                return;
            }
            stage = "remove";
            fixtureCommand.command = ["rm", "-f", UserConfig.configPath];
            fixtureCommand.running = true;
            return;
        }
        case "removed":
        {
            if (!awaitState(UserConfig.recoveryRequired && UserConfig.recoveryKind === "missing",
                            "missing-after-load did not preserve last-good")) {
                return;
            }
            require(UserConfig.resetAll(), "missing settings can be explicitly reset");
            stage = "missing-reset";
            poll.restart();
            return;
        }
        case "missing-reset":
        {
            if (!awaitState(UserConfig.status === "ready" && configReader.loaded,
                            "missing settings reset did not recreate the file")) {
                return;
            }
            console.log("versioned settings normal tests passed");
            Qt.exit(0);
            return;
        }
        default:
            fail("unexpected normal stage");
        }
    }

    function runVersion2Migration() {
        if (!awaitState(UserConfig.status === "ready" && !UserConfig._writeInProgress
                        && version2BackupReader.loaded && configReader.text().indexOf(
                            "schema_version=3") !== -1, "V2 settings upgrade did not complete")) {
            return;
        }
        require(UserConfig.snapshot.appearance.idleFontFamily === "Noto Sans"
                && UserConfig.snapshot.appearance.expandedFontFamily === "Noto Sans"
                && UserConfig.snapshot.appearance.controlCenterFontFamily === "Noto Sans"
                && UserConfig.snapshot.appearance.idleBaseFontSize === 13
                && UserConfig.snapshot.appearance.expandedBaseFontSize === 13
                && UserConfig.snapshot.appearance.controlCenterBaseFontSize === 13,
                "V2 font choice expands to all three V3 scopes with baseline sizes");
        require(version2BackupReader.text().indexOf("[settings]\nschema_version=2") === 0,
                "V2 settings backup retains the exact source schema");
        require(configReader.text().indexOf("idle_font_family=Noto Sans") !== -1
                && configReader.text().indexOf("expanded_font_family=Noto Sans") !== -1
                && configReader.text().indexOf("control_center_font_family=Noto Sans") !== -1,
                "V2 settings upgrade writes the canonical scoped typography keys");
        console.log("versioned settings V2 upgrade tests passed");
        Qt.exit(0);
    }

    function runMigration() {
        if (!awaitState(UserConfig.status === "ready" && backupReader.loaded,
                        "legacy migration did not complete")) {
            return;
        }
        require(UserConfig.snapshot.appearance.accentMode === "custom"
                && UserConfig.snapshot.appearance.customAccent === "#123456"
                && UserConfig.snapshot.appearance.surfaceOpacity === 0.85
                && UserConfig.snapshot.appearance.idleFontFamily === "Noto Sans"
                && UserConfig.snapshot.appearance.expandedFontFamily === "Noto Sans"
                && UserConfig.snapshot.appearance.controlCenterFontFamily === "Noto Sans"
                && UserConfig.snapshot.appearance.idleBaseFontSize === 13
                && UserConfig.snapshot.appearance.expandedBaseFontSize === 13
                && UserConfig.snapshot.appearance.controlCenterBaseFontSize === 13 &&
                !UserConfig.snapshot.media.enabled && UserConfig.snapshot.weather.enabled
                && UserConfig.snapshot.weather.consent && UserConfig.snapshot.weather.locationLabel
                === "Configured location" && UserConfig.snapshot.weather.latitude === -90
                && UserConfig.snapshot.weather.longitude === 180
                && UserConfig.snapshot.clock.format === "12h",
                "all valid V1 values migrated without loss");
        require(backupReader.text() === legacyContent, "migration backup is byte-for-byte exact");
        require(configReader.text().indexOf("schema_version=3") !== -1,
                "migration writes canonical V3");
        fixtureCommand.command = ["test", "!", "-e", UserConfig.legacyPath];
        stage = "migration-file-check";
        fixtureCommand.running = true;
    }

    function runFuture() {
        if (!awaitState(UserConfig.status === "future", "future schema was not detected")) {
            return;
        }
        require(UserConfig.readOnly && !UserConfig.writable, "future settings are read-only");
        require(UserConfig.snapshot.appearance.customAccent === "#ABCDEF",
                "future schema runs from persistent last-good state");
        require(!UserConfig.resetAll() && !UserConfig.updatePage("media", {
                                                                     "enabled": false
                                                                 }, false),
                "future settings are never downgraded or rewritten");
        require(configReader.text() === "[settings]\nschema_version=99\n[future]\nvalue=kept\n",
                "future file is retained exactly");
        console.log("versioned settings future tests passed");
        Qt.exit(0);
    }

    function runFailure() {
        switch (stage) {
        case "startup":
            if (!awaitState(UserConfig.status === "ready", "failure fixture did not load")) {
                return;
            }
            preservedSnapshot = UserConfig.snapshot;
            require(UserConfig.updatePage("appearance", {
                                              "surfaceOpacity": 0.9
                                          }, false), "failing update publishes immediately");
            require(UserConfig.snapshot.appearance.surfaceOpacity === 0.9,
                    "failing update is initially visible");
            stage = "failed";
            poll.restart();
            return;
        case "failed":
            if (!awaitState(UserConfig.status === "write-failed",
                            "injected persistence failure was not reported")) {
                return;
            }
            require(UserConfig.snapshot.appearance.surfaceOpacity
                    === preservedSnapshot.appearance.surfaceOpacity,
                    "persistence failure rolls back the complete snapshot");
            require(UserConfig.errorMessage.indexOf("could not be saved") !== -1,
                    "persistence failure is actionable and bounded");
            console.log("versioned settings rollback tests passed");
            Qt.exit(0);
            return;
        default:
            fail("unexpected failure stage");
        }
    }

    function runUnsafe() {
        if (!awaitState(UserConfig.recoveryRequired && UserConfig.recoveryKind === "path",
                        "unsafe settings path was not rejected")) {
            return;
        }
        require(UserConfig.readOnly && !UserConfig.writable,
                "unsafe settings path blocks every write");
        require(!UserConfig.resetAll() && !UserConfig.updatePage("clock", {
                                                                     "format": "12h"
                                                                 }, false),
                "unsafe path cannot be overwritten through recovery");
        console.log("versioned settings unsafe-path tests passed");
        Qt.exit(0);
    }

    function run() {
        if (!configReader.loaded) {
            configReader.reload();
        }
        if (phase === "migration" && !backupReader.loaded) {
            backupReader.reload();
        }
        if (phase === "version2" && !version2BackupReader.loaded) {
            version2BackupReader.reload();
        }
        if (stage === "restored" && !invalidReader.loaded) {
            invalidReader.reload();
        }
        if (phase === "normal") {
            runNormal();
        } else if (phase === "version2") {
            runVersion2Migration();
        } else if (phase === "migration") {
            runMigration();
        } else if (phase === "future") {
            runFuture();
        } else if (phase === "failure") {
            runFailure();
        } else if (phase === "unsafe") {
            runUnsafe();
        } else {
            fail("unknown phase");
        }
    }

    readonly property string legacyContent:
        "; preserved comment\n[theme]\nmode=accent\naccent=#123456\nsurface_opacity=0.85\nfont_family=Noto Sans\nouter_radius=32\n\n[media]\nenabled=false\n\n[weather]\nenabled=true\nlatitude=-90\nlongitude=180\n\n[clock]\nformat=12h\ndate_format=yyyy-MM-dd\nshow_idle_date=true\n"

    Component.onCompleted: poll.restart()

    FileView {
        id: configReader
        path: UserConfig.configPath
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: {
            test.writeEvents += 1;
            reload();
        }
    }

    FileView {
        id: backupReader
        path: UserConfig.migrationBackupPath
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
    }
    FileView {
        id: version2BackupReader
        path: UserConfig.version2BackupPath
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
    }

    FileView {
        id: invalidReader
        path: UserConfig.invalidBackupPath
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
    }

    FileView {
        id: fixtureWriter
        path: UserConfig.configPath
        atomicWrites: true
        blockWrites: true
        printErrors: false
        onSaved: poll.restart()
        onSaveFailed: test.fail("fixture write failed")
    }

    Process {
        id: fixtureCommand
        onExited: function (exitCode) {
            test.require(exitCode === 0, "fixture command succeeded");
            if (test.stage === "remove") {
                test.stage = "removed";
                poll.restart();
            } else if (test.stage === "migration-file-check") {
                console.log("versioned settings migration tests passed");
                Qt.exit(0);
            }
        }
    }

    Timer {
        id: poll
        interval: 50
        onTriggered: test.run()
    }

    Timer {
        interval: 15000
        running: true
        onTriggered: test.fail("settings test timed out")
    }
}

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
        require(snapshot.schemaVersion === 2, "schema version is independent and exact");
        require(snapshot.appearance.surfaceOpacity >= 0.85
                && snapshot.appearance.surfaceOpacity <= 1, "opacity is bounded");
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
            "fontFamily": "Noto Sans",
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
        require(parsed !== null && parsed.futureVersion === undefined
                && UserConfig.snapshotKey(parsed) === UserConfig.snapshotKey(normalized),
                "every schema field round-trips canonically");
        const invalidDate = UserConfig.mutableSnapshot(normalized);
        invalidDate.clock.dateFormat = "yyyy qqq unsafe";
        require(UserConfig.validateCandidate(invalidDate) === null,
                "unregistered date patterns are rejected at the settings boundary");
        const continuousPartitions = [{
                                          "page": "appearance",
                                          "key": "surfaceOpacity",
                                          "values": [0.85, 0.9, 0.96, 1]
                                      }, {
                                          "page": "appearance",
                                          "key": "borderIntensity",
                                          "values": [0, 0.25, 0.5, 0.75, 1]
                                      }, {
                                          "page": "appearance",
                                          "key": "outerRadius",
                                          "values": [8, 12, 16, 24, 32]
                                      }, {
                                          "page": "island",
                                          "key": "compactHeight",
                                          "values": [44, 45, 46, 47, 48]
                                      }, {
                                          "page": "island",
                                          "key": "compactPadding",
                                          "values": [16, 20, 24, 28, 32]
                                      }, {
                                          "page": "island",
                                          "key": "expandedWidthPercent",
                                          "values": [0.6, 0.7, 0.8, 0.9, 1]
                                      }, {
                                          "page": "island",
                                          "key": "expandedHeightPercent",
                                          "values": [0.6, 0.7, 0.8, 0.9, 1]
                                      }];
        for (let partition = 0; partition < continuousPartitions.length; partition += 1) {
            const entry = continuousPartitions[partition];
            for (let valueIndex = 0; valueIndex < entry.values.length; valueIndex += 1) {
                const candidate = UserConfig.mutableSnapshot(UserConfig.defaultSnapshot(0));
                candidate[entry.page][entry.key] = entry.values[valueIndex];
                require(UserConfig.validateCandidate(candidate) !== null,
                        entry.page + "." + entry.key + " partition " + entry.values[valueIndex]
                        + " stays inside the complete schema invariants");
            }
        }


        const legacyAlphaContent = "[theme]\nmode=accent\naccent=#CC24C78A\n";
        const legacyAlpha = UserConfig.parseLegacyConfiguration(
                    legacyAlphaContent, UserConfig.utf8Length(legacyAlphaContent));
        require(legacyAlpha !== null
                && legacyAlpha.appearance.customAccent === "#CC24C78A",
                "valid V1 alpha accent migrates without loss");

        const invalid = [
            "[settings]\nschema_version=2\n[unknown]\nvalue=x\n",
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
            "[settings]\nschema_version=2\u0000\n"
        ];
        for (let index = 0; index < invalid.length; index += 1) {
            require(UserConfig.parseConfiguration(invalid[index], UserConfig.utf8Length(
                                                      invalid[index])) === null,
                    "invalid schema fixture " + index + " is rejected");
        }
        require(UserConfig.parseConfiguration("x".repeat(UserConfig.maximumConfigBytes + 1),
                                              UserConfig.maximumConfigBytes + 1) === null,
                "oversized settings are rejected before parsing");
        const futureContent = "[settings]\nschema_version=3\n[x]\ny=z\n";
        const future = UserConfig.parseConfiguration(futureContent,
                                                     UserConfig.utf8Length(futureContent));
        require(future !== null && future.futureVersion === 3,
                "future schema detection ignores unknown future fields safely");
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
                    && snapshot.contrast.statusOnSurface >= 4.5
                    && snapshot.contrast.dangerOnFills >= 4.5
                    && snapshot.contrast.focusRingOnSurface >= 3,
                    "maintained scheme " + schemes[index] + " publishes a complete safe palette: "
                    + JSON.stringify(snapshot));
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
                    && snapshot.contrast.accentForeground >= 4.5,
                    "accent mode " + accentModes[index] + " derives readable state roles");
        }
        Theme.wallpaperPalette = null;

        const unsafeText = UserConfig.mutableSnapshot(UserConfig.defaultSnapshot(0));
        unsafeText.appearance.scheme = "custom";
        unsafeText.appearance.customSurface = "#101010";
        unsafeText.appearance.customText = "#202020";
        require(UserConfig.validateCandidate(unsafeText) === null,
                "unreadable custom text is rejected before settings publication");
        const unsafeAccent = UserConfig.mutableSnapshot(UserConfig.defaultSnapshot(0));
        unsafeAccent.appearance.scheme = "custom";
        unsafeAccent.appearance.accentMode = "custom";
        unsafeAccent.appearance.customSurface = "#101010";
        unsafeAccent.appearance.customText = "#F0F0F0";
        unsafeAccent.appearance.customAccent = "#202020";
        const normalizedAccent = UserConfig.validateCandidate(unsafeAccent);
        require(normalizedAccent !== null, "syntactically valid custom accent is normalized");
        const derivedAccent = Theme.buildSnapshot(
                    Theme.visualConfiguration(normalizedAccent.appearance));
        require(derivedAccent !== null && derivedAccent.contrast.accentOnSurface >= 3
                && derivedAccent.contrast.accentForeground >= 4.5,
                "low-contrast custom accent derives safe non-text and foreground roles");
        require(Theme.effectiveMotionScale("full", 1) === 1
                && Theme.motionMode(Theme.effectiveMotionScale("full", 1)) === "full"
                && Theme.effectiveMotionScale("reduced", 1) === 0.5
                && Theme.motionMode(Theme.effectiveMotionScale("reduced", 1)) === "reduced"
                && Theme.effectiveMotionScale("minimal", 1) === 0
                && Theme.effectiveMotionScale("full", 0) === 0,
                "effective motion always chooses the most restrictive Nagi or KDE preference");
    }


    function runNormal() {
        switch (stage) {
        case "startup": {
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
            require(configReader.text().indexOf("[settings]\nschema_version=2") === 0,
                    "default file is canonical V2");
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
        case "debounced": {
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
        case "queued-write": {
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
        case "external-valid": {
            if (!awaitState(UserConfig.snapshot.clock.format === "12h",
                            "valid external edit did not win atomically")) {
                return;
            }
            preservedSnapshot = UserConfig.snapshot;
            stage = "external-invalid";
            fixtureWriter.setText("[broken\npartial=true\n");
            return;
        }
        case "external-invalid": {
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
        case "restored": {
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
        case "page-reset": {
            if (!awaitState(UserConfig.status === "ready" && UserConfig.snapshot.clock.format === "24h",
                            "page reset did not persist defaults")) {
                return;
            }
            require(UserConfig.updatePage("media", {
                                              "enabled": false
                                          }, false), "media update is accepted");
            stage = "media-off";
            poll.restart();
            return;
        }
        case "media-off": {
            if (!awaitState(UserConfig.status === "ready" && !UserConfig.snapshot.media.enabled,
                            "media disable did not persist")) {
                return;
            }
            require(UserConfig.resetAll(), "global reset is accepted");
            stage = "reset-all";
            poll.restart();
            return;
        }
        case "reset-all": {
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
        case "removed": {
            if (!awaitState(UserConfig.recoveryRequired && UserConfig.recoveryKind === "missing",
                            "missing-after-load did not preserve last-good")) {
                return;
            }
            require(UserConfig.resetAll(), "missing settings can be explicitly reset");
            stage = "missing-reset";
            poll.restart();
            return;
        }
        case "missing-reset": {
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

    function runMigration() {
        if (!awaitState(UserConfig.status === "ready" && backupReader.loaded,
                        "legacy migration did not complete")) {
            return;
        }
        require(UserConfig.snapshot.appearance.accentMode === "custom"
                && UserConfig.snapshot.appearance.customAccent === "#123456"
                && UserConfig.snapshot.appearance.surfaceOpacity === 0.85
                && !UserConfig.snapshot.media.enabled && UserConfig.snapshot.weather.enabled
                && UserConfig.snapshot.clock.format === "12h",
                "all valid V1 values migrated without loss");
        require(backupReader.text() === legacyContent,
                "migration backup is byte-for-byte exact");
        require(configReader.text().indexOf("schema_version=2") !== -1,
                "migration writes canonical V2");
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
        if (stage === "restored" && !invalidReader.loaded) {
            invalidReader.reload();
        }
        if (phase === "normal") {
            runNormal();
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

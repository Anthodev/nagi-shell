import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    readonly property var assetFiles: ["navigation-back.svg", "launcher.svg",
        "notification-bell.svg", "tray.svg", "session.svg", "wifi.svg", "wifi-off.svg",
        "bluetooth.svg", "bluetooth-off.svg", "volume-high.svg", "volume-low.svg",
        "volume-muted.svg", "microphone.svg", "microphone-muted.svg", "brightness.svg",
        "notification.svg", "media-previous.svg", "media-play.svg", "media-pause.svg",
        "media-next.svg", "placeholder.svg"]
    readonly property var boldWirelessAssets: [
        {
            "file": "wifi.svg",
            "legacySvg":
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.75' stroke-linecap='round' stroke-linejoin='round'><path d='M3.5 8.5a13 13 0 0 1 17 0M6.5 12a8.5 8.5 0 0 1 11 0M9.5 15.5a4 4 0 0 1 5 0'/><circle cx='12' cy='19' r='.7' fill='currentColor' stroke='none'/></svg>"
        },
        {
            "file": "wifi-off.svg",
            "legacySvg":
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.75' stroke-linecap='round' stroke-linejoin='round'><path d='M3 3l18 18M4 8.3a13 13 0 0 1 4-2.1M13.5 5.3a13 13 0 0 1 6.5 3M7 12a8.5 8.5 0 0 1 3.1-1.4M14.7 11a8.5 8.5 0 0 1 2.3 1M10 15.5a4 4 0 0 1 2-.5'/></svg>"
        },
        {
            "file": "bluetooth.svg",
            "legacySvg":
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.75' stroke-linecap='round' stroke-linejoin='round'><path d='M8 7l8 10-4 3V4l4 3L8 17'/></svg>"
        },
        {
            "file": "bluetooth-off.svg",
            "legacySvg":
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.75' stroke-linecap='round' stroke-linejoin='round'><path d='M3 3l18 18M12 12V4l4 3-2.6 3.2M12 12v8l4-3-2.6-3.2M8 7l2.2 2.8M8 17l2.2-2.8'/></svg>"
        }
    ]
    readonly property string applicationSource: "file://" + Quickshell.shellPath(
                                                    "assets/icons/nagi/launcher.svg")
    readonly property string themeApplicationSource: Quickshell.iconPath("system-file-manager")
    property int lifecycleUnmountCount: 0
    property bool lifecycleRemountReady: false

    function fail(message) {
        console.error("FAIL: " + message);
        Qt.exit(1);
        throw new Error(message);
    }

    function require(condition, message) {
        if (!condition) {
            fail(message);
        }
    }

    function colorString(value) {
        return String(value).toUpperCase();
    }
    function contrastForState(state) {
        return Theme.contrast(IconResolver.resolve("launcher", state, "", "").tint.toString(),
                              IconResolver.iconSurface);
    }

    function cycleLifecycleIcon() {
        if (lifecycleUnmountCount < 12) {
            lifecycleLoader.active = false;
            lifecycleUnmountCount += 1;
            Qt.callLater(function () {
                lifecycleLoader.active = true;
                lifecycleTimer.restart();
            });
            return;
        }
        const remountedIcon = lifecycleLoader.item;
        if (remountedIcon === null || remountedIcon.loadStatus !== Image.Ready ||
                !remountedIcon.displayedSource.startsWith("data:image/svg+xml")) {
            lifecycleTimer.restart();
            return;
        }
        lifecycleRemountReady = true;
        settleTimer.restart();
    }

    function allLoadsSettled() {
        if (!lifecycleRemountReady) {
            return false;
        }
        if (invalidApplication.loadStatus !== Image.Ready) {
            return false;
        }
        if (themeApplicationIcon.loadStatus !== Image.Ready || themeTrayIcon.loadStatus
                !== Image.Ready) {
            return false;
        }
        for (let index = 0; index < assetRepeater.count; index += 1) {
            const image = assetRepeater.itemAt(index);
            if (image === null || image.status === Image.Loading || image.status === Image.Null) {
                return false;
            }
        }
        for (let index = 0; index < boldAssetRepeater.count; index += 1) {
            const sample = boldAssetRepeater.itemAt(index);
            if (sample === null || !sample.sampled) {
                return false;
            }
        }
        if (!microphoneShapeSample.sampled) {
            return false;
        }
        return true;
    }

    function runChecks() {
        if (!allLoadsSettled()) {
            // Wait until the asynchronous icon sources have settled.
            settleTimer.restart();
            return;
        }

        const nagi = IconResolver.resolve("launcher", "normal", "", "");
        require(nagi.kind === "nagi" && nagi.source.endsWith("/assets/icons/nagi/launcher.svg"),
                "Nagi identity meaning resolves to owned artwork");
        const history = IconResolver.resolve("history", "normal", "", "");
        require(history.kind === "nagi" && history.source.endsWith(
                    "/assets/icons/nagi/notification-bell.svg") && history.accessibleName
                === "Notification history",
                "History keeps its semantic label while resolving to owned bell artwork");
        const microphoneMuted = IconResolver.resolve("microphoneMuted", "off", "", "");
        require(microphoneMuted.kind === "nagi" && microphoneMuted.source.endsWith(
                    "/assets/icons/nagi/microphone-muted.svg") && microphoneMuted.accessibleName
                === "Muted microphone",
                "muted microphone meaning resolves to distinct owned artwork and label");
        require(microphoneShapeSample.microphonePixels > 0 && microphoneShapeSample.mutedPixels > 0
                && microphoneShapeSample.differentPixels > 0,
                "microphone and muted microphone assets render occupied, distinct pixel shapes");

        const system = IconResolver.resolve("lock", "normal", "", "");
        require(system.kind === "system" && String(system.source) === String(Quickshell.iconPath(
                                                                                 "system-lock-screen")),
                "normalized operating-system meaning resolves through the current icon theme");
        const settings = IconResolver.resolve("settings", "normal", "", "");
        require(settings.kind === "system" && settings.accessibleName === "Nagi Control Center"
                && String(settings.source) === String(Quickshell.iconPath("preferences-system"))
                && !settings.tintable,
                "Settings preserves the current KDE theme icon without destructive colorization");


        const application = IconResolver.resolve("application", "active", applicationSource,
                                                 "Example application");
        require(application.kind === "application" && application.source === applicationSource &&
                !application.tintable && application.tint === "transparent",
                "application artwork passes through untouched and untinted");
        require(themeApplicationIcon.resolvedKind === "application" && themeTrayIcon.resolvedKind
                === "application" && themeApplicationIcon.usesQuickshellIconProvider
                && themeTrayIcon.usesQuickshellIconProvider &&
                !themeApplicationIcon.loadsAsynchronously && !themeTrayIcon.loadsAsynchronously,
                "application and tray image-provider artwork load synchronously on the GUI thread");
        require(!applicationIcon.usesQuickshellIconProvider && applicationIcon.loadsAsynchronously,
                "local application files remain on the asynchronous image path");

        const unknown = IconResolver.resolve("not-a-meaning", "normal", "", "");
        require(unknown.kind === "placeholder" && unknown.source === IconResolver.placeholderSource,
                "invalid meanings resolve to the neutral placeholder");
        require(invalidApplication.showingFallback && invalidApplication.tinted
                && invalidApplication.rawSource === IconResolver.placeholderSource
                && invalidApplication.displayedSource.startsWith("data:image/svg+xml"),
                "invalid application files fall back to a neutral CPU-tinted placeholder");

        require(colorString(IconResolver.resolve("launcher", "normal", "", "").tint) === colorString(
                    Theme.color.textPrimary), "normal state uses the near-white icon tint");
        require(colorString(IconResolver.resolve("launcher", "off", "", "").tint) === colorString(
                    Theme.color.textPrimary), "off state stays near-white and legible");
        require(colorString(IconResolver.resolve("launcher", "disabled", "", "").tint)
                === colorString(Theme.color.textPrimary),
                "disabled state communicates through opacity without a dark tint");
        require(colorString(IconResolver.resolve("launcher", "pending", "", "").tint)
                === colorString(Theme.color.warning), "pending state uses the light warning tint");
        require(colorString(IconResolver.resolve("launcher", "error", "", "").tint) === colorString(
                    Theme.color.danger), "error state uses the readable danger tint");
        require(attentionIcon.attention && attentionIcon.tinted,
                "attention retains monochrome tint and adds the attention treatment");
        require(disabledIcon.opacity === Theme.opacity.disabled,
                "disabled state applies the shared disabled opacity");

        const states = ["normal", "active", "off", "pending", "attention", "disabled", "error"];
        for (let stateIndex = 0; stateIndex < states.length; stateIndex += 1) {
            const state = states[stateIndex];
            const floor = state === "normal" || state === "off" ? 4.5 : 3;
            require(contrastForState(state) >= floor, state + " icon tint meets its " + floor
                    + ":1 contrast floor against the island base");
        }

        Theme.wallpaperPalette = {
            "accent": "#3B5D83"
        };
        const darkWallpaperActive = IconResolver.resolve("launcher", "active", "", "").tint;
        const darkWallpaperAttention = IconResolver.resolve("launcher", "attention", "", "").tint;
        require(Theme.contrast(darkWallpaperActive.toString(), IconResolver.iconSurface) >= 4.5
                && colorString(darkWallpaperAttention) === colorString(darkWallpaperActive),
                "dark wallpaper accents produce one lightness-ensured active/attention icon tint");

        require(smallIcon.iconSize === Theme.size.iconSizeSm && normalIcon.iconSize
                === Theme.size.iconSizeMd && largeIcon.iconSize === Theme.size.iconSizeLg,
                "semantic size scale maps only to Theme icon tokens");
        require(normalIcon.accessibleName === "Launcher" && applicationIcon.accessibleName
                === "Example application",
                "primitive exposes stable semantic and application accessible names");
        require(applicationIcon.resolvedKind === "application" && !applicationIcon.tinted,
                "application-kind primitive remains untinted");
        require(normalIcon.usesSvgMask && normalIcon.displayedSource.startsWith(
                    "data:image/svg+xml"),
                "Nagi SVGs receive their tint in the source data without a shader dependency");
        require(lifecycleUnmountCount === 12 && lifecycleLoader.item !== null
                && lifecycleLoader.item.loadStatus === Image.Ready
                && lifecycleLoader.item.displayedSource.startsWith("data:image/svg+xml"),
                "rapid Loader destruction leaves the final IslandIcon remount ready");

        for (let index = 0; index < assetRepeater.count; index += 1) {
            const image = assetRepeater.itemAt(index);
            require(image.status === Image.Ready, assetFiles[index] + " parses and renders");
            require(image.implicitWidth > 0 && image.implicitHeight > 0, assetFiles[index]
                    + " has non-null implicit size");
        }
        const occupiedPixels = [];
        for (let index = 0; index < boldAssetRepeater.count; index += 1) {
            const sample = boldAssetRepeater.itemAt(index);
            require(sample.inkPixels >= 60, sample.modelData.file
                    + " occupies at least 60 visible pixels at the 18 px md size");
            require(sample.inkPixels >= Math.ceil(sample.legacyInkPixels * 1.25),
                    sample.modelData.file + " occupies at least 25% more pixels than its old mask");
            require(sample.width === Theme.size.iconSizeMd && sample.height === Theme.size.iconSizeMd,
                    sample.modelData.file + " is visibly sampled at the md icon size");
            occupiedPixels.push(sample.modelData.file + "=" + sample.inkPixels + " (old "
                                + sample.legacyInkPixels + ")");
        }

        console.warn("icon system tests passed; 18 px occupied pixels: " + occupiedPixels.join(
                         ", "));
        if (Quickshell.env("NAGI_ICON_HOLD") !== "1") {
            Qt.exit(0);
        }
    }

    Component.onCompleted: {
        Qt.callLater(test.runChecks);
        lifecycleTimer.start();
    }

    Window {
        visible: true
        width: 480
        height: 160
        color: IconResolver.iconSurface

        Row {
            spacing: 8

            IslandIcon {
                id: smallIcon
                meaning: "back"
                size: "sm"
            }
            IslandIcon {
                id: normalIcon
                meaning: "launcher"
            }
            IslandIcon {
                id: largeIcon
                meaning: "session"
                size: "lg"
            }
            IslandIcon {
                id: attentionIcon
                meaning: "notification"
                semanticState: "attention"
            }
            IslandIcon {
                id: disabledIcon
                meaning: "wifi"
                semanticState: "disabled"
            }
            IslandIcon {
                id: applicationIcon
                meaning: "application"
                semanticState: "active"
                applicationSource: test.applicationSource
                applicationName: "Example application"
            }
            IslandIcon {
                id: invalidApplication
                meaning: "application"
                applicationSource: "file:///nagi-icon-test/does-not-exist.svg"
                applicationName: "Missing application"
            }
            IslandIcon {
                id: themeApplicationIcon
                meaning: "application"
                applicationSource: test.themeApplicationSource
                applicationName: "Theme application"
                size: "lg"
            }
            IslandIcon {
                id: themeTrayIcon
                meaning: "trayApplication"
                applicationSource: test.themeApplicationSource
                applicationName: "Theme tray application"
                size: "lg"
            }
        }

        Loader {
            id: lifecycleLoader

            x: 320
            active: true
            sourceComponent: Component {
                IslandIcon {
                    meaning: "microphone"
                    semanticState: "off"
                }
            }
        }

        Repeater {
            id: assetRepeater
            model: test.assetFiles

            Image {
                required property string modelData

                x: -100
                y: -100
                width: 24
                height: 24
                source: "file://" + Quickshell.shellPath("assets/icons/nagi/" + modelData)
                sourceSize.width: 24
                sourceSize.height: 24
                asynchronous: true
            }
        }

        Repeater {
            id: boldAssetRepeater
            model: test.boldWirelessAssets

            Canvas {
                required property var modelData
                readonly property string assetSource: "file://" + Quickshell.shellPath(
                                                          "assets/icons/nagi/" + modelData.file)
                readonly property string legacySource: "data:image/svg+xml;utf8,"
                                                       + encodeURIComponent(modelData.legacySvg)
                property int inkPixels: 0
                property int legacyInkPixels: 0
                property bool sampled: false

                x: -100
                y: 40
                width: Theme.size.iconSizeMd
                height: Theme.size.iconSizeMd

                function countOccupiedPixels(context) {
                    const pixelData = context.getImageData(0, 0, width, height).data;
                    let occupied = 0;
                    for (let offset = 3; offset < pixelData.length; offset += 4) {
                        if (pixelData[offset] >= 32) {
                            occupied += 1;
                        }
                    }
                    return occupied;
                }

                Component.onCompleted: {
                    loadImage(assetSource);
                    loadImage(legacySource);
                }
                onImageLoaded: requestPaint()
                onPaint: {
                    if (!isImageLoaded(assetSource) || !isImageLoaded(legacySource)) {
                        return;
                    }
                    const context = getContext("2d");
                    context.clearRect(0, 0, width, height);
                    context.drawImage(assetSource, 0, 0, width, height);
                    inkPixels = countOccupiedPixels(context);
                    context.clearRect(0, 0, width, height);
                    context.drawImage(legacySource, 0, 0, width, height);
                    legacyInkPixels = countOccupiedPixels(context);
                    sampled = true;
                }
            }
        }

        Canvas {
            id: microphoneShapeSample

            readonly property string microphoneSource: IconResolver.resolve("microphone", "normal",
                                                                            "", "").source
            readonly property string mutedSource: IconResolver.resolve("microphoneMuted", "off", "",
                                                                       "").source
            property int microphonePixels: 0
            property int mutedPixels: 0
            property int differentPixels: 0
            property bool sampled: false

            x: -100
            y: 80
            width: 24
            height: 24

            function occupied(pixelData) {
                let count = 0;
                for (let offset = 3; offset < pixelData.length; offset += 4) {
                    if (pixelData[offset] >= 32) {
                        count += 1;
                    }
                }
                return count;
            }

            Component.onCompleted: {
                loadImage(microphoneSource);
                loadImage(mutedSource);
            }
            onImageLoaded: requestPaint()
            onPaint: {
                if (!isImageLoaded(microphoneSource) || !isImageLoaded(mutedSource)) {
                    return;
                }
                const context = getContext("2d");
                context.clearRect(0, 0, width, height);
                context.drawImage(microphoneSource, 0, 0, width, height);
                const microphoneData = context.getImageData(0, 0, width, height).data;
                microphonePixels = occupied(microphoneData);
                context.clearRect(0, 0, width, height);
                context.drawImage(mutedSource, 0, 0, width, height);
                const mutedData = context.getImageData(0, 0, width, height).data;
                mutedPixels = occupied(mutedData);
                let differences = 0;
                for (let offset = 3; offset < mutedData.length; offset += 4) {
                    if (microphoneData[offset] !== mutedData[offset]) {
                        differences += 1;
                    }
                }
                differentPixels = differences;
                sampled = true;
            }
        }
    }
    Timer {
        id: lifecycleTimer

        interval: 1
        onTriggered: test.cycleLifecycleIcon()
    }

    Timer {
        id: settleTimer
        interval: 25
        onTriggered: test.runChecks()
    }

    Timer {
        interval: 10000
        running: true
        onTriggered: test.fail("icon system test timed out")
    }
}

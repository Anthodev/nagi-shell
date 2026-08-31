pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "qml"

ShellRoot {
    id: test

    property string stage: "initial"
    property int toggleRequests: 0
    property int sliderRequests: 0
    property int choiceRequests: 0
    property int colorRequests: 0
    property int actionRequests: 0
    property int pageResetRequests: 0
    property int resetAllRequests: 0
    property int unloadRequestCount: 0
    property var controls: []
    property var repeatedSection: null
    readonly property string captureDirectory: Quickshell.env("NAGI_CONTROL_CENTER_CAPTURE_DIR")
                                               ?? ""
    property var tokenA: ({})
    property var tokenB: ({})

    readonly property string privacyArtifactDirectory: Quickshell.env(
                                                           "NAGI_CONTROL_CENTER_ARTIFACT_DIR") ?? ""
    readonly property var privacyCorpus: Object.freeze({
                                                           "wifiSsid": "SensitiveSSID",
                                                           "wifiSecret": "wifi-secret-82",
                                                           "bluetoothAddress": "AA:BB:CC:DD:EE:82",
                                                           "bluetoothName": "Private Headset 82",
                                                           "bluetoothPin": "4821",
                                                           "bluetoothPasskey": "654321",
                                                           "notificationSender": "sender-private-82",
                                                           "notificationBody":
                                                           "notification-body-private-82",
                                                           "weatherLabel":
                                                           "Private Weather Label 82",
                                                           "weatherLatitude": 48.8566,
                                                           "weatherLongitude": 2.3522,
                                                           "weatherProviderBody":
                                                           "provider-body-private-82",
                                                           "displayMetadata":
                                                           "Display Serial Private 82",
                                                           "wallpaperPath":
                                                           "/home/test/private-wallpaper-82.png",
                                                           "wallpaperDigest": "digest-private-82",
                                                           "executable":
                                                           "/opt/private/bin/private-app-82",
                                                           "pid": 824282,
                                                           "rawDbus": "raw-dbus-private-82"
                                                       })
    readonly property var privacyForbiddenValues: Object.freeze([privacyCorpus.wifiSsid,
                                                                 privacyCorpus.wifiSecret,
                                                                 privacyCorpus.bluetoothAddress,
                                                                 privacyCorpus.bluetoothName,
                                                                 privacyCorpus.bluetoothPin,
                                                                 privacyCorpus.bluetoothPasskey,
                                                                 privacyCorpus.notificationSender,
                                                                 privacyCorpus.notificationBody,
                                                                 privacyCorpus.weatherLabel, String(
                                                                     privacyCorpus.weatherLatitude),
                                                                 String(privacyCorpus.weatherLongitude),
                                                                 privacyCorpus.weatherProviderBody,
                                                                 privacyCorpus.displayMetadata,
                                                                 privacyCorpus.wallpaperPath,
                                                                 privacyCorpus.wallpaperDigest,
                                                                 privacyCorpus.executable, String(
                                                                     privacyCorpus.pid),
                                                                 privacyCorpus.rawDbus])
    readonly property string alternateWifiSsid: "Alternate-Fixture-Network-82"
    readonly property string alternateWifiSecret: "alternate-wifi-render-secret-with-another-length"
    property var privacyAccessibility: []
    property string privacyDiagnostic: ""
    property int privacyArtifactSaveCount: 0
    property string writableSettingsFixture: ""
    property real requestedTallHeight: 0
    property real requestedTiledWidth: 0
    function fail(message) {
        console.error("FAIL: " + message + " (stage=" + stage + ")");
        Qt.exit(1);
        throw new Error(message);
    }

    function require(condition, message) {
        if (!condition) {
            fail(message);
        }
    }

    function routeHeaderName(routeId) {
        const headerNames = {
            "island": "islandPageHeader",
            "appearance": "appearancePageHeader",
            "clock-date": "clockPageHeader",
            "media": "mediaPageHeader",
            "weather": "weatherPageHeader",
            "notifications": "notificationsPageHeader",
            "wifi": "wifiPageHeader",
            "bluetooth": "bluetoothPageHeader",
            "wallpaper": "wallpaperPageHeader",
            "displays": "displaysPageHeader",
            "about": "aboutPageHeader"
        };
        return headerNames[routeId];
    }

    function requireCurrentPageHeader() {
        if (controlCenter.loadedPageItem === null) {
            return;
        }
        const routeIndex = controlCenter.currentRouteIndex();
        const route = controlCenter.availableRoutes[routeIndex];
        const page = controlCenter.loadedPageItem;
        const header = findObject(page, routeHeaderName(route.id));
        const surface = findObject(header, "controlCenterPageHeaderSurface");
        const well = findObject(header, "controlCenterPageHeaderIconWell");
        const title = findObject(header, "controlCenterPageHeaderTitle");
        const description = findObject(header, "controlCenterPageHeaderDescription");
        const icon = findObject(header, "controlCenterPageHeaderIcon");
        const focusRing = findObject(header, "controlCenterPageHeaderFocusRing");
        require(header !== null && surface !== null && well !== null && title !== null
                && description !== null && icon !== null && focusRing !== null
                && header.iconMeaning === route.icon && title.text === route.name
                && description.text !== "" && icon.resolvedKind === "nagi"
                && icon.width === Theme.size.iconSizeLg, route.name
                + " uses the shared semantic hero");
        const pageTitleSize = Theme.type.sizeFor("controlCenter", "pageTitle");
        require(title.typographyScope === "controlCenter"
                && title.font.pixelSize === pageTitleSize && pageTitleSize
                > Theme.type.sizeFor("controlCenter", "title") && pageTitleSize
                < Theme.type.sizeFor("controlCenter", "display")
                && title.Accessible.role !== 0 && title.Accessible.name === route.name, route.name
                + " keeps the sole pageTitle above the section-caption scale");
        require(header.controlCenterPageFocusTarget && !header.activeFocusOnTab
                && header.Accessible.role === Accessible.Pane
                && header.Accessible.name === route.name
                && header.Accessible.description === description.text
                && header.Accessible.focusable && header.Accessible.focused === header.activeFocus
                && focusRing.visible === header.activeFocus, route.name
                + " exposes one programmatic accessible page-focus fallback");
        require(countInSubtree(page, function (item) {
                    return item.controlCenterPageFocusTarget === true;
                }) === 1, route.name + " owns exactly one explicit page-focus fallback");
        require(surface.color === Theme.color.controlFill && surface.radius === Theme.radius.lg
                && surface.border.width === 0 && Math.abs(surface.width - header.width) <= 0.5
                && header.Layout.bottomMargin === Theme.spacing.lg
                && header.parent.spacing === Theme.spacing.sm, route.name
                + " uses one full-width borderless tonal hero on the 8 px root rhythm");
        const pageBase = Theme.rgb(String(Theme.color.surfaceOpaque));
        const heroFill = Theme.rgb(String(surface.color), String(Theme.color.surfaceOpaque));
        require(Theme.contrast(heroFill, pageBase) >= 1.12, route.name
                + " keeps the hero visibly distinct from the page base");
        require(well.width === Theme.size.controlCenterHeroIconWellSize && well.height
                === Theme.size.controlCenterHeroIconWellSize && well.radius === well.width / 2
                && well.color === Theme.color.surfaceActive,
                route.name + " uses the circular neutral hero icon well");
        const wellFill = Theme.rgb(String(well.color), Theme.hex(heroFill));
        const titleForeground = Theme.rgb(String(title.color), Theme.hex(heroFill));
        const descriptionForeground = Theme.rgb(String(description.color), Theme.hex(heroFill));
        const iconForeground = Theme.rgb(String(icon.tint), Theme.hex(wellFill));
        const focusRingForeground = Theme.rgb(String(focusRing.border.color), Theme.hex(heroFill));
        require(Theme.contrast(titleForeground, heroFill) >= 4.5
                && Theme.contrast(descriptionForeground, heroFill) >= 4.5
                && Theme.contrast(iconForeground, wellFill) >= 3
                && Theme.contrast(focusRingForeground, heroFill) >= 3, route.name
                + " keeps hero text, icon, and keyboard focus contrast against their actual surfaces");
        const surfaceRect = captureItemRect(surface, page);
        const layoutRect = captureItemRect(well.parent, page);
        const wellRect = captureItemRect(well, page);
        const iconRect = captureItemRect(icon, page);
        const titleRect = captureItemRect(title, page);
        const descriptionRect = captureItemRect(description, page);
        requireCaptureRectInside(captureItemRect(focusRing, header), {
                                     "x": 0,
                                     "y": 0,
                                     "width": header.width,
                                     "height": header.height
                                 }, route.name + " keeps the page focus cue inside the clipped hero");
        const centerX = surfaceRect.x + surfaceRect.width / 2;
        require(Math.abs(layoutRect.x - surfaceRect.x - Theme.spacing.xl) <= 1
                && Math.abs(layoutRect.x + layoutRect.width - (surfaceRect.x + surfaceRect.width
                                                               - Theme.spacing.xl)) <= 1
                && Math.abs(layoutRect.y - surfaceRect.y - Theme.spacing.xl) <= 1
                && Math.abs(layoutRect.y + layoutRect.height - (surfaceRect.y + surfaceRect.height
                                                                 - Theme.spacing.xl)) <= 1,
                route.name + " keeps exact 24 px hero padding");
        require(Math.abs(titleRect.y - (wellRect.y + wellRect.height) - Theme.spacing.md) <= 1
                && Math.abs(descriptionRect.y - (titleRect.y + titleRect.height)
                            - Theme.spacing.sm) <= 1, route.name
                + " keeps the 12 px icon/title and 8 px title/description rhythm");
        require(Math.abs(wellRect.x + wellRect.width / 2 - centerX) <= 1
                && Math.abs(titleRect.x + titleRect.width / 2 - centerX) <= 1
                && Math.abs(descriptionRect.x + descriptionRect.width / 2 - centerX) <= 1
                && Math.abs(iconRect.x + iconRect.width / 2 - (wellRect.x + wellRect.width / 2))
                <= 1, route.name + " centers the icon, title, and description on one hero axis");
        require(title.horizontalAlignment === Text.AlignHCenter
                && description.horizontalAlignment === Text.AlignHCenter
                && description.width <= Theme.size.controlCenterHeroDescriptionMaximumWidth + 0.5
                && description.elide === Text.ElideNone && description.wrapMode !== Text.NoWrap
                && !description.truncated && description.paintedWidth <= description.width + 0.5
                && description.paintedHeight <= description.height + 0.5 && header.height <= 240
                && countInSubtree(page, function (item) {
                    return item.objectName === "controlCenterPageHeaderTitle";
                }) === 1, route.name
                + " keeps one bounded centered hero heading readable through 18 px");
    }
    function captureRoutePrefix() {
        return controlCenter.layoutMode === "sidebar" ? "controlCenterSidebarRoute-" :
                                                        "controlCenterCompactRoute-";
    }

    function captureRouteIconsTerminalReady() {
        const prefix = captureRoutePrefix();
        for (let index = 0; index < controlCenter.availableRoutes.length; index += 1) {
            const route = controlCenter.availableRoutes[index];
            const routeItem = findObject(controlCenter.contentItem, prefix + route.id);
            const icon = findObject(routeItem, "controlCenterRouteIcon-" + index);
            if (routeItem === null || icon === null || !icon.terminalReady) {
                return false;
            }
        }
        return true;
    }

    function captureItemRect(item, target) {
        const origin = item.mapToItem(target, 0, 0);
        return {
            "x": origin.x,
            "y": origin.y,
            "width": item.width,
            "height": item.height
        };
    }

    function requireCaptureRectInside(candidate, boundary, context) {
        require(candidate.width > 0 && candidate.height > 0 && candidate.x
                >= boundary.x - 0.5 && candidate.y >= boundary.y - 0.5 && candidate.x
                + candidate.width <= boundary.x + boundary.width + 0.5 && candidate.y
                + candidate.height <= boundary.y + boundary.height + 0.5, context);
    }


    function itemDescendsFrom(item, ancestor) {
        let candidate = item;
        for (let depth = 0; candidate !== null && candidate !== undefined && depth < 128;
             depth += 1) {
            if (candidate === ancestor) {
                return true;
            }
            candidate = candidate.parent;
        }
        return false;
    }

    function pageFocusFallback(page) {
        return findInSubtree(page, function (item) {
            return item.controlCenterPageFocusTarget === true;
        });
    }

    function routeActivationFocusReady(expectFallback) {
        if (!controlCenter.pageLoaded || controlCenter.loadedPageItem === null
                || controlCenter.backingWindow === null) {
            return false;
        }
        const page = controlCenter.loadedPageItem;
        const target = controlCenter.backingWindow.activeFocusItem;
        const expected = expectFallback === true ? pageFocusFallback(page) :
                                                   page.nextItemInFocusChain(true);
        return expected !== null && target === expected && itemDescendsFrom(target, page)
                && target.visible && target.enabled && target.width > 0 && target.height > 0;
    }

    function requireRouteActivationFocus(context, expectFallback) {
        const fallbackExpected = expectFallback === true;
        require(routeActivationFocusReady(fallbackExpected), context
                + (fallbackExpected
                   ? " focuses the explicit page header when no setting control is eligible"
                   : " focuses the deterministic first eligible control inside the loaded page"));
        const page = controlCenter.loadedPageItem;
        const target = controlCenter.backingWindow.activeFocusItem;
        requireCaptureRectInside(captureItemRect(target, page), {
                                     "x": 0,
                                     "y": 0,
                                     "width": page.width,
                                     "height": page.height
                                 }, context + " reveals the focused page target inside its viewport");
        require(target.Accessible.name !== undefined && String(target.Accessible.name) !== "",
                context + " focuses an accessibly named page target");
        if (fallbackExpected) {
            const fallback = pageFocusFallback(page);
            const firstEligible = page.nextItemInFocusChain(true);
            const focusRing = findObject(fallback, "controlCenterPageHeaderFocusRing");
            require(target === fallback && fallback.activeFocus && !fallback.activeFocusOnTab
                    && fallback.Accessible.focusable && fallback.Accessible.focused
                    && focusRing !== null && focusRing.visible
                    && (firstEligible === null || firstEligible === page
                        || firstEligible === fallback || !itemDescendsFrom(firstEligible, page)),
                    context + " uses the visible page-owned fallback only without an eligible control");
        } else {
            require(target === page.nextItemInFocusChain(true), context
                    + " preserves first-control focus for writable pages");
        }
    }

    function requirePageHeaderTabContinuation(context) {
        const page = controlCenter.loadedPageItem;
        const header = pageFocusFallback(page);
        const firstControl = page.nextItemInFocusChain(true);
        const previousControl = header === null ? null : header.nextItemInFocusChain(false);
        const focusRing = findObject(header, "controlCenterPageHeaderFocusRing");
        require(header !== null && firstControl !== null && firstControl !== page
                && firstControl !== header && itemDescendsFrom(firstControl, page)
                && firstControl.visible && firstControl.enabled && previousControl !== null
                && previousControl !== header && previousControl.visible && previousControl.enabled,
                context + " exposes normal focus-chain neighbors around the page header");
        header.forceActiveFocus(Qt.TabFocusReason);
        require(header.activeFocus && focusRing !== null && focusRing.visible, context
                + " renders keyboard focus on the programmatic page entry target");
        require(header.focusPreviousControl()
                && controlCenter.backingWindow.activeFocusItem === previousControl
                && previousControl.activeFocus, context
                + " preserves reverse Shift+Tab traversal from the page header");
        header.forceActiveFocus(Qt.TabFocusReason);
        require(header.activeFocus && focusRing.visible && header.focusNextControl()
                && controlCenter.backingWindow.activeFocusItem === firstControl
                && firstControl.activeFocus, context
                + " continues forward Tab focus into the first enabled control");
    }
    function requireRouteComposition(mode, context, requireOverflow) {
        const sidebar = mode === "sidebar";
        const prefix = sidebar ? "controlCenterSidebarRoute-" : "controlCenterCompactRoute-";
        const viewport = findObject(controlCenter.contentItem, sidebar
                                    ? "controlCenterSidebarRouteViewport" :
                                      "controlCenterCompactRouteViewport");
        require(viewport !== null && viewport.visible && viewport.clip && viewport.contentWidth
                === viewport.width, context + " exposes one clipped route viewport");
        if (requireOverflow === true) {
            require(viewport.contentHeight > viewport.height && viewport.interactive, context
                    + " scrolls the eleven routes at the minimum window height");
        }
        let previousBottom = -Theme.spacing.xs;
        for (let index = 0; index < controlCenter.availableRoutes.length; index += 1) {
            const route = controlCenter.availableRoutes[index];
            const routeItem = findObject(controlCenter.contentItem, prefix + route.id);
            const well = findObject(routeItem, "controlCenterRouteIconWell-" + index);
            const icon = findObject(routeItem, "controlCenterRouteIcon-" + index);
            const label = findObject(routeItem, "controlCenterRouteLabel-" + index);
            require(routeItem !== null && routeItem.visible && well !== null && icon !== null
                    && label !== null && icon.terminalReady && icon.loadStatus === Image.Ready,
                    context + " renders the complete " + route.name + " route");
            const routeRect = captureItemRect(routeItem, viewport.contentItem);
            const wellRect = captureItemRect(well, routeItem);
            const iconRect = captureItemRect(icon, routeItem);
            const labelRect = captureItemRect(label, routeItem);
            require(routeItem.height >= Theme.size.controlCenterRouteHeight
                    && Math.abs(routeItem.width - viewport.width) <= 0.5
                    && Math.abs(routeRect.y - previousBottom - Theme.spacing.xs) <= 1, context
                    + " keeps 44 px routes on the contiguous 4 px rhythm");
            previousBottom = routeRect.y + routeRect.height;
            require(well.width === Theme.size.controlCenterRouteIconWellSize && well.height
                    === Theme.size.controlCenterRouteIconWellSize && well.radius === well.width / 2
                    && icon.width === Theme.size.iconSizeMd && icon.height
                    === Theme.size.iconSizeMd, context + " keeps " + route.name
                    + " in one neutral 32 px icon well");
            requireCaptureRectInside(wellRect, {
                                         "x": 0,
                                         "y": 0,
                                         "width": routeItem.width,
                                         "height": routeItem.height
                                     }, context + " keeps the icon well inside " + route.name);
            requireCaptureRectInside(iconRect, wellRect, context + " centers the " + route.name
                                     + " icon inside its well");
            requireCaptureRectInside(labelRect, {
                                         "x": 0,
                                         "y": 0,
                                         "width": routeItem.width,
                                         "height": routeItem.height
                                     }, context + " keeps the " + route.name
                                     + " label inside its route");
            const routeSurface = Theme.rgb(String(routeItem.background.color), sidebar
                                           ? String(Theme.color.controlCenterRailSurface) :
                                             String(Theme.color.surfaceOpaque));
            const wellSurface = Theme.rgb(String(well.color), Theme.hex(routeSurface));
            const labelForeground = Theme.rgb(String(label.color), Theme.hex(routeSurface));
            const iconForeground = Theme.rgb(String(icon.tint), Theme.hex(wellSurface));
            require(Theme.contrast(wellSurface, routeSurface) >= 1.08
                    && Theme.contrast(labelForeground, routeSurface) >= 4.5
                    && Theme.contrast(iconForeground, wellSurface) >= 3, context + " keeps "
                    + route.name + " well, label, and icon distinct from their immediate surfaces");
            require(label.text === route.name && label.lineCount === 1
                    && label.wrapMode === Text.NoWrap && label.elide === Text.ElideRight
                    && !label.truncated && label.paintedWidth <= label.width + 0.5
                    && label.paintedHeight <= label.height + 0.5
                    && routeItem.Accessible.name === route.name, context + " keeps the full "
                    + route.name + " label through the 18 px typography bound");
        }
        require(Math.abs(previousBottom - viewport.contentHeight) <= 1, context
                + " gives the viewport exactly the route-list extent");
        const selectedRoute = findObject(controlCenter.contentItem, prefix
                                         + controlCenter.currentPageId);
        const selectedRect = captureItemRect(selectedRoute, viewport);
        requireCaptureRectInside(selectedRect, {
                                     "x": 0,
                                     "y": 0,
                                     "width": viewport.width,
                                     "height": viewport.height
                                 }, context + " reveals the selected route inside the viewport");
        return viewport;
    }

    function requireCaptureGeometry(target) {
        const sidebar = controlCenter.layoutMode === "sidebar";
        const navigationVisible = sidebar || controlCenter.compactNavigationVisible;
        if (navigationVisible) {
            const boundaryItem = sidebar ? findObject(controlCenter.contentItem,
                                                       "controlCenterRail") : target;
            require(boundaryItem !== null && boundaryItem.visible,
                    "captured navigation exposes its visible route boundary");
            const viewport = requireRouteComposition(sidebar ? "sidebar" : "compact",
                                                     "captured navigation", false);
            requireCaptureRectInside(captureItemRect(viewport, target),
                                     captureItemRect(boundaryItem, target),
                                     "captured route viewport stays inside its navigation plane");
        }

        if (controlCenter.layoutMode === "compact" && !controlCenter.compactNavigationVisible
                && controlCenter.pageLoaded) {
            const compactBack = findObject(controlCenter.contentItem, "controlCenterCompactBack");
            const focusRing = findObject(compactBack, "islandFocusRing");
            const activeItem = controlCenter.backingWindow === null ? null :
                                                                       controlCenter.backingWindow.activeFocusItem;
            const pageOwnsFocus = itemDescendsFrom(activeItem, controlCenter.loadedPageItem);
            require(compactBack !== null && compactBack.visible
                    && (compactBack.activeFocus || pageOwnsFocus),
                    "compact loaded-page captures retain explicit All settings or page focus");
            if (compactBack.activeFocus) {
                require(focusRing !== null && focusRing.visible,
                        "compact navigation-context focus remains visibly on All settings");
                const targetRect = {
                    "x": 0,
                    "y": 0,
                    "width": target.width,
                    "height": target.height
                };
                requireCaptureRectInside(captureItemRect(focusRing, target), targetRect,
                                         "compact All settings focus ring stays inside the capture");
            }
        }
    }

    function performCapture(name, continuation, windowContent) {
        requireCurrentPageHeader();
        requireCaptureGeometry(windowContent);
        windowContent.grabToImage(function (result) {
            const path = test.captureDirectory + "/" + name + ".png";
            require(result.saveToFile(path), "real Control Center " + name + " capture is saved");
            Qt.callLater(continuation);
        });
    }

    function captureCurrent(name, continuation) {
        const windowContent = findObject(controlCenter.contentItem,
                                         "controlCenterWindowContent");
        require(windowContent !== null, "Control Center capture target is available");
        renderedFrameBarrier.begin(function () {
            performCapture(name, continuation, windowContent);
        }, true);
    }

    function requireMinimalMotion(context) {
        require(UserConfig.snapshot.appearance.motion === "minimal" && Theme.motion.effectiveMode
                === "minimal" && controlCenter.reducedMotion, context
                + " runs under the explicitly fixed Minimal motion policy");
    }

    function requireCorpusAbsent(value, context) {
        const text = String(value);
        for (let index = 0; index < privacyForbiddenValues.length; index += 1) {
            require(text.indexOf(privacyForbiddenValues[index]) === -1, context
                    + " excludes every synthetic private value");
        }
    }

    function recordSecretAccessibility(flow, input, boundary) {
        require(input !== null && input !== undefined && boundary !== null && boundary !== undefined
                && privacyAccessibility.every(record => record.flow !== flow), flow
                + " exposes one unique secret accessibility boundary");
        const record = {
            "flow": flow,
            "objectName": input.objectName,
            "name": String(boundary.semanticName),
            "description": String(boundary.semanticDescription),
            "role": "editableText",
            "passwordEdit": input.Accessible.passwordEdit === true
        };
        require(record.objectName !== "" && record.name !== "" && record.description !== ""
                && record.passwordEdit, flow + " exports purpose-only password metadata");
        requireCorpusAbsent(JSON.stringify(record), flow + " accessibility metadata");
        privacyAccessibility = privacyAccessibility.concat([record]);
    }

    function privacySnapshot() {
        return {
            "schemaVersion": 1,
            "controlCenter": {
                "visible": controlCenter.visible,
                "loadedPageCount": controlCenter.loadedPageCount
            },
            "pageInterest": {
                "wifi": fakeWifi.wifiManagerOpen,
                "bluetooth": fakeWifi.bluetoothManagerOpen,
                "wallpaper": fakeWallpaper.pageOpen,
                "weatherResults": fakeLocationSearch.results.length
            },
            "privateState": {
                "notificationHistoryCount": fakeNotifications.historyCount,
                "wallpaperPreviewActive": fakeWallpaper.preview !== null,
                "wifiSecretLength": fakeWifi.lastWifiSecretLength,
                "wifiSsidLength": fakeWifi.lastSsidLength,
                "bluetoothSecretLength": fakeWifi.lastBluetoothSecretLength,
                "bluetoothPrompt": fakeWifi.bluetoothPairingPrompt
            }
        };
    }

    function finalizePrivacyState() {
        controlCenter.closeWindow();
        fakeHost.clearPrivateState();
        fakeMedia.clearPrivateState();
        fakeLocationSearch.clear();
        fakeNotifications.clearHistory();
        fakeWifi.clearPrivateState();
        fakeWallpaper.clearPrivateState();
        const retainedState = JSON.stringify({
                                                 "host": fakeHost.privacyState(),
                                                 "media": fakeMedia.privacyState(),
                                                 "weather": fakeLocationSearch.privacyState(),
                                                 "notifications": fakeNotifications.privacyState(),
                                                 "connectivity": fakeWifi.privacyState(),
                                                 "wallpaper": fakeWallpaper.privacyState(),
                                                 "settings": UserConfig.serializeConfiguration(
                                                                 UserConfig.snapshot)
                                             });
        requireCorpusAbsent(retainedState, "final normalized fixture state");
        const snapshot = privacySnapshot();
        require(!snapshot.controlCenter.visible && snapshot.controlCenter.loadedPageCount === 0 &&
                !snapshot.pageInterest.wifi && !snapshot.pageInterest.bluetooth &&
                !snapshot.pageInterest.wallpaper && snapshot.pageInterest.weatherResults === 0
                && snapshot.privateState.notificationHistoryCount === 0 &&
                !snapshot.privateState.wallpaperPreviewActive
                && snapshot.privateState.wifiSecretLength === 0
                && snapshot.privateState.wifiSsidLength === 0
                && snapshot.privateState.bluetoothSecretLength === 0
                && snapshot.privateState.bluetoothPrompt === "none",
                "final cleanup clears every private model, operation, prompt, and page interest");
    }

    function writePrivacyArtifacts() {
        require(privacyArtifactDirectory !== "" && privacyDiagnostic !== ""
                && privacyAccessibility.length === 3,
                "the private runner exposes complete diagnostic and accessibility artifacts");
        const snapshotText = JSON.stringify(privacySnapshot(), null, 2);
        const accessibilityText = JSON.stringify(privacyAccessibility, null, 2);
        requireCorpusAbsent(privacyDiagnostic, "safe diagnostic artifact");
        requireCorpusAbsent(snapshotText, "safe IPC snapshot artifact");
        requireCorpusAbsent(accessibilityText, "accessibility artifact");
        privacyArtifactSaveCount = 0;
        diagnosticArtifactWriter.setText(privacyDiagnostic + "\n");
        snapshotArtifactWriter.setText(snapshotText + "\n");
        accessibilityArtifactWriter.setText(accessibilityText + "\n");
    }

    function privacyArtifactSaved() {
        privacyArtifactSaveCount += 1;
        if (privacyArtifactSaveCount === 3) {
            console.log("control center tests passed");
            Qt.exit(0);
        }
    }

    function findObject(item, objectName) {
        if (item === null || item === undefined) {
            return null;
        }
        if (item.objectName === objectName) {
            return item;
        }
        const children = item.children ?? [];
        for (let index = 0; index < children.length; index += 1) {
            const found = findObject(children[index], objectName);
            if (found !== null) {
                return found;
            }
        }
        return null;
    }

    function findInSubtree(item, predicate) {
        if (item === null || item === undefined) {
            return null;
        }
        if (predicate(item)) {
            return item;
        }
        const children = item.children ?? [];
        for (let index = 0; index < children.length; index += 1) {
            const found = findInSubtree(children[index], predicate);
            if (found !== null) {
                return found;
            }
        }
        return null;
    }

    function countInSubtree(item, predicate) {
        if (item === null || item === undefined) {
            return 0;
        }
        let count = predicate(item) ? 1 : 0;
        const children = item.children ?? [];
        for (let index = 0; index < children.length; index += 1) {
            count += countInSubtree(children[index], predicate);
        }
        return count;
    }
    function collectInSubtree(item, predicate, accumulator) {
        if (item === null || item === undefined) {
            return;
        }
        if (predicate(item)) {
            accumulator.push(item);
        }
        const children = item.children ?? [];
        for (let index = 0; index < children.length; index += 1) {
            collectInSubtree(children[index], predicate, accumulator);
        }
    }

    function isSettingRowSeparator(item) {
        return item.objectName === "controlCenterSettingRowSeparator"
                || item.objectName === "wifiNetworkSeparator"
                || item.objectName === "bluetoothDeviceSeparator";
    }

    function visiblePanelRows(section) {
        const entries = findObject(section, "controlCenterSectionEntries");
        const separators = [];
        const rows = [];
        collectInSubtree(entries, isSettingRowSeparator, separators);
        for (let index = 0; index < separators.length; index += 1) {
            const row = separators[index].parent;
            if (row !== null && row.visible && rows.indexOf(row) < 0) {
                rows.push(row);
            }
        }
        rows.sort(function (first, second) {
            return first.mapToItem(entries, 0, 0).y - second.mapToItem(entries, 0, 0).y;
        });
        return rows;
    }

    function requirePanelRowSequence(section, expectedCount, context, checkGeometry) {
        const entries = findObject(section, "controlCenterSectionEntries");
        const rows = visiblePanelRows(section);
        require(entries !== null && rows.length === expectedCount, context + " exposes exactly "
                + expectedCount + " visible row entries");
        if (checkGeometry !== true) {
            let visibleSeparatorCount = 0;
            for (let index = 0; index < rows.length; index += 1) {
                const separator = findInSubtree(rows[index], isSettingRowSeparator);
                require(separator !== null && separator.visible === rows[index].separatorVisible,
                        context + " keeps every explicit row separator binding coherent");
                if (rows[index].separatorVisible) {
                    visibleSeparatorCount += 1;
                }
            }
            require(visibleSeparatorCount === Math.max(0, rows.length - 1), context
                    + " exposes one separator between every pair of visible rows");
            return;
        }
        for (let index = 0; index < rows.length; index += 1) {
            const row = rows[index];
            const shouldSeparate = index < rows.length - 1;
            const separator = findInSubtree(row, isSettingRowSeparator);
            require(row.separatorVisible === shouldSeparate && separator !== null, context
                    + " binds each row to its final visible separator");
            const rowRect = captureItemRect(row, entries);
            const separatorRect = captureItemRect(separator, row);
            require(row.height >= Theme.size.controlCenterSettingRowMinimumHeight
                    && Math.abs(rowRect.x) <= 0.5 && Math.abs(row.width - entries.width) <= 0.5,
                    context + " gives every row the full inset lane and 56 px minimum");
            require(separator.visible === shouldSeparate && separator.height
                    === Theme.size.hairlineWidth && separator.color === Theme.color.surfaceBorder
                    && Math.abs(separator.opacity - 0.72) <= 0.001
                    && Math.abs(separatorRect.y + separatorRect.height - row.height) <= 0.5,
                    context + " renders only the explicit row-owned bottom hairlines");
            if (index > 0) {
                const previous = captureItemRect(rows[index - 1], entries);
                require(Math.abs(rowRect.y - (previous.y + previous.height)) <= 1, context
                        + " keeps neighboring rows contiguous");
            }
        }
    }

    function collectHeadings(item, headingRole, headingName, accumulator) {
        if (item === null || item === undefined) {
            return;
        }
        if (item.Accessible.role === headingRole && item.Accessible.name === headingName) {
            accumulator.push(item);
        }
        const children = item.children ?? [];
        for (let index = 0; index < children.length; index += 1) {
            collectHeadings(children[index], headingRole, headingName, accumulator);
        }
    }

    function requireSectionHierarchy(page, sections, context) {
        const pageTitleText = findObject(page, "controlCenterPageHeaderTitle");
        const heroSurface = findObject(page, "controlCenterPageHeaderSurface");
        require(pageTitleText !== null && heroSurface !== null, context
                + " owns its title inside the shared page hero");
        let previousY = -1;
        for (let index = 0; index < sections.length; index += 1) {
            const specification = sections[index];
            const section = findObject(page, specification.name);
            const surface = findObject(section, "controlCenterSectionSurface");
            const entries = findObject(section, "controlCenterSectionEntries");
            require(section !== null && surface !== null && entries !== null && section.text !== ""
                    && section.width > 0 && section.implicitHeight > 0
                    && section.parent === heroSurface.parent.parent
                    && Math.abs(section.width - heroSurface.width) <= 0.5, context + " exposes "
                    + specification.name + " as one broad root caption-and-panel section");
            const expectedRole = specification.list === true ? Accessible.List :
                                                                   Accessible.Grouping;
            const accessibleNameMatches = section.Accessible.name === section.text
                                          || (specification.list === true
                                              && section.Accessible.name.indexOf(section.text) === 0);
            require(section.Accessible.role === expectedRole && accessibleNameMatches
                    && !section.activeFocusOnTab, context
                    + " exposes one non-focusable semantic section group");
            const position = section.mapToItem(page.contentItem, 0, 0);
            require(position.y > previousY, context + " keeps sections in document order");
            previousY = position.y;
            if (index === 0 && specification.separated === false) {
                const heroRect = captureItemRect(heroSurface, page.contentItem);
                require(Math.abs(position.y - (heroRect.y + heroRect.height)
                                 - Theme.spacing.lg - Theme.spacing.sm) <= 1, context
                        + " keeps exactly 24 px from the hero to the first section");
            }
            const sectionHeadings = [];
            collectHeadings(section, pageTitleText.Accessible.role, section.text, sectionHeadings);
            require(sectionHeadings.length === 1 && sectionHeadings[0].font.pixelSize
                    === Theme.type.sizeFor("controlCenter", "caption")
                    && sectionHeadings[0].font.pixelSize < pageTitleText.font.pixelSize
                    && sectionHeadings[0].font.capitalization === Font.AllUppercase
                    && sectionHeadings[0].font.weight === Theme.type.weightSemibold, context
                    + " renders one small uppercase caption with its natural accessible name");
            const sectionSurfaces = [];
            collectInSubtree(section, function (item) {
                return item.objectName === "controlCenterSectionSurface";
            }, sectionSurfaces);
            require(sectionSurfaces.length === 1 && surface.color === Theme.color.controlFill
                    && surface.radius === Theme.radius.lg && surface.border.width === 0
                    && surface.clip && entries.spacing === 0
                    && Math.abs(surface.width - section.width) <= 0.5, context
                    + " uses one broad clipped tonal panel without nested section surfaces");
            const pageBase = Theme.rgb(String(Theme.color.surfaceOpaque));
            const panelFill = Theme.rgb(String(surface.color), String(Theme.color.surfaceOpaque));
            const captionForeground = Theme.rgb(String(sectionHeadings[0].color),
                                                Theme.hex(pageBase));
            require(Theme.contrast(panelFill, pageBase) >= 1.12
                    && Theme.contrast(captionForeground, pageBase) >= 4.5, context
                    + " keeps the section panel and caption distinct from the page base");
            const headingRect = captureItemRect(sectionHeadings[0].parent, section);
            const surfaceRect = captureItemRect(surface, section);
            const entriesRect = captureItemRect(entries, section);
            require(Math.abs(surfaceRect.y - (headingRect.y + headingRect.height)
                             - Theme.spacing.sm) <= 1, context
                    + " keeps the caption outside the panel with an 8 px gap");
            require(Math.abs(entriesRect.x - (surfaceRect.x + Theme.spacing.lg)) <= 1
                    && Math.abs(entriesRect.x + entriesRect.width - (surfaceRect.x
                                                                     + surfaceRect.width
                                                                     - Theme.spacing.lg)) <= 1,
                    context + " keeps a symmetric 16 px panel inset");
            if (specification.rows !== undefined) {
                requirePanelRowSequence(section, specification.rows, context + " "
                                        + specification.name, true);
            }
        }
    }

    function routeNamesExact() {
        const names = ["Island", "Appearance", "Clock & Date", "Media", "Weather",
                       "Notifications", "Wi-Fi", "Bluetooth", "Wallpaper", "Displays",
                       "About"];
        if (controlCenter.availableRoutes.length !== names.length) {
            return false;
        }
        for (let index = 0; index < names.length; index += 1) {
            if (controlCenter.availableRoutes[index].name !== names[index]) {
                return false;
            }
        }
        return true;
    }
    function routeIconsExact() {
        const meanings = ["controlCenterIsland", "controlCenterAppearance", "controlCenterClock",
                          "controlCenterMedia", "controlCenterWeather",
                          "controlCenterNotifications", "wifi", "bluetooth",
                          "controlCenterWallpaper", "controlCenterDisplays",
                          "controlCenterAbout"];
        if (controlCenter.availableRoutes.length !== meanings.length) {
            return false;
        }
        for (let index = 0; index < meanings.length; index += 1) {
            const route = controlCenter.availableRoutes[index];
            const resolved = IconResolver.resolve(route.icon, "normal", "", "");
            if (route.icon !== meanings[index] || resolved.kind !== "nagi"
                    || resolved.source === IconResolver.placeholderSource) {
                return false;
            }
        }
        return true;
    }

    function requireHeaderInViewport(page, context) {
        const route = controlCenter.availableRoutes[controlCenter.currentRouteIndex()];
        const header = findObject(page, routeHeaderName(route.id));
        require(header !== null && header.visible && header.opacity === 1 && header.height > 0,
                context + " keeps the shared page header mounted and visible");
        if (page.contentY !== undefined) {
            require(page.contentY === 0, context
                    + " checks header geometry from the content keyline");
        }
        const origin = header.mapToItem(page, 0, 0);
        require(origin.y >= 0 && origin.y + header.height <= page.height + 0.5, context
                + " keeps the shared page header unclipped inside the viewport");
    }

    function requireRailContract(context) {
        require(controlCenter.layoutMode === "sidebar", context
                + " exercises the persistent wide navigation rail");
        const rail = findObject(controlCenter.contentItem, "controlCenterRail");
        require(Theme.size.controlCenterResponsiveBreakpoint === 800
                && Theme.size.controlCenterSidebarWidth === 240
                && Theme.size.controlCenterRouteHeight === 44
                && Theme.size.controlCenterRouteIconWellSize === 32, context
                + " publishes the 800/240/44/32 Control Center geometry");
        require(rail !== null && rail.visible && rail.width
                === Theme.size.controlCenterSidebarWidth && Math.abs(rail.height
                                                                    - controlCenter.height) <= 0.5
                && rail.color === Theme.color.controlCenterRailSurface
                && rail.border.width === 0, context
                + " exposes one full-height tonal 240 px rail");
        const pageBase = Theme.rgb(String(Theme.color.surfaceOpaque));
        const railSurface = Theme.rgb(String(rail.color), String(Theme.color.surfaceOpaque));
        const railContrast = Theme.contrast(railSurface, pageBase);
        require(railContrast >= 1.08 && railContrast < 2, context
                + " keeps the rail separate from the page without becoming a second dominant block");
        const viewport = requireRouteComposition("sidebar", context + " rail", false);
        const viewportRect = captureItemRect(viewport, rail);
        require(Math.abs(viewportRect.x - Theme.spacing.md) <= 1
                && Math.abs(viewportRect.x + viewportRect.width - (rail.width
                                                                  - Theme.spacing.md)) <= 1,
                context + " preserves the rail's symmetric 12 px route inset");
        const selectedRoute = findObject(controlCenter.contentItem, "controlCenterSidebarRoute-"
                                                              + controlCenter.currentPageId);
        const selectedSurface = Theme.rgb(String(selectedRoute.background.color),
                                          String(Theme.color.controlCenterRailSurface));
        require(selectedRoute !== null && selectedRoute.selected
                && selectedRoute.background.color === Theme.color.controlCenterRailSelectedSurface
                && Theme.contrast(selectedSurface, railSurface) >= 1.16
                && Math.abs(selectedRoute.background.width - selectedRoute.width) <= 0.5, context
                + " gives the selected route one broad contrast-qualified surface");
        const seam = findInSubtree(selectedRoute.background, function (item) {
            return item.visible && Math.abs(item.width - 2) <= 0.5;
        });
        const routeIcon = findObject(selectedRoute, "controlCenterRouteIcon-"
                                                   + controlCenter.currentRouteIndex());
        require(seam !== null && routeIcon !== null && routeIcon.semanticState === "active", context
                + " keeps the two-pixel accent seam and active icon inside the selected surface");
        const selectedLabel = findObject(selectedRoute, "controlCenterRouteLabel-"
                                                        + controlCenter.currentRouteIndex());
        require(selectedLabel !== null && selectedLabel.font.weight
                === Theme.type.weightSemibold && selectedLabel.color
                === Theme.color.textPrimary && selectedLabel.color !== Theme.snapshot.accent,
                context + " keeps the selected label semibold and neutral");
    }

    function requireCompactChromeContract(context) {
        require(controlCenter.layoutMode === "compact" && controlCenter.loadedPageCount === 1,
                context + " exercises the loaded compact page");
        const page = controlCenter.loadedPageItem;
        const header = findObject(page, routeHeaderName(controlCenter.currentPageId));
        const headerTitle = header === null ? null : findObject(header,
                                                                "controlCenterPageHeaderTitle");
        require(headerTitle !== null, context + " keeps the shared page header title mounted");
        const headingRole = headerTitle.Accessible.role;
        const backRow = findObject(controlCenter.contentItem, "controlCenterCompactBackRow");
        require(backRow !== null && backRow.visible,
                context + " keeps one compact chrome row");
        require(findInSubtree(backRow, function (item) {
                    return item.label === "All settings";
                }) !== null, context + " retains the All settings return action");
        require(countInSubtree(backRow, function (item) {
                    return item.Accessible.role === headingRole;
                }) === 0, context + " compact chrome adds no duplicate page heading");
        const routeHeadings = [];
        collectHeadings(controlCenter.contentItem, headingRole, headerTitle.text, routeHeadings);
        require(routeHeadings.length === 1 && routeHeadings[0].objectName
                === "controlCenterPageHeaderTitle", context
                + " keeps exactly one accessible page heading owned by the shared header");
    }

    function createControls() {
        const parent = controlCenter.contentItem;
        const toggle = toggleFactory.createObject(parent, {
                                                      "label": "Toggle test",
                                                      "value": false,
                                                      "width": 200,
                                                      "visible": false
                                                  });
        const slider = sliderFactory.createObject(parent, {
                                                      "label": "Slider test",
                                                      "value": 0,
                                                      "from": 0,
                                                      "to": 10,
                                                      "stepSize": 1,
                                                      "width": 480,
                                                      "visible": false
                                                  });
        const choice = choiceFactory.createObject(parent, {
                                                      "label": "Choice test",
                                                      "value": "one",
                                                      "choices": ["one", "two"],
                                                      "width": 480,
                                                      "visible": false
                                                  });
        const color = colorFactory.createObject(parent, {
                                                    "label": "Color test",
                                                    "value": "#080D16",
                                                    "width": 200,
                                                    "visible": false
                                                });
        const action = actionFactory.createObject(parent, {
                                                      "label": "Action test",
                                                      "actionLabel": "Run",
                                                      "width": 200,
                                                      "visible": false
                                                  });
        const reset = resetFactory.createObject(parent, {
                                                    "pageId": "appearance",
                                                    "visible": false
                                                });
        const repeated = repeatedSectionFactory.createObject(parent, {
                                                                 "width": 512,
                                                                 "x": -10000
                                                             });
        require(toggle !== null && slider !== null && choice !== null && color !== null && action
                !== null && reset !== null && repeated !== null,
                "all reusable setting controls and the repeated section instantiate");
        toggle.valueRequested.connect(value => toggleRequests += value ? 1 : 100);
        slider.valueRequested.connect((value, continuous) => sliderRequests += value === 5 && continuous
                                                             ? 1 : 100);
        choice.valueRequested.connect(value => choiceRequests += value === "two" ? 1 : 100);
        color.valueRequested.connect(value => colorRequests += value === "#AABBCC" ? 1 : 100);
        action.actionRequested.connect(() => actionRequests += 1);
        reset.resetPageRequested.connect(page => pageResetRequests += page === "appearance" ? 1 :
                                                                                              100);
        reset.resetAllRequested.connect(() => resetAllRequests += 1);
        repeatedSection = repeated;
        controls = [toggle, slider, choice, color, action, reset, repeated];
    }

    function exerciseControls() {
        const toggle = controls[0];
        const slider = controls[1];
        const choice = controls[2];
        const color = controls[3];
        const action = controls[4];
        const reset = controls[5];
        require(toggle.requestToggle() && toggleRequests === 1,
                "toggle row dispatches one bounded setting request");
        require(slider.requestAt(0.5, true) && sliderRequests === 1,
                "slider row clamps and marks continuous requests");
        require(choice.request("two") && !choice.request("one") && !choice.request("missing") && choiceRequests
                === 1, "choice row ignores the current value and accepts only another registered value");
        require(!color.submit("/home/private") && color.submit("#aabbcc") && colorRequests === 1,
                "color row validates before dispatch");
        require(action.requestAction() && actionRequests === 1,
                "action row dispatches explicit activation");
        require(reset.requestPageReset() && pageResetRequests === 1,
                "page reset carries the fixed page identifier");
        require(!reset.confirmResetAll() && reset.beginResetAll()
                && reset.resetAllConfirmationVisible && reset.confirmResetAll() && resetAllRequests
                === 1 && !reset.resetAllConfirmationVisible,
                "reset all requires explicit confirmation");
        const secondChoice = findObject(choice, "settingChoice-two");
        require(secondChoice !== null && secondChoice.label === "two"
                && secondChoice.contentItem.text === "two",
                "choice controls render their visible labels");
        toggle.writable = false;
        require(!toggle.requestToggle() && toggleRequests === 1,
                "disabled setting rows reject writes");
        slider.writable = false;
        choice.value = "two";
        choice.writable = false;
        require(!slider.requestAt(0.75, true) && sliderRequests === 1 && secondChoice.opacity
                === Theme.opacity.disabled && secondChoice.contentItem.color
                === Theme.color.textMuted && Theme.opacity.disabled >= 0.6,
                "disabled controls reject writes while their labels remain readable");
    }

    function requireControlPlacement() {
        const toggle = controls[0];
        const slider = controls[1];
        const choice = controls[2];
        const color = controls[3];
        const action = controls[4];
        require(toggle.controlPlacement === ControlCenterSettingRow.Inline
                && color.controlPlacement === ControlCenterSettingRow.Inline
                && action.controlPlacement === ControlCenterSettingRow.Inline && !toggle.stacked
                && !color.stacked && !action.stacked, "toggles, colors, and actions stay inline");
        require(slider.controlPlacement === ControlCenterSettingRow.Below && slider.stacked,
                "sliders always use the below-label placement");
        require(choice.controlPlacement === ControlCenterSettingRow.Auto,
                "choices use measured automatic placement");
        const secondChoice = findObject(choice, "settingChoice-two");
        const choiceControls = secondChoice.parent;
        const threshold = Theme.size.controlCenterInlineLabelMinimumWidth
                          + choiceControls.implicitWidth + Theme.spacing.lg;
        choice.width = threshold - 1;
        require(choice.stacked, "Auto stacks one pixel below the measured label/control threshold");
        choice.width = threshold;
        require(!choice.stacked,
                "Auto remains inline at the exact measured label/control threshold");
        choice.width = 480;
        const sliderControl = findInSubtree(slider, function (item) {
            return item.Accessible.role === Accessible.Slider;
        });
        const trailingValue = findInSubtree(slider, function (item) {
            return item !== sliderControl && item.text === slider.valueText
                    && item.Accessible.ignored;
        });
        const sliderLabel = findInSubtree(slider, function (item) {
            return item !== trailingValue && item.text === slider.label;
        });
        require(sliderControl !== null && trailingValue !== null && sliderLabel !== null,
                "slider exposes its track, label, and trailing value");
        const sliderRect = captureItemRect(sliderControl, slider);
        const valueRect = captureItemRect(trailingValue, slider);
        const labelRect = captureItemRect(sliderLabel, slider);
        require(sliderControl.width > Theme.spacing.xxl * 5
                && Math.abs(sliderControl.parent.width - slider.width) <= 1
                && Math.abs(trailingValue.width - trailingValue.implicitWidth) <= 1
                && valueRect.x >= sliderRect.x + sliderRect.width + Theme.spacing.sm - 1
                && valueRect.x + valueRect.width <= slider.width + 0.5
                && sliderRect.y >= labelRect.y + labelRect.height + Theme.spacing.sm - 1,
                "slider fills the below-label lane and keeps a natural trailing value");
    }

    function requireAppearanceColorCases(page) {
        const section = findObject(page, "appearanceColorSection");
        const originalScheme = UserConfig.snapshot.appearance.scheme;
        const originalAccentMode = UserConfig.snapshot.appearance.accentMode;
        const originalCustomSurface = UserConfig.snapshot.appearance.customSurface;
        const originalCustomText = UserConfig.snapshot.appearance.customText;
        const originalCustomAccent = UserConfig.snapshot.appearance.customAccent;
        const cases = [{
                           "scheme": "nagi-dark",
                           "accentMode": "nagi",
                           "rows": 2
                       }, {
                           "scheme": "custom",
                           "accentMode": "nagi",
                           "rows": 4
                       }, {
                           "scheme": "nagi-dark",
                           "accentMode": "custom",
                           "rows": 3
                       }, {
                           "scheme": "custom",
                           "accentMode": "custom",
                           "rows": 5
                       }];
        require(section !== null, "Appearance exposes the conditional Color panel");
        for (let index = 0; index < cases.length; index += 1) {
            const specification = cases[index];
            require(page.request({
                                     "scheme": specification.scheme,
                                     "accentMode": specification.accentMode
                                 }, false), "Appearance accepts the bounded conditional Color fixture");
            requirePanelRowSequence(section, specification.rows,
                                    "Appearance Color " + specification.scheme + "/"
                                    + specification.accentMode, false);
        }
        require(page.request({
                                 "scheme": "custom",
                                 "accentMode": "custom",
                                 "customSurface": "#000000",
                                 "customText": "#7A7A7A",
                                 "customAccent": "#FFFFFF"
                             }, false), "Appearance accepts a legacy-valid extreme custom palette");
        require(Theme.snapshot.source === "custom",
                "the legacy-valid custom palette publishes without fallback");
        const selectedRoute = findObject(controlCenter.contentItem,
                                         "controlCenterSidebarRoute-appearance");
        require(selectedRoute !== null, "Appearance keeps its selected sidebar route mounted");
        const selectedLabel = findObject(selectedRoute, "controlCenterRouteLabel-1");
        const selectedWell = findObject(selectedRoute, "controlCenterRouteIconWell-1");
        const selectedIcon = findObject(selectedRoute, "controlCenterRouteIcon-1");
        const selectedSurface = Theme.rgb(String(selectedRoute.background.color),
                                          Theme.snapshot.controlCenterRailSelectedSurface);
        const selectedForeground = Theme.rgb(String(selectedLabel.color),
                                             Theme.snapshot.controlCenterRailSelectedForeground);
        const wellSurface = Theme.rgb(String(selectedWell.color), Theme.snapshot.surfaceOpaque);
        const iconForeground = Theme.rgb(String(selectedIcon.tint),
                                         Theme.snapshot.controlCenterRailSelectedAccent);
        require(selectedLabel !== null && selectedWell !== null && selectedIcon !== null
                && Theme.contrast(selectedForeground, selectedSurface) >= 4.5
                && Theme.contrast(iconForeground, wellSurface) >= 3,
                "the real selected route consumes contrast-safe legacy palette roles");
        const resetButton = findInSubtree(page, function (item) {
            return item.label === "Reset page";
        });
        require(resetButton !== null, "Appearance keeps its real standard reset action mounted");
        const resetFill = Theme.rgb(String(resetButton.fillColor()), Theme.snapshot.controlFill);
        const resetForeground = Theme.rgb(String(resetButton.contentColor()),
                                          Theme.snapshot.controlFillForeground);
        require(Theme.contrast(resetForeground, resetFill) >= 4.5,
                "a real standard button consumes the custom palette control foreground");
        require(page.request({
                                 "scheme": originalScheme,
                                 "accentMode": originalAccentMode,
                                 "customSurface": originalCustomSurface,
                                 "customText": originalCustomText,
                                 "customAccent": originalCustomAccent
                             }, false), "Appearance restores the original Color fixture");
    }

    function initialStage() {
        require(!controlCenter.visible && controlCenter.loadedPageCount === 0,
                "closed singleton retains no loaded page");
        require(controlCenter.minimumSize.width === Theme.size.controlCenterMinimumWidth
                && controlCenter.minimumSize.height === Theme.size.controlCenterMinimumHeight
                && controlCenter.title === "Nagi Control Center" && controlCenter.parentWindow
                === null && Theme.size.controlCenterMinimumWidth === 640
                && Theme.size.controlCenterMinimumHeight === 480
                && Theme.size.controlCenterPreferredWidth === 920
                && Theme.size.controlCenterPreferredHeight === 660,
                "normal independent window exposes the 640 by 480 minimum and 920 by 660 preference");
        require(Theme.size.controlCenterResponsiveBreakpoint === 800
                && Theme.size.controlCenterSidebarWidth === 240
                && Theme.size.controlCenterHeroIconWellSize === 56
                && Theme.size.controlCenterHeroDescriptionMaximumWidth === 480
                && Theme.size.controlCenterSettingRowMinimumHeight === 56
                && Theme.size.controlCenterInlineLabelMinimumWidth === 288,
                "Theme publishes the complete responsive hero and row composition contract");
        require(routeNamesExact() && routeIconsExact() && controlCenter.availableRoutes.length
                === 11 && controlCenter.availableRoutes[0].id === "island"
                && controlCenter.availableRoutes[1].id === "appearance"
                && controlCenter.availableRoutes[2].id === "clock-date"
                && controlCenter.availableRoutes[3].id === "media"
                && controlCenter.availableRoutes[4].id === "weather"
                && controlCenter.availableRoutes[5].id === "notifications"
                && controlCenter.availableRoutes[6].id === "wifi"
                && controlCenter.availableRoutes[7].id === "bluetooth"
                && controlCenter.availableRoutes[8].id === "wallpaper"
                && controlCenter.availableRoutes[9].id === "displays"
                && controlCenter.availableRoutes[10].id === "about",
                "final route names and semantic icons stay fixed across all complete pages");
        require(UserConfig.updatePage("appearance", {
                                          "motion": "minimal"
                                      }, false),
                "privacy captures fix the persisted motion policy to Minimal");
        requireMinimalMotion("Control Center fixture");
        createControls();
        exerciseControls();
        require(controlCenter.open("appearance", tokenA), "initiating island opens Appearance");
        stage = "primitive-three";
        settle.restart();
    }

    function primitiveThreeStage() {
        require(controlCenter.visible && controlCenter.currentPageId === "appearance"
                && controlCenter.loadedPageCount === 1,
                "primitive checks run beside one lazy-loaded Appearance page");
        requireControlPlacement();
        requirePanelRowSequence(repeatedSection, 3, "three-row Repeater panel", true);
        repeatedSection.rowModel = ["Only"];
        stage = "primitive-one";
        settle.restart();
    }

    function primitiveOneStage() {
        requirePanelRowSequence(repeatedSection, 1, "one-row rebuilt Repeater panel", true);
        repeatedSection.rowModel = ["One", "Two", "Three"];
        stage = "primitive-restored";
        settle.restart();
    }

    function primitiveRestoredStage() {
        requirePanelRowSequence(repeatedSection, 3, "restored Repeater panel", true);
        stage = "opened-a";
        settle.restart();
    }

    function openedAStage() {
        require(controlCenter.visible && controlCenter.currentPageId === "appearance"
                && controlCenter.loadedPageCount === 1 && controlCenter.loadedPageItem !== null
                && controlCenter.screen === Quickshell.screens[0],
                "fresh deep link places the complete Appearance page on the initiating screen");
        const appearancePage = controlCenter.loadedPageItem;
        const familySelectors = [findObject(appearancePage, "appearanceIdleFontFamily"), findObject(
                                     appearancePage, "appearanceExpandedFontFamily"), findObject(
                                     appearancePage, "appearanceControlCenterFontFamily")];
        const sizeSelectors = [findObject(appearancePage, "appearanceIdleBaseFontSize"), findObject(
                                   appearancePage, "appearanceExpandedBaseFontSize"), findObject(
                                   appearancePage, "appearanceControlCenterBaseFontSize")];
        const validInstalledFamilies = Qt.fontFamilies().filter(family => UserConfig.boundedString(
                                                                              family, UserConfig.maximumFontFamilyBytes,
                                                                              false)).sort((first,
                                                                                            second)
                                                                                           => first.localeCompare(
                                                                                                  second));
        require(familySelectors.every(selector => selector !== null && selector.count
                                                  === validInstalledFamilies.length
                                                  && selector.count > 1) && sizeSelectors.every(
                    selector => selector !== null),
                "Appearance exposes three complete family and base-size selectors");
        for (let selectorIndex = 0; selectorIndex < familySelectors.length; selectorIndex += 1) {
            const selector = familySelectors[selectorIndex];
            for (let index = 0; index < selector.count; index += 1) {
                require(validInstalledFamilies.indexOf(selector.model[index]) >= 0,
                        "each scoped selector contains only installed bounded families");
            }
        }
        requireAppearanceColorCases(appearancePage);
        const originalFamilies = [UserConfig.snapshot.appearance.idleFontFamily,
                                  UserConfig.snapshot.appearance.expandedFontFamily,
                                  UserConfig.snapshot.appearance.controlCenterFontFamily];
        const targetFamilies = familySelectors.map((selector, index) => selector.model.find(family
                                                                                            => family
                                                                                               !== originalFamilies[index]));
        require(targetFamilies.every(family => family !== undefined),
                "each typography scope has an alternate installed family");
        const fontFocusRing = findObject(familySelectors[0], "islandFocusRing");
        familySelectors[0].forceActiveFocus(Qt.TabFocusReason);
        require(familySelectors[0].activeFocus && familySelectors[0].visualFocus && fontFocusRing
                !== null && fontFocusRing.visible,
                "the scoped font selector exposes its shared keyboard focus shape");
        for (let index = 0; index < familySelectors.length; index += 1) {
            familySelectors[index].activated(familySelectors[index].model.indexOf(
                                                 targetFamilies[index]));
        }
        const targetSizes = [11, 16, 18];
        for (let index = 0; index < sizeSelectors.length; index += 1) {
            sizeSelectors[index].requestAt((targetSizes[index] - UserConfig.minimumBaseFontSize) / (
                                               UserConfig.maximumBaseFontSize
                                               - UserConfig.minimumBaseFontSize), false);
        }
        require(UserConfig.snapshot.appearance.idleFontFamily === targetFamilies[0]
                && UserConfig.snapshot.appearance.expandedFontFamily === targetFamilies[1]
                && UserConfig.snapshot.appearance.controlCenterFontFamily === targetFamilies[2]
                && UserConfig.snapshot.appearance.idleBaseFontSize === targetSizes[0]
                && UserConfig.snapshot.appearance.expandedBaseFontSize === targetSizes[1]
                && UserConfig.snapshot.appearance.controlCenterBaseFontSize === targetSizes[2],
                "the three typography selectors update only their scoped settings");
        require(Theme.type.familyFor("idle") === targetFamilies[0] && Theme.type.familyFor(
                    "expanded") === targetFamilies[1] && Theme.type.familyFor("controlCenter")
                === targetFamilies[2] && Theme.type.sizeFor("idle", "body") === targetSizes[0]
                && Theme.type.sizeFor("expanded", "body") === targetSizes[1] && Theme.type.sizeFor("controlCenter",
                                                                                                   "body")
                === targetSizes[2] && Theme.type.sizeFor("controlCenter", "caption") === Math.round(
                    targetSizes[2] * 11 / 13) && Theme.type.sizeFor("controlCenter", "title")
                === Math.round(targetSizes[2] * 15 / 13),
                "Theme publishes independent scoped families and proportional semantic roles");
        const appearanceTitle = findObject(appearancePage, "controlCenterPageHeaderTitle");
        require(appearanceTitle !== null && appearanceTitle.typographyScope === "controlCenter"
                && appearanceTitle.font.family === targetFamilies[2]
                && appearanceTitle.font.pixelSize === Theme.type.sizeFor("controlCenter",
                                                                          "pageTitle"),
                "loaded Control Center text resolves the Control Center typography scope");
        require(Theme.type.sizeFor("controlCenter", "pageTitle")
                > Theme.type.sizeFor("controlCenter", "title")
                && Theme.type.sizeFor("controlCenter", "pageTitle")
                < Theme.type.sizeFor("controlCenter", "display"),
                "the pageTitle role stays between section-title and display scale at the alternate size");
        require(UserConfig.updatePage("appearance", {
                                          "controlCenterBaseFontSize":
                                          UserConfig.minimumBaseFontSize
                                      }, false) && Theme.type.sizeFor("controlCenter", "pageTitle")
                > Theme.type.sizeFor("controlCenter", "title"),
                "the pageTitle role stays larger than section titles at the minimum bounded size");
        require(UserConfig.updatePage("appearance", {
                                          "controlCenterBaseFontSize":
                                          UserConfig.maximumBaseFontSize
                                      }, false) && Theme.type.sizeFor("controlCenter", "pageTitle")
                > Theme.type.sizeFor("controlCenter", "title"),
                "the pageTitle role stays larger than section titles at the maximum bounded size");
        require(UserConfig.updatePage("appearance", {
                                          "controlCenterBaseFontSize": targetSizes[2]
                                      }, false),
                "the alternate Control Center size restores after the pageTitle bound probes");
        requireSectionHierarchy(appearancePage, [
                                    {
                                        "name": "appearanceIdleFontFamilySection",
                                        "separated": false,
                                        "rows": 2
                                    },
                                    {
                                        "name": "appearanceExpandedFontFamilySection",
                                        "separated": true,
                                        "rows": 2
                                    },
                                    {
                                        "name": "appearanceControlCenterFontFamilySection",
                                        "separated": true,
                                        "rows": 2
                                    },
                                    {
                                        "name": "appearanceColorSection",
                                        "separated": true,
                                        "rows": 2
                                    },
                                    {
                                        "name": "appearanceSurfaceMotionSection",
                                        "separated": true,
                                        "rows": 5
                                    },
                                    {
                                        "name": "settingsResetSection",
                                        "separated": true
                                    }
                                ], "Appearance");
        captureCurrent("sidebar-appearance", function () {
            const controlCenterSelectorPosition = familySelectors[2].mapToItem(
                      appearancePage.contentItem, 0, 0);
            appearancePage.contentY = Math.max(0, Math.min(appearancePage.contentHeight
                                                           - appearancePage.height,
                                                           controlCenterSelectorPosition.y
                                                           - Theme.spacing.xxl * 4));
            Qt.callLater(function () {
                captureCurrent("sidebar-appearance-control-center", function () {
                    appearancePage.contentY = 0;
                    const originalScreen = controlCenter.screen;
                    require(controlCenter.open("island", tokenB) && controlCenter.screen
                            === originalScreen && controlCenter.currentPageId === "island",
                            "repeated activation deep-links to Island without moving the open singleton");
                    test.stage = "island";
                    settle.restart();
                });
            });
        });
    }

    function islandStage() {
        require(controlCenter.currentPageId === "island" && controlCenter.loadedPageItem !== null,
                "complete Island page loads in the shared page viewport");
        requireSectionHierarchy(controlCenter.loadedPageItem, [
                                    {
                                        "name": "islandGeometrySection",
                                        "separated": false,
                                        "rows": 4
                                    },
                                    {
                                        "name": "islandFeedbackSection",
                                        "separated": true,
                                        "rows": 1
                                    },
                                    {
                                        "name": "islandCompactContentSection",
                                        "separated": true,
                                        "rows": 2
                                    },
                                    {
                                        "name": "settingsResetSection",
                                        "separated": true
                                    }
                                ], "Island");
        const gamingToggle = findObject(controlCenter.loadedPageItem, "gamingPerformanceToggle");
        require(gamingToggle !== null && gamingToggle.label === "Gaming performance indicator"
                && gamingToggle.value === true && gamingToggle.description.indexOf(
                    "passive system-status feedback") >= 0,
                "Island Feedback exposes the enabled gaming indicator toggle");
        require(gamingToggle.requestToggle() && UserConfig.snapshot.island.gamingIndicator
                === false && gamingToggle.requestToggle()
                && UserConfig.snapshot.island.gamingIndicator === true,
                "gaming indicator toggle updates and restores the persisted setting");
        controlCenter.capabilities = Object.assign({}, controlCenter.capabilities, {
                                                       "gamingPerformance": false
                                                   });
        require(gamingToggle.description
                === "No supported Gaming Performance backend is currently available.",
                "backend absence marks the gaming setting unavailable");
        captureCurrent("sidebar-island", function () {
            require(controlCenter.open("clock-date", tokenB) && controlCenter.currentPageId
                    === "clock-date", "Clock & Date joins the shared responsive page viewport");
            test.stage = "clock";
            settle.restart();
        });
    }
    function clockStage() {
        require(controlCenter.loadedPageItem !== null && fakeClock.text !== ""
                && fakeClock.dateText !== "", "Clock & Date uses the shared clock preview");
        requireSectionHierarchy(controlCenter.loadedPageItem, [
                                    {
                                        "name": "clockPresentationSection",
                                        "separated": true,
                                        "rows": 4
                                    },
                                    {
                                        "name": "settingsResetSection",
                                        "separated": true
                                    }
                                ], "Clock & Date");
        captureCurrent("sidebar-clock-date", function () {
            require(controlCenter.open("media", tokenB) && controlCenter.currentPageId === "media",
                    "Media joins the shared responsive page viewport");
            test.stage = "media";
            settle.restart();
        });
    }

    function mediaStage() {
        require(fakeMedia.queueApplicationEvent(privacyCorpus.executable, privacyCorpus.pid)
                && fakeMedia.pendingApplication.executable === privacyCorpus.executable
                && fakeMedia.pendingApplication.pid === privacyCorpus.pid
                && fakeMedia.publishApplicationEvent() && fakeMedia.pendingApplication === null,
                "application executable and PID cross the owning adapter event before normalization");
        requireCorpusAbsent(JSON.stringify(fakeMedia.availableApplications),
                            "normalized Media application policy");
        require(controlCenter.loadedPageItem !== null && fakeMedia.availableApplications.length
                === 1, "Media receives the normalized shared application policy source");
        requireSectionHierarchy(controlCenter.loadedPageItem, [
                                    {
                                        "name": "mediaVisibilitySection",
                                        "separated": false,
                                        "rows": 3
                                    },
                                    {
                                        "name": "mediaPlayerSelectionSection",
                                        "separated": true,
                                        "rows": 1
                                    },
                                    {
                                        "name": "settingsResetSection",
                                        "separated": true
                                    }
                                ], "Media");
        captureCurrent("sidebar-media", function () {
            require(controlCenter.open("weather", tokenB) && controlCenter.currentPageId
                    === "weather", "Weather joins the shared responsive page viewport");
            test.stage = "weather";
            settle.restart();
        });
    }

    function weatherStage() {
        const page = controlCenter.loadedPageItem;
        require(page !== null && !controlCenter.weatherLookupAllowed,
                "Weather preview loads without enabling location lookup");
        requireSectionHierarchy(page, [
                                    {
                                        "name": "weatherPrivacySection",
                                        "separated": false
                                    }
                                ], "unconfigured Weather");
        page.privacyAccepted = true;
        require(fakeLocationSearch.queueProviderResponse(privacyCorpus.weatherLabel,
                                                         privacyCorpus.weatherLatitude,
                                                         privacyCorpus.weatherLongitude,
                                                         privacyCorpus.weatherProviderBody)
                && controlCenter.weatherLookupAllowed && fakeLocationSearch.search(
                    "private fixture"),
                "privacy acceptance drives the synthetic provider response through location search");
        const privateResult = fakeLocationSearch.results[0];
        require(privateResult.label === privacyCorpus.weatherLabel && privateResult.latitude
                === privacyCorpus.weatherLatitude && privateResult.longitude
                === privacyCorpus.weatherLongitude && fakeLocationSearch.providerBody
                === privacyCorpus.weatherProviderBody,
                "Weather owns the complete synthetic provider result before confirmation");
        require(page.confirm(privateResult) && UserConfig.snapshot.weather.enabled
                && UserConfig.snapshot.weather.locationLabel === privacyCorpus.weatherLabel
                && UserConfig.snapshot.weather.latitude === privacyCorpus.weatherLatitude
                && UserConfig.snapshot.weather.longitude === privacyCorpus.weatherLongitude,
                "confirmed private location crosses the normalized settings boundary");
        require(fakeLocationSearch.results.length === 0 && fakeLocationSearch.providerBody === "",
                "confirmation clears provider body, lookup models, and query state");
        stage = "weather-private-persisted";
        settle.restart();
    }

    function weatherPrivatePersistedStage() {
        if (UserConfig._writeInProgress || UserConfig._writeCandidate !== null
                || UserConfig._persistedSnapshot.weather.locationLabel
                !== privacyCorpus.weatherLabel) {
            settle.restart();
            return;
        }
        require(UserConfig._persistedSnapshot.weather.latitude === privacyCorpus.weatherLatitude
                && UserConfig._persistedSnapshot.weather.longitude
                === privacyCorpus.weatherLongitude,
                "the owning settings flow completed its private persistence cycle");
        require(UserConfig.resetPage("weather"),
                "Weather cleanup replaces the persisted private location");
        stage = "weather-private-cleared";
        settle.restart();
    }

    function weatherPrivateClearedStage() {
        const defaults = UserConfig.defaultSnapshot(0);
        if (UserConfig._writeInProgress || UserConfig._writeCandidate !== null
                || UserConfig._persistedSnapshot.weather.locationLabel
                !== defaults.weather.locationLabel) {
            settle.restart();
            return;
        }
        const page = controlCenter.loadedPageItem;
        require(page !== null && UserConfig.snapshot.weather.locationLabel === ""
                && UserConfig.snapshot.weather.latitude === null
                && UserConfig.snapshot.weather.longitude === null,
                "Weather cleanup clears private values from published and persisted settings");
        page.privacyAccepted = true;
        require(fakeLocationSearch.search("Paris") && page.confirm(fakeLocationSearch.results[0])
                && UserConfig.snapshot.weather.enabled && UserConfig.snapshot.weather.locationLabel
                === "Paris, France",
                "the ordinary normalized Weather path remains available after private cleanup");
        require(fakeLocationSearch.results.length === 0 && fakeLocationSearch.providerBody === "",
                "safe confirmation also clears page-owned lookup state");
        requireSectionHierarchy(page, [
                                    {
                                        "name": "weatherPrivacySection",
                                        "separated": false
                                    },
                                    {
                                        "name": "weatherLocationSection",
                                        "separated": true
                                    },
                                    {
                                        "name": "weatherForecastPreferencesSection",
                                        "separated": true,
                                        "rows": 3
                                    },
                                    {
                                        "name": "settingsResetSection",
                                        "separated": true
                                    }
                                ], "Weather");
        captureCurrent("sidebar-weather", function () {
            require(controlCenter.open("notifications", tokenB) && controlCenter.currentPageId
                    === "notifications", "Notifications joins the shared responsive page viewport");
            test.stage = "notifications";
            settle.restart();
        });
    }

    function notificationsStage() {
        require(controlCenter.loadedPageItem !== null && fakeNotifications.historyCount === 1,
                "Notifications receives the shared memory-history service");
        require(fakeNotifications.admit(privacyCorpus.notificationSender,
                                        privacyCorpus.notificationBody)
                && fakeNotifications.historyCount === 2 && fakeNotifications.history[1].sender
                === privacyCorpus.notificationSender && fakeNotifications.history[1].body
                === privacyCorpus.notificationBody,
                "sender and body cross the owning bounded notification history flow");
        fakeNotifications.clearHistory();
        require(fakeNotifications.historyCount === 0,
                "Clear history stays inside the existing service boundary");
        requireSectionHierarchy(controlCenter.loadedPageItem, [
                                    {
                                        "name": "notificationsPopupPolicySection",
                                        "separated": false,
                                        "rows": 3
                                    },
                                    {
                                        "name": "notificationsFeedbackSection",
                                        "separated": true,
                                        "rows": 1
                                    },
                                    {
                                        "name": "notificationsIslandContentSection",
                                        "separated": true,
                                        "rows": 2
                                    },
                                    {
                                        "name": "notificationsHistorySection",
                                        "separated": true,
                                        "rows": 2
                                    },
                                    {
                                        "name": "settingsResetSection",
                                        "separated": true
                                    }
                                ], "Notifications");
        captureCurrent("sidebar-notifications", function () {
            require(controlCenter.open("wifi", tokenB) && controlCenter.currentPageId === "wifi",
                    "Wi-Fi joins the shared responsive page viewport");
            test.stage = "wifi";
            settle.restart();
        });
    }

    function wifiStage() {
        const page = controlCenter.loadedPageItem;
        requireMinimalMotion("Wi-Fi privacy flow");
        require(page !== null && fakeWifi.wifiManagerOpen && fakeWifi.wifiNetworks.length === 3,
                "Wi-Fi receives the one shared NetworkManager projection and opens scan interest");
        requireSectionHierarchy(page, [
                                    {
                                        "name": "wifiRadioSection",
                                        "separated": false,
                                        "rows": 1
                                    },
                                    {
                                        "name": "wifiNetworksSection",
                                        "separated": true,
                                        "rows": 3
                                    }
                                ], "Wi-Fi list");

        require(page.openNetwork(fakeWifi.wifiNetworks[2]) && page.mode === "password",
                "protected visible network opens the dedicated password flow");
        const passwordInput = findObject(page, "wifiPasswordInput");
        require(passwordInput !== null,
                "protected input mounts one explicit accessibility boundary");
        require(passwordInput.echoMode === TextInput.NoEcho && passwordInput.Accessible.passwordEdit,
                "protected input starts hidden with the password-edit semantic");
        const passwordBoundary = passwordInput.parent.parent;
        require(passwordBoundary.semanticName === "Wi-Fi password",
                "protected input exposes a purpose-only accessible name");
        passwordInput.text = privacyCorpus.wifiSecret;
        require(passwordBoundary.semanticName.indexOf(passwordInput.text) === -1
                && passwordBoundary.semanticDescription.indexOf(passwordInput.text) === -1,
                "Wi-Fi secret bytes never enter accessibility metadata");
        recordSecretAccessibility("wifi", passwordInput, passwordBoundary);
        page.rememberConnection = true;
        require(page.submitVisibleNetwork() && passwordInput.text === "" && fakeWifi.lastOperation
                === "connect" && fakeWifi.lastToken === 3 && fakeWifi.lastWifiSecretLength
                === privacyCorpus.wifiSecret.length && fakeWifi.lastRemember,
                "visible PSK crosses the owning request once and clears immediately");
        beginWifiHiddenCapture(page, privacyCorpus.wifiSsid, privacyCorpus.wifiSecret,
                               "privacy-wifi-a", function () {
                                   beginWifiHiddenCapture(page, alternateWifiSsid,
                                                          alternateWifiSecret, "privacy-wifi-b",
                                                          function () {
                                                              completeWifiStage(page);
                                                          });
                               });
    }

    function beginWifiHiddenCapture(page, ssid, secret, captureName, continuation) {
        page.clearPrivateState();
        page.mode = "hidden";
        const hiddenSsid = findObject(page, "wifiHiddenSsid");
        const hiddenPassword = findObject(page, "wifiHiddenPasswordInput");
        hiddenSsid.text = ssid;
        hiddenPassword.text = secret;
        require(page.submitHiddenNetwork() && hiddenSsid.text === "" && hiddenPassword.text === ""
                && fakeWifi.lastOperation === "hidden-connect" && fakeWifi.lastSsidLength
                === ssid.length && fakeWifi.lastWifiSecretLength === secret.length,
                "hidden SSID and PSK cross the owning request and clear immediately");
        requireMinimalMotion(captureName);
        page.contentY = 0;
        controlCenter.contentItem.forceActiveFocus(Qt.OtherFocusReason);
        captureCurrent(captureName, continuation);
    }

    function completeWifiStage(page) {
        page.mode = "hidden";
        const hiddenSsid = findObject(page, "wifiHiddenSsid");
        const hiddenPassword = findObject(page, "wifiHiddenPasswordInput");
        hiddenSsid.text = "cancelled fixture network";
        hiddenPassword.text = "cancelled-fixture-password";
        page.clearPrivateState();
        require(hiddenSsid.text === "" && hiddenPassword.text === "" && page.mode === "list",
                "Wi-Fi cancellation clears every private field without dispatch");
        require(page.requestForget(fakeWifi.wifiNetworks[0]) && page.confirmForget()
                && fakeWifi.lastOperation === "forget" && fakeWifi.lastToken === 1,
                "forget requires confirmation and dispatches only a proven personal token");
        captureCurrent("sidebar-wifi", function () {
            require(controlCenter.open("bluetooth", tokenB) && controlCenter.currentPageId
                    === "bluetooth", "Bluetooth joins the shared responsive page viewport");
            test.stage = "bluetooth";
            settle.restart();
        });
    }

    function bluetoothStage() {
        const page = controlCenter.loadedPageItem;
        requireMinimalMotion("Bluetooth privacy flow");
        require(page !== null && !fakeWifi.wifiManagerOpen && fakeWifi.bluetoothManagerOpen
                && fakeWifi.bluetoothDevices.length === 3,
                "Bluetooth shares the connectivity owner and suspends Wi-Fi page interest");
        requireSectionHierarchy(page, [
                                    {
                                        "name": "bluetoothRadioSection",
                                        "separated": false,
                                        "rows": 2
                                    },
                                    {
                                        "name": "bluetoothConnectedSection",
                                        "separated": true,
                                        "list": true,
                                        "rows": 1
                                    },
                                    {
                                        "name": "bluetoothPairedSection",
                                        "separated": true,
                                        "list": true,
                                        "rows": 1
                                    },
                                    {
                                        "name": "bluetoothAvailableSection",
                                        "separated": true,
                                        "list": true,
                                        "rows": 1
                                    }
                                ], "Bluetooth device lists");
        require(fakeWifi.installPrivateBluetoothDevice(privacyCorpus.bluetoothAddress,
                                                       privacyCorpus.bluetoothName)
                && fakeWifi.bluetoothDevices[2].address === privacyCorpus.bluetoothAddress
                && fakeWifi.bluetoothDevices[2].name === privacyCorpus.bluetoothName,
                "Bluetooth address and name cross the owning device projection");
        require(fakeWifi.scanBluetooth() && fakeWifi.bluetoothDiscovering,
                "Scan starts only from an explicit manager action");
        fakeWifi.nextBluetoothPairingPrompt = "enter-pin";
        require(fakeWifi.pairBluetooth(13) && fakeWifi.bluetoothOperation === "pairing"
                && fakeWifi.bluetoothPairingPrompt === "enter-pin",
                "pairing replaces discovery and opens the owning PIN prompt");
        const pairingPanel = findObject(page, "bluetoothPairingPanel");
        const pairingInput = findObject(page, "bluetoothPairingInput");
        const pairingBoundary = pairingInput === null ? null : pairingInput.parent.parent;
        require(pairingPanel !== null && pairingInput !== null
                && pairingInput.Accessible.passwordEdit && pairingBoundary !== null
                && pairingBoundary.semanticName === "Bluetooth PIN" && pairingPanel.deviceName
                === privacyCorpus.bluetoothName,
                "Bluetooth PIN mounts beside the projected private device without merging metadata");
        pairingPanel.focusInput();
        require(pairingInput.echoMode === TextInput.NoEcho && pairingInput.activeFocus &&
                !pairingBoundary.clipboardEnabled,
                "Bluetooth PIN starts hidden, receives focus, and blocks clipboard export");
        pairingInput.text = privacyCorpus.bluetoothPin;
        require(pairingBoundary.semanticName.indexOf(pairingInput.text) === -1
                && pairingBoundary.semanticDescription.indexOf(pairingInput.text) === -1,
                "Bluetooth PIN never enters purpose-only accessibility metadata");
        recordSecretAccessibility("bluetooth-pin", pairingInput, pairingBoundary);
        require(pairingPanel.submitInput() && pairingInput.text === ""
                && fakeWifi.lastBluetoothSecretLength === privacyCorpus.bluetoothPin.length
                && fakeWifi.bluetoothOperationResult === "paired-connected",
                "PIN submits once as an argument, clears immediately, and completes pairing");
        fakeWifi.clearPrivateBluetoothDevice();
        requireCorpusAbsent(JSON.stringify(fakeWifi.bluetoothDevices),
                            "cleaned Bluetooth device projection");
        page.contentY = 0;
        controlCenter.contentItem.forceActiveFocus(Qt.OtherFocusReason);
        captureCurrent("privacy-bluetooth-a", function () {
            completeBluetoothPasskeyStage(page);
        });
    }

    function completeBluetoothPasskeyStage(page) {
        fakeWifi.nextBluetoothPairingPrompt = "enter-passkey";
        require(fakeWifi.pairBluetooth(13) && fakeWifi.bluetoothOperation === "pairing"
                && fakeWifi.bluetoothPairingPrompt === "enter-passkey",
                "the same owning flow accepts a bounded passkey prompt");
        const pairingPanel = findObject(page, "bluetoothPairingPanel");
        const pairingInput = findObject(page, "bluetoothPairingInput");
        const pairingBoundary = pairingInput === null ? null : pairingInput.parent.parent;
        require(pairingPanel !== null && pairingInput !== null && pairingBoundary !== null
                && pairingBoundary.semanticName === "Bluetooth passkey",
                "passkey input keeps a purpose-only accessibility boundary");
        pairingInput.text = privacyCorpus.bluetoothPasskey;
        recordSecretAccessibility("bluetooth-passkey", pairingInput, pairingBoundary);
        require(pairingPanel.submitInput() && pairingInput.text === ""
                && fakeWifi.lastBluetoothSecretLength === privacyCorpus.bluetoothPasskey.length
                && fakeWifi.bluetoothOperationResult === "paired-connected",
                "passkey submits once and clears at the owning terminal path");
        fakeWifi.bluetoothPairingValue = privacyCorpus.bluetoothPin;
        fakeWifi.nextBluetoothPairingPrompt = "display-pin";
        require(fakeWifi.pairBluetooth(13), "Bluetooth display PIN opens its owning prompt");
        const displayedPin = findInSubtree(pairingPanel, function (item) {
            return item.text === privacyCorpus.bluetoothPin;
        });
        require(displayedPin !== null && displayedPin.Accessible.name === "Pairing PIN"
                && displayedPin.Accessible.name.indexOf(privacyCorpus.bluetoothPin) === -1,
                "displayed Bluetooth PIN stays out of accessibility metadata");
        require(fakeWifi.cancelBluetoothPairing(), "Bluetooth display PIN prompt cancels cleanly");
        fakeWifi.bluetoothPairingValue = privacyCorpus.bluetoothPasskey;
        fakeWifi.nextBluetoothPairingPrompt = "confirm-passkey";
        require(fakeWifi.pairBluetooth(13), "Bluetooth passkey confirmation opens its owning prompt");
        const displayedPasskey = findInSubtree(pairingPanel, function (item) {
            return item.text === privacyCorpus.bluetoothPasskey;
        });
        require(displayedPasskey !== null
                && displayedPasskey.Accessible.name === "Pairing passkey"
                && displayedPasskey.Accessible.name.indexOf(privacyCorpus.bluetoothPasskey) === -1,
                "confirmed Bluetooth passkey stays out of accessibility metadata");
        require(fakeWifi.cancelBluetoothPairing(),
                "Bluetooth passkey confirmation prompt cancels cleanly");
        requireMinimalMotion("privacy-bluetooth-b");
        page.contentY = 0;
        controlCenter.contentItem.forceActiveFocus(Qt.OtherFocusReason);
        captureCurrent("privacy-bluetooth-b", function () {
            completeBluetoothStage(page);
        });
    }

    function completeBluetoothStage(page) {
        fakeWifi.nextBluetoothPairingPrompt = "enter-pin";
        require(fakeWifi.pairBluetooth(13), "Bluetooth cancellation opens a current prompt");
        const pairingInput = findObject(page, "bluetoothPairingInput");
        pairingInput.text = "731";
        page.clearPrivateState();
        require(fakeWifi.cancelBluetoothPairing() && pairingInput.text === ""
                && fakeWifi.bluetoothOperation === "idle" && fakeWifi.bluetoothPairingPrompt
                === "none",
                "Bluetooth cancellation clears pairing input and service-owned prompt state");
        require(page.requestUnpair(12, "Fixture Keyboard") && page.confirmUnpair()
                && fakeWifi.lastOperation === "bluetooth-unpair" && fakeWifi.lastToken === 12,
                "unpair requires an explicit confirmation and selected opaque token");
        captureCurrent("sidebar-bluetooth", function () {
            require(controlCenter.open("wallpaper", tokenB) && controlCenter.currentPageId
                    === "wallpaper", "Wallpaper joins the shared responsive page viewport");
            test.stage = "wallpaper";
            settle.restart();
        });
    }

    function requireWallpaperPreviewGeometry(page, context) {
        const panel = findObject(page, "wallpaperPreviewPanel");
        const metadata = findObject(page, "wallpaperPreviewMetadata");
        const nameFrame = findObject(page, "wallpaperPreviewNameFrame");
        const nameViewport = findObject(page, "wallpaperPreviewNameViewport");
        const name = findObject(page, "wallpaperPreviewName");
        const details = findObject(page, "wallpaperPreviewDetails");
        const actions = findObject(page, "wallpaperPreviewActions");
        const apply = findObject(page, "wallpaperApplyButton");
        const clear = findObject(page, "wallpaperClearButton");
        require(panel !== null && metadata !== null && nameFrame !== null && nameViewport !== null
                && name !== null && details !== null && actions !== null && apply !== null
                && clear !== null && panel.visible && metadata.visible, context
                + " exposes one complete preview rail");
        const panelRect = captureItemRect(panel, page);
        const metadataRect = captureItemRect(metadata, page);
        const nameViewportRect = captureItemRect(nameViewport, page);
        const nameRect = captureItemRect(name, page);
        const detailsRect = captureItemRect(details, page);
        const actionsRect = captureItemRect(actions, page);
        const applyRect = captureItemRect(apply, page);
        const clearRect = captureItemRect(clear, page);
        requireCaptureRectInside(metadataRect, panelRect, context
                                 + " keeps preview metadata inside the rail");
        requireCaptureRectInside(nameViewportRect, metadataRect, context
                                 + " keeps the readable filename viewport inside preview metadata");
        requireCaptureRectInside(detailsRect, metadataRect, context
                                 + " keeps dimensions and size inside preview metadata");
        requireCaptureRectInside(actionsRect, panelRect, context
                                 + " keeps the action composition inside the rail");
        requireCaptureRectInside(applyRect, actionsRect, context
                                 + " keeps the Apply action inside its composition");
        requireCaptureRectInside(clearRect, actionsRect, context
                                 + " keeps the Clear action inside its composition");
        require(name.text === fakeWallpaper.preview.name && name.Accessible.ignored
                && nameViewport.Accessible.name === name.text && name.elide === Text.ElideNone
                && name.wrapMode === Text.WrapAnywhere && name.lineCount >= 1 && !name.truncated
                && name.paintedWidth <= name.width + 0.5 && name.paintedHeight
                <= name.height + 0.5 && nameViewport.contentHeight >= name.height - 0.5
                && details.text === qsTr("%1×%2 · %3").arg(
                    fakeWallpaper.preview.width).arg(fakeWallpaper.preview.height).arg(
                    page.formatBytes(fakeWallpaper.preview.byteSize))
                && details.elide === Text.ElideNone && details.wrapMode === Text.Wrap
                && details.lineCount >= 1 && !details.truncated
                && details.paintedWidth <= details.width + 0.5
                && details.paintedHeight <= details.height + 0.5,
                context + " renders the full filename and split dimensions/size without elision");
        const maximumNameOffset = Math.max(0, nameViewport.contentHeight - nameViewport.height);
        if (maximumNameOffset > 0.5) {
            const focusRing = findObject(nameFrame, "islandFocusRing");
            nameViewport.forceActiveFocus(Qt.TabFocusReason);
            require(nameViewport.interactive && nameViewport.focusPolicy === Qt.StrongFocus
                    && nameViewport.activeFocusOnTab && nameViewport.activeFocus
                    && nameViewport.Accessible.focused && nameViewport.Accessible.role
                    === Accessible.Pane && focusRing !== null && focusRing.visible
                    && nameViewport.height <= Theme.size.controlHeightLg * 2 + 0.5, context
                    + " gives a long filename keyboard focus, instructions, and a visible focus shape");
            requireCaptureRectInside(captureItemRect(focusRing, page),
                                     captureItemRect(panel, page), context
                                     + " keeps the filename focus shape inside the preview rail");
            require(nameViewport.handleScrollKey(Qt.Key_End)
                    && Math.abs(nameViewport.contentY - maximumNameOffset) <= 0.5, context
                    + " End reaches the final wrapped filename line");
            const endOffset = nameViewport.contentY;
            require(nameViewport.handleScrollKey(Qt.Key_Up)
                    && nameViewport.contentY < endOffset, context
                    + " Up scrolls a long filename by the semantic step");
            const upOffset = nameViewport.contentY;
            require(nameViewport.handleScrollKey(Qt.Key_PageUp)
                    && nameViewport.contentY <= upOffset
                    && (upOffset <= 0.5 || nameViewport.contentY < upOffset), context
                    + " Page Up scrolls a long filename toward its start");
            require(nameViewport.handleScrollKey(Qt.Key_Home) && nameViewport.contentY <= 0.5,
                    context + " Home reaches the first wrapped filename line");
            require(nameViewport.handleScrollKey(Qt.Key_Down) && nameViewport.contentY > 0,
                    context + " Down scrolls a long filename by the semantic step");
            const downOffset = nameViewport.contentY;
            require(nameViewport.handleScrollKey(Qt.Key_PageDown)
                    && nameViewport.contentY > downOffset, context
                    + " Page Down scrolls a long filename toward its end");
            require(nameViewport.handleScrollKey(Qt.Key_End)
                    && Math.abs(nameViewport.contentY - maximumNameOffset) <= 0.5, context
                    + " repeated End remains bounded at the final filename line");
            const scrolledNameRect = captureItemRect(name, page);
            const currentNameViewportRect = captureItemRect(nameViewport, page);
            require(scrolledNameRect.y + scrolledNameRect.height
                    <= currentNameViewportRect.y + currentNameViewportRect.height + 0.5
                    && scrolledNameRect.y + scrolledNameRect.height > currentNameViewportRect.y,
                    context + " keeps the final wrapped filename line reachable without elision");
            require(nameViewport.handleScrollKey(Qt.Key_Home) && nameViewport.contentY <= 0.5,
                    context + " keyboard filename inspection restores its initial position");
            controlCenter.focusCurrentContext();
            require(!nameViewport.activeFocus && !focusRing.visible, context
                    + " filename inspection restores the Control Center focus path");
        } else {
            require(!nameViewport.interactive && nameViewport.focusPolicy === Qt.NoFocus
                    && !nameViewport.activeFocusOnTab && nameViewport.Accessible.role
                    === Accessible.StaticText, context
                    + " keeps a fitting filename passive without a redundant scroll affordance");
            requireCaptureRectInside(nameRect, nameViewportRect, context
                                     + " keeps a fitting full filename inside its viewport");
        }
        const currentApplyRect = captureItemRect(apply, page);
        const currentClearRect = captureItemRect(clear, page);
        requireCaptureRectInside(captureItemRect(apply.contentItem, page), currentApplyRect, context
                                 + " keeps the Apply label inside its control");
        requireCaptureRectInside(captureItemRect(clear.contentItem, page), currentClearRect, context
                                 + " keeps the Clear label inside its control");
        require(apply.contentItem.paintedWidth <= apply.contentItem.width + 0.5
                && clear.contentItem.paintedWidth <= clear.contentItem.width + 0.5, context
                + " keeps action text painted inside assigned control widths");
        const shouldStack = actions.width + 0.5 < actions.inlineImplicitWidth;
        require(actions.stackActions === shouldStack && actions.columns === (shouldStack ? 1 : 2),
                context + " composes the same actions from their combined implicit width");
        if (shouldStack) {
            require(currentClearRect.y >= currentApplyRect.y + currentApplyRect.height
                    + actions.rowSpacing - 0.5, context
                    + " stacks actions without overlap when their inline width does not fit");
        } else {
            require(currentClearRect.x >= currentApplyRect.x + currentApplyRect.width
                    + actions.columnSpacing - 0.5, context
                    + " keeps fitting actions on one non-overlapping row");
        }
        require(countInSubtree(panel, function (item) {
                    return item.objectName === "wallpaperApplyButton";
                }) === 1 && countInSubtree(panel, function (item) {
                    return item.objectName === "wallpaperClearButton";
                }) === 1, context + " retains one Apply and one Clear action");
        const imageGrid = findObject(page, "wallpaperImageGrid");
        require(imageGrid !== null, context + " keeps the wallpaper image grid mounted");
        const pageViewport = {
            "x": 0,
            "y": 0,
            "width": page.width,
            "height": page.height
        };
        const gridRect = captureItemRect(imageGrid, page);
        const panelContentOrigin = panel.mapToItem(page.contentItem, 0, 0);
        require(page.effectiveContentWidth === Math.max(
                    0, page.width - page.verticalScrollbarReservation)
                && page.twoColumnWorkspace === (page.effectiveContentWidth >= 580), context
                + " derives workspace columns from the scrollbar-adjusted content lane");
        require(imageGrid.height >= Theme.size.controlHeightLg * 2 && gridRect.y < page.height
                && gridRect.y + gridRect.height > 0, context
                + " preserves a nonzero visible wallpaper grid viewport");
        if (page.twoColumnWorkspace) {
            require(panelRect.x >= gridRect.x + gridRect.width + Theme.spacing.md - 1, context
                    + " keeps the preview beside the library in the wide workspace");
        } else {
            require(imageGrid.height >= page.stackedGridMinimumHeight
                    && imageGrid.height <= page.stackedGridMaximumHeight + 0.5
                    && panelRect.y >= gridRect.y + gridRect.height + Theme.spacing.md - 1, context
                    + " keeps a bounded nonzero library above the reachable stacked preview");
        }
        require(page.contentHeight >= page.height && panelContentOrigin.y + panel.height
                <= page.contentHeight + 0.5, context
                + " keeps the complete preview rail reachable in the page scroll extent");
        if (page.contentHeight > page.height + 0.5) {
            clear.forceActiveFocus(Qt.TabFocusReason);
            requireCaptureRectInside(captureItemRect(clear, page), pageViewport, context
                                     + " reveals a keyboard-focused preview action");
            page.contentY = Math.max(0, page.contentHeight - page.height);
            const scrolledPanelRect = captureItemRect(panel, page);
            require(scrolledPanelRect.y + scrolledPanelRect.height <= page.height + 0.5
                    && scrolledPanelRect.y + scrolledPanelRect.height > 0, context
                    + " reaches the final preview result through page scrolling");
            page.contentY = 0;
            controlCenter.focusCurrentContext();
        }
    }

    function verifyWallpaperGeometryMatrix(page, finished) {
        const defaultSize = UserConfig.defaultSnapshot(
                              0).appearance.controlCenterBaseFontSize;
        const originalName = fakeWallpaper.preview.name;
        const maximumName = "w".repeat(251) + ".png";
        require(maximumName.length === 255,
                "Wallpaper maximum-length filename fixture reaches the validated character bound");
        const cases = [{
                           "fontSize": UserConfig.minimumBaseFontSize,
                           "windowWidth": Theme.size.controlCenterPreferredWidth,
                           "mode": "sidebar",
                           "capture": false
                       }, {
                           "fontSize": UserConfig.minimumBaseFontSize,
                           "windowWidth": Theme.size.controlCenterMinimumWidth,
                           "mode": "compact",
                           "capture": false
                       }, {
                           "fontSize": defaultSize,
                           "windowWidth": Theme.size.controlCenterPreferredWidth,
                           "mode": "sidebar",
                           "capture": false
                       }, {
                           "fontSize": defaultSize,
                           "windowWidth": Theme.size.controlCenterResponsiveBreakpoint,
                           "mode": "sidebar",
                           "stacked": true,
                           "capture": "sidebar-wallpaper-stacked-default"
                       }, {
                           "fontSize": defaultSize,
                           "windowWidth": Theme.size.controlCenterMinimumWidth,
                           "mode": "compact",
                           "capture": false
                       }, {
                           "fontSize": UserConfig.maximumBaseFontSize,
                           "windowWidth": Theme.size.controlCenterPreferredWidth,
                           "mode": "sidebar",
                           "capture": false,
                           "longName": true
                       }, {
                           "fontSize": UserConfig.maximumBaseFontSize,
                           "windowWidth": Theme.size.controlCenterResponsiveBreakpoint,
                           "mode": "sidebar",
                           "stacked": true,
                           "capture": "sidebar-wallpaper-stacked-18",
                           "longName": true
                       }, {
                           "fontSize": UserConfig.maximumBaseFontSize,
                           "windowWidth": Theme.size.controlCenterMinimumWidth,
                           "mode": "compact",
                           "capture": false,
                           "longName": true
                       }, {
                           "fontSize": UserConfig.maximumBaseFontSize,
                           "windowWidth": Theme.size.controlCenterMinimumWidth,
                           "mode": "compact",
                           "capture": "compact-wallpaper-18",
                           "longName": false
                       }];

        function applyCase(index) {
            if (index >= cases.length) {
                if (fakeWallpaper.preview.name !== originalName) {
                    fakeWallpaper.preview = Object.assign({}, fakeWallpaper.preview, {
                                                              "name": originalName
                                                          });
                }
                controlCenter.backingWindow.width = Theme.size.controlCenterPreferredWidth;
                renderedFrameBarrier.begin(function () {
                    require(controlCenter.layoutMode === "sidebar"
                            && UserConfig.snapshot.appearance.controlCenterBaseFontSize
                            === UserConfig.maximumBaseFontSize,
                            "Wallpaper restores the supported 18 px wide capture state");
                    requireWallpaperPreviewGeometry(page, "18 px wide Wallpaper");
                    finished();
                }, true);
                return;
            }
            const specification = cases[index];
            const requestedName = specification.longName === true ? maximumName : originalName;
            if (fakeWallpaper.preview.name !== requestedName) {
                fakeWallpaper.preview = Object.assign({}, fakeWallpaper.preview, {
                                                          "name": requestedName
                                                      });
            }
            require(UserConfig.snapshot.appearance.controlCenterBaseFontSize
                    === specification.fontSize || UserConfig.updatePage("appearance", {
                                                                           "controlCenterBaseFontSize":
                                                                           specification.fontSize
                                                                       }, false),
                    "Wallpaper selects the requested supported typography bound");
            controlCenter.backingWindow.width = specification.windowWidth;
            renderedFrameBarrier.begin(function () {
                require(controlCenter.layoutMode === specification.mode
                        && UserConfig.snapshot.appearance.controlCenterBaseFontSize
                        === specification.fontSize, specification.fontSize + " px Wallpaper enters "
                        + specification.mode + " mode");
                requireWallpaperPreviewGeometry(page, specification.fontSize + " px "
                                                      + specification.mode + " Wallpaper"
                                                      + (specification.longName === true
                                                         ? " maximum filename" : ""));
                if (specification.stacked === true) {
                    require(!page.twoColumnWorkspace && page.effectiveContentWidth < 580,
                            specification.fontSize
                            + " px Wallpaper uses the stacked sidebar workspace");
                }
                if (typeof specification.capture === "string") {
                    captureCurrent(specification.capture, function () {
                        applyCase(index + 1);
                    });
                } else {
                    applyCase(index + 1);
                }
            }, true);
        }

        applyCase(0);
    }

    function leaveWallpaperAfterCapture() {
        require(fakeHost.queueDisplayEvent(privacyCorpus.displayMetadata,
                                           privacyCorpus.rawDbus)
                && fakeHost.pendingDisplayEvent.metadata === privacyCorpus.displayMetadata
                && fakeHost.pendingDisplayEvent.rawPayload === privacyCorpus.rawDbus
                && fakeHost.publishDisplayEvent() && fakeHost.pendingDisplayEvent === null,
                "display metadata and raw D-Bus payload cross the owning topology event");
        requireCorpusAbsent(JSON.stringify(fakeHost.privacyState()),
                            "normalized display topology projection");
        require(controlCenter.open("displays", tokenB) && controlCenter.currentPageId === "displays",
                "leaving Wallpaper loads Displays through the same singleton");
        test.stage = "displays-after-wallpaper";
        settle.restart();
    }

    function wallpaperStage() {
        const page = controlCenter.loadedPageItem;
        require(page !== null && fakeWallpaper.pageOpen && page.currentDirectory().breadcrumb
                === "Wallpapers" && page.childDirectories().length === 1 && page.filteredImages(
                    ).length === 1,
                "Wallpaper opens lazy interest with bounded breadcrumb navigation and filtering");
        requireSectionHierarchy(page, [
                                    {
                                        "name": "wallpaperCurrentSection",
                                        "separated": false
                                    }
                                ], "Wallpaper");
        require(fakeWallpaper.installPrivateRecord(privacyCorpus.wallpaperPath,
                                                   privacyCorpus.wallpaperDigest)
                && fakeWallpaper.images[0].sourcePath === privacyCorpus.wallpaperPath
                && fakeWallpaper.images[0].digest === privacyCorpus.wallpaperDigest
                && page.selectImage(fakeWallpaper.images[0]) && fakeWallpaper.preview !== null,
                "wallpaper path and digest cross the owning library and preview flow");
        require(fakeWallpaper.cancelPreview(), "private wallpaper preview cancellation succeeds");
        page.selectedLibraryId = "";
        fakeWallpaper.clearPrivateRecord();
        requireCorpusAbsent(JSON.stringify(fakeWallpaper.images),
                            "cleaned wallpaper library projection");
        const filter = findObject(page, "wallpaperFilterInput");
        require(filter !== null, "Wallpaper exposes a keyboard-focusable image filter");
        filter.forceActiveFocus(Qt.TabFocusReason);
        filter.text = "missing";
        require(filter.activeFocus && page.filteredImages().length === 0,
                "keyboard filter focus updates the bounded image projection");
        filter.text = "";
        page.currentDirectoryId = fakeWallpaper.directories[1].id;
        require(page.currentDirectory().breadcrumb === "Wallpapers / Landscapes"
                && page.filteredImages().length === 1,
                "directory navigation updates breadcrumb and local image scope");
        page.currentDirectoryId = fakeWallpaper.directories[0].id;
        require(page.selectImage(fakeWallpaper.images[0]) && fakeWallpaper.preview !== null
                && fakeWallpaper.preview.status === "ready",
                "wallpaper selection previews one opaque library image");
        const applyButton = findObject(page, "wallpaperApplyButton");
        require(applyButton !== null && applyButton.enabled,
                "validated preview enables the accessible all-display action");
        require(!page.requestApply() && page.applyWarningVisible,
                "unsupported current plugins require a warned Apply");
        require(page.requestApply() && fakeWallpaper.applySuccess,
                "confirmed Apply targets every active display through the shared service");
        const wallpaperHeader = findObject(page, "wallpaperPageHeader");
        require(wallpaperHeader !== null && wallpaperHeader.visible && wallpaperHeader.width > 0
                && Math.abs(wallpaperHeader.width - wallpaperHeader.parent.width) <= 0.5,
                "Wallpaper keeps its shared header on the full content width");
        const wallpaperHeaderBottom = wallpaperHeader.mapToItem(page, 0, 0).y
                                      + wallpaperHeader.height;
        const wallpaperActionNames = ["wallpaperBrowseButton", "wallpaperAddRootButton"];
        for (let wallpaperActionIndex = 0; wallpaperActionIndex
                < wallpaperActionNames.length; wallpaperActionIndex += 1) {
            const wallpaperAction = findObject(page, wallpaperActionNames[wallpaperActionIndex]);
            require(wallpaperAction !== null && wallpaperAction.visible
                    && wallpaperAction.mapToItem(page, 0, 0).y >= wallpaperHeaderBottom - 0.5,
                    "Wallpaper keeps " + wallpaperActionNames[wallpaperActionIndex]
                    + " below the full-width shared header");
        }
        verifyWallpaperGeometryMatrix(page, function () {
            captureCurrent("sidebar-wallpaper", leaveWallpaperAfterCapture);
        });
    }

    function displaysAfterWallpaperStage() {
        require(!fakeWifi.bluetoothManagerOpen && !fakeWallpaper.pageOpen,
                "leaving managed pages stops Bluetooth and wallpaper page interest");
        const displaysPage = controlCenter.loadedPageItem;
        require(displaysPage !== null && displaysPage.contentHeight < displaysPage.height,
                "tall tiled windows keep display rows packed at the top");
        requireSectionHierarchy(displaysPage, [
                                    {
                                        "name": "displaysActiveSection",
                                        "separated": false,
                                        "list": true,
                                        "rows": 2
                                    },
                                    {
                                        "name": "displaysRememberedSection",
                                        "separated": true,
                                        "list": true,
                                        "rows": 0
                                    }
                                ], "Displays");
        captureCurrent("sidebar-displays", function () {
            test.requestedTallHeight = Math.min(1200, controlCenter.maximumSize.height);
            test.requestedTiledWidth = Math.min(1200, controlCenter.maximumSize.width);
            controlCenter.backingWindow.width = test.requestedTiledWidth;
            controlCenter.backingWindow.height = test.requestedTallHeight;
            test.stage = "displays-tall";
            settle.restart();
        });
    }

    function displaysTallStage() {
        const displaysPage = controlCenter.loadedPageItem;
        require(Math.abs(controlCenter.backingWindow.width - test.requestedTiledWidth) < 1 && Math.abs(
                    controlCenter.backingWindow.height - test.requestedTallHeight) < 1,
                "the harness exercises compositor-sized Control Center geometry");
        require(displaysPage !== null && displaysPage.contentHeight < displaysPage.height,
                "tiled height adds empty space below one intrinsic top-aligned display list");
        captureCurrent("sidebar-displays-tall", function () {
            controlCenter.closeWindow();
            controlCenter.backingWindow.height = Theme.size.controlCenterPreferredHeight;
            controlCenter.backingWindow.width = Theme.size.controlCenterPreferredWidth;
            test.stage = "closed";
            settle.restart();
        });
    }

    function closedStage() {
        require(!controlCenter.visible && controlCenter.loadedPageCount === 0
                && controlCenter.currentPageId === "displays",
                "close unloads page content but retains the last valid page id");
        controlCenter.open("control-center", tokenB);
        stage = "reopened";
        focusReadinessBarrier.begin(function () {
            const route = findObject(controlCenter.contentItem,
                                     "controlCenterSidebarRoute-displays");
            return controlCenter.pageLoaded && route !== null && route.activeFocus;
        }, test.runStage);
    }

    function reopenedStage() {
        require(controlCenter.currentPageId === "displays" && controlCenter.activeTargetScreen
                === Quickshell.screens[1],
                "reopen restores the valid page and routes the fresh open to its new initiator");
        const displaysRoute = findObject(controlCenter.contentItem,
                                         "controlCenterSidebarRoute-displays");
        require(displaysRoute !== null && displaysRoute.activeFocus,
                "wide navigation-only reopening focuses the retained route");
        const displaysPage = controlCenter.pageLoaded ? controlCenter.contentItem : null;
        require(displaysPage !== null, "delivered Displays page loads inside the singleton");
        fakeHost.rejectChanges = true;
        require(controlCenter.selectRoute("about") && controlCenter.visible,
                "one page failure cannot block unrelated navigation or island operation");
        stage = "about";
        focusReadinessBarrier.begin(test.routeActivationFocusReady, test.runStage);
    }

    function aboutStage() {
        requireRouteActivationFocus("wide route activation");
        const aboutRoute = findObject(controlCenter.contentItem, "controlCenterSidebarRoute-about");
        const displaysRoute = findObject(controlCenter.contentItem,
                                         "controlCenterSidebarRoute-displays");
        const islandRoute = findObject(controlCenter.contentItem,
                                       "controlCenterSidebarRoute-island");
        require(aboutRoute !== null && displaysRoute !== null && islandRoute !== null
                && !aboutRoute.activeFocus && aboutRoute.Accessible.name === "About"
                && aboutRoute.Accessible.description === "Open About",
                "route activation leaves stable navigation metadata without retaining rail focus");
        aboutRoute.forceActiveFocus(Qt.TabFocusReason);
        require(aboutRoute.focusRelativeRoute(-1) && displaysRoute.activeFocus,
                "sidebar Up navigation moves to the preceding route");
        require(displaysRoute.focusRelativeRoute(1) && aboutRoute.activeFocus
                && aboutRoute.focusRelativeRoute(1) && islandRoute.activeFocus,
                "sidebar Down navigation advances and wraps at the final route");
        require(islandRoute.focusRouteAt(controlCenter.availableRoutes.length - 1)
                && aboutRoute.activeFocus && aboutRoute.focusRouteAt(0) && islandRoute.activeFocus,
                "sidebar Home and End navigation reach deterministic route boundaries");
        aboutRoute.forceActiveFocus(Qt.TabFocusReason);
        require(controlCenter.pageLoaded, "About page remains available with unavailable services");
        requireSectionHierarchy(controlCenter.loadedPageItem, [
                                    {
                                        "name": "aboutProjectSection",
                                        "separated": true
                                    },
                                    {
                                        "name": "aboutDiagnosticSection",
                                        "separated": true
                                    }
                                ], "About");
        const diagnostic = controlCenter.diagnosticText;
        require(diagnostic.indexOf("Nagi Shell 0.1.0") === 0 && diagnostic.indexOf(
                    "Settings schema: 3") !== -1 && diagnostic.indexOf("Wi-Fi: unavailable") !== -1,
                "About diagnostic exposes exact allowlisted component states");
        const aboutPage = controlCenter.loadedPageItem;
        const aboutHeader = findObject(aboutPage, "aboutPageHeader");
        const projectSection = findObject(aboutPage, "aboutProjectSection");
        const versionText = findInSubtree(aboutPage, function (item) {
            return item.text === "Nagi Shell 0.1.0";
        });
        const safeDiagnostic = findInSubtree(aboutPage, function (item) {
            return item.Accessible.name === "Safe diagnostic text";
        });
        const copyDiagnostic = findInSubtree(aboutPage, function (item) {
            return item.label === "Copy diagnostic";
        });
        require(aboutHeader !== null && projectSection !== null && versionText !== null,
                "About exposes its header, standalone version, and first section");
        const headerRect = captureItemRect(aboutHeader, aboutPage.contentItem);
        const versionRect = captureItemRect(versionText, aboutPage.contentItem);
        const projectRect = captureItemRect(projectSection, aboutPage.contentItem);
        require(versionText.parent === aboutHeader.parent
                && versionRect.y >= headerRect.y + headerRect.height
                && projectRect.y >= versionRect.y + versionRect.height,
                "About keeps its version outside and before the two semantic sections");
        require(safeDiagnostic !== null && copyDiagnostic !== null && safeDiagnostic.readOnly
                && safeDiagnostic.selectByMouse && safeDiagnostic.text === diagnostic
                && safeDiagnostic.background.color === Theme.color.controlFill
                && safeDiagnostic.background.border.width === Theme.size.hairlineWidth,
                "About retains one bordered selectable diagnostic control and its copy action");
        privacyDiagnostic = diagnostic;
        requireCorpusAbsent(diagnostic, "About diagnostic identity and content allowlist");
        captureCurrent("sidebar-about", function () {
            controlCenter.backingWindow.width = Theme.size.controlCenterResponsiveBreakpoint - 1;
            controlCenter.backingWindow.height = Theme.size.controlCenterMinimumHeight;
            controlCenter.compactNavigationVisible = true;
            test.stage = "boundary-799";
            focusReadinessBarrier.begin(function () {
                const route = findObject(controlCenter.contentItem,
                                         "controlCenterCompactRoute-about");
                return controlCenter.loadedPageCount === 0 && route !== null && route.activeFocus;
            }, test.runStage);
        });
    }

    function boundary799Stage() {
        require(Math.abs(controlCenter.backingWindow.width
                         - (Theme.size.controlCenterResponsiveBreakpoint - 1)) <= 0.5
                && Math.abs(controlCenter.backingWindow.height
                            - Theme.size.controlCenterMinimumHeight) <= 0.5
                && controlCenter.layoutMode === "compact"
                && controlCenter.compactNavigationVisible
                && controlCenter.loadedPageCount === 0, "799 x 480 uses lazy compact navigation");
        require(UserConfig.snapshot.appearance.controlCenterBaseFontSize
                === UserConfig.maximumBaseFontSize,
                "799 x 480 capture keeps the supported 18 px typography bound");
        const route = findObject(controlCenter.contentItem, "controlCenterCompactRoute-about");
        const viewport = findObject(controlCenter.contentItem,
                                    "controlCenterCompactRouteViewport");
        require(route !== null && viewport !== null && route.activeFocus,
                "799 x 480 exposes and focuses the selected compact route");
        requireRouteComposition("compact", "799 x 480 compact navigation", true);
        captureCurrent("compact-boundary-799-18", function () {
            controlCenter.backingWindow.width = Theme.size.controlCenterResponsiveBreakpoint;
            test.stage = "boundary-800";
            focusReadinessBarrier.begin(function () {
                const route = findObject(controlCenter.contentItem,
                                         "controlCenterSidebarRoute-about");
                return controlCenter.pageLoaded && route !== null && route.activeFocus;
            }, test.runStage);
        });
    }

    function boundary800Stage() {
        require(Math.abs(controlCenter.backingWindow.width
                         - Theme.size.controlCenterResponsiveBreakpoint) <= 0.5
                && Math.abs(controlCenter.backingWindow.height
                            - Theme.size.controlCenterMinimumHeight) <= 0.5
                && controlCenter.layoutMode === "sidebar"
                && controlCenter.loadedPageCount === 1,
                "800 x 480 crosses exactly into the persistent rail layout");
        require(UserConfig.snapshot.appearance.controlCenterBaseFontSize
                === UserConfig.maximumBaseFontSize,
                "800 x 480 capture keeps the supported 18 px typography bound");
        const page = controlCenter.loadedPageItem;
        const route = findObject(controlCenter.contentItem, "controlCenterSidebarRoute-about");
        const viewport = findObject(controlCenter.contentItem,
                                    "controlCenterSidebarRouteViewport");
        require(page !== null && route !== null && viewport !== null
                && Math.abs(page.width - (Theme.size.controlCenterResponsiveBreakpoint
                                          - Theme.size.controlCenterSidebarWidth
                                          - Theme.spacing.xl * 2)) <= 1,
                "800 px allocates the exact 512 px content lane beside the 240 px rail");
        require(route.activeFocus,
                "800 x 480 navigation replacement focuses the selected rail route");
        requireHeaderInViewport(page, "800 x 480 About");
        requireRailContract("800 x 480");
        requireRouteComposition("sidebar", "800 x 480 sidebar navigation", true);
        require(page.contentHeight > page.height + 1,
                "800 x 480 keeps the full About composition in one page scroll extent");
        const maximumContentY = Math.max(0, page.contentHeight - page.height);
        page.contentY = maximumContentY;
        require(Math.abs(page.contentY - maximumContentY) <= 1,
                "minimum-height page scrolling reaches the end of the composition");
        page.contentY = 0;
        requireSectionHierarchy(page, [
                                    {
                                        "name": "aboutProjectSection",
                                        "separated": true
                                    },
                                    {
                                        "name": "aboutDiagnosticSection",
                                        "separated": true
                                    }
                                ], "800 x 480 About");
        captureCurrent("sidebar-boundary-800-18", function () {
            controlCenter.closeWindow();
            controlCenter.implicitWidth = Theme.size.controlCenterMinimumWidth;
            controlCenter.backingWindow.width = Theme.size.controlCenterMinimumWidth;
            controlCenter.backingWindow.height = Theme.size.controlCenterMinimumHeight;
            controlCenter.open("about", tokenA);
            test.stage = "compact";
            focusReadinessBarrier.begin(function () {
                const back = findObject(controlCenter.contentItem, "controlCenterCompactBack");
                return controlCenter.pageLoaded && back !== null && back.activeFocus;
            }, test.runStage);
        });
    }

    function compactStage() {
        require(controlCenter.layoutMode === "compact",
                "below the breakpoint uses compact replacement navigation");
        require(Math.abs(controlCenter.backingWindow.width - Theme.size.controlCenterMinimumWidth)
                <= 0.5 && Math.abs(controlCenter.backingWindow.height
                                   - Theme.size.controlCenterMinimumHeight) <= 0.5,
                "compact navigation exercises the exact 640 x 480 minimum window");
        const compactBack = findObject(controlCenter.contentItem, "controlCenterCompactBack");
        require(compactBack !== null && compactBack.activeFocus,
                "compact navigation-only reopening focuses All settings");
        compactBack.clicked();
        focusReadinessBarrier.begin(function () {
            const route = findObject(controlCenter.contentItem,
                                     "controlCenterCompactRoute-about");
            return controlCenter.loadedPageCount === 0 && route !== null && route.activeFocus;
        }, function () {
            requireRouteComposition("compact", "640 x 480 compact navigation", true);
            captureCurrent("compact-navigation", function () {
                require(controlCenter.selectRoute("about")
                        && !controlCenter.compactNavigationVisible,
                        "compact route activation replaces navigation with one loaded page");
                test.stage = "compact-loaded";
                focusReadinessBarrier.begin(test.routeActivationFocusReady, test.runStage);
            });
        });
    }

    function compactLoadedStage() {
        const compactPage = controlCenter.loadedPageItem;
        requireRouteActivationFocus("compact route activation");
        const compactBack = findObject(controlCenter.contentItem, "controlCenterCompactBack");
        require(compactBack !== null && !compactBack.activeFocus,
                "compact route activation does not retain All settings focus");
        require(compactPage.contentHeight > compactPage.height + 1
                && Math.abs(compactPage.width - (Theme.size.controlCenterMinimumWidth
                                                 - Theme.spacing.lg * 2)) <= 1,
                "640 x 480 keeps a 608 px compact lane and one page scroll extent");
        const maximumContentY = Math.max(0, compactPage.contentHeight - compactPage.height);
        compactPage.contentY = maximumContentY;
        require(Math.abs(compactPage.contentY - maximumContentY) <= 1,
                "minimum compact page scrolling reaches the end of the composition");
        compactPage.contentY = 0;
        requireHeaderInViewport(compactPage, "640 x 480 compact About");
        requireCompactChromeContract("compact About");
        captureCurrent("compact-about", function () {
            controlCenter.closeWindow();
            controlCenter.implicitWidth = Theme.size.controlCenterPreferredWidth;
            controlCenter.backingWindow.width = Theme.size.controlCenterPreferredWidth;
            controlCenter.backingWindow.height = Theme.size.controlCenterPreferredHeight;
            controlCenter.open("about", tokenA);
            test.stage = "wide";
            focusReadinessBarrier.begin(function () {
                const route = findObject(controlCenter.contentItem,
                                         "controlCenterSidebarRoute-about");
                return controlCenter.pageLoaded && route !== null && route.activeFocus;
            }, test.runStage);
        });
    }

    function wideStage() {
        const page = controlCenter.loadedPageItem;
        const route = findObject(controlCenter.contentItem, "controlCenterSidebarRoute-about");
        require(route !== null && route.activeFocus,
                "wide navigation-only reopening focuses the retained route");
        require(controlCenter.layoutMode === "sidebar" && controlCenter.loadedPageCount === 1
                && page !== null && Math.abs(page.width - (Theme.size.controlCenterPreferredWidth
                                                           - Theme.size.controlCenterSidebarWidth
                                                           - Theme.spacing.xl * 2)) <= 1,
                "920 x 660 uses the persistent rail with an exact 632 px page lane");
        require(Math.abs(controlCenter.backingWindow.width
                         - Theme.size.controlCenterPreferredWidth) <= 0.5
                && Math.abs(controlCenter.backingWindow.height
                            - Theme.size.controlCenterPreferredHeight) <= 0.5,
                "wide stage exercises the exact 920 x 660 preferred window");
        requireHeaderInViewport(controlCenter.loadedPageItem, "wide alternate-typography About");
        requireRailContract("wide alternate-typography");
        captureCurrent("sidebar-responsive", function () {
            require(UserConfig.snapshot.weather.enabled && controlCenter.currentPageId === "about",
                    "read-only focus coverage starts from non-default V3 settings on an unrelated page");
            test.writableSettingsFixture = UserConfig.serializeConfiguration(UserConfig.snapshot);
            require(test.writableSettingsFixture.indexOf("[settings]\nschema_version=3\n") === 0,
                    "read-only focus coverage preserves one canonical V3 fixture for restoration");
            test.stage = "settings-read-only";
            settingsFixtureWriter.setText("[settings]\nschema_version=4\n[future]\nvalue=kept\n");
        });
    }

    function settingsReadOnlyStage() {
        if (UserConfig.status !== "future") {
            settle.restart();
            return;
        }
        require(UserConfig.readOnly && !UserConfig.writable
                && test.writableSettingsFixture !== "",
                "a future settings file exposes the production non-writable state");
        require(controlCenter.selectRoute("island") && controlCenter.layoutMode === "sidebar",
                "wide non-writable coverage activates the all-settings Island route");
        test.stage = "settings-read-only-wide";
        focusReadinessBarrier.begin(function () {
            return test.routeActivationFocusReady(true);
        }, test.runStage);
    }

    function settingsReadOnlyWideStage() {
        const page = controlCenter.loadedPageItem;
        const route = findObject(controlCenter.contentItem, "controlCenterSidebarRoute-island");
        const statusPanel = findObject(controlCenter.contentItem, "controlCenterSettingsStatus");
        requireRouteActivationFocus("wide non-writable Island route activation", true);
        require(page !== null && controlCenter.currentPageId === "island"
                && controlCenter.settingsUnavailable && statusPanel !== null && statusPanel.visible
                && route !== null && !route.activeFocus,
                "wide non-writable Island activation leaves navigation for readable page content");
        test.stage = "settings-read-only-compact-page";
        controlCenter.backingWindow.width = Theme.size.controlCenterMinimumWidth;
        focusReadinessBarrier.begin(function () {
            const back = findObject(controlCenter.contentItem, "controlCenterCompactBack");
            return controlCenter.layoutMode === "compact" && controlCenter.pageLoaded
                    && back !== null && back.activeFocus;
        }, test.runStage);
    }

    function settingsReadOnlyCompactPageStage() {
        const header = pageFocusFallback(controlCenter.loadedPageItem);
        const back = findObject(controlCenter.contentItem, "controlCenterCompactBack");
        require(controlCenter.layoutMode === "compact" && controlCenter.currentPageId === "island"
                && controlCenter.pageLoaded && back !== null && back.activeFocus
                && header !== null && !header.activeFocus,
                "compact layout replacement keeps explicit focus on All settings");
        test.stage = "settings-read-only-compact-navigation";
        back.clicked();
        focusReadinessBarrier.begin(function () {
            const route = findObject(controlCenter.contentItem, "controlCenterCompactRoute-island");
            return controlCenter.compactNavigationVisible && controlCenter.loadedPageCount === 0
                    && route !== null && route.activeFocus;
        }, test.runStage);
    }

    function settingsReadOnlyCompactNavigationStage() {
        const route = findObject(controlCenter.contentItem, "controlCenterCompactRoute-island");
        require(controlCenter.compactNavigationVisible && controlCenter.loadedPageCount === 0
                && route !== null && route.activeFocus,
                "compact All settings preserves selected-route navigation focus");
        require(controlCenter.selectRoute("island") && !controlCenter.compactNavigationVisible,
                "compact non-writable Island activation replaces navigation with the page");
        test.stage = "settings-read-only-compact";
        focusReadinessBarrier.begin(function () {
            return test.routeActivationFocusReady(true);
        }, test.runStage);
    }

    function settingsReadOnlyCompactStage() {
        const back = findObject(controlCenter.contentItem, "controlCenterCompactBack");
        const route = findObject(controlCenter.contentItem, "controlCenterCompactRoute-island");
        requireRouteActivationFocus("compact non-writable Island route activation", true);
        require(controlCenter.layoutMode === "compact" && controlCenter.currentPageId === "island"
                && controlCenter.settingsUnavailable && back !== null && !back.activeFocus
                && (route === null || !route.activeFocus),
                "compact non-writable Island activation leaves All settings and route focus");
        test.stage = "settings-writable-restored";
        settingsFixtureWriter.setText(test.writableSettingsFixture);
    }

    function settingsWritableRestoredStage() {
        if (UserConfig.status !== "ready" || !UserConfig.writable) {
            settle.restart();
            return;
        }
        require(UserConfig.snapshot.schemaVersion === 3
                && UserConfig.serializeConfiguration(UserConfig.snapshot).indexOf(
                    "[settings]\nschema_version=3\n") === 0,
                "restoring the writable fixture resumes the exact V3 settings contract");
        requirePageHeaderTabContinuation("restored writable Island page");
        test.stage = "settings-writable-wide";
        controlCenter.backingWindow.width = Theme.size.controlCenterPreferredWidth;
        focusReadinessBarrier.begin(function () {
            const route = findObject(controlCenter.contentItem, "controlCenterSidebarRoute-island");
            return controlCenter.layoutMode === "sidebar" && route !== null && route.activeFocus;
        }, test.runStage);
    }

    function settingsWritableWideStage() {
        const route = findObject(controlCenter.contentItem, "controlCenterSidebarRoute-island");
        require(route !== null && route.activeFocus && controlCenter.currentPageId === "island",
                "wide layout replacement restores selected-route navigation focus");
        require(controlCenter.selectRoute("about"),
                "restored writable settings reactivate the unrelated About route");
        test.stage = "settings-writable-about";
        focusReadinessBarrier.begin(test.routeActivationFocusReady, test.runStage);
    }

    function settingsWritableAboutStage() {
        requireRouteActivationFocus("writable route activation after read-only recovery");
        require(UserConfig.snapshot.weather.enabled && controlCenter.currentPageId === "about",
                "settings recovery starts from restored non-default V3 settings on an unrelated page");
        test.stage = "settings-invalid";
        settingsFixtureWriter.setText("[broken\npartial=true\n");
    }

    function settingsInvalidStage() {
        if (!UserConfig.recoveryRequired) {
            settle.restart();
            return;
        }
        const statusPanel = findObject(controlCenter.contentItem, "controlCenterSettingsStatus");
        const resetButton = findObject(controlCenter.contentItem, "controlCenterResetDefaults");
        const cancelButton = findObject(controlCenter.contentItem,
                                        "controlCenterCancelResetDefaults");
        const confirmButton = findObject(controlCenter.contentItem,
                                         "controlCenterConfirmResetDefaults");
        require(UserConfig.recoveryKind === "invalid" && controlCenter.settingsUnavailable
                && controlCenter.canResetInvalidSettings && statusPanel !== null
                && statusPanel.visible && resetButton !== null && resetButton.visible
                && resetButton.label === "Reset to defaults" && cancelButton !== null
                && confirmButton !== null,
                "invalid settings expose one contextual default recovery action");
        captureCurrent("sidebar-settings-recovery", function () {
            resetButton.clicked();
            require(UserConfig.recoveryRequired
                    && controlCenter.settingsRecoveryConfirmationVisible && !resetButton.visible
                    && cancelButton.visible && confirmButton.visible,
                    "default recovery requires explicit confirmation before writing");
            Qt.callLater(function () {
                require(confirmButton.activeFocus,
                        "recovery confirmation receives deterministic initial focus");
                cancelButton.clicked();
                Qt.callLater(function () {
                    require(UserConfig.recoveryRequired &&
                            !controlCenter.settingsRecoveryConfirmationVisible
                            && resetButton.visible && resetButton.activeFocus,
                            "cancel returns focus without changing invalid settings");
                    resetButton.clicked();
                    captureCurrent("sidebar-settings-recovery-confirmation", function () {
                        require(confirmButton.activeFocus,
                                "reopened recovery confirmation receives focus");
                        confirmButton.clicked();
                        test.stage = "settings-recovered";
                        settle.restart();
                    });
                });
            });
        });
    }

    function settingsRecoveredStage() {
        if (UserConfig.status !== "ready") {
            settle.restart();
            return;
        }
        const defaults = UserConfig.defaultSnapshot(0);
        const statusPanel = findObject(controlCenter.contentItem, "controlCenterSettingsStatus");
        require(UserConfig.snapshotKey(UserConfig.snapshot) === UserConfig.snapshotKey(defaults) &&
                !controlCenter.settingsUnavailable &&
                !controlCenter.settingsRecoveryConfirmationVisible && statusPanel !== null &&
                !statusPanel.visible,
                "confirmed recovery atomically publishes defaults and clears the error state");
        controlCenter.screen = null;
        controlCenter.rehomeAfterDisplayLoss();
        require(controlCenter.screen === Quickshell.screens[0],
                "invalid Qt screen rehomes through pointer or fallback routing");
        stage = "rehomed";
        settle.restart();
    }

    function rehomedStage() {
        const routePrefix = controlCenter.layoutMode === "sidebar" ? "controlCenterSidebarRoute-" :
                                                                     "controlCenterCompactRoute-";
        const activeRoute = findObject(controlCenter.contentItem, routePrefix
                                       + controlCenter.currentPageId);
        require(activeRoute !== null && activeRoute.visible && activeRoute.activeFocus,
                "display loss restores one visible valid Control Center focus target");
        require(controlCenter.layoutMode === "sidebar"
                && UserConfig.snapshot.appearance.controlCenterBaseFontSize
                === UserConfig.defaultSnapshot(0).appearance.controlCenterBaseFontSize,
                "the rehomed wide state runs at default typography");
        requireHeaderInViewport(controlCenter.loadedPageItem, "rehomed default-typography About");
        requireRailContract("rehomed default-typography");
        captureCurrent("sidebar-rehomed-default", function () {
            controlCenter.closeWindow();
            controlCenter.implicitWidth = Theme.size.controlCenterMinimumWidth;
            controlCenter.open("removed-page", null);
            test.stage = "compact-default";
            settle.restart();
        });
    }

    function compactDefaultStage() {
        require(controlCenter.layoutMode === "compact" && controlCenter.visible
                && controlCenter.currentPageId === "displays" && controlCenter.loadedPageCount
                === 1, "the compact default state loads one page below the breakpoint");
        const displaysPage = controlCenter.loadedPageItem;
        displaysPage.contentY = 0;
        requireCompactChromeContract("compact default-typography Displays");
        requireHeaderInViewport(displaysPage, "compact default-typography Displays");
        captureCurrent("compact-displays-default", function () {
            controlCenter.closeWindow();
            controlCenter.implicitWidth = Theme.size.controlCenterPreferredWidth;
            controlCenter.open("removed-page", null);
            test.stage = "fallback";
            settle.restart();
        });
    }

    function fallbackStage() {
        require(controlCenter.currentPageId === "displays" && controlCenter.screen
                === Quickshell.screens[0],
                "missing routes fall back deterministically through pointer routing");
        if (UserConfig._writeInProgress || UserConfig._writeCandidate !== null
                || UserConfig._pendingLastGoodSnapshot !== null) {
            settle.restart();
            return;
        }
        const defaults = UserConfig.defaultSnapshot(0);
        require(UserConfig.snapshotKey(UserConfig._persistedSnapshot) === UserConfig.snapshotKey(
                    defaults),
                "final reload cleanup persists only the default normalized configuration");
        const unloadCountBeforeNativeClose = unloadRequestCount;
        controlCenter.visible = false;
        controlCenter.closed();
        require(unloadRequestCount === unloadCountBeforeNativeClose + 1
                && controlCenter.closeUnloadRequested,
                "native window close unloads the Control Center after visibility is already false");
        for (let index = 0; index < controls.length; index += 1) {
            controls[index].destroy();
        }
        controls = [];
        finalizePrivacyState();
        writePrivacyArtifacts();
    }

    function runStage() {
        switch (stage) {
        case "initial":
            initialStage();
            break;
        case "primitive-three":
            primitiveThreeStage();
            break;
        case "primitive-one":
            primitiveOneStage();
            break;
        case "primitive-restored":
            primitiveRestoredStage();
            break;
        case "opened-a":
            openedAStage();
            break;
        case "island":
            islandStage();
            break;
        case "clock":
            clockStage();
            break;
        case "media":
            mediaStage();
            break;
        case "weather":
            weatherStage();
            break;
        case "weather-private-persisted":
            weatherPrivatePersistedStage();
            break;
        case "weather-private-cleared":
            weatherPrivateClearedStage();
            break;
        case "notifications":
            notificationsStage();
            break;
        case "wifi":
            wifiStage();
            break;
        case "bluetooth":
            bluetoothStage();
            break;
        case "wallpaper":
            wallpaperStage();
            break;
        case "displays-after-wallpaper":
            displaysAfterWallpaperStage();
            break;
        case "displays-tall":
            displaysTallStage();
            break;
        case "closed":
            closedStage();
            break;
        case "reopened":
            reopenedStage();
            break;
        case "about":
            aboutStage();
            break;
        case "boundary-799":
            boundary799Stage();
            break;
        case "boundary-800":
            boundary800Stage();
            break;
        case "compact":
            compactStage();
            break;
        case "compact-loaded":
            compactLoadedStage();
            break;
        case "wide":
            wideStage();
            break;
        case "settings-read-only":
            settingsReadOnlyStage();
            break;
        case "settings-read-only-wide":
            settingsReadOnlyWideStage();
            break;
        case "settings-read-only-compact-page":
            settingsReadOnlyCompactPageStage();
            break;
        case "settings-read-only-compact-navigation":
            settingsReadOnlyCompactNavigationStage();
            break;
        case "settings-read-only-compact":
            settingsReadOnlyCompactStage();
            break;
        case "settings-writable-restored":
            settingsWritableRestoredStage();
            break;
        case "settings-writable-wide":
            settingsWritableWideStage();
            break;
        case "settings-writable-about":
            settingsWritableAboutStage();
            break;
        case "settings-invalid":
            settingsInvalidStage();
            break;
        case "settings-recovered":
            settingsRecoveredStage();
            break;
        case "rehomed":
            rehomedStage();
            break;
        case "compact-default":
            compactDefaultStage();
            break;
        case "fallback":
            fallbackStage();
            break;
        default:
            fail("unexpected stage");
        }
    }

    QtObject {
        id: fakeHost

        property int revision: 1
        property int enabledDisplayCount: Quickshell.screens.length
        property var rememberedDisplays: []
        property string lastFailure: ""
        property bool rejectChanges: false
        property var pendingDisplayEvent: null

        function routeSurfaceToken(excludedToken) {
            return test.tokenA;
        }

        function screenForToken(token) {
            if (token === test.tokenA) {
                return Quickshell.screens[0];
            }
            if (token === test.tokenB && Quickshell.screens.length > 1) {
                return Quickshell.screens[1];
            }
            return null;
        }

        function activeDisplays() {
            const rows = [];
            for (let index = 0; index < Quickshell.screens.length; index += 1) {
                rows.push({
                              "connected": true,
                              "enabled": true,
                              "fallback": index === 0,
                              "label": "Connected display " + (index + 1),
                              "reliable": false,
                              "screen": Quickshell.screens[index]
                          });
            }
            return rows;
        }

        function queueDisplayEvent(metadata, rawPayload) {
            if (typeof metadata !== "string" || typeof rawPayload !== "string"
                    || pendingDisplayEvent !== null) {
                return false;
            }
            pendingDisplayEvent = {
                "metadata": metadata,
                "rawPayload": rawPayload
            };
            return true;
        }

        function publishDisplayEvent() {
            if (pendingDisplayEvent === null) {
                return false;
            }
            revision += 1;
            pendingDisplayEvent = null;
            return true;
        }

        function clearPrivateState() {
            pendingDisplayEvent = null;
            lastFailure = "";
        }

        function privacyState() {
            return {
                "pendingDisplayEvent": pendingDisplayEvent,
                "revision": revision,
                "enabledDisplayCount": enabledDisplayCount,
                "rememberedDisplayCount": rememberedDisplays.length,
                "lastFailure": lastFailure
            };
        }

        function setEnabled(screen, enabled) {
            if (rejectChanges) {
                lastFailure = "Synthetic unavailable display controller.";
                return false;
            }
            return true;
        }

        function setFallback(screen) {
            if (rejectChanges) {
                lastFailure = "Synthetic unavailable display controller.";
                return false;
            }
            return true;
        }

        function confirmForget(identity) {
            return false;
        }
    }

    QtObject {
        id: fakeClock
        property string text: "12:34"
        property string dateText: "Wednesday, 26 August"
    }

    QtObject {
        id: fakeMedia
        property var pendingApplication: null
        property var availableApplications: [
            {
                "label": "Fixture Player",
                "value": "fixture"
            }
        ]

        function queueApplicationEvent(executable, pid) {
            if (typeof executable !== "string" || !Number.isInteger(pid) || pendingApplication
                    !== null) {
                return false;
            }
            pendingApplication = {
                "executable": executable,
                "pid": pid
            };
            return true;
        }

        function publishApplicationEvent() {
            if (pendingApplication === null) {
                return false;
            }
            availableApplications = [
                        {
                            "label": "Fixture Player",
                            "value": "fixture"
                        }
                    ];
            pendingApplication = null;
            return true;
        }

        function clearPrivateState() {
            pendingApplication = null;
        }

        function privacyState() {
            return {
                "pendingApplication": pendingApplication,
                "availableApplications": availableApplications
            };
        }
    }

    QtObject {
        id: fakeWeather
        property bool available: false
        property bool stale: false
        property var model: null
        property var current: null
    }

    QtObject {
        id: fakeLocationSearch
        property bool inFlight: false
        property var results: []
        property string failure: "none"
        property string attribution: "Location data by GeoNames via Open-Meteo · CC BY 4.0"
        property string providerBody: ""
        property var queuedResponse: null

        function queueProviderResponse(label, latitude, longitude, body) {
            if (typeof label !== "string" || typeof latitude !== "number" || typeof longitude
                    !== "number" || typeof body !== "string" || queuedResponse !== null) {
                return false;
            }
            queuedResponse = {
                "label": label,
                "latitude": latitude,
                "longitude": longitude,
                "body": body
            };
            return true;
        }

        function search(query) {
            if (query === "Paris") {
                results = [
                            {
                                "label": "Paris, France",
                                "latitude": 48.8534,
                                "longitude": 2.3488
                            }
                        ];
                providerBody = "";
                return true;
            }
            if (query !== "private fixture" || queuedResponse === null) {
                return false;
            }
            results = [
                        {
                            "label": queuedResponse.label,
                            "latitude": queuedResponse.latitude,
                            "longitude": queuedResponse.longitude
                        }
                    ];
            providerBody = queuedResponse.body;
            queuedResponse = null;
            return true;
        }

        function clear() {
            results = [];
            providerBody = "";
            queuedResponse = null;
            failure = "none";
        }

        function privacyState() {
            return {
                "inFlight": inFlight,
                "results": results,
                "failure": failure,
                "providerBody": providerBody,
                "queuedResponse": queuedResponse
            };
        }
    }
    QtObject {
        id: fakeWifi
        property bool backendReady: true
        property bool wifiAvailable: true
        property bool wifiEnabled: true
        property bool wifiHardwareEnabled: true
        property bool wifiBusy: false
        property bool wifiScanning: false
        property bool wifiManagerOpen: false
        property int lastWifiSecretLength: 0
        property int lastSsidLength: 0
        property int lastBluetoothSecretLength: 0
        property int lastToken: 0
        property bool lastRemember: false
        property string lastOperation: ""
        property string wifiCurrentNetwork: "Fixture"
        property var wifiNetworks: [
            {
                "token": 1,
                "ssid": "Fixture",
                "security": "wpa-personal",
                "strength": 80,
                "connected": true,
                "saved": true,
                "forgettable": true,
                "connectable": true,
                "forgetReason": "none"
            },
            {
                "token": 2,
                "ssid": "Cafe",
                "security": "open",
                "strength": 50,
                "connected": false,
                "saved": false,
                "forgettable": false,
                "connectable": true,
                "forgetReason": "none"
            },
            {
                "token": 3,
                "ssid": "Protected",
                "security": "wpa-personal",
                "strength": 70,
                "connected": false,
                "saved": false,
                "forgettable": false,
                "connectable": true,
                "forgetReason": "none"
            }
        ]
        property string wifiOperation: "idle"
        property int wifiOperationGeneration: 0
        property string wifiOperationFailure: "none"
        property string wifiOperationResult: "none"

        property bool bluetoothAvailable: true
        property bool bluetoothEnabled: true
        property bool bluetoothBusy: false
        property bool bluetoothDiscovering: false
        property bool bluetoothManagerOpen: false
        property int bluetoothControllerCount: 2
        property var bluetoothDevices: [
            {
                "token": 11,
                "name": "Fixture Headphones",
                "type": "audio",
                "signal": 90,
                "paired": true,
                "connected": true,
                "trusted": true,
                "pairable": false,
                "connectable": false,
                "disconnectable": true,
                "unpairable": true
            },
            {
                "token": 12,
                "name": "Fixture Keyboard",
                "type": "input",
                "signal": 65,
                "paired": true,
                "connected": false,
                "trusted": true,
                "pairable": false,
                "connectable": true,
                "disconnectable": false,
                "unpairable": true
            },
            {
                "token": 13,
                "name": "Fixture Phone",
                "type": "phone",
                "signal": 45,
                "paired": false,
                "connected": false,
                "trusted": false,
                "pairable": true,
                "connectable": false,
                "disconnectable": false,
                "unpairable": false
            }
        ]
        property string bluetoothOperation: "idle"
        property int bluetoothOperationGeneration: 0
        property string bluetoothOperationFailure: "none"
        property string bluetoothOperationResult: "none"
        property string bluetoothPairingPrompt: "none"
        property string bluetoothPairingValue: ""
        property int bluetoothPairingEntered: 0
        property int bluetoothPairingToken: 0
        property string nextBluetoothPairingPrompt: "enter-pin"

        function setWifiManagerOpen(open) {
            wifiManagerOpen = open;
            return true;
        }
        function requestWifiEnabled(enabled) {
            return false;
        }
        function refreshWifi() {
            lastOperation = "scan";
            return true;
        }
        function connectWifi(token, secret, remember) {
            lastOperation = "connect";
            lastToken = token;
            lastWifiSecretLength = secret.length;
            lastRemember = remember;
            return true;
        }
        function connectHiddenWifi(ssid, security, secret, remember) {
            lastOperation = "hidden-connect";
            lastToken = 0;
            lastSsidLength = ssid.length;
            lastWifiSecretLength = secret.length;
            lastRemember = remember;
            return true;
        }
        function disconnectWifi() {
            lastOperation = "disconnect";
            return true;
        }
        function forgetWifi(token) {
            lastOperation = "forget";
            lastToken = token;
            return true;
        }

        function setBluetoothManagerOpen(open) {
            bluetoothManagerOpen = open;
            if (!open) {
                bluetoothDiscovering = false;
                bluetoothOperation = "idle";
                bluetoothPairingPrompt = "none";
                bluetoothPairingValue = "";
                bluetoothPairingToken = 0;
            }
            return true;
        }
        function installPrivateBluetoothDevice(address, name) {
            if (typeof address !== "string" || typeof name !== "string" || bluetoothDevices.length
                    !== 3) {
                return false;
            }
            const devices = bluetoothDevices.slice();
            devices[2] = Object.assign({}, devices[2], {
                                           "address": address,
                                           "name": name
                                       });
            bluetoothDevices = devices;
            return true;
        }
        function clearPrivateBluetoothDevice() {
            if (bluetoothDevices.length !== 3) {
                return;
            }
            const devices = bluetoothDevices.slice();
            const cleaned = Object.assign({}, devices[2], {
                                              "name": "Fixture Phone"
                                          });
            delete cleaned.address;
            devices[2] = cleaned;
            bluetoothDevices = devices;
        }
        function requestBluetoothEnabled(enabled) {
            bluetoothEnabled = enabled;
            return true;
        }
        function scanBluetooth() {
            lastOperation = "bluetooth-scan";
            bluetoothDiscovering = true;
            bluetoothOperation = "discovering";
            bluetoothOperationGeneration += 1;
            return true;
        }
        function stopBluetoothScan() {
            bluetoothDiscovering = false;
            bluetoothOperation = "idle";
            bluetoothOperationGeneration += 1;
            return true;
        }
        function pairBluetooth(token) {
            lastOperation = "bluetooth-pair";
            lastToken = token;
            bluetoothDiscovering = false;
            bluetoothOperation = "pairing";
            bluetoothOperationGeneration += 1;
            bluetoothPairingPrompt = nextBluetoothPairingPrompt;
            nextBluetoothPairingPrompt = "enter-pin";
            bluetoothPairingToken = token;
            return true;
        }
        function respondBluetoothPairing(accepted, response) {
            lastBluetoothSecretLength = response.length;
            bluetoothPairingPrompt = "none";
            bluetoothPairingValue = "";
            bluetoothPairingToken = 0;
            bluetoothOperation = "idle";
            bluetoothOperationResult = accepted ? "paired-connected" : "cancelled";
            return true;
        }
        function cancelBluetoothPairing() {
            bluetoothOperation = "idle";
            bluetoothOperationResult = "cancelled";
            bluetoothPairingPrompt = "none";
            bluetoothPairingValue = "";
            bluetoothPairingToken = 0;
            return true;
        }
        function connectBluetooth(token) {
            lastOperation = "bluetooth-connect";
            lastToken = token;
            return true;
        }
        function disconnectBluetooth(token) {
            lastOperation = "bluetooth-disconnect";
            lastToken = token;
            return true;
        }
        function unpairBluetooth(token) {
            lastOperation = "bluetooth-unpair";
            lastToken = token;
            return true;
        }

        function clearPrivateState() {
            setWifiManagerOpen(false);
            setBluetoothManagerOpen(false);
            clearPrivateBluetoothDevice();
            lastWifiSecretLength = 0;
            lastSsidLength = 0;
            lastBluetoothSecretLength = 0;
            lastRemember = false;
            bluetoothPairingValue = "";
            bluetoothPairingEntered = 0;
            nextBluetoothPairingPrompt = "enter-pin";
        }

        function privacyState() {
            return {
                "wifiManagerOpen": wifiManagerOpen,
                "wifiNetworks": wifiNetworks,
                "lastWifiSecretLength": lastWifiSecretLength,
                "lastSsidLength": lastSsidLength,
                "bluetoothManagerOpen": bluetoothManagerOpen,
                "bluetoothDevices": bluetoothDevices,
                "lastBluetoothSecretLength": lastBluetoothSecretLength,
                "bluetoothPairingPrompt": bluetoothPairingPrompt,
                "bluetoothPairingValue": bluetoothPairingValue,
                "bluetoothPairingToken": bluetoothPairingToken
            };
        }
    }

    QtObject {
        id: fakeWallpaper

        property bool pageOpen: false
        property string status: "Multiple"
        property bool available: false
        property bool multiple: true
        property bool unsupported: true
        property var screens: [
            {
                "label": "Display 1",
                "status": "Ready",
                "supported": true
            },
            {
                "label": "Display 2",
                "status": "UnsupportedPlugin",
                "supported": false
            }
        ]
        property int libraryGeneration: 1
        property string libraryStatus: "ready"
        property bool libraryScanning: false
        property bool libraryTruncated: false
        property int libraryVisited: 3
        property var directories: [
            {
                "id": "d000000000000000000000000",
                "parentId": "",
                "rootId": "d000000000000000000000000",
                "name": "Wallpapers",
                "breadcrumb": "Wallpapers"
            },
            {
                "id": "d111111111111111111111111",
                "parentId": "d000000000000000000000000",
                "rootId": "d000000000000000000000000",
                "name": "Landscapes",
                "breadcrumb": "Wallpapers / Landscapes"
            }
        ]
        property var images: [
            {
                "id": "i000000000000000000000000",
                "directoryId": "d000000000000000000000000",
                "name": "calm-water.png",
                "byteSize": 4096,
                "modifiedMs": 1,
                "width": 1920,
                "height": 1080
            },
            {
                "id": "i111111111111111111111111",
                "directoryId": "d111111111111111111111111",
                "name": "mountains.png",
                "byteSize": 8192,
                "modifiedMs": 2,
                "width": 2560,
                "height": 1440
            }
        ]
        property int thumbnailRevision: 1
        property var preview: null
        property int previewGeneration: 0
        property string applyStatus: "idle"
        property bool applySuccess: false
        property bool applyPartial: false
        property var applyResults: []
        property var savedImages: []
        property var privateRecord: null

        function setPageOpen(open, roots) {
            pageOpen = open;
            return true;
        }
        function installPrivateRecord(path, digest) {
            if (typeof path !== "string" || typeof digest !== "string" || privateRecord !== null) {
                return false;
            }
            savedImages = images;
            privateRecord = {
                "id": "i222222222222222222222222",
                "path": path,
                "digest": digest
            };
            images = [
                        {
                            "id": privateRecord.id,
                            "directoryId": "d000000000000000000000000",
                            "name": "Imported fixture image",
                            "sourcePath": path,
                            "digest": digest,
                            "byteSize": 12288,
                            "modifiedMs": 3,
                            "width": 1920,
                            "height": 1080
                        }
                    ];
            return true;
        }
        function clearPrivateRecord() {
            privateRecord = null;
            if (savedImages.length > 0) {
                images = savedImages;
                savedImages = [];
            }
        }
        function refreshLibrary(roots) {
            libraryGeneration += 1;
            return pageOpen;
        }
        function requestThumbnail(identity) {
            return pageOpen;
        }
        function thumbnailFor(identity) {
            return "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
        }
        function previewImage(identity) {
            if (privateRecord !== null && identity === privateRecord.id && (privateRecord.path === ""
                                                                            || privateRecord.digest
                                                                            === "")) {
                return false;
            }
            preview = {
                "status": "ready",
                "id": "c000000000000000000000000",
                "name": "calm-water.png",
                "thumbnail": thumbnailFor(identity),
                "accent": "#5B6FF5",
                "width": 1920,
                "height": 1080,
                "byteSize": 4096,
                "outsideLibrary": false
            };
            previewGeneration += 1;
            return true;
        }
        function previewExternal(selectedFile) {
            return false;
        }
        function applyPreview() {
            applySuccess = true;
            applyPartial = false;
            applyResults = [
                        {
                            "label": "Display 1",
                            "status": "success"
                        },
                        {
                            "label": "Display 2",
                            "status": "success"
                        }
                    ];
            applyStatus = "success";
            return true;
        }
        function cancelPreview() {
            preview = null;
            previewGeneration += 1;
            return true;
        }

        function clearPrivateState() {
            pageOpen = false;
            cancelPreview();
            clearPrivateRecord();
            applyStatus = "idle";
            applySuccess = false;
            applyPartial = false;
            applyResults = [];
        }

        function privacyState() {
            return {
                "pageOpen": pageOpen,
                "screens": screens,
                "directories": directories,
                "images": images,
                "preview": preview,
                "privateRecord": privateRecord,
                "applyStatus": applyStatus,
                "applyResults": applyResults
            };
        }
    }

    QtObject {
        id: fakeNotifications
        property var history: [
            {
                "sender": "Fixture sender",
                "body": "Fixture body"
            }
        ]
        readonly property int historyCount: history.length

        function admit(sender, body) {
            if (typeof sender !== "string" || typeof body !== "string") {
                return false;
            }
            history = history.concat([
                                         {
                                             "sender": sender,
                                             "body": body
                                         }
                                     ]).slice(-50);
            return true;
        }
        function clearHistory() {
            history = [];
        }
        function privacyState() {
            return {
                "history": history,
                "historyCount": historyCount
            };
        }
    }

    ControlCenterWindow {
        id: controlCenter

        surfaceHost: fakeHost
        settingsModel: UserConfig
        clock: fakeClock
        media: fakeMedia
        notificationService: fakeNotifications
        weather: fakeWeather
        locationSearch: fakeLocationSearch
        wifi: fakeWifi
        wallpaper: fakeWallpaper
        reducedMotion: Theme.motion.effectiveMode === "minimal"
        capabilities: ({
                           "displayRouting": true,
                           "audio": false,
                           "media": false,
                           "gamingPerformance": true,
                           "wifi": false,
                           "bluetooth": false,
                           "notifications": false,
                           "weather": false
                       })
        onUnloadRequested: test.unloadRequestCount += 1
    }

    Component {
        id: toggleFactory
        SettingToggleRow {
            separatorVisible: false
        }
    }
    Component {
        id: sliderFactory
        SettingSliderRow {
            separatorVisible: false
        }
    }
    Component {
        id: choiceFactory
        SettingChoiceRow {
            separatorVisible: false
        }
    }
    Component {
        id: colorFactory
        SettingColorRow {
            separatorVisible: false
        }
    }
    Component {
        id: actionFactory
        SettingActionRow {
            separatorVisible: false
        }
    }
    Component {
        id: resetFactory
        SettingsResetActions {}
    }
    Component {
        id: repeatedSectionFactory

        ControlCenterSectionPanel {
            id: repeatedSectionRoot

            property var rowModel: ["One", "Two", "Three"]

            text: "Repeated rows"
            opacity: 0

            Repeater {
                id: repeatedRows
                model: repeatedSectionRoot.rowModel

                delegate: SettingActionRow {
                    required property var modelData
                    required property int index

                    objectName: "repeatedSettingRow-" + index
                    Layout.fillWidth: true
                    separatorVisible: index < repeatedRows.count - 1
                    label: String(modelData)
                    actionLabel: "Run"
                }
            }
        }
    }

    FileView {
        id: settingsFixtureWriter

        path: UserConfig.configPath
        atomicWrites: true
        blockWrites: true
        printErrors: false
        onSaved: settle.restart()
        onSaveFailed: test.fail("invalid settings fixture write failed")
    }

    FileView {
        id: diagnosticArtifactWriter
        path: test.privacyArtifactDirectory === "" ? "" : test.privacyArtifactDirectory
                                                     + "/diagnostic.txt"
        atomicWrites: true
        blockWrites: true
        printErrors: false
        onSaved: test.privacyArtifactSaved()
        onSaveFailed: test.fail("safe diagnostic artifact write failed")
    }

    FileView {
        id: snapshotArtifactWriter
        path: test.privacyArtifactDirectory === "" ? "" : test.privacyArtifactDirectory
                                                     + "/ipc-snapshot.json"
        atomicWrites: true
        blockWrites: true
        printErrors: false
        onSaved: test.privacyArtifactSaved()
        onSaveFailed: test.fail("safe IPC snapshot artifact write failed")
    }

    FileView {
        id: accessibilityArtifactWriter
        path: test.privacyArtifactDirectory === "" ? "" : test.privacyArtifactDirectory
                                                     + "/accessibility.json"
        atomicWrites: true
        blockWrites: true
        printErrors: false
        onSaved: test.privacyArtifactSaved()
        onSaveFailed: test.fail("accessibility artifact write failed")
    }

    FrameAnimation {
        id: focusReadinessBarrier

        property var readiness: null
        property var continuation: null

        running: false

        function begin(ready, next) {
            test.require(typeof ready === "function" && typeof next === "function" && !running
                         && readiness === null && continuation === null,
                         "focus-readiness barrier admits one continuation");
            readiness = ready;
            continuation = next;
            restart();
        }

        onTriggered: {
            if (!readiness()) {
                return;
            }
            stop();
            const next = continuation;
            readiness = null;
            continuation = null;
            next();
        }
    }

    FrameAnimation {
        id: renderedFrameBarrier

        property int frameCount: 0
        property bool waitForRouteIcons: false
        property var continuation: null

        running: false

        function begin(next, requireRouteIcons) {
            test.require(typeof next === "function" && !running && continuation === null,
                         "frame-synchronized render barrier admits one continuation");
            frameCount = 0;
            waitForRouteIcons = requireRouteIcons === true;
            continuation = next;
            restart();
        }

        onTriggered: {
            if (waitForRouteIcons && !test.captureRouteIconsTerminalReady()) {
                frameCount = 0;
                return;
            }
            frameCount += 1;
            if (frameCount < 2) {
                return;
            }
            stop();
            const next = continuation;
            continuation = null;
            waitForRouteIcons = false;
            frameCount = 0;
            next();
        }
    }


    Timer {
        id: settle
        interval: 80
        onTriggered: test.runStage()
    }

    Timer {
        interval: 20000
        running: true
        onTriggered: test.fail("control center test timed out")
    }

    Component.onCompleted: {
        require(captureDirectory !== "" && privacyArtifactDirectory !== "",
                "private runner exposes capture and artifact directories");
        require(Quickshell.screens.length >= 2, "two virtual screens are available");
        settle.start();
    }
}

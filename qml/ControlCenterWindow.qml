pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

FloatingWindow {
    id: root

    required property var surfaceHost
    required property var settingsModel
    required property var clock
    required property var media
    required property var notificationService
    required property var weather
    required property var locationSearch
    required property var wifi
    required property var wallpaper
    required property var capabilities
    property bool reducedMotion: false
    property string version: "0.1.0"
    property string currentPageId: "displays"
    property bool compactNavigationVisible: false
    property var pendingFreshScreen: null
    property var activeTargetScreen: null
    property bool settingsRecoveryConfirmationVisible: false
    property var settingsRecoveryReturnFocus: null
    property bool closeUnloadRequested: false
    property bool routeActivationFocusPending: false
    property string routeActivationPageId: ""
    property int routeActivationReadyFrames: 0
    signal unloadRequested

    readonly property var availableRoutes: Object.freeze([
                                                             {
                                                                 "id": "island",
                                                                 "name": qsTr("Island"),
                                                                 "icon": "controlCenterIsland"
                                                             },
                                                             {
                                                                 "id": "appearance",
                                                                 "name": qsTr("Appearance"),
                                                                 "icon": "controlCenterAppearance"
                                                             },
                                                             {
                                                                 "id": "clock-date",
                                                                 "name": qsTr("Clock & Date"),
                                                                 "icon": "controlCenterClock"
                                                             },
                                                             {
                                                                 "id": "media",
                                                                 "name": qsTr("Media"),
                                                                 "icon": "controlCenterMedia"
                                                             },
                                                             {
                                                                 "id": "weather",
                                                                 "name": qsTr("Weather"),
                                                                 "icon": "controlCenterWeather"
                                                             },
                                                             {
                                                                 "id": "notifications",
                                                                 "name": qsTr("Notifications"),
                                                                 "icon": "controlCenterNotifications"
                                                             },
                                                             {
                                                                 "id": "wifi",
                                                                 "name": qsTr("Wi-Fi"),
                                                                 "icon": "wifi"
                                                             },
                                                             {
                                                                 "id": "bluetooth",
                                                                 "name": qsTr("Bluetooth"),
                                                                 "icon": "bluetooth"
                                                             },
                                                             {
                                                                 "id": "wallpaper",
                                                                 "name": qsTr("Wallpaper"),
                                                                 "icon": "controlCenterWallpaper"
                                                             },
                                                             {
                                                                 "id": "displays",
                                                                 "name": qsTr("Displays"),
                                                                 "icon": "controlCenterDisplays"
                                                             },
                                                             {
                                                                 "id": "about",
                                                                 "name": qsTr("About"),
                                                                 "icon": "controlCenterAbout"
                                                             }
                                                         ])
    readonly property string layoutMode: width >= Theme.size.controlCenterResponsiveBreakpoint
                                         ? "sidebar" : "compact"
    readonly property bool pageLoaded: pageLoader.active && pageLoader.item !== null
    readonly property int loadedPageCount: pageLoaded ? 1 : 0
    readonly property var loadedPageItem: pageLoaded ? pageLoader.item : null
    readonly property string diagnosticText: currentPageId === "about" && pageLoader.item !== null
                                             ? pageLoader.item.diagnosticText : ""
    readonly property bool weatherLookupAllowed: currentPageId === "weather" && pageLoader.item
                                                 !== null && pageLoader.item.lookupAllowed === true
    readonly property var backingWindow: contentItem.Window.window
    readonly property bool currentPageUsesSettings: currentPageId === "island" || currentPageId
                                                    === "appearance" || currentPageId
                                                    === "clock-date" || currentPageId === "media"
                                                    || currentPageId === "weather" || currentPageId
                                                    === "notifications" || currentPageId
                                                    === "wallpaper"
    readonly property bool invalidSettingsRecoveryRequired: settingsModel.status === "recovery"
                                                            && settingsModel.recoveryKind
                                                            === "invalid"
    readonly property bool settingsUnavailable: !settingsModel.writable && (currentPageUsesSettings
                                                                            || invalidSettingsRecoveryRequired)
    readonly property string settingsUnavailableText: settingsModel.status === "loading" ? qsTr(
                                                                                               "Preparing the private settings writer…") :
                                                                                           settingsModel.errorMessage
                                                                                           !== "" ? settingsModel.errorMessage :
                                                                                                    qsTr("Settings are read-only until the private writer is available.")
    readonly property bool canResetInvalidSettings: invalidSettingsRecoveryRequired &&
                                                    !settingsModel.readOnly

    onCanResetInvalidSettingsChanged: {
        if (!canResetInvalidSettings) {
            settingsRecoveryConfirmationVisible = false;
        }
    }

    function restoreSettingsRecoveryFocus() {
        const target = settingsRecoveryReturnFocus;
        settingsRecoveryReturnFocus = null;
        if (visible && target !== null && target.visible && target.enabled) {
            Qt.callLater(() => target.forceActiveFocus(Qt.TabFocusReason));
        } else {
            Qt.callLater(focusCurrentContext);
        }
    }

    function beginSettingsRecoveryReset() {
        if (!canResetInvalidSettings) {
            return false;
        }
        settingsRecoveryReturnFocus = settingsRecoveryResetButton;
        settingsRecoveryConfirmationVisible = true;
        Qt.callLater(() => settingsRecoveryConfirmButton.forceActiveFocus(Qt.TabFocusReason));
        return true;
    }

    function cancelSettingsRecoveryReset() {
        settingsRecoveryConfirmationVisible = false;
        restoreSettingsRecoveryFocus();
    }

    function confirmSettingsRecoveryReset() {
        if (!canResetInvalidSettings || !settingsRecoveryConfirmationVisible) {
            return false;
        }
        settingsRecoveryConfirmationVisible = false;
        const accepted = settingsModel.resetAll();
        if (accepted) {
            settingsRecoveryReturnFocus = null;
            Qt.callLater(focusCurrentContext);
        } else {
            restoreSettingsRecoveryFocus();
        }
        return accepted;
    }

    title: qsTr("Nagi Control Center")
    visible: false
    color: Theme.color.surfaceOpaque
    implicitWidth: Theme.size.controlCenterPreferredWidth
    implicitHeight: Theme.size.controlCenterPreferredHeight
    minimumSize: Qt.size(Theme.size.controlCenterMinimumWidth,
                         Theme.size.controlCenterMinimumHeight)
    maximumSize: Qt.size(screen === null ? 16777215 : Math.max(Theme.size.controlCenterMinimumWidth,
                                                               screen.width - Theme.spacing.xxl),
                         screen === null ? 16777215 : Math.max(Theme.size.controlCenterMinimumHeight,
                                                               screen.height - Theme.spacing.xxl))

    function routeAvailable(routeId) {
        return routeId === "island" || routeId === "appearance" || routeId === "clock-date"
                || routeId === "media" || routeId === "weather" || routeId === "notifications"
                || routeId === "wifi" || routeId === "bluetooth" || routeId === "wallpaper"
                || routeId === "displays" || routeId === "about";
    }

    function normalizeRoute(routeId) {
        if (routeId === "" || routeId === "control-center") {
            return routeAvailable(currentPageId) ? currentPageId : "displays";
        }
        return routeAvailable(routeId) ? routeId : "displays";
    }

    function connected(candidate) {
        if (candidate === null || candidate === undefined) {
            return false;
        }
        for (let index = 0; index < Quickshell.screens.length; index += 1) {
            if (Quickshell.screens[index] === candidate) {
                return true;
            }
        }
        return false;
    }

    function routedScreen(initiatingSurfaceToken) {
        let token = initiatingSurfaceToken;
        let candidate = surfaceHost.screenForToken(token);
        if (!connected(candidate)) {
            token = surfaceHost.routeSurfaceToken(null);
            candidate = surfaceHost.screenForToken(token);
        }
        return connected(candidate) ? candidate : null;
    }

    function selectRoute(routeId) {
        if (!routeAvailable(routeId)) {
            return false;
        }
        requestRouteActivationFocus(routeId);
        currentPageId = routeId;
        compactNavigationVisible = false;
        return true;
    }

    function cancelRouteActivationFocus() {
        routeActivationFocusPending = false;
        routeActivationPageId = "";
        routeActivationReadyFrames = 0;
    }

    function requestRouteActivationFocus(routeId) {
        routeActivationPageId = routeId;
        routeActivationReadyFrames = 0;
        routeActivationFocusPending = true;
    }

    function pageContainsItem(page, item) {
        let candidate = item;
        for (let depth = 0; candidate !== null && candidate !== undefined && depth < 128; depth
             += 1) {
            if (candidate === page) {
                return true;
            }
            candidate = candidate.parent;
        }
        return false;
    }

    function pageFocusFallback(page) {
        if (page === null || page === undefined) {
            return null;
        }
        const maximumCandidates = 512;
        const candidates = [page];
        for (let index = 0; index < candidates.length && index < maximumCandidates; index += 1) {
            const candidate = candidates[index];
            if (candidate !== page && candidate.controlCenterPageFocusTarget === true) {
                return candidate;
            }
            const children = candidate.children ?? [];
            const remaining = maximumCandidates - candidates.length;
            const childCount = Math.min(children.length, remaining);
            for (let childIndex = 0; childIndex < childCount; childIndex += 1) {
                candidates.push(children[childIndex]);
            }
        }
        return null;
    }

    function loadedPageFocusTarget(page) {
        if (page === null || page === undefined) {
            return null;
        }
        const target = page.nextItemInFocusChain(true);
        if (target !== null && target !== page && pageContainsItem(page, target)) {
            return target;
        }
        return pageFocusFallback(page);
    }

    function pageFocusTargetReady(page, target) {
        let candidate = target;
        for (let depth = 0; candidate !== null && candidate !== undefined && depth < 128; depth
             += 1) {
            if (!candidate.visible || !candidate.enabled || candidate.width <= 0 || candidate.height
                    <= 0) {
                return false;
            }
            if (candidate === page) {
                return true;
            }
            candidate = candidate.parent;
        }
        return false;
    }

    function revealPageFocusTarget(page, target) {
        if (page === null || target === null || page.contentItem === undefined || page.contentY
                === undefined || page.contentHeight === undefined) {
            return false;
        }
        page.cancelFlick();
        const position = target.mapToItem(page.contentItem, 0, 0);
        if (!Number.isFinite(position.y)) {
            return false;
        }
        const inset = Theme.size.focusRingGap;
        const targetTop = position.y - inset;
        const targetBottom = position.y + target.height + inset;
        const maximumContentY = Math.max(0, page.contentHeight - page.height);
        page.contentY = Math.max(0, Math.min(maximumContentY, page.contentY));
        if (targetTop < page.contentY) {
            page.contentY = Math.max(0, Math.min(maximumContentY, targetTop));
        } else if (targetBottom > page.contentY + page.height) {
            page.contentY = Math.max(0, Math.min(maximumContentY, targetBottom - page.height));
        }
        return true;
    }

    function completeRouteActivationFocus() {
        if (!routeActivationFocusPending || routeActivationPageId !== currentPageId || !visible
                || compactNavigationVisible || !pageLoaded) {
            return false;
        }
        const page = loadedPageItem;
        const target = loadedPageFocusTarget(page);
        if (target === null) {
            routeActivationReadyFrames = 0;
            return false;
        }
        if (!pageFocusTargetReady(page, target)) {
            routeActivationReadyFrames = 0;
            return false;
        }
        target.forceActiveFocus(Qt.TabFocusReason);
        if (!target.activeFocus) {
            return false;
        }
        revealPageFocusTarget(page, target);
        cancelRouteActivationFocus();
        return true;
    }

    function currentRouteIndex() {
        for (let index = 0; index < availableRoutes.length; index += 1) {
            if (availableRoutes[index].id === currentPageId) {
                return index;
            }
        }
        return 0;
    }

    function revealRoute(viewport, route) {
        if (viewport === null || route === null || viewport.height <= 0) {
            return false;
        }
        viewport.cancelFlick();
        const position = route.mapToItem(viewport.contentItem, 0, 0);
        const routeTop = position.y;
        const routeBottom = routeTop + route.height;
        const maximumContentY = Math.max(0, viewport.contentHeight - viewport.height);
        viewport.contentY = Math.max(0, Math.min(maximumContentY, viewport.contentY));
        if (routeTop < viewport.contentY) {
            viewport.contentY = Math.max(0, Math.min(maximumContentY, routeTop));
        } else if (routeBottom > viewport.contentY + viewport.height) {
            viewport.contentY = Math.max(0, Math.min(maximumContentY, routeBottom
                                                     - viewport.height));
        }
        return true;
    }

    function revealFocusedRoute(viewport, repeater) {
        if (viewport === null || repeater === null || repeater === undefined) {
            return false;
        }
        for (let index = 0; index < availableRoutes.length; index += 1) {
            const route = repeater.itemAt(index);
            if (route !== null && route.activeFocus) {
                return revealRoute(viewport, route);
            }
        }
        const maximumContentY = Math.max(0, viewport.contentHeight - viewport.height);
        viewport.contentY = Math.max(0, Math.min(maximumContentY, viewport.contentY));
        return false;
    }

    function forceNavigationFocus(target) {
        if (target === null) {
            return false;
        }
        if (target.activeFocus && target.visualFocus !== undefined && !target.visualFocus) {
            target.focus = false;
        }
        target.forceActiveFocus(Qt.TabFocusReason);
        return target.activeFocus;
    }

    function focusCurrentContext() {
        cancelRouteActivationFocus();
        if (!visible) {
            return false;
        }
        if (layoutMode === "compact" && compactNavigationVisible) {
            return forceNavigationFocus(compactRouteRepeater.itemAt(currentRouteIndex()));
        } else if (layoutMode === "compact") {
            return forceNavigationFocus(compactBack);
        }
        return forceNavigationFocus(sidebarRouteRepeater.itemAt(currentRouteIndex()));
    }

    function raiseExisting() {
        cancelRouteActivationFocus();
        minimized = false;
        visible = true;
        if (backingWindow !== null) {
            backingWindow.raise();
            backingWindow.requestActivate();
        }
        Qt.callLater(focusCurrentContext);
    }

    function placeOnScreen(targetScreen) {
        if (!connected(targetScreen)) {
            return false;
        }
        activeTargetScreen = targetScreen;
        screen = targetScreen;
        return true;
    }

    function applyFreshScreen() {
        placeOnScreen(pendingFreshScreen);
        pendingFreshScreen = null;
    }

    function open(routeId, initiatingSurfaceToken) {
        const nextRoute = normalizeRoute(routeId);
        cancelRouteActivationFocus();
        if (visible) {
            currentPageId = nextRoute;
            compactNavigationVisible = false;
            raiseExisting();
            return true;
        }
        closeUnloadRequested = false;
        const targetScreen = routedScreen(initiatingSurfaceToken);
        if (targetScreen !== null) {
            screen = targetScreen;
        }
        activeTargetScreen = targetScreen;
        pendingFreshScreen = targetScreen;
        currentPageId = nextRoute;
        compactNavigationVisible = false;
        raiseExisting();
        Qt.callLater(applyFreshScreen);
        return true;
    }

    function requestCloseUnload() {
        cancelRouteActivationFocus();
        if (closeUnloadRequested) {
            return;
        }
        closeUnloadRequested = true;
        pendingFreshScreen = null;
        activeTargetScreen = null;
        compactNavigationVisible = false;
        unloadRequested();
    }

    function closeWindow() {
        visible = false;
        requestCloseUnload();
    }

    function rehomeAfterDisplayLoss() {
        cancelRouteActivationFocus();
        if (activeTargetScreen === null || (connected(activeTargetScreen) && connected(screen))) {
            return;
        }
        const targetScreen = routedScreen(null);
        if (targetScreen !== null) {
            placeOnScreen(targetScreen);
        }
        visible = true;
        if (backingWindow !== null) {
            backingWindow.raise();
            backingWindow.requestActivate();
        }
        Qt.callLater(focusCurrentContext);
    }
    onClosed: requestCloseUnload()
    onLayoutModeChanged: {
        cancelRouteActivationFocus();
        if (layoutMode === "sidebar") {
            compactNavigationVisible = false;
        }
        Qt.callLater(focusCurrentContext);
    }

    FrameAnimation {
        running: root.routeActivationFocusPending && root.visible

        onTriggered: {
            if (root.routeActivationPageId !== root.currentPageId
                    || root.compactNavigationVisible) {
                root.cancelRouteActivationFocus();
                return;
            }
            const page = root.loadedPageItem;
            if (page === null || pageLoader.status !== Loader.Ready || pageLoader.width <= 0
                    || pageLoader.height <= 0 || page.width <= 0 || page.height <= 0) {
                root.routeActivationReadyFrames = 0;
                return;
            }
            root.routeActivationReadyFrames += 1;
            if (root.routeActivationReadyFrames < 2) {
                return;
            }
            root.completeRouteActivationFocus();
        }
    }

    component RouteButton: AbstractButton {
        id: routeButton

        required property string routeLabel
        required property string routeIcon
        property bool selected: false
        required property int routeIndex
        required property var routeRepeater
        required property var routeViewport
        required property color iconWellSurface
        required property color hoverIconWellSurface
        required property color navigationSurface
        required property color selectedSurface
        required property color iconWellForeground
        required property color hoverIconWellForeground
        required property color navigationForeground
        required property color selectedForeground
        required property color selectedAccent
        required property color selectedIconAccent

        implicitHeight: Theme.size.controlCenterRouteHeight
        implicitWidth: implicitContentWidth + leftPadding + rightPadding
        Layout.minimumWidth: 0
        Layout.minimumHeight: Theme.size.controlCenterRouteHeight
        leftPadding: Theme.spacing.sm
        rightPadding: Theme.spacing.sm
        topPadding: (Theme.size.controlCenterRouteHeight
                     - Theme.size.controlCenterRouteIconWellSize) / 2
        bottomPadding: topPadding
        focusPolicy: Qt.StrongFocus
        hoverEnabled: true
        Accessible.role: Accessible.ListItem
        Accessible.name: routeLabel
        Accessible.description: qsTr("Open %1").arg(routeLabel)
        onActiveFocusChanged: {
            if (activeFocus) {
                routeViewport.revealItem(routeButton);
            }
        }

        function focusRouteAt(index) {
            const target = routeRepeater.itemAt(index);
            if (target === null) {
                return false;
            }
            target.forceActiveFocus(Qt.TabFocusReason);
            return true;
        }

        function focusRelativeRoute(offset) {
            const count = root.availableRoutes.length;
            if (count < 1) {
                return false;
            }
            return focusRouteAt((routeIndex + offset + count) % count);
        }

        Keys.onUpPressed: event => event.accepted = focusRelativeRoute(-1)
        Keys.onDownPressed: event => event.accepted = focusRelativeRoute(1)
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Home) {
                event.accepted = focusRouteAt(0);
            } else if (event.key === Qt.Key_End) {
                event.accepted = focusRouteAt(root.availableRoutes.length - 1);
            }
        }

        background: Rectangle {
            radius: Theme.radius.sm
            color: routeButton.selected ? routeButton.selectedSurface : routeButton.hovered
                                          ? Theme.color.surfaceHover : "transparent"

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacing.xs
                anchors.verticalCenter: parent.verticalCenter
                width: 2
                height: Theme.spacing.lg
                radius: 1
                visible: routeButton.selected
                color: routeButton.selectedAccent
            }
        }

        contentItem: RowLayout {
            spacing: Theme.spacing.sm

            Rectangle {
                objectName: "controlCenterRouteIconWell-" + routeButton.routeIndex
                Layout.minimumWidth: Theme.size.controlCenterRouteIconWellSize
                Layout.preferredWidth: Theme.size.controlCenterRouteIconWellSize
                Layout.maximumWidth: Theme.size.controlCenterRouteIconWellSize
                Layout.minimumHeight: Theme.size.controlCenterRouteIconWellSize
                Layout.preferredHeight: Theme.size.controlCenterRouteIconWellSize
                Layout.maximumHeight: Theme.size.controlCenterRouteIconWellSize
                radius: width / 2
                color: routeButton.selected ? routeButton.navigationSurface : routeButton.hovered
                                              ? routeButton.hoverIconWellSurface :
                                                routeButton.iconWellSurface

                IslandIcon {
                    objectName: "controlCenterRouteIcon-" + routeButton.routeIndex
                    anchors.centerIn: parent
                    meaning: routeButton.routeIcon
                    semanticState: routeButton.selected ? "active" : "normal"
                    tint: routeButton.selected ? routeButton.selectedIconAccent :
                                                 routeButton.hovered
                                                 ? routeButton.hoverIconWellForeground :
                                                   routeButton.iconWellForeground
                    size: "md"
                    Accessible.ignored: true
                }
            }

            IslandText {
                objectName: "controlCenterRouteLabel-" + routeButton.routeIndex
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: routeButton.routeLabel
                size: "body"
                font.weight: routeButton.selected ? Theme.type.weightSemibold :
                                                    Theme.type.weightMedium
                color: routeButton.selected ? routeButton.selectedForeground : routeButton.hovered
                                              ? Theme.snapshot.surfaceHoverForeground :
                                                routeButton.navigationForeground
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                elide: Text.ElideRight
                clip: true
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
            }
        }

        Item {
            id: routeFocusBounds

            anchors.fill: parent
            anchors.margins: Theme.size.focusRingGap
        }

        IslandFocusRing {
            anchors.fill: routeFocusBounds
            visible: routeButton.visualFocus
            controlRadius: Theme.radius.sm
        }
    }

    Connections {
        target: Quickshell

        function onScreensChanged() {
            root.rehomeAfterDisplayLoss();
        }
    }

    Rectangle {
        objectName: "controlCenterWindowContent"
        anchors.fill: parent
        color: Theme.color.surfaceOpaque

        Item {
            id: keyScope
            readonly property string nagiTypographyScope: "controlCenter"

            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: event => {
                if (root.settingsRecoveryConfirmationVisible) {
                    root.cancelSettingsRecoveryReset();
                } else if (root.layoutMode === "compact" && !root.compactNavigationVisible) {
                    root.cancelRouteActivationFocus();
                    root.compactNavigationVisible = true;
                    Qt.callLater(root.focusCurrentContext);
                } else {
                    root.closeWindow();
                }
                event.accepted = true;
            }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    objectName: "controlCenterRail"
                    Layout.preferredWidth: Theme.size.controlCenterSidebarWidth
                    Layout.minimumWidth: Theme.size.controlCenterSidebarWidth
                    Layout.maximumWidth: Theme.size.controlCenterSidebarWidth
                    Layout.fillHeight: true
                    visible: root.layoutMode === "sidebar"
                    color: Theme.color.controlCenterRailSurface
                    border.width: 0

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacing.md
                        anchors.rightMargin: Theme.spacing.md
                        anchors.topMargin: Theme.spacing.lg
                        anchors.bottomMargin: Theme.spacing.lg
                        spacing: Theme.spacing.md

                        IslandText {
                            Layout.fillWidth: true
                            text: qsTr("Nagi Control Center")
                            size: "title"
                            font.weight: Theme.type.weightSemibold
                            color: Theme.snapshot.controlCenterRailForeground
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            Accessible.role: Accessible.Heading
                            Accessible.name: text
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Theme.size.hairlineWidth
                            color: Theme.color.surfaceBorder
                        }

                        Flickable {
                            id: sidebarRouteViewport

                            objectName: "controlCenterSidebarRouteViewport"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentWidth: width
                            contentHeight: sidebarNavigation.implicitHeight
                            readonly property bool overflowing: contentHeight > height + 0.5
                            onHeightChanged: root.revealFocusedRoute(sidebarRouteViewport,
                                                                     sidebarRouteRepeater)
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            flickableDirection: Flickable.VerticalFlick
                            interactive: overflowing
                            pixelAligned: true

                            function revealItem(item) {
                                return root.revealRoute(sidebarRouteViewport, item);
                            }

                            ScrollBar.vertical: ScrollBar {
                                policy: sidebarRouteViewport.overflowing ? ScrollBar.AlwaysOn :
                                                                           ScrollBar.AlwaysOff
                            }

                            ColumnLayout {
                                id: sidebarNavigation

                                width: sidebarRouteViewport.width
                                height: implicitHeight
                                spacing: Theme.spacing.xs
                                Accessible.role: Accessible.List
                                Accessible.name: qsTr("Control Center pages")

                                Repeater {
                                    id: sidebarRouteRepeater
                                    model: root.availableRoutes

                                    delegate: RouteButton {
                                        required property var modelData
                                        required property int index

                                        routeIndex: index
                                        routeRepeater: sidebarRouteRepeater
                                        routeViewport: sidebarRouteViewport
                                        iconWellSurface: Theme.color.surfaceOpaque
                                        hoverIconWellSurface: Theme.color.surfaceOpaque
                                        navigationSurface: Theme.color.controlCenterRailSurface
                                        selectedSurface:
                                            Theme.color.controlCenterRailSelectedSurface
                                        iconWellForeground: Theme.color.textPrimary
                                        hoverIconWellForeground: Theme.color.textPrimary
                                        navigationForeground:
                                            Theme.snapshot.controlCenterRailForeground
                                        selectedForeground:
                                            Theme.snapshot.controlCenterRailSelectedForeground
                                        selectedAccent:
                                            Theme.snapshot.controlCenterRailSelectedAccent
                                        selectedIconAccent: Theme.snapshot.controlCenterRailAccent
                                        objectName: "controlCenterSidebarRoute-" + modelData.id
                                        Layout.fillWidth: true
                                        routeLabel: modelData.name
                                        routeIcon: modelData.icon
                                        selected: root.currentPageId === modelData.id
                                        onClicked: root.selectRoute(modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        width: Theme.size.hairlineWidth
                        color: Theme.color.surfaceBorder
                        opacity: 0.72
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: root.layoutMode === "sidebar" ? Theme.spacing.xl :
                                                                       Theme.spacing.lg
                    Layout.rightMargin: root.layoutMode === "sidebar" ? Theme.spacing.xl :
                                                                        Theme.spacing.lg
                    Layout.topMargin: root.layoutMode === "sidebar" ? Theme.spacing.xl :
                                                                      Theme.spacing.lg
                    Layout.bottomMargin: root.layoutMode === "sidebar" ? Theme.spacing.xl :
                                                                         Theme.spacing.lg
                    spacing: Theme.spacing.sm

                    RowLayout {
                        objectName: "controlCenterCompactBackRow"
                        Layout.fillWidth: true
                        visible: root.layoutMode === "compact" && !root.compactNavigationVisible
                        spacing: Theme.spacing.sm

                        IslandButton {
                            id: compactBack
                            objectName: "controlCenterCompactBack"

                            label: qsTr("All settings")
                            showActiveFocusRing: true
                            reducedMotion: root.reducedMotion
                            onClicked: {
                                root.cancelRouteActivationFocus();
                                root.compactNavigationVisible = true;
                                Qt.callLater(root.focusCurrentContext);
                            }
                        }
                    }

                    ColumnLayout {
                        id: compactNavigation

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.layoutMode === "compact" && root.compactNavigationVisible
                        spacing: Theme.spacing.md
                        Accessible.role: Accessible.List
                        Accessible.name: qsTr("Control Center pages")

                        IslandText {
                            Layout.fillWidth: true
                            text: qsTr("Nagi Control Center")
                            size: "title"
                            font.weight: Theme.type.weightSemibold
                            Accessible.role: Accessible.Heading
                            Accessible.name: text
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Theme.size.hairlineWidth
                            color: Theme.color.surfaceBorder
                        }

                        Flickable {
                            id: compactRouteViewport

                            objectName: "controlCenterCompactRouteViewport"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentWidth: width
                            contentHeight: compactRouteList.implicitHeight
                            readonly property bool overflowing: contentHeight > height + 0.5
                            onHeightChanged: root.revealFocusedRoute(compactRouteViewport,
                                                                     compactRouteRepeater)
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            flickableDirection: Flickable.VerticalFlick
                            interactive: overflowing
                            pixelAligned: true

                            function revealItem(item) {
                                return root.revealRoute(compactRouteViewport, item);
                            }

                            ScrollBar.vertical: ScrollBar {
                                policy: compactRouteViewport.overflowing ? ScrollBar.AlwaysOn :
                                                                           ScrollBar.AlwaysOff
                            }

                            ColumnLayout {
                                id: compactRouteList

                                width: compactRouteViewport.width
                                height: implicitHeight
                                spacing: Theme.spacing.xs

                                Repeater {
                                    id: compactRouteRepeater
                                    model: root.availableRoutes

                                    delegate: RouteButton {
                                        required property var modelData
                                        required property int index

                                        routeIndex: index
                                        routeRepeater: compactRouteRepeater
                                        routeViewport: compactRouteViewport
                                        iconWellSurface: Theme.color.controlFill
                                        hoverIconWellSurface: Theme.color.surfaceOpaque
                                        navigationSurface: Theme.color.surfaceOpaque
                                        selectedSurface: Theme.color.surfaceActive
                                        iconWellForeground: Theme.snapshot.controlFillForeground
                                        hoverIconWellForeground: Theme.color.textPrimary
                                        navigationForeground: Theme.color.textPrimary
                                        selectedForeground: Theme.snapshot.surfaceActiveForeground
                                        selectedAccent: Theme.snapshot.surfaceActiveAccent
                                        selectedIconAccent: Theme.snapshot.accent
                                        objectName: "controlCenterCompactRoute-" + modelData.id
                                        Layout.fillWidth: true
                                        routeLabel: modelData.name
                                        routeIcon: modelData.icon
                                        selected: root.currentPageId === modelData.id
                                        onClicked: root.selectRoute(modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    IslandPanel {
                        objectName: "controlCenterSettingsStatus"
                        Layout.fillWidth: true
                        visible: root.settingsUnavailable
                        implicitHeight: settingsStatusLayout.implicitHeight + Theme.spacing.md * 2
                        color: root.settingsModel.status === "loading" ? Theme.color.controlFill :
                                                                         Theme.color.dangerFill
                        border.color: root.settingsModel.status === "loading"
                                      ? Theme.color.surfaceBorder : Theme.color.danger
                        Accessible.role: Accessible.AlertMessage
                        Accessible.name: settingsStatusText.text

                        ColumnLayout {
                            id: settingsStatusLayout

                            anchors.fill: parent
                            anchors.margins: Theme.spacing.md
                            spacing: Theme.spacing.sm

                            IslandText {
                                id: settingsStatusText

                                Layout.fillWidth: true
                                text: root.settingsUnavailableText
                                size: "caption"
                                color: root.settingsModel.status === "loading"
                                       ? Theme.color.textSecondary : Theme.color.danger
                                wrapMode: Text.Wrap
                            }

                            IslandButton {
                                id: settingsRecoveryResetButton
                                objectName: "controlCenterResetDefaults"
                                Layout.alignment: Qt.AlignRight
                                visible: root.canResetInvalidSettings &&
                                         !root.settingsRecoveryConfirmationVisible
                                label: qsTr("Reset to defaults")
                                variant: "danger"
                                reducedMotion: root.reducedMotion
                                Accessible.description: qsTr(
                                                            "Request confirmation before replacing invalid settings with defaults")
                                onClicked: root.beginSettingsRecoveryReset()
                            }

                            IslandText {
                                Layout.fillWidth: true
                                visible: root.settingsRecoveryConfirmationVisible
                                text: qsTr(
                                          "Replace the invalid settings file with Nagi defaults? The rejected file will be kept as settings.conf.invalid.")
                                size: "caption"
                                color: Theme.color.danger
                                wrapMode: Text.Wrap
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                visible: root.settingsRecoveryConfirmationVisible
                                spacing: Theme.spacing.sm

                                Item {
                                    Layout.fillWidth: true
                                }

                                IslandButton {
                                    objectName: "controlCenterCancelResetDefaults"
                                    label: qsTr("Cancel")
                                    reducedMotion: root.reducedMotion
                                    onClicked: root.cancelSettingsRecoveryReset()
                                }

                                IslandButton {
                                    id: settingsRecoveryConfirmButton
                                    objectName: "controlCenterConfirmResetDefaults"
                                    label: qsTr("Confirm reset")
                                    variant: "danger"
                                    reducedMotion: root.reducedMotion
                                    onClicked: root.confirmSettingsRecoveryReset()
                                }
                            }
                        }
                    }

                    Loader {
                        id: pageLoader

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        active: root.visible && (root.layoutMode === "sidebar" ||
                                                 !root.compactNavigationVisible)
                        sourceComponent: root.currentPageId === "island" ? islandPageComponent :
                                                                           root.currentPageId
                                                                           === "appearance"
                                                                           ? appearancePageComponent :
                                                                             root.currentPageId
                                                                             === "clock-date"
                                                                             ? clockDatePageComponent :
                                                                               root.currentPageId
                                                                               === "media"
                                                                               ? mediaPageComponent :
                                                                                 root.currentPageId
                                                                                 === "weather"
                                                                                 ? weatherPageComponent :
                                                                                   root.currentPageId
                                                                                   === "notifications"
                                                                                   ? notificationsPageComponent :
                                                                                     root.currentPageId
                                                                                     === "wifi"
                                                                                     ? wifiPageComponent :
                                                                                       root.currentPageId
                                                                                       === "bluetooth"
                                                                                       ? bluetoothPageComponent :
                                                                                         root.currentPageId
                                                                                         === "wallpaper"
                                                                                         ? wallpaperPageComponent :
                                                                                           root.currentPageId
                                                                                           === "displays"
                                                                                           ? displaysPageComponent :
                                                                                             aboutPageComponent
                        onLoaded: {
                            root.routeActivationReadyFrames = 0;
                            if (!root.routeActivationFocusPending) {
                                Qt.callLater(root.focusCurrentContext);
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: islandPageComponent

        IslandPage {
            settingsModel: root.settingsModel
            gamingPerformanceAvailable: root.capabilities.gamingPerformance === true
            reducedMotion: root.reducedMotion
        }
    }

    Component {
        id: appearancePageComponent

        AppearancePage {
            settingsModel: root.settingsModel
            reducedMotion: root.reducedMotion
        }
    }
    Component {
        id: clockDatePageComponent

        ClockDatePage {
            settingsModel: root.settingsModel
            clock: root.clock
            reducedMotion: root.reducedMotion
        }
    }

    Component {
        id: mediaPageComponent

        MediaPage {
            settingsModel: root.settingsModel
            media: root.media
            reducedMotion: root.reducedMotion
        }
    }

    Component {
        id: weatherPageComponent

        WeatherPage {
            settingsModel: root.settingsModel
            weather: root.weather
            locationSearch: root.locationSearch
            reducedMotion: root.reducedMotion
        }
    }

    Component {
        id: notificationsPageComponent

        NotificationsPage {
            settingsModel: root.settingsModel
            notificationService: root.notificationService
            reducedMotion: root.reducedMotion
        }
    }

    Component {
        id: wifiPageComponent

        WifiPage {
            wifi: root.wifi
            reducedMotion: root.reducedMotion
        }
    }

    Component {
        id: bluetoothPageComponent

        BluetoothPage {
            bluetooth: root.wifi
            reducedMotion: root.reducedMotion
        }
    }

    Component {
        id: wallpaperPageComponent

        WallpaperPage {
            settingsModel: root.settingsModel
            wallpaper: root.wallpaper
            reducedMotion: root.reducedMotion
        }
    }

    Component {
        id: displaysPageComponent

        DisplaysPage {
            displayController: root.surfaceHost
            reducedMotion: root.reducedMotion
        }
    }

    Component {
        id: aboutPageComponent

        AboutPage {
            settingsModel: root.settingsModel
            capabilities: root.capabilities
            reducedMotion: root.reducedMotion
            version: root.version
        }
    }
}

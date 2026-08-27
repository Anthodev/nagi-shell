pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import QtQuick.Layouts

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
    required property var capabilities
    property bool reducedMotion: false
    property string version: "0.1.0"
    property string currentPageId: "displays"
    property bool compactNavigationVisible: false
    property var pendingFreshScreen: null
    property var activeTargetScreen: null

    readonly property var availableRoutes: Object.freeze([
                                                             {
                                                                 "id": "island",
                                                                 "name": "Island"
                                                             },
                                                             {
                                                                 "id": "appearance",
                                                                 "name": "Appearance"
                                                             },
                                                             {
                                                                 "id": "clock-date",
                                                                 "name": "Clock & Date"
                                                             },
                                                             {
                                                                 "id": "media",
                                                                 "name": "Media"
                                                             },
                                                             {
                                                                 "id": "weather",
                                                                 "name": "Weather"
                                                             },
                                                             {
                                                                 "id": "notifications",
                                                                 "name": "Notifications"
                                                             },
                                                             {
                                                                 "id": "wifi",
                                                                 "name": "Wi-Fi"
                                                             },
                                                             {
                                                                 "id": "displays",
                                                                 "name": "Displays"
                                                             },
                                                             {
                                                                 "id": "about",
                                                                 "name": "About"
                                                             }
                                                         ])
    readonly property string layoutMode: width >= Theme.size.controlCenterResponsiveBreakpoint
                                         ? "sidebar" : "compact"
    readonly property bool pageLoaded: pageLoader.active && pageLoader.item !== null
    readonly property int loadedPageCount: pageLoaded ? 1 : 0
    readonly property var loadedPageItem: pageLoaded ? pageLoader.item : null
    readonly property string activeRouteName: routeName(currentPageId)
    readonly property string diagnosticText: currentPageId === "about" && pageLoader.item !== null
                                             ? pageLoader.item.diagnosticText : ""
    readonly property bool weatherLookupAllowed: currentPageId === "weather" && pageLoader.item
                                                 !== null && pageLoader.item.lookupAllowed === true
    readonly property var backingWindow: contentItem.Window.window

    title: "Nagi Control Center"
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
                || routeId === "wifi" || routeId === "displays" || routeId === "about";
    }

    function routeName(routeId) {
        switch (routeId) {
        case "island":
            return "Island";
        case "appearance":
            return "Appearance";
        case "clock-date":
            return "Clock & Date";
        case "media":
            return "Media";
        case "weather":
            return "Weather";
        case "notifications":
            return "Notifications";
        case "wifi":
            return "Wi-Fi";
        case "bluetooth":
            return "Bluetooth";
        case "wallpaper":
            return "Wallpaper";
        case "displays":
            return "Displays";
        case "about":
            return "About";
        default:
            return "";
        }
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
        currentPageId = routeId;
        compactNavigationVisible = false;
        Qt.callLater(focusCurrentContext);
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

    function focusCurrentContext() {
        if (!visible) {
            return;
        }
        if (layoutMode === "compact" && compactNavigationVisible) {
            const compactRoute = compactRouteRepeater.itemAt(currentRouteIndex());
            if (compactRoute !== null) {
                compactRoute.forceActiveFocus(Qt.TabFocusReason);
            }
        } else if (layoutMode === "compact") {
            compactBack.forceActiveFocus(Qt.TabFocusReason);
        } else {
            const sidebarRoute = sidebarRouteRepeater.itemAt(currentRouteIndex());
            if (sidebarRoute !== null) {
                sidebarRoute.forceActiveFocus(Qt.TabFocusReason);
            }
        }
    }

    function raiseExisting() {
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
        if (visible) {
            currentPageId = nextRoute;
            compactNavigationVisible = false;
            raiseExisting();
            return true;
        }
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

    function closeWindow() {
        pendingFreshScreen = null;
        visible = false;
        activeTargetScreen = null;
        compactNavigationVisible = false;
    }

    function rehomeAfterDisplayLoss() {
        if (!visible || (connected(activeTargetScreen) && connected(screen))) {
            return;
        }
        const targetScreen = routedScreen(null);
        if (targetScreen !== null) {
            placeOnScreen(targetScreen);
        }
    }

    onClosed: closeWindow()
    onLayoutModeChanged: {
        if (layoutMode === "sidebar") {
            compactNavigationVisible = false;
        }
        Qt.callLater(focusCurrentContext);
    }

    Connections {
        target: Quickshell

        function onScreensChanged() {
            root.rehomeAfterDisplayLoss();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.color.surfaceOpaque

        Item {
            id: keyScope

            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: event => {
                if (root.layoutMode === "compact" && !root.compactNavigationVisible) {
                    root.compactNavigationVisible = true;
                    Qt.callLater(root.focusCurrentContext);
                } else {
                    root.closeWindow();
                }
                event.accepted = true;
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacing.xl
                spacing: Theme.spacing.xl

                IslandPanel {
                    Layout.preferredWidth: Theme.size.controlCenterSidebarWidth
                    Layout.fillHeight: true
                    visible: root.layoutMode === "sidebar"
                    color: Theme.color.controlFill

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacing.md
                        spacing: Theme.spacing.sm

                        IslandText {
                            Layout.fillWidth: true
                            text: "Nagi Control Center"
                            size: "title"
                            Accessible.role: Accessible.Heading
                            Accessible.name: text
                        }

                        ColumnLayout {
                            id: sidebarNavigation

                            Layout.fillWidth: true
                            spacing: Theme.spacing.xs
                            Accessible.role: Accessible.List
                            Accessible.name: "Control Center pages"

                            Repeater {
                                id: sidebarRouteRepeater
                                model: root.availableRoutes

                                delegate: IslandButton {
                                    required property var modelData

                                    Layout.fillWidth: true
                                    label: modelData.name
                                    reducedMotion: root.reducedMotion
                                    variant: root.currentPageId === modelData.id ? "accent" :
                                                                                   "standard"
                                    Accessible.role: Accessible.ListItem
                                    Accessible.description: "Open " + modelData.name
                                    onClicked: root.selectRoute(modelData.id)
                                }
                            }
                        }

                        Item {
                            Layout.fillHeight: true
                        }

                        IslandText {
                            Layout.fillWidth: true
                            text: "Only complete pages are listed."
                            size: "caption"
                            color: Theme.color.textMuted
                            wrapMode: Text.Wrap
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Theme.spacing.md

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.layoutMode === "compact" && !root.compactNavigationVisible
                        spacing: Theme.spacing.sm

                        IslandButton {
                            id: compactBack

                            label: "All settings"
                            reducedMotion: root.reducedMotion
                            Accessible.description: "Return to Control Center navigation"
                            onClicked: {
                                root.compactNavigationVisible = true;
                                Qt.callLater(root.focusCurrentContext);
                            }
                        }

                        IslandText {
                            Layout.fillWidth: true
                            text: root.activeRouteName
                            size: "title"
                            horizontalAlignment: Text.AlignRight
                            Accessible.role: Accessible.Heading
                            Accessible.name: text
                        }
                    }

                    ColumnLayout {
                        id: compactNavigation

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.layoutMode === "compact" && root.compactNavigationVisible
                        spacing: Theme.spacing.sm
                        Accessible.role: Accessible.List
                        Accessible.name: "Control Center pages"

                        IslandText {
                            Layout.fillWidth: true
                            text: "Nagi Control Center"
                            size: "title"
                            Accessible.role: Accessible.Heading
                            Accessible.name: text
                        }

                        Repeater {
                            id: compactRouteRepeater
                            model: root.availableRoutes

                            delegate: IslandButton {
                                required property var modelData

                                Layout.fillWidth: true
                                label: modelData.name
                                reducedMotion: root.reducedMotion
                                Accessible.role: Accessible.ListItem
                                Accessible.description: "Open " + modelData.name
                                onClicked: root.selectRoute(modelData.id)
                            }
                        }

                        Item {
                            Layout.fillHeight: true
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
                                                                                       === "displays"
                                                                                       ? displaysPageComponent :
                                                                                         aboutPageComponent
                        onLoaded: Qt.callLater(root.focusCurrentContext)
                    }
                }
            }
        }
    }

    Component {
        id: islandPageComponent

        IslandPage {
            settingsModel: root.settingsModel
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

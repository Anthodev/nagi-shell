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

    readonly property var availableRoutes: Object.freeze([
                                                             {
                                                                 "id": "island",
                                                                 "name": qsTr("Island")
                                                             },
                                                             {
                                                                 "id": "appearance",
                                                                 "name": qsTr("Appearance")
                                                             },
                                                             {
                                                                 "id": "clock-date",
                                                                 "name": qsTr("Clock & Date")
                                                             },
                                                             {
                                                                 "id": "media",
                                                                 "name": qsTr("Media")
                                                             },
                                                             {
                                                                 "id": "weather",
                                                                 "name": qsTr("Weather")
                                                             },
                                                             {
                                                                 "id": "notifications",
                                                                 "name": qsTr("Notifications")
                                                             },
                                                             {
                                                                 "id": "wifi",
                                                                 "name": qsTr("Wi-Fi")
                                                             },
                                                             {
                                                                 "id": "bluetooth",
                                                                 "name": qsTr("Bluetooth")
                                                             },
                                                             {
                                                                 "id": "wallpaper",
                                                                 "name": qsTr("Wallpaper")
                                                             },
                                                             {
                                                                 "id": "displays",
                                                                 "name": qsTr("Displays")
                                                             },
                                                             {
                                                                 "id": "about",
                                                                 "name": qsTr("About")
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

    function routeName(routeId) {
        switch (routeId) {
        case "island":
            return qsTr("Island");
        case "appearance":
            return qsTr("Appearance");
        case "clock-date":
            return qsTr("Clock & Date");
        case "media":
            return qsTr("Media");
        case "weather":
            return qsTr("Weather");
        case "notifications":
            return qsTr("Notifications");
        case "wifi":
            return qsTr("Wi-Fi");
        case "bluetooth":
            return qsTr("Bluetooth");
        case "wallpaper":
            return qsTr("Wallpaper");
        case "displays":
            return qsTr("Displays");
        case "about":
            return qsTr("About");
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
    onClosed: closeWindow()
    onLayoutModeChanged: {
        if (layoutMode === "sidebar") {
            compactNavigationVisible = false;
        }
        Qt.callLater(focusCurrentContext);
    }

    component RouteButton: AbstractButton {
        id: routeButton

        required property string routeLabel
        property bool selected: false
        required property int routeIndex
        required property var routeRepeater

        implicitHeight: Theme.size.controlHeightLg
        implicitWidth: implicitContentWidth + leftPadding + rightPadding
        leftPadding: Theme.spacing.lg
        rightPadding: Theme.spacing.md
        focusPolicy: Qt.StrongFocus
        hoverEnabled: true
        Accessible.role: Accessible.ListItem
        Accessible.name: routeLabel
        Accessible.description: qsTr("Open %1").arg(routeLabel)

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
            color: routeButton.selected ? Theme.color.surfaceActive : routeButton.hovered
                                          ? Theme.color.surfaceHover : "transparent"

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacing.xs
                anchors.verticalCenter: parent.verticalCenter
                width: 2
                height: Theme.spacing.lg
                radius: 1
                visible: routeButton.selected
                color: Theme.snapshot.accent
            }
        }

        contentItem: IslandText {
            text: routeButton.routeLabel
            size: "body"
            font.weight: routeButton.selected ? Theme.type.weightSemibold : Theme.type.weightMedium
            color: routeButton.selected ? Theme.snapshot.accent : Theme.color.textPrimary
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
        }

        IslandFocusRing {
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
                    root.compactNavigationVisible = true;
                    Qt.callLater(root.focusCurrentContext);
                } else {
                    root.closeWindow();
                }
                event.accepted = true;
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacing.lg
                spacing: Theme.spacing.lg

                Rectangle {
                    Layout.preferredWidth: Theme.size.controlCenterSidebarWidth
                    Layout.fillHeight: true
                    visible: root.layoutMode === "sidebar"
                    radius: Theme.radius.lg
                    color: Theme.color.surface
                    border.width: Theme.size.hairlineWidth
                    border.color: Theme.color.surfaceBorder

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacing.md
                        spacing: Theme.spacing.md

                        IslandText {
                            Layout.fillWidth: true
                            text: qsTr("Nagi Control Center")
                            size: "title"
                            font.weight: Theme.type.weightSemibold
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

                        ColumnLayout {
                            id: sidebarNavigation

                            Layout.fillWidth: true
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
                                    objectName: "controlCenterSidebarRoute-" + modelData.id
                                    Layout.fillWidth: true
                                    routeLabel: modelData.name
                                    selected: root.currentPageId === modelData.id
                                    onClicked: root.selectRoute(modelData.id)
                                }
                            }
                        }

                        Item {
                            Layout.fillHeight: true
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

                            label: qsTr("All settings")
                            reducedMotion: root.reducedMotion
                            Accessible.description: qsTr("Return to Control Center navigation")
                            onClicked: {
                                root.compactNavigationVisible = true;
                                Qt.callLater(root.focusCurrentContext);
                            }
                        }

                        IslandText {
                            Layout.fillWidth: true
                            text: root.activeRouteName
                            size: "title"
                            font.weight: Theme.type.weightSemibold
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

                        Repeater {
                            id: compactRouteRepeater
                            model: root.availableRoutes

                            delegate: RouteButton {
                                required property var modelData
                                required property int index

                                routeIndex: index
                                routeRepeater: compactRouteRepeater
                                objectName: "controlCenterCompactRoute-" + modelData.id
                                Layout.fillWidth: true
                                routeLabel: modelData.name
                                selected: root.currentPageId === modelData.id
                                onClicked: root.selectRoute(modelData.id)
                            }
                        }

                        Item {
                            Layout.fillHeight: true
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

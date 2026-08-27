pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
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
    property var controls: []
    readonly property string capturePath: Quickshell.env("NAGI_CONTROL_CENTER_CAPTURE") ?? ""
    readonly property string appearanceCapturePath: Quickshell.env(
                                                        "NAGI_APPEARANCE_CAPTURE") ?? ""
    readonly property string islandCapturePath: Quickshell.env("NAGI_ISLAND_CAPTURE") ?? ""
    property var tokenA: ({})
    property var tokenB: ({})

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

    function routeNamesExact() {
        return controlCenter.routeName("island") === "Island"
                && controlCenter.routeName("appearance") === "Appearance"
                && controlCenter.routeName("clock-date") === "Clock & Date"
                && controlCenter.routeName("media") === "Media"
                && controlCenter.routeName("weather") === "Weather"
                && controlCenter.routeName("notifications") === "Notifications"
                && controlCenter.routeName("wifi") === "Wi-Fi"
                && controlCenter.routeName("bluetooth") === "Bluetooth"
                && controlCenter.routeName("wallpaper") === "Wallpaper"
                && controlCenter.routeName("displays") === "Displays"
                && controlCenter.routeName("about") === "About";
    }

    function createControls() {
        const parent = controlCenter.contentItem;
        const toggle = toggleFactory.createObject(parent, {
                                                       "label": "Toggle test",
                                                       "value": false,
                                                       "visible": false
                                                   });
        const slider = sliderFactory.createObject(parent, {
                                                       "label": "Slider test",
                                                       "value": 0,
                                                       "from": 0,
                                                       "to": 10,
                                                       "stepSize": 1,
                                                       "visible": false
                                                   });
        const choice = choiceFactory.createObject(parent, {
                                                       "label": "Choice test",
                                                       "value": "one",
                                                       "choices": ["one", "two"],
                                                       "visible": false
                                                   });
        const color = colorFactory.createObject(parent, {
                                                     "label": "Color test",
                                                     "value": "#080D16",
                                                     "visible": false
                                                 });
        const action = actionFactory.createObject(parent, {
                                                       "label": "Action test",
                                                       "actionLabel": "Run",
                                                       "visible": false
                                                   });
        const reset = resetFactory.createObject(parent, {
                                                     "pageId": "appearance",
                                                     "visible": false
                                                 });
        require(toggle !== null && slider !== null && choice !== null && color !== null
                && action !== null && reset !== null, "all reusable setting controls instantiate");
        toggle.valueRequested.connect(value => toggleRequests += value ? 1 : 100);
        slider.valueRequested.connect((value, continuous) => sliderRequests += value === 5
                                      && continuous ? 1 : 100);
        choice.valueRequested.connect(value => choiceRequests += value === "two" ? 1 : 100);
        color.valueRequested.connect(value => colorRequests += value === "#AABBCC" ? 1 : 100);
        action.actionRequested.connect(() => actionRequests += 1);
        reset.resetPageRequested.connect(page => pageResetRequests += page === "appearance" ? 1 : 100);
        reset.resetAllRequested.connect(() => resetAllRequests += 1);
        controls = [toggle, slider, choice, color, action, reset];
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
        require(choice.request("two") && !choice.request("one") && !choice.request("missing")
                && choiceRequests === 1,
                "choice row ignores the current value and accepts only another registered value");
        require(!color.submit("/home/private") && color.submit("#aabbcc") && colorRequests === 1,
                "color row validates before dispatch");
        require(action.requestAction() && actionRequests === 1,
                "action row dispatches explicit activation");
        require(reset.requestPageReset() && pageResetRequests === 1,
                "page reset carries the fixed page identifier");
        require(!reset.confirmResetAll() && reset.beginResetAll()
                && reset.resetAllConfirmationVisible && reset.confirmResetAll()
                && resetAllRequests === 1 && !reset.resetAllConfirmationVisible,
                "reset all requires explicit confirmation");
        toggle.writable = false;
        require(!toggle.requestToggle() && toggleRequests === 1,
                "disabled setting rows reject writes");
    }

    function initialStage() {
        require(!controlCenter.visible && controlCenter.loadedPageCount === 0,
                "closed singleton retains no loaded page");
        require(controlCenter.minimumSize.width === Theme.size.controlCenterMinimumWidth
                && controlCenter.minimumSize.height === Theme.size.controlCenterMinimumHeight
                && controlCenter.title === "Nagi Control Center"
                && controlCenter.parentWindow === null,
                "normal independent window exposes tested semantic minimum bounds");
        require(routeNamesExact() && controlCenter.availableRoutes.length === 8
                && controlCenter.availableRoutes[0].id === "island"
                && controlCenter.availableRoutes[1].id === "appearance"
                && controlCenter.availableRoutes[2].id === "clock-date"
                && controlCenter.availableRoutes[3].id === "media"
                && controlCenter.availableRoutes[4].id === "weather"
                && controlCenter.availableRoutes[5].id === "notifications"
                && controlCenter.availableRoutes[6].id === "displays"
                && controlCenter.availableRoutes[7].id === "about",
                "final route names stay fixed and all complete pages are exposed");
        createControls();
        exerciseControls();
        require(controlCenter.open("appearance", tokenA), "initiating island opens Appearance");
        stage = "opened-a";
        settle.restart();
    }

    function openedAStage() {
        require(controlCenter.visible && controlCenter.currentPageId === "appearance"
                && controlCenter.loadedPageCount === 1 && controlCenter.loadedPageItem !== null
                && controlCenter.screen === Quickshell.screens[0],
                "fresh deep link places the complete Appearance page on the initiating screen");
        controlCenter.contentItem.children[0].grabToImage(function (result) {
            require(test.appearanceCapturePath !== ""
                    && result.saveToFile(test.appearanceCapturePath),
                    "real Control Center Appearance capture is saved");
            const originalScreen = controlCenter.screen;
            require(controlCenter.open("island", tokenB) && controlCenter.screen === originalScreen
                    && controlCenter.currentPageId === "island",
                    "repeated activation deep-links to Island without moving the open singleton");
            test.stage = "island";
            settle.restart();
        });
    }

    function islandStage() {
        require(controlCenter.currentPageId === "island" && controlCenter.loadedPageItem !== null,
                "complete Island page loads in the shared page viewport");
        controlCenter.contentItem.children[0].grabToImage(function (result) {
            require(test.islandCapturePath !== "" && result.saveToFile(test.islandCapturePath),
                    "real Control Center Island capture is saved");
            require(controlCenter.open("clock-date", tokenB)
                    && controlCenter.currentPageId === "clock-date",
                    "Clock & Date joins the shared responsive page viewport");
            test.stage = "clock";
            settle.restart();
        });
    }
    function clockStage() {
        require(controlCenter.loadedPageItem !== null && fakeClock.text !== ""
                && fakeClock.dateText !== "",
                "Clock & Date uses the shared clock preview");
        require(controlCenter.open("media", tokenB) && controlCenter.currentPageId === "media",
                "Media joins the shared responsive page viewport");
        stage = "media";
        settle.restart();
    }

    function mediaStage() {
        require(controlCenter.loadedPageItem !== null && fakeMedia.availableApplications.length === 1,
                "Media receives the normalized shared application policy source");
        require(controlCenter.open("weather", tokenB)
                && controlCenter.currentPageId === "weather",
                "Weather joins the shared responsive page viewport");
        stage = "weather";
        settle.restart();
    }

    function weatherStage() {
        const page = controlCenter.loadedPageItem;
        require(page !== null && !controlCenter.weatherLookupAllowed,
                "Weather preview loads without enabling location lookup");
        page.privacyAccepted = true;
        require(controlCenter.weatherLookupAllowed && fakeLocationSearch.search("Paris"),
                "privacy acceptance gates explicit location search");
        require(page.confirm(fakeLocationSearch.results[0])
                && UserConfig.snapshot.weather.enabled
                && UserConfig.snapshot.weather.locationLabel === "Paris, France",
                "confirmed normalized location atomically enables Weather");
        require(fakeLocationSearch.results.length === 0,
                "confirmation clears page-owned lookup models and query state");
        require(controlCenter.open("notifications", tokenB)
                && controlCenter.currentPageId === "notifications",
                "Notifications joins the shared responsive page viewport");
        stage = "notifications";
        settle.restart();
    }

    function notificationsStage() {
        require(controlCenter.loadedPageItem !== null && fakeNotifications.historyCount === 1,
                "Notifications receives the shared memory-history service");
        fakeNotifications.clearHistory();
        require(fakeNotifications.historyCount === 0,
                "Clear history stays inside the existing service boundary");
        require(controlCenter.open("displays", tokenB)
                && controlCenter.currentPageId === "displays",
                "all complete pages share the same singleton");
        controlCenter.closeWindow();
        stage = "closed";
        settle.restart();
    }


    function closedStage() {
        require(!controlCenter.visible && controlCenter.loadedPageCount === 0
                && controlCenter.currentPageId === "displays",
                "close unloads page content but retains the last valid page id");
        controlCenter.open("control-center", tokenB);
        stage = "reopened";
        settle.restart();
    }

    function reopenedStage() {
        require(controlCenter.currentPageId === "displays"
                && controlCenter.activeTargetScreen === Quickshell.screens[1],
                "reopen restores the valid page and routes the fresh open to its new initiator");
        const displaysPage = controlCenter.pageLoaded ? controlCenter.contentItem : null;
        require(displaysPage !== null, "delivered Displays page loads inside the singleton");
        fakeHost.rejectChanges = true;
        require(controlCenter.selectRoute("about") && controlCenter.visible,
                "one page failure cannot block unrelated navigation or island operation");
        stage = "about";
        settle.restart();
    }

    function aboutStage() {
        require(controlCenter.pageLoaded,
                "About page remains available with unavailable services");
        const diagnostic = controlCenter.diagnosticText;
        require(diagnostic.indexOf("Nagi Shell 0.1.0") === 0
                && diagnostic.indexOf("Settings schema: 2") !== -1
                && diagnostic.indexOf("Wi-Fi: unavailable") !== -1,
                "About diagnostic exposes exact allowlisted component states");
        const forbidden = ["SensitiveSSID", "/home/test", "secret-value", "12345", "executable"];
        for (let index = 0; index < forbidden.length; index += 1) {
            require(diagnostic.indexOf(forbidden[index]) === -1,
                    "diagnostic excludes forbidden identity and content data");
        }
        controlCenter.contentItem.children[0].grabToImage(function (result) {
            require(test.capturePath !== "" && result.saveToFile(test.capturePath),
                    "real Control Center About capture is saved");
            controlCenter.closeWindow();
            controlCenter.implicitWidth = Theme.size.controlCenterMinimumWidth;
            controlCenter.open("about", tokenA);
            stage = "compact";
            settle.restart();
        });
    }

    function compactStage() {
        require(controlCenter.layoutMode === "compact",
                "below the breakpoint uses compact replacement navigation");
        controlCenter.compactNavigationVisible = true;
        require(controlCenter.loadedPageCount === 0,
                "compact navigation replaces and unloads page content");
        controlCenter.closeWindow();
        controlCenter.implicitWidth = Theme.size.controlCenterPreferredWidth;
        controlCenter.open("about", tokenA);
        stage = "wide";
        settle.restart();
    }

    function wideStage() {
        require(controlCenter.layoutMode === "sidebar" && controlCenter.loadedPageCount === 1,
                "above the breakpoint uses persistent sidebar plus content");
        controlCenter.screen = null;
        controlCenter.rehomeAfterDisplayLoss();
        require(controlCenter.screen === Quickshell.screens[0],
                "invalid Qt screen rehomes through pointer or fallback routing");
        controlCenter.closeWindow();
        controlCenter.open("removed-page", null);
        stage = "fallback";
        settle.restart();
    }

    function fallbackStage() {
        require(controlCenter.currentPageId === "displays"
                && controlCenter.screen === Quickshell.screens[0],
                "missing routes fall back deterministically through pointer routing");
        controlCenter.closeWindow();
        for (let index = 0; index < controls.length; index += 1) {
            controls[index].destroy();
        }
        console.log("control center tests passed");
        Qt.exit(0);
    }

    function runStage() {
        switch (stage) {
        case "initial":
            initialStage();
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
        case "notifications":
            notificationsStage();
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
        case "compact":
            compactStage();
            break;
        case "wide":
            wideStage();
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
        property var availableApplications: [{"label": "Fixture Player", "value": "fixture"}]
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
        function search(query) {
            if (query !== "Paris")
                return false;
            results = [{
                           "label": "Paris, France",
                           "latitude": 48.8534,
                           "longitude": 2.3488
                       }];
            return true;
        }
        function clear() {
            results = [];
            failure = "none";
        }
    }

    QtObject {
        id: fakeNotifications
        property int historyCount: 1
        function clearHistory() {
            historyCount = 0;
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
        capabilities: ({
                           "displayRouting": true,
                           "audio": false,
                           "media": false,
                           "wifi": false,
                           "bluetooth": false,
                           "notifications": false,
                           "weather": false,
                           "ssid": "SensitiveSSID",
                           "path": "/home/test",
                           "secret": "secret-value",
                           "pid": 12345,
                           "executable": "qs"
                       })
    }

    Component {
        id: toggleFactory
        SettingToggleRow {}
    }
    Component {
        id: sliderFactory
        SettingSliderRow {}
    }
    Component {
        id: choiceFactory
        SettingChoiceRow {}
    }
    Component {
        id: colorFactory
        SettingColorRow {}
    }
    Component {
        id: actionFactory
        SettingActionRow {}
    }
    Component {
        id: resetFactory
        SettingsResetActions {}
    }

    Timer {
        id: settle
        interval: 80
        onTriggered: test.runStage()
    }

    Timer {
        interval: 10000
        running: true
        onTriggered: test.fail("control center test timed out")
    }

    Component.onCompleted: {
        require(Quickshell.screens.length >= 2, "two virtual screens are available");
        settle.start();
    }
}

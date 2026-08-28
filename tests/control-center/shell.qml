pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
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
    readonly property string captureDirectory: Quickshell.env("NAGI_CONTROL_CENTER_CAPTURE_DIR")
                                               ?? ""
    property var tokenA: ({})
    property var tokenB: ({})

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

    function captureCurrent(name, continuation) {
        if (captureDirectory === "") {
            continuation();
            return;
        }
        const windowContent = controlCenter.contentItem.children[0];
        require(windowContent !== null && windowContent !== undefined,
                "Control Center capture target is available");
        windowContent.grabToImage(function (result) {
            const path = test.captureDirectory + "/" + name + ".png";
            require(result.saveToFile(path), "real Control Center " + name + " capture is saved");
            continuation();
        });
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

    function requireSectionHierarchy(page, sections, context) {
        let previousY = -1;
        for (let index = 0; index < sections.length; index += 1) {
            const specification = sections[index];
            const section = findObject(page, specification.name);
            require(section !== null && section.text !== "" && section.width > 0
                    && section.implicitHeight > 0, context + " exposes " + specification.name);
            require(section.separated === specification.separated
                    && section.topSeparation === (specification.separated ? Theme.spacing.lg : 0),
                    context + " uses the shared subsection spacing contract");
            const position = section.mapToItem(page.contentItem, 0, 0);
            require(position.y > previousY, context + " keeps subsection headings in document order");
            previousY = position.y;
        }
    }

    function routeNamesExact() {
        return controlCenter.routeName("island") === "Island" && controlCenter.routeName(
                    "appearance") === "Appearance" && controlCenter.routeName("clock-date")
                === "Clock & Date" && controlCenter.routeName("media") === "Media"
                && controlCenter.routeName("weather") === "Weather" && controlCenter.routeName(
                    "notifications") === "Notifications" && controlCenter.routeName("wifi")
                === "Wi-Fi" && controlCenter.routeName("bluetooth") === "Bluetooth"
                && controlCenter.routeName("wallpaper") === "Wallpaper" && controlCenter.routeName(
                    "displays") === "Displays" && controlCenter.routeName("about") === "About";
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
        require(toggle !== null && slider !== null && choice !== null && color !== null && action
                !== null && reset !== null, "all reusable setting controls instantiate");
        toggle.valueRequested.connect(value => toggleRequests += value ? 1 : 100);
        slider.valueRequested.connect((value, continuous) => sliderRequests += value === 5 && continuous
                                                             ? 1 : 100);
        choice.valueRequested.connect(value => choiceRequests += value === "two" ? 1 : 100);
        color.valueRequested.connect(value => colorRequests += value === "#AABBCC" ? 1 : 100);
        action.actionRequested.connect(() => actionRequests += 1);
        reset.resetPageRequested.connect(page => pageResetRequests += page === "appearance" ? 1 :
                                                                                              100);
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
                === Theme.color.textPrimary && Theme.opacity.disabled >= 0.6,
                "disabled controls reject writes while their labels remain readable");
    }

    function initialStage() {
        require(!controlCenter.visible && controlCenter.loadedPageCount === 0,
                "closed singleton retains no loaded page");
        require(controlCenter.minimumSize.width === Theme.size.controlCenterMinimumWidth
                && controlCenter.minimumSize.height === Theme.size.controlCenterMinimumHeight
                && controlCenter.title === "Nagi Control Center" && controlCenter.parentWindow
                === null, "normal independent window exposes tested semantic minimum bounds");
        require(routeNamesExact() && controlCenter.availableRoutes.length === 11
                && controlCenter.availableRoutes[0].id === "island"
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
        const appearanceTitle = findObject(appearancePage, "appearancePageTitle");
        require(appearanceTitle !== null && appearanceTitle.typographyScope === "controlCenter"
                && appearanceTitle.font.family === targetFamilies[2]
                && appearanceTitle.font.pixelSize === Theme.type.sizeFor("controlCenter", "title"),
                "loaded Control Center text resolves the Control Center typography scope");
        requireSectionHierarchy(appearancePage, [{
                                                     "name": "appearanceIdleFontFamilySection",
                                                     "separated": false
                                                 }, {
                                                     "name": "appearanceExpandedFontFamilySection",
                                                     "separated": true
                                                 }, {
                                                     "name": "appearanceControlCenterFontFamilySection",
                                                     "separated": true
                                                 }, {
                                                     "name": "appearanceColorSection",
                                                     "separated": true
                                                 }, {
                                                     "name": "appearanceSurfaceMotionSection",
                                                     "separated": true
                                                 }], "Appearance");
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
        requireSectionHierarchy(controlCenter.loadedPageItem, [{
                                                                  "name": "islandGeometrySection",
                                                                  "separated": false
                                                              }, {
                                                                  "name": "islandFeedbackSection",
                                                                  "separated": true
                                                              }, {
                                                                  "name": "islandCompactContentSection",
                                                                  "separated": true
                                                              }], "Island");
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
        requireSectionHierarchy(controlCenter.loadedPageItem, [{
                                                                  "name": "clockPresentationSection",
                                                                  "separated": true
                                                              }], "Clock & Date");
        captureCurrent("sidebar-clock-date", function () {
            require(controlCenter.open("media", tokenB) && controlCenter.currentPageId === "media",
                    "Media joins the shared responsive page viewport");
            test.stage = "media";
            settle.restart();
        });
    }

    function mediaStage() {
        require(controlCenter.loadedPageItem !== null && fakeMedia.availableApplications.length
                === 1, "Media receives the normalized shared application policy source");
        requireSectionHierarchy(controlCenter.loadedPageItem, [{
                                                                  "name": "mediaVisibilitySection",
                                                                  "separated": false
                                                              }, {
                                                                  "name": "mediaPlayerSelectionSection",
                                                                  "separated": true
                                                              }], "Media");
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
        page.privacyAccepted = true;
        require(controlCenter.weatherLookupAllowed && fakeLocationSearch.search("Paris"),
                "privacy acceptance gates explicit location search");
        require(page.confirm(fakeLocationSearch.results[0]) && UserConfig.snapshot.weather.enabled
                && UserConfig.snapshot.weather.locationLabel === "Paris, France",
                "confirmed normalized location atomically enables Weather");
        require(fakeLocationSearch.results.length === 0,
                "confirmation clears page-owned lookup models and query state");
        requireSectionHierarchy(page, [{
                                           "name": "weatherLocationSection",
                                           "separated": true
                                       }, {
                                           "name": "weatherForecastPreferencesSection",
                                           "separated": true
                                       }], "Weather");
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
        fakeNotifications.clearHistory();
        require(fakeNotifications.historyCount === 0,
                "Clear history stays inside the existing service boundary");
        requireSectionHierarchy(controlCenter.loadedPageItem, [{
                                                                  "name": "notificationsPopupPolicySection",
                                                                  "separated": false
                                                              }, {
                                                                  "name": "notificationsFeedbackSection",
                                                                  "separated": true
                                                              }, {
                                                                  "name": "notificationsIslandContentSection",
                                                                  "separated": true
                                                              }, {
                                                                  "name": "notificationsHistorySection",
                                                                  "separated": true
                                                              }], "Notifications");
        captureCurrent("sidebar-notifications", function () {
            require(controlCenter.open("wifi", tokenB) && controlCenter.currentPageId === "wifi",
                    "Wi-Fi joins the shared responsive page viewport");
            test.stage = "wifi";
            settle.restart();
        });
    }

    function wifiStage() {
        const page = controlCenter.loadedPageItem;
        require(page !== null && fakeWifi.wifiManagerOpen && fakeWifi.wifiNetworks.length === 3,
                "Wi-Fi receives the one shared NetworkManager projection and opens scan interest");

        require(page.openNetwork(fakeWifi.wifiNetworks[2]) && page.mode === "password",
                "protected visible network opens the dedicated password flow");
        const passwordInput = findObject(page, "wifiPasswordInput");
        require(passwordInput !== null,
                "protected input mounts one explicit accessibility boundary");
        require(passwordInput.echoMode === TextInput.NoEcho
                && passwordInput.Accessible.passwordEdit,
                "protected input starts hidden with the password-edit semantic");
        const passwordBoundary = passwordInput.parent.parent;
        require(passwordBoundary.semanticName === "Wi-Fi password",
                "protected input exposes a purpose-only accessible name");
        passwordInput.text = "fixture-password";
        require(passwordBoundary.semanticName.indexOf(passwordInput.text) === -1
                && passwordBoundary.semanticDescription.indexOf(passwordInput.text) === -1,
                "Wi-Fi secret bytes never enter accessibility metadata");
        page.rememberConnection = true;
        require(page.submitVisibleNetwork() && passwordInput.text === "" && fakeWifi.lastOperation
                === "connect" && fakeWifi.lastToken === 3 && fakeWifi.lastSecretLength === 16
                && fakeWifi.lastRemember,
                "visible password submits once, delegates Remember, and clears immediately");

        page.clearPrivateState();
        page.mode = "hidden";
        const hiddenSsid = findObject(page, "wifiHiddenSsid");
        const hiddenPassword = findObject(page, "wifiHiddenPasswordInput");
        hiddenSsid.text = "Hidden Fixture";
        hiddenPassword.text = "hidden-password";
        require(page.submitHiddenNetwork() && hiddenSsid.text === "" && hiddenPassword.text === ""
                && fakeWifi.lastOperation === "hidden-connect" && fakeWifi.lastSecretLength === 15,
                "hidden WPA Personal submits bounded arguments and clears SSID and secret");

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
        require(page !== null && !fakeWifi.wifiManagerOpen && fakeWifi.bluetoothManagerOpen
                && fakeWifi.bluetoothDevices.length === 3,
                "Bluetooth shares the connectivity owner and suspends Wi-Fi page interest");
        require(fakeWifi.scanBluetooth() && fakeWifi.bluetoothDiscovering,
                "Scan starts only from an explicit manager action");
        require(fakeWifi.pairBluetooth(13) && fakeWifi.bluetoothOperation === "pairing"
                && fakeWifi.bluetoothPairingPrompt === "enter-pin",
                "pairing replaces discovery and opens the owning prompt");
        const pairingPanel = findObject(page, "bluetoothPairingPanel");
        const pairingInput = findObject(page, "bluetoothPairingInput");
        const pairingBoundary = pairingInput === null ? null : pairingInput.parent.parent;
        require(pairingPanel !== null && pairingInput !== null
                && pairingInput.Accessible.passwordEdit && pairingBoundary !== null
                && pairingBoundary.semanticName === "Bluetooth PIN",
                "Bluetooth pairing mounts one redacted password-edit boundary");
        pairingPanel.focusInput();
        require(pairingInput.echoMode === TextInput.NoEcho && pairingInput.activeFocus &&
                !pairingBoundary.clipboardEnabled,
                "Bluetooth PIN starts hidden, receives focus, and blocks clipboard export");
        pairingInput.text = "1234";
        require(pairingBoundary.semanticName.indexOf(pairingInput.text) === -1
                && pairingBoundary.semanticDescription.indexOf(pairingInput.text) === -1,
                "Bluetooth pairing codes never enter accessibility metadata");
        require(pairingPanel.submitInput() && pairingInput.text === "" && fakeWifi.lastSecretLength
                === 4 && fakeWifi.bluetoothOperationResult === "paired-connected",
                "PIN submits once as an argument, clears immediately, and completes pairing");
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

    function wallpaperStage() {
        const page = controlCenter.loadedPageItem;
        require(page !== null && fakeWallpaper.pageOpen && page.currentDirectory().breadcrumb
                === "Wallpapers" && page.childDirectories().length === 1 && page.filteredImages(
                    ).length === 1,
                "Wallpaper opens lazy interest with bounded breadcrumb navigation and filtering");
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
        captureCurrent("sidebar-wallpaper", function () {
            require(controlCenter.open("displays", tokenB) && controlCenter.currentPageId
                    === "displays", "leaving Wallpaper loads Displays through the same singleton");
            test.stage = "displays-after-wallpaper";
            settle.restart();
        });
    }

    function displaysAfterWallpaperStage() {
        require(!fakeWifi.bluetoothManagerOpen && !fakeWallpaper.pageOpen,
                "leaving managed pages stops Bluetooth and wallpaper page interest");
        const displaysPage = controlCenter.loadedPageItem;
        require(displaysPage !== null && displaysPage.contentHeight < displaysPage.height,
                "tall tiled windows keep display rows packed at the top");
        requireSectionHierarchy(displaysPage, [{
                                                  "name": "displaysActiveSection",
                                                  "separated": false
                                              }, {
                                                  "name": "displaysRememberedSection",
                                                  "separated": true
                                              }], "Displays");
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
        settle.restart();
    }

    function reopenedStage() {
        require(controlCenter.currentPageId === "displays" && controlCenter.activeTargetScreen
                === Quickshell.screens[1],
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
        const aboutRoute = findObject(controlCenter.contentItem, "controlCenterSidebarRoute-about");
        const displaysRoute = findObject(controlCenter.contentItem,
                                         "controlCenterSidebarRoute-displays");
        const islandRoute = findObject(controlCenter.contentItem, "controlCenterSidebarRoute-island");
        require(aboutRoute !== null && displaysRoute !== null && islandRoute !== null
                && aboutRoute.activeFocus && aboutRoute.Accessible.name === "About"
                && aboutRoute.Accessible.description === "Open About",
                "deep links focus the active sidebar route with stable accessibility metadata");
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
        const diagnostic = controlCenter.diagnosticText;
        require(diagnostic.indexOf("Nagi Shell 0.1.0") === 0 && diagnostic.indexOf(
                    "Settings schema: 3") !== -1 && diagnostic.indexOf("Wi-Fi: unavailable") !== -1,
                "About diagnostic exposes exact allowlisted component states");
        const forbidden = ["SensitiveSSID", "/home/test", "secret-value", "12345", "executable"];
        for (let index = 0; index < forbidden.length; index += 1) {
            require(diagnostic.indexOf(forbidden[index]) === -1,
                    "diagnostic excludes forbidden identity and content data");
        }
        captureCurrent("sidebar-about", function () {
            controlCenter.closeWindow();
            controlCenter.implicitWidth = Theme.size.controlCenterMinimumWidth;
            controlCenter.open("about", tokenA);
            test.stage = "compact";
            settle.restart();
        });
    }

    function compactStage() {
        require(controlCenter.layoutMode === "compact",
                "below the breakpoint uses compact replacement navigation");
        controlCenter.compactNavigationVisible = true;
        controlCenter.focusCurrentContext();
        const compactAboutRoute = findObject(controlCenter.contentItem,
                                             "controlCenterCompactRoute-about");
        require(controlCenter.loadedPageCount === 0 && compactAboutRoute !== null
                && compactAboutRoute.activeFocus,
                "compact navigation replaces unloaded page content and focuses the active route");
        captureCurrent("compact-navigation", function () {
            controlCenter.closeWindow();
            controlCenter.implicitWidth = Theme.size.controlCenterPreferredWidth;
            controlCenter.open("about", tokenA);
            test.stage = "wide";
            settle.restart();
        });
    }

    function wideStage() {
        require(controlCenter.layoutMode === "sidebar" && controlCenter.loadedPageCount === 1,
                "above the breakpoint uses persistent sidebar plus content");
        captureCurrent("sidebar-responsive", function () {
            require(UserConfig.snapshot.weather.enabled && controlCenter.currentPageId === "about",
                    "recovery starts from non-default settings on an unrelated page");
            test.stage = "settings-invalid";
            settingsFixtureWriter.setText("[broken\npartial=true\n");
        });
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
                    require(UserConfig.recoveryRequired
                            && !controlCenter.settingsRecoveryConfirmationVisible
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
        const activeRoute = findObject(controlCenter.contentItem,
                                       routePrefix + controlCenter.currentPageId);
        require(activeRoute !== null && activeRoute.visible && activeRoute.activeFocus,
                "display loss restores one visible valid Control Center focus target");
        controlCenter.closeWindow();
        controlCenter.open("removed-page", null);
        stage = "fallback";
        settle.restart();
    }

    function fallbackStage() {
        require(controlCenter.currentPageId === "displays" && controlCenter.screen
                === Quickshell.screens[0],
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
        case "compact":
            compactStage();
            break;
        case "wide":
            wideStage();
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
        property var availableApplications: [
            {
                "label": "Fixture Player",
                "value": "fixture"
            }
        ]
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
            results = [
                        {
                            "label": "Paris, France",
                            "latitude": 48.8534,
                            "longitude": 2.3488
                        }
                    ];
            return true;
        }
        function clear() {
            results = [];
            failure = "none";
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
        property int lastSecretLength: 0
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
            lastSecretLength = secret.length;
            lastRemember = remember;
            return true;
        }
        function connectHiddenWifi(ssid, security, secret, remember) {
            lastOperation = "hidden-connect";
            lastToken = 0;
            lastSecretLength = secret.length;
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
            bluetoothPairingPrompt = "enter-pin";
            bluetoothPairingToken = token;
            return true;
        }
        function respondBluetoothPairing(accepted, response) {
            lastSecretLength = response.length;
            bluetoothPairingPrompt = "none";
            bluetoothPairingToken = 0;
            bluetoothOperation = "idle";
            bluetoothOperationResult = accepted ? "paired-connected" : "cancelled";
            return true;
        }
        function cancelBluetoothPairing() {
            bluetoothOperation = "idle";
            bluetoothOperationResult = "cancelled";
            bluetoothPairingPrompt = "none";
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

        function setPageOpen(open, roots) {
            pageOpen = open;
            return true;
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
        wifi: fakeWifi
        wallpaper: fakeWallpaper
        capabilities: ({
                           "displayRouting": true,
                           "audio": false,
                           "media": false,
                           "gamingPerformance": true,
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

    FileView {
        id: settingsFixtureWriter

        path: UserConfig.configPath
        atomicWrites: true
        blockWrites: true
        printErrors: false
        onSaved: settle.restart()
        onSaveFailed: test.fail("invalid settings fixture write failed")
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

import Quickshell
import QtQuick
import QtQuick.Window
import "qml"

ShellRoot {
    id: test

    property bool launchTracked: false
    property int pinCalls: 0
    property int moveCalls: 0
    property int shortcutOpenCalls: 0
    property int settingsOpenCalls: 0

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            return false;
        }
        return true;
    }
    function shortcutState(available, launcherShortcut, launcherConflict) {
        const names = ["openDashboard", "openLauncher", "openTray", "openHistory", "openAudio",
                       "openSession", "openSystemSettings"];
        const actions = {};
        for (let index = 0; index < names.length; index += 1) {
            const launcherAction = names[index] === "openLauncher";
            actions[names[index]] = {
                "activeShortcut": launcherAction ? launcherShortcut : null,
                "preferredShortcut": launcherAction ? "Meta+Space" : null,
                "preferredConflict": launcherAction ? launcherConflict : false
            };
        }
        return JSON.stringify({
                                  "type": "state",
                                  "available": available,
                                  "actions": actions
                              });
    }

    function findObjects(item, objectName, matches) {
        if (item === null || item === undefined) {
            return;
        }
        if (item.objectName === objectName) {
            matches.push(item);
        }
        const children = item.children ?? [];
        for (let index = 0; index < children.length; ++index) {
            findObjects(children[index], objectName, matches);
        }
    }
    function directChild(item, objectName) {
        const children = item === null || item === undefined ? [] : item.children ?? [];
        for (let index = 0; index < children.length; ++index) {
            if (children[index].objectName === objectName) {
                return children[index];
            }
        }
        return null;
    }
    function requireResultLayout(count) {
        const visibleCount = Math.min(count, launcher.maximumVisibleResults);
        const expectedHeight = count === 0 ? Theme.size.controlHeightMd : visibleCount
                                             * launcher.resultRowExtent + Math.max(0, visibleCount
                                                                                   - 1) * launcher.resultRowSpacing;
        return require(launcher.resultCount === count,
                       "launcher did not render the requested result count " + count) && require(
                    launcher.resultViewportHeight === expectedHeight,
                    "launcher viewport height was not exact for " + count + " results") && require(
                    launcher.resultScrollVisible === (count > launcher.maximumVisibleResults),
                    "launcher scrollbar threshold was wrong for " + count + " results") && require(
                    launcher.resultScrollBarActive === (count > launcher.maximumVisibleResults),
                    "launcher scrollbar policy was wrong for " + count + " results");
    }

    QtObject {
        id: coordinator

        function openLauncher(origin) {
            test.shortcutOpenCalls += 1;
            return true;
        }
    }

    GlobalShortcutAdapter {
        id: shortcut

        coordinator: coordinator
        helperPath: ""
        onControlCenterRequested: test.settingsOpenCalls += 1
    }

    QtObject {
        id: fakeModel

        property bool initialized: true
        property bool available: true
        property bool pinMutationPending: false
        property string pinFailure: "none"
        property var pinIds: ["pin-two.desktop", "pin-one.desktop"]
        property var recencyIds: ["recent-one.desktop", "pin-one.desktop"]
        property var applications: [
            {
                "id": "pin-one.desktop",
                "name": "Pinned One",
                "keywords": ["common"],
                "icon": "system-file-manager",
                "nameOrder": 0,
                "idOrder": 3
            },
            {
                "id": "pin-two.desktop",
                "name": "Pinned Two",
                "keywords": ["common"],
                "icon": "",
                "nameOrder": 1,
                "idOrder": 4
            },
            {
                "id": "recent-one.desktop",
                "name": "Recent One",
                "keywords": ["common"],
                "icon": "",
                "nameOrder": 2,
                "idOrder": 5
            },
            {
                "id": "alpha.desktop",
                "name": "Alpha Application With A Deliberately Long Descriptive Name",
                "keywords": ["common"],
                "icon": "",
                "nameOrder": 3,
                "idOrder": 0
            },
            {
                "id": "cafe.desktop",
                "name": "Café Editor",
                "keywords": ["common"],
                "icon": "",
                "nameOrder": 4,
                "idOrder": 1
            },
            {
                "id": "gamma.desktop",
                "name": "Gamma",
                "keywords": ["common"],
                "icon": "",
                "nameOrder": 5,
                "idOrder": 2
            },
            {
                "id": "six.desktop",
                "name": "Six",
                "keywords": ["common"],
                "icon": "",
                "nameOrder": 6,
                "idOrder": 6
            },
            {
                "id": "seven.desktop",
                "name": "Seven",
                "keywords": ["common"],
                "icon": "",
                "nameOrder": 7,
                "idOrder": 7
            },
            {
                "id": "eight.desktop",
                "name": "Eight",
                "keywords": ["common"],
                "icon": "",
                "nameOrder": 8,
                "idOrder": 8
            }
        ]
        property var pinnedApplications: [applications[1], applications[0]]
        property var recentApplications: [applications[2]]

        signal launchAccepted(int requestId, string desktopFileId)
        signal launchRejected(int requestId, string category)
        signal pinCommitted(string desktopFileId)
        signal pinRemoved(string desktopFileId)
        signal pinReordered(string desktopFileId)
        signal pinMutationFailed(string category)

        function dispatchLaunch(desktopFileId) {
            return 42;
        }

        function captureDiscoveryGeneration() {
        }

        function pin(desktopFileId) {
            test.pinCalls += 1;
            pinFailure = "limit";
            return false;
        }

        function unpin(desktopFileId) {
            test.pinCalls += 1;
            return true;
        }

        function movePin(desktopFileId, index) {
            test.moveCalls += 1;
            return true;
        }
    }

    Window {
        id: window

        width: 700
        height: 480
        visible: true

        LauncherView {
            id: launcher

            anchors.fill: parent
            applicationModel: fakeModel
            ownerEpoch: 17
            onLaunchDispatched: (requestId, epoch) => {
                test.launchTracked = requestId === 42 && epoch === 17;
            }
        }
    }

    Timer {
        interval: 0
        running: true
        onTriggered: {
            const allApplications = fakeModel.applications.slice();
            launcher.query = "common";
            fakeModel.applications = [];
            if (!test.requireResultLayout(0)) {
                return;
            }
            fakeModel.applications = allApplications.slice(0, 1);
            if (!test.requireResultLayout(1)) {
                return;
            }
            fakeModel.applications = allApplications.slice(0, 5);
            if (!test.requireResultLayout(5)) {
                return;
            }
            fakeModel.applications = allApplications.slice(0, 6);
            if (!test.requireResultLayout(6) || !test.require(launcher.contentWidth
                                                              === Theme.spacing.xxl * 15
                                                              && launcher.implicitWidth
                                                              === launcher.contentWidth
                                                              + Theme.spacing.lg * 2,
                                                              "launcher uses the exact 480 px content lane and 512 px surface")
                    || !test.require(launcher.searchFieldItem.width === launcher.contentWidth
                                     && launcher.resultViewportItem.width === launcher.contentWidth
                                     && launcher.resultListItem.width === launcher.contentWidth,
                                     "search, results, and empty-state viewport fill the natural width")) {
                return;
            }
            fakeModel.applications = allApplications;
            launcher.query = "";

            if (!test.require(JSON.stringify(launcher.rows.map(row => row.application.id))
                              === JSON.stringify(["pin-two.desktop", "pin-one.desktop",
                                                  "recent-one.desktop"]),
                              "empty query did not expose pins then deduplicated recents")) {
                return;
            }
            const applicationIcons = [];
            test.findObjects(launcher, "launcherApplicationIcon", applicationIcons);
            const validIcon = applicationIcons.find(icon => icon.applicationName === "Pinned One");
            const invalidIcon = applicationIcons.find(icon => icon.applicationName
                                                              === "Pinned Two");
            if (!test.require(applicationIcons.length === 3 && validIcon !== undefined
                              && validIcon.meaning === "application" && validIcon.resolvedKind
                              === "application" && !validIcon.tinted && validIcon.resolvedSource
                              === Quickshell.iconPath("system-file-manager")
                              && validIcon.accessibleName === "Pinned One",
                              "valid launcher artwork routes through the untinted application semantic path")
                    || !test.require(invalidIcon !== undefined && invalidIcon.meaning
                                     === "application" && invalidIcon.showingFallback
                                     && invalidIcon.resolvedKind === "placeholder"
                                     && invalidIcon.rawSource === IconResolver.placeholderSource,
                                     "missing launcher artwork resolves to the neutral semantic fallback")) {
                return;
            }

            launcher.query = "COMMON";
            if (!test.require(launcher.resultCount === 8, "search result bound was not enforced")
                    || !test.require(JSON.stringify(launcher.rows.slice(0, 3).map(row
                                                                                  => row.application.id))
                                     === JSON.stringify(["pin-two.desktop", "pin-one.desktop",
                                                         "recent-one.desktop"]),
                                     "search tie-breaks did not prioritize pin and MRU order")) {
                return;
            }

            launcher.query = "cafe";
            if (!test.require(launcher.resultCount === 1 && launcher.selectedId === "cafe.desktop",
                              "normalized name search did not match diacritics")) {
                return;
            }

            launcher.query = "alpha";
            launcher.restoreSelection();
            laneTimer.start();
        }
    }

    Timer {
        id: laneTimer

        interval: 0
        onTriggered: {
            if (!test.require(!launcher.toggleSelectedPin() && launcher.pinStatus
                              === "The eight-pin limit is full.",
                              "ninth-pin rejection was not visible") || !test.require(test.pinCalls
                                                                                      === 1, "pin action was not dispatched exactly once")) {
                return;
            }
            const alphaRow = launcher.resultListItem.currentItem;
            if (!test.require(alphaRow !== null && alphaRow.labelLaneWidth > Theme.spacing.xxl * 8
                              && alphaRow.primaryLabelWidth === alphaRow.labelLaneWidth
                              && alphaRow.metadataLabelWidth === alphaRow.labelLaneWidth,
                              "long application names and metadata receive the wider label lane")
                    || !test.require(Math.abs(alphaRow.pinActionRightEdge - (alphaRow.width
                                                                             - Theme.spacing.sm))
                                     <= 1, "Pin remains aligned to the widened row trailing edge: "
                                     + alphaRow.pinActionRightEdge + " vs " + (alphaRow.width
                                                                               - Theme.spacing.sm))) {
                return;
            }
            const resultFocusRing = test.directChild(alphaRow, "islandFocusRing");
            const resultBackground = alphaRow.children[0];
            alphaRow.forceActiveFocus(Qt.TabFocusReason);
            if (!test.require(resultFocusRing !== null && resultFocusRing.visible
                              && resultBackground.radius === Theme.radius.md
                              && resultFocusRing.controlRadius === resultBackground.radius
                              && resultFocusRing.radius === resultBackground.radius
                              + Theme.size.focusRingGap,
                              "launcher result keyboard focus ring follows its medium owner curve")) {
                return;
            }

            launcher.query = "pinned one";
            launcher.restoreSelection();
            if (!test.require(launcher.moveSelectedPin(-1) && test.moveCalls === 1,
                              "keyboard-accessible pin reorder was not dispatched")) {
                return;
            }

            if (!test.require(launcher.launchSelected() && launcher.pendingLaunchRequestId === 42,
                              "selected application was not dispatched")) {
                return;
            }
            if (!test.require(test.launchTracked,
                              "accepted launch was not tied to the current owner epoch")) {
                return;
            }
            fakeModel.launchAccepted(42, "pin-one.desktop");

            launcher.focusInitialControl();
            if (!test.require(launcher.searchFocused, "launcher did not focus search")) {
                return;
            }
            shortcut.acceptLine(test.shortcutState(true, "Meta+Space", false));
            if (!test.require(shortcut.available && shortcut.activeShortcut === "Meta+Space",
                              "valid shortcut state was not exposed")) {
                return;
            }
            shortcut.acceptLine("{\"type\":\"activation\",\"action\":\"openLauncher\"}");
            shortcut.acceptLine(
                        "{\"type\":\"activation\",\"action\":\"openLauncher\",\"command\":\"ignored\"}");
            if (!test.require(test.shortcutOpenCalls === 1,
                              "shortcut activation validation did not forward exactly one intent")) {
                return;
            }
            shortcut.acceptLine("{\"type\":\"activation\",\"action\":\"openSystemSettings\"}");
            if (!test.require(test.settingsOpenCalls === 1,
                              "Settings activation remains outside island state")) {
                return;
            }
            shortcut.acceptLine(test.shortcutState(false, null, false));
            if (!test.require(!shortcut.available && shortcut.activeShortcut === "",
                              "unavailable shortcut state was not exposed")) {
                return;
            }
            console.log("launcher view tests passed");
            Qt.exit(0);
        }
    }

    Timer {
        interval: 5000
        running: true
        onTriggered: {
            console.error("FAIL: launcher view tests timed out");
            Qt.exit(1);
        }
    }
}

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

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            return false;
        }
        return true;
    }

    QtObject {
        id: coordinator

        function openLauncher(origin) {
            test.shortcutOpenCalls += 1;
            return true;
        }
    }

    LauncherShortcutAdapter {
        id: shortcut

        coordinator: coordinator
        helperPath: ""
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
                "icon": "",
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
                "name": "Alpha",
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
            if (!test.require(JSON.stringify(launcher.rows.map(row => row.application.id))
                              === JSON.stringify(["pin-two.desktop", "pin-one.desktop",
                                                 "recent-one.desktop"]),
                              "empty query did not expose pins then deduplicated recents")) {
                return;
            }

            launcher.query = "COMMON";
            if (!test.require(launcher.resultCount === 8, "search result bound was not enforced")
                    || !test.require(JSON.stringify(launcher.rows.slice(0, 3).map(
                                                                           row => row.application.id))
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
            if (!test.require(!launcher.toggleSelectedPin()
                              && launcher.pinStatus === "The eight-pin limit is full.",
                              "ninth-pin rejection was not visible") || !test.require(
                        test.pinCalls === 1, "pin action was not dispatched exactly once")) {
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
            shortcut.acceptLine(
                        "{\"type\":\"state\",\"available\":true,\"activeShortcut\":\"Meta+Space\",\"preferredShortcut\":\"Meta+Space\",\"preferredConflict\":false}");
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
            shortcut.acceptLine(
                        "{\"type\":\"state\",\"available\":false,\"activeShortcut\":null,\"preferredShortcut\":\"Meta+Space\",\"preferredConflict\":false}");
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

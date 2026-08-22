import Quickshell
import QtQuick
import QtQuick.Layouts
import "qml"

ShellRoot {
    id: test

    property var mediaActions: []
    property var audioActions: []
    property var connectivityActions: []
    property var launchActions: []

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
        return true;
    }

    function focusNames(start) {
        const names = [];
        let current = start;
        for (let hop = 0; hop < 64 && current !== null; ++hop) {
            const name = current.objectName;
            if (name !== "" && names.indexOf(name) === -1) {
                names.push(name);
            }
            current = current.nextItemInFocusChain(true);
            if (current === start) {
                break;
            }
        }
        return names;
    }

    function containsText(item, text) {
        if (item === null || item === undefined) {
            return false;
        }
        if (typeof item.text === "string" && item.text === text) {
            return true;
        }
        const children = item.children ?? [];
        for (let index = 0; index < children.length; ++index) {
            if (containsText(children[index], text)) {
                return true;
            }
        }
        return false;
    }

    function runChecks() {
        require(dashboard.loadedRegionCount === 6, "all implemented dashboard regions mount");
        require(mediaView.previous() === "dispatched" && mediaView.togglePlayback()
                === "dispatched" && mediaView.next() === "dispatched" && mediaActions.join(",")
                === "previous,toggle,next",
                "media controls dispatch only through normalized actions");
        mediaAdapter.canNext = false;
        require(mediaView.next() === "rejected" && mediaActions.length === 3,
                "unsupported media control is locally rejected");

        mediaView.visible = true;
        require(mediaView.artworkRequest === mediaAdapter.artworkSource,
                "visible media requests only the validated selected artwork");
        mediaView.visible = false;
        require(mediaView.artworkRequest === "", "hidden media drops its artwork request");

        require(quickView.outputCount === 2 && quickView.pinCount === 2,
                "quick controls consume normalized outputs and shared eligible pins");
        require(quickView.toggleWifi() && quickView.toggleBluetooth() && connectivityActions.join(
                    ",") === "wifi,bluetooth",
                "connectivity controls dispatch real adapter toggles");
        connectivityAdapter.bluetoothFailure = "backend";
        require(quickView.bluetoothFailureVisible,
                "connectivity backend failure remains visible beside confirmed state");
        connectivityAdapter.bluetoothFailure = "none";
        require(quickView.selectOutput(1) && audioActions[0] === "select:virtual-output",
                "virtual normalized output remains selectable");
        require(quickView.launchPin(0) === 41 && launchActions[0] === "first.desktop",
                "pinned control dispatches the exact shared desktop ID");
        applications.pinnedApplications = [applications.eligibleEntries[1]];
        require(quickView.pinCount === 1 && applications.pinIds.length === 2
                && applications.pinIds[0] === "dormant.desktop",
                "eligible-pin updates hide dormant slots without mutating persistence");

        require(audioView.requestVolume("output", 0.7, true) && audioActions[audioActions.length
                                                                             - 1] === "output-volume:0.7:true",
                "output volume gesture reaches the confirmed audio adapter");
        audioAdapter.pendingOutputVolume = true;
        require(outputVolume.stateText.indexOf("Pending · confirmed 40%") === 0,
                "pending output remains distinct from the confirmed value");
        audioAdapter.outputAvailable = false;
        require(!audioView.requestVolume("output", 0.2, true),
                "unavailable output blocks writes without optimistic state");
        audioAdapter.outputAvailable = true;

        require(recentView.rowCount === 4 && !recentView.empty,
                "recent notifications use the service-owned four-record projection");
        notificationsModel.setProperty(0, "summary", "Replaced in place");

        dashboard.focusInitialControl();
        require(dashboardWindow.activeFocusItem !== null
                && dashboardWindow.activeFocusItem.objectName === "dashboardCloseButton",
                "dashboard exposes a visible initial keyboard focus");
        const names = focusNames(dashboardWindow.activeFocusItem);
        const expected = ["dashboardMediaPrevious", "dashboardMediaToggle", "dashboardWifi",
                          "dashboardBluetooth", "dashboardOutputCandidate",
                          "dashboardPinnedApplication", "dashboardOutputVolume",
                          "dashboardOutputMute", "dashboardInputVolume", "dashboardInputMute",
                          "dashboardLauncher", "dashboardHistory", "dashboardSession"];
        for (let index = 0; index < expected.length; ++index) {
            require(names.indexOf(expected[index]) !== -1, "focus traversal reaches "
                    + expected[index]);
        }

        Qt.callLater(function () {
            require(test.containsText(recentView, "Replaced in place"),
                    "notification replacement updates the live delegate without a view copy");
            dashboard.mediaContent = null;
            Qt.callLater(function () {
                require(dashboard.loadedRegionCount === 5,
                        "hidden media collapses without leaving a loaded placeholder");
                console.warn("expanded dashboard tests passed");
                Qt.exit(0);
            });
        });
    }

    Component.onCompleted: Qt.callLater(test.runChecks)

    QtObject {
        id: mediaAdapter

        property bool available: true
        property string title: "Track"
        property string artist: "Artist"
        property string album: "Album"
        property string playbackState: "playing"
        property real position: 30
        property real duration: 120
        property bool canPrevious: true
        property bool canTogglePlayback: true
        property bool canNext: true
        property string artworkSource: "file:///tmp/nagi-dashboard-artwork.png"
        property string artworkStatus: "ready"
        property int artworkMaximumWidth: 512
        property string pendingAction: "none"

        function previous() {
            test.mediaActions.push("previous");
            return "dispatched";
        }
        function togglePlayback() {
            test.mediaActions.push("toggle");
            return "dispatched";
        }
        function next() {
            test.mediaActions.push("next");
            return "dispatched";
        }
    }

    QtObject {
        id: connectivityAdapter

        property bool wifiAvailable: true
        property bool wifiEnabled: true
        property bool wifiPending: false
        property bool bluetoothAvailable: true
        property bool bluetoothEnabled: false
        property bool bluetoothPending: false
        property string wifiFailure: "none"
        property string bluetoothFailure: "none"

        function toggleWifi() {
            test.connectivityActions.push("wifi");
            return true;
        }
        function toggleBluetooth() {
            test.connectivityActions.push("bluetooth");
            return true;
        }
    }

    QtObject {
        id: audioAdapter

        property bool available: true
        property bool isSynchronized: true
        property bool outputAvailable: true
        property string outputLabel: "Built-in Audio"
        property string outputDisplayLabel: outputLabel
        property real outputVolume: 0.4
        property bool outputMuted: false
        property bool outputOveramplified: false
        property bool inputAvailable: true
        property real inputVolume: 0.3
        property bool inputMuted: false
        property bool inputOveramplified: false
        property bool pendingOutputVolume: false
        property bool pendingInputVolume: false
        property bool pendingOutputMute: false
        property bool pendingInputMute: false
        property bool pendingOutputSelection: false
        property var outputCandidates: [
            {
                "endpointKey": "physical-output",
                "label": "Built-in Audio",
                "isDefault": true
            },
            {
                "endpointKey": "virtual-output",
                "label": "EasyEffects Sink",
                "isDefault": false
            }
        ]

        function requestOutputSelection(endpointKey) {
            test.audioActions.push("select:" + endpointKey);
            return true;
        }
        function requestOutputVolume(value, finalValue) {
            test.audioActions.push("output-volume:" + value + ":" + finalValue);
            return true;
        }
        function requestInputVolume(value, finalValue) {
            test.audioActions.push("input-volume:" + value + ":" + finalValue);
            return true;
        }
        function requestOutputMute(muted) {
            test.audioActions.push("output-mute:" + muted);
            return true;
        }
        function requestInputMute(muted) {
            test.audioActions.push("input-mute:" + muted);
            return true;
        }
    }

    QtObject {
        id: applications

        property var eligibleEntries: [
            {
                "id": "first.desktop",
                "name": "First"
            },
            {
                "id": "second.desktop",
                "name": "Second"
            }
        ]
        property var pinnedApplications: eligibleEntries
        property var pinIds: ["dormant.desktop", "second.desktop"]
        property bool launchPending: false

        function dispatchLaunch(desktopFileId) {
            test.launchActions.push(desktopFileId);
            return 41;
        }
    }

    QtObject {
        id: trayAdapter

        readonly property var items: []
        readonly property int itemCount: 0
    }

    ListModel {
        id: notificationsModel

        ListElement {
            appName: "Mail"
            summary: "Newest"
            body: "Body"
            state: "live"
        }
        ListElement {
            appName: "Calendar"
            summary: "Meeting"
            body: "Body"
            state: "live"
        }
        ListElement {
            appName: "Chat"
            summary: "Message"
            body: "Body"
            state: "expired"
        }
        ListElement {
            appName: "Build"
            summary: "Complete"
            body: "Body"
            state: "live"
        }
    }

    QtObject {
        id: notificationService

        readonly property var dashboardModel: notificationsModel
        readonly property bool serverOwned: true
    }

    QtObject {
        id: clockState

        readonly property string text: "12:34"
        readonly property string dateText: "Saturday, 22 August"
        readonly property string weekText: "Saturday"
    }

    Component {
        id: mediaContent
        DashboardMedia {
            media: mediaAdapter
        }
    }
    Component {
        id: clockContent
        DashboardClock {
            clock: clockState
        }
    }
    Component {
        id: quickContent
        DashboardQuickControls {
            connectivity: connectivityAdapter
            audio: audioAdapter
            applicationModel: applications
            tray: trayAdapter
        }
    }
    Component {
        id: audioContent
        DashboardAudio {
            audio: audioAdapter
        }
    }
    Component {
        id: notificationContent
        DashboardNotifications {
            service: notificationService
        }
    }
    Component {
        id: navigationContent
        RowLayout {
            IslandButton {
                objectName: "dashboardLauncher"
                label: "Launcher"
            }
            IslandButton {
                objectName: "dashboardHistory"
                label: "History"
            }
            IslandButton {
                objectName: "dashboardSession"
                label: "Session"
            }
        }
    }

    Window {
        id: dashboardWindow

        visible: true
        width: 700
        height: 480
        color: "black"

        ExpandedDashboard {
            id: dashboard

            anchors.fill: parent
            mediaContent: mediaContent
            clockContent: clockContent
            quickControlsContent: quickContent
            audioContent: audioContent
            notificationsContent: notificationContent
            navigationContent: navigationContent
        }

        Item {
            x: -2000
            width: 700
            height: 480

            DashboardMedia {
                id: mediaView
                visible: false
                width: 340
                height: 132
                media: mediaAdapter
            }

            DashboardQuickControls {
                id: quickView
                y: 140
                width: 700
                height: 100
                connectivity: connectivityAdapter
                audio: audioAdapter
                applicationModel: applications
                tray: trayAdapter
            }

            DashboardAudio {
                id: audioView
                y: 250
                width: 340
                height: 92
                audio: audioAdapter
            }

            DashboardVolumeControl {
                id: outputVolume
                y: 350
                width: 300
                label: "Output"
                available: audioAdapter.outputAvailable
                volume: audioAdapter.outputVolume
                muted: audioAdapter.outputMuted
                overamplified: audioAdapter.outputOveramplified
                pendingVolume: audioAdapter.pendingOutputVolume
                pendingMute: audioAdapter.pendingOutputMute
            }

            DashboardNotifications {
                id: recentView
                x: 350
                y: 250
                width: 300
                height: 92
                service: notificationService
            }
        }
    }
}

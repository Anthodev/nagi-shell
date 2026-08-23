import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    property int observedSnapshots: 0
    property string configuredHelperPath: ""

    function startWhenThemeReady() {
        if (configuredHelperPath === "" && Theme.snapshot.source === "configured") {
            configuredHelperPath = Quickshell.env("NAGI_WALLPAPER_HELPER") ?? "";
        }
    }

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

    Component.onCompleted: Qt.callLater(test.startWhenThemeReady)

    Connections {
        target: Theme

        function onSnapshotChanged() {
            test.startWhenThemeReady();
        }
    }

    WallpaperPaletteBridge {
        id: bridge

        helperPath: test.configuredHelperPath

        onGenerationChanged: {
            test.observedSnapshots += 1;
            if (generation === 1) {
                test.require(available && status === "Ready" && accent === "#D94A38",
                             "Ready snapshot is normalized");
                test.require(Theme.wallpaperPalette !== null
                             && Theme.wallpaperPalette.accent === "#D94A38"
                             && Theme.snapshot.source === "wallpaper",
                             "Ready snapshot injects only the wallpaper accent");
            } else if (generation === 2) {
                test.require(!available && status === "UnsupportedPlugin" && accent === "",
                             "failure snapshot is normalized through public roles");
                test.require(Theme.wallpaperPalette === null && Theme.snapshot.source === "configured"
                             && Theme.snapshot.configuredAccent === "#FF8A00",
                             "failure status restores the configured fallback");
            } else if (generation === 3) {
                test.require(available && status === "Ready" && accent === "#1E6FD9",
                             "later Ready snapshot replaces the palette atomically");
                test.require(Theme.wallpaperPalette.accent === "#1E6FD9"
                             && Theme.snapshot.source === "wallpaper",
                             "later Ready snapshot reaches Theme");
                settle.start();
            } else {
                test.fail("unexpected wallpaper generation");
            }
        }
    }

    Timer {
        id: settle

        interval: 150
        repeat: false
        onTriggered: {
            test.require(bridge.generation === 3 && test.observedSnapshots === 3,
                         "settled helper emits no recurring snapshots");
            test.require(bridge.activeTimerCount === 0,
                         "wallpaper bridge has no recurring timer work");
            console.log("wallpaper QML tests passed");
            Qt.exit(0);
        }
    }
}

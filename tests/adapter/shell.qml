import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            return false;
        }
        return true;
    }

    function run() {
        const initial = "{\"available\":true,\"currentId\":\"first\",\"desktops\":[{\"id\":\"second\",\"name\":\"Desktop 2\",\"position\":1},{\"id\":\"first\",\"name\":\"Desktop 1\",\"position\":0}]}";
        adapter.acceptSnapshotLine(initial);
        if (!require(adapter.available, "valid state is available")
                || !require(adapter.desktops.length === 2, "complete desktop list is exposed")
                || !require(adapter.desktops[0].id === "first", "desktop list is ordered")
                || !require(adapter.currentName === "Desktop 1", "current name resolves")
                || !require(adapter.currentPosition === 0, "current position resolves")) {
            return;
        }

        adapter.acceptSnapshotLine("not json");
        adapter.acceptSnapshotLine("{\"available\":true");
        adapter.acceptSnapshotLine("x".repeat(adapter.maximumLineLength + 1));
        adapter.acceptSnapshotLine("{\"available\":true,\"currentId\":\"missing\",\"desktops\":[{\"id\":\"first\",\"name\":\"Desktop 1\",\"position\":0}]}");
        adapter.acceptSnapshotLine("still not json");
        if (!require(adapter.available, "invalid lines preserve availability")
                || !require(adapter.currentId === "first", "invalid lines preserve current desktop")
                || !require(adapter.currentPosition === 0, "invalid lines preserve coherent state")) {
            return;
        }

        adapter.acceptSnapshotLine("{\"available\":true,\"currentId\":\"second\",\"desktops\":[{\"id\":\"first\",\"name\":\"Desktop 1\",\"position\":0},{\"id\":\"second\",\"name\":\"Desktop 2\",\"position\":1}]}");
        if (!require(adapter.currentId === "second", "replacement current ID updates")
                || !require(adapter.currentName === "Desktop 2", "replacement current name is coherent")
                || !require(adapter.currentPosition === 1, "replacement current position is coherent")) {
            return;
        }

        console.log("adapter boundary tests passed");
        Qt.exit(0);
    }

    KWinVirtualDesktopAdapter {
        id: adapter

        helperPath: "/usr/bin/true"
    }

    Component.onCompleted: Qt.callLater(test.run)
}

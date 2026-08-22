import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test
    property int workspaceChangeCount: 0
    property int workspaceInvalidationCount: 0
    property string lastSourceToken: ""
    property int lastSourceGeneration: 0
    property int lastRevision: 0

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            return false;
        }
        return true;
    }

    function run() {
        const initial
              = "{\"available\":true,\"currentId\":\"first\",\"desktops\":[{\"id\":\"second\",\"name\":\"Desktop 2\",\"position\":1},{\"id\":\"first\",\"name\":\"Desktop 1\",\"position\":0}]}";
        adapter.acceptSnapshotLine(initial);
        if (!require(adapter.available, "valid state is available") || !require(
                    adapter.desktops.length === 2, "complete desktop list is exposed") || !require(
                    adapter.desktops[0].id === "first", "desktop list is ordered") || !require(
                    adapter.currentName === "Desktop 1", "current name resolves") || !require(
                    adapter.currentPosition === 0, "current position resolves") || !require(
                    workspaceChangeCount === 0,
                    "initial backend projection does not replay as a transient")) {
            return;
        }

        adapter.acceptSnapshotLine("not json");
        adapter.acceptSnapshotLine("{\"available\":true");
        adapter.acceptSnapshotLine("x".repeat(adapter.maximumLineLength + 1));
        adapter.acceptSnapshotLine(
                    "{\"available\":true,\"currentId\":\"missing\",\"desktops\":[{\"id\":\"first\",\"name\":\"Desktop 1\",\"position\":0}]}");
        adapter.acceptSnapshotLine("still not json");
        if (!require(adapter.available, "invalid lines preserve availability") || !require(
                    adapter.currentId === "first", "invalid lines preserve current desktop") ||
                !require(adapter.currentPosition === 0, "invalid lines preserve coherent state")) {
            return;
        }

        adapter.acceptSnapshotLine(
                    "{\"available\":true,\"currentId\":\"second\",\"desktops\":[{\"id\":\"first\",\"name\":\"Desktop 1\",\"position\":0},{\"id\":\"second\",\"name\":\"Desktop 2\",\"position\":1}]}");
        if (!require(adapter.currentId === "second", "replacement current ID updates") || !require(
                    adapter.currentName === "Desktop 2", "replacement current name is coherent") ||
                !require(adapter.currentPosition === 1, "replacement current position is coherent")
                || !require(workspaceChangeCount === 1 && lastSourceToken === "workspace-current"
                            && lastSourceGeneration === 1 && lastRevision === 2,
                            "confirmed switch publishes one generation-scoped revision")) {
            return;
        }
        const switched = adapter.resolveTransient(lastSourceToken, lastSourceGeneration,
                                                  lastRevision);
        if (!require(switched !== null && switched.primary === "Desktop 2" && switched.detail === "Current desktop"
                     && switched.value === "2 / 2",
                     "exact switch revision resolves current name and relative position") ||
                !require(adapter.resolveTransient(lastSourceToken, lastSourceGeneration, 1) === null,
                         "stale workspace revision cannot resolve")) {
            return;
        }

        adapter.acceptSnapshotLine(
                    "{\"available\":true,\"currentId\":\"second\",\"desktops\":[{\"id\":\"first\",\"name\":\"Desktop 1\",\"position\":0},{\"id\":\"second\",\"name\":\"Focus\",\"position\":1}]}");
        if (!require(workspaceChangeCount === 2 && lastRevision === 3 && adapter.resolveTransient(
                         lastSourceToken, 1, 3).primary === "Focus",
                     "current projection rename publishes one latest coalescing revision")) {
            return;
        }

        adapter.publishUnavailable();
        if (!require(!adapter.available && workspaceInvalidationCount === 1
                     && adapter.resolveTransient(lastSourceToken, 1, 3) === null,
                     "backend loss invalidates the current workspace source")) {
            return;
        }
        adapter.acceptSnapshotLine(initial);
        if (!require(adapter.available && workspaceChangeCount === 2 && workspaceInvalidationCount
                     === 1, "fresh backend generation synchronizes without replaying startup feedback")) {
            return;
        }

        console.warn("adapter boundary tests passed");
        Qt.exit(0);
    }

    KWinVirtualDesktopAdapter {
        id: adapter

        helperPath: "/usr/bin/true"
        onConfirmedWorkspaceChanged: function (sourceToken, sourceGeneration, revision) {
            test.workspaceChangeCount += 1;
            test.lastSourceToken = sourceToken;
            test.lastSourceGeneration = sourceGeneration;
            test.lastRevision = revision;
        }
        onConfirmedWorkspaceInvalidated: function (sourceToken, sourceGeneration) {
            test.workspaceInvalidationCount += 1;
        }
    }

    Component.onCompleted: Qt.callLater(test.run)
}

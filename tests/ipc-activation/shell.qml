pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

// Issue #70 gate 3: same-process singleton activation probe. One root-scope
// IpcHandler exposes a raise/activate target; an external caller uses the
// `qs ipc` CLI against the running instance.
ShellRoot {
    id: root

    property int activationCount: 0

    function activate(reason: string): string {
        root.activationCount += 1;
        console.warn("PROBE ACTIVATED count=" + root.activationCount + " reason=" + reason);
        return "count=" + root.activationCount;
    }

    PanelWindow {
        implicitWidth: 120
        implicitHeight: 40
        color: "transparent"
        visible: false
    }

    IpcHandler {
        target: "nagi"

        function activate(reason: string): string {
            return root.activate(reason);
        }
    }

    Component.onCompleted: console.warn("PROBE READY")
}

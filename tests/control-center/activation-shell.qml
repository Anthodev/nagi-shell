import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    property int activationCount: 0
    readonly property string recordPath: Quickshell.env("NAGI_ACTIVATION_RECORD") ?? ""

    FileView {
        id: record
        path: root.recordPath
        blockWrites: true
        atomicWrites: true
        printErrors: false
    }

    IpcHandler {
        target: "nagi"

        function activate(reason: string): bool {
            if (reason !== "control-center" && reason !== "island" && reason !== "appearance"
                    && reason !== "displays" && reason !== "about") {
                return false;
            }
            root.activationCount += 1;
            record.setText("count=" + root.activationCount + "\nroute=" + reason + "\n");
            return true;
        }
    }
}

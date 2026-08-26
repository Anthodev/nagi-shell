pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import "qml"

// Drives the production adapter through atomic replacement and deletion.
ShellRoot {
    id: root

    function emitSnapshot() {
        const snapshot = appearance.snapshot;
        console.warn("APPEARANCE scheme=" + snapshot.schemeName + " accent=" + snapshot.accent
                     + " motion=" + snapshot.animationFactor);
    }

    KdeAppearanceAdapter {
        id: appearance

        onSnapshotChanged: root.emitSnapshot()
    }

    Component.onCompleted: console.warn("PROBE READY path=" + appearance.resolvedPath)
}

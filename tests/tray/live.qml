//@ pragma UseQApplication
import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    property int stage: 0
    property int attempts: 0
    property int controlledToken: 0
    property string initialIcon: ""

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function findLabel(label) {
        for (let index = 0; index < tray.items.length; ++index) {
            if (tray.items[index].label === label) {
                return tray.items[index];
            }
        }
        return null;
    }

    function findToken(token) {
        for (let index = 0; index < tray.items.length; ++index) {
            if (tray.items[index].token === token) {
                return tray.items[index];
            }
        }
        return null;
    }

    function advance() {
        attempts += 1;
        require(attempts < 240, "controlled tray lifecycle did not settle");

        if (stage === 0) {
            const initial = findLabel("Nagi tray initial");
            if (initial === null) {
                return;
            }
            require(initial.iconSource !== "" && initial.hasMenu && !initial.onlyMenu,
                    "real item exposes icon identity and supported behavior");
            controlledToken = initial.token;
            initialIcon = initial.iconSource;
            require(tray.activate(controlledToken) === "dispatched",
                    "real primary activation dispatches");
            console.warn("tray live: primary activation dispatched");
            stage = 1;
            return;
        }

        if (stage === 1) {
            const activated = findLabel("Nagi tray activated");
            if (activated === null) {
                return;
            }
            require(activated.token === controlledToken && activated.iconSource !== initialIcon,
                    "real tooltip and icon updates preserve lifecycle identity");
            require(tray.openMenu(controlledToken, window, 32, 32) === "dispatched",
                    "real platform menu dispatches against the live window");
            console.warn("tray live: platform menu dispatched");
            stage = 2;
            return;
        }

        if (stage === 2) {
            const invoked = findLabel("Nagi tray menu invoked");
            if (invoked === null) {
                return;
            }
            require(invoked.token === controlledToken,
                    "real menu action updates the same connected item");
            require(tray.activate(controlledToken) === "dispatched",
                    "controlled failure/exit activation dispatches");
            console.warn("tray live: menu action observed; requesting exit");
            stage = 3;
            return;
        }

        if (findToken(controlledToken) === null) {
            require(tray.trackedItemCount === tray.itemCount,
                    "exiting item releases its adapter record without blocking peers");
            console.warn("tray live: start, update, activation, menu, and exit passed");
            Qt.exit(0);
        }
    }

    TrayAdapter {
        id: tray
    }

    PanelWindow {
        id: window

        anchors.top: true
        color: "transparent"
        implicitWidth: 64
        implicitHeight: 64
        exclusiveZone: 0
    }

    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: test.advance()
    }
}

pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Services.Notifications
import QtQuick

// Issue #70 gate 1: multi-PanelWindow contract probe. One process hosts one
// PanelWindow per connected screen, exercises independent assignment,
// destruction/recreation, and records observed display identity and scale data.
// Runs entirely inside tests/run-kwin-virtual.sh disposable sessions.
ShellRoot {
    id: root

    readonly property int expectedOutputs: parseInt(Quickshell.env("NAGI_PROBE_OUTPUTS") ?? "2")
    readonly property int maximumRetryAttempts: 600
    property int retryAttempts: 0
    property var surfaces: []
    property var reassignedFrom: null
    property var destroyedScreen: null
    property var reassignedSurface: null
    property int stepIndex: 0

    function advance() {
        Qt.callLater(root.runStep);
    }

    function awaitState(condition, message) {
        if (condition) {
            root.retryAttempts = 0;
            return true;
        }

        root.retryAttempts += 1;
        if (root.retryAttempts > root.maximumRetryAttempts) {
            root.fail(message);
        }
        retry.restart();
        return false;
    }

    function fail(message) {
        console.error("PROBE FAIL: " + message);
        Qt.exit(1);
    }

    function emit(text) {
        console.warn("PROBE " + text);
    }

    function identityDump(screen) {
        const fields = {};
        const keys = ["name", "model", "manufacturer", "serialNumber", "width", "height",
            "physicalWidth", "physicalHeight"];
        for (let index = 0; index < keys.length; index += 1) {
            try {
                const value = screen[keys[index]];
                if (value !== undefined) {
                    fields[keys[index]] = String(value);
                }
            } catch (error) {
                fields[keys[index]] = "<unreadable>";
            }
        }
        return JSON.stringify(fields);
    }

    function connectedScreens() {
        const found = [];
        for (let index = 0; index < Quickshell.screens.length; index += 1) {
            found.push(Quickshell.screens[index]);
        }
        return found;
    }

    function surfaceOn(screen) {
        for (let index = 0; index < root.surfaces.length; index += 1) {
            if (root.surfaces[index].screen === screen) {
                return root.surfaces[index];
            }
        }
        return null;
    }

    function allSurfacesSettled(screens) {
        if (root.surfaces.length !== screens.length) {
            return false;
        }
        for (let index = 0; index < root.surfaces.length; index += 1) {
            const surface = root.surfaces[index];
            if (!surface.visible || surface.screen === null || surface.contentItem === null) {
                return false;
            }
        }
        return true;
    }

    function remainingSurfacesSettled(screens) {
        if (root.surfaces.length !== screens.length - 1) {
            return false;
        }
        for (let index = 0; index < root.surfaces.length; index += 1) {
            const surface = root.surfaces[index];
            if (!surface.visible || surface.screen === null
                    || !screens.includes(surface.screen)) {
                return false;
            }
        }
        return true;
    }

    function othersUnchanged(exceptSurface, screens) {
        for (let index = 0; index < root.surfaces.length; index += 1) {
            const surface = root.surfaces[index];
            if (surface === exceptSurface) {
                continue;
            }
            if (!surface.visible || !screens.includes(surface.screen)) {
                return false;
            }
        }
        return true;
    }

    component ProbeSurface: PanelWindow {
        id: surface

        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: "#202124"

            Text {
                anchors.centerIn: parent
                color: "#e8eaed"
                text: "probe"
            }
        }
    }

    Component {
        id: probeSurfaceComponent

        ProbeSurface {}
    }

    NotificationServer {
        id: server

        keepOnReload: false
    }

    Timer {
        id: retry

        interval: 50
        onTriggered: root.runStep()
    }

    Timer {
        id: settleTimer

        interval: 100
        onTriggered: root.advance()
    }

    Component.onCompleted: root.advance()

    function runStep() {
        switch (root.stepIndex) {
        case 0:
            if (!root.awaitState(Quickshell.screens.length === root.expectedOutputs,
                                 "expected " + root.expectedOutputs + " screens, saw "
                                     + Quickshell.screens.length)) {
                return;
            }
            root.emit("screens=" + root.expectedOutputs);
            for (let index = 0; index < Quickshell.screens.length; index += 1) {
                root.emit("IDENTITY " + root.identityDump(Quickshell.screens[index]));
            }
            root.stepIndex = 1;
            root.advance();
            return;
        case 1: {
            const screens = root.connectedScreens();
            for (let index = 0; index < screens.length; index += 1) {
                const surface = probeSurfaceComponent.createObject(root, {
                                                                       "screen": screens[index],
                                                                       "visible": true
                                                                   });
                surface.objectName = "probe-" + index;
                root.surfaces.push(surface);
            }
            root.stepIndex = 2;
            settleTimer.restart();
            return;
        }
        case 2:
            if (!root.awaitState(root.allSurfacesSettled(root.connectedScreens()),
                                 "surfaces did not settle onto their assigned screens")) {
                return;
            }
            for (let index = 0; index < root.surfaces.length; index += 1) {
                const surface = root.surfaces[index];
                if (!root.connectedScreens().includes(surface.screen)) {
                    root.fail("surface " + surface.objectName + " lost its assigned screen");
                    return;
                }
            }
            root.emit("ASSIGN one-surface-per-screen OK");
            root.stepIndex = 3;
            root.advance();
            return;
        case 3: {
            if (root.expectedOutputs < 2) {
                root.emit("REASSIGN skipped (single output)");
                root.stepIndex = 5;
                root.advance();
                return;
            }
            const screens = root.connectedScreens();
            root.reassignedSurface = root.surfaceOn(screens[0]);
            const mover = root.reassignedSurface;
            if (mover === null) {
                root.fail("no surface on the first screen");
                return;
            }
            root.reassignedFrom = screens[0];
            const target = screens[screens.length - 1];
            if (target === screens[0]) {
                root.fail("need a distinct target screen");
                return;
            }
            mover.screen = target;
            root.stepIndex = 4;
            settleTimer.restart();
            return;
        }
        case 4: {
            const screens = root.connectedScreens();
            const target = screens[screens.length - 1];
            const mover = root.reassignedSurface;
            if (!root.awaitState(mover !== null && mover.screen === target,
                                 "moved surface did not follow independent assignment")) {
                return;
            }
            let duplicates = 0;
            for (let index = 0; index < root.surfaces.length; index += 1) {
                if (root.surfaces[index].screen === target) {
                    duplicates += 1;
                }
            }
            if (duplicates !== 2) {
                root.fail("target screen should host moved + native surfaces, saw " + duplicates);
                return;
            }
            if (!root.othersUnchanged(mover, screens)) {
                root.fail("unrelated surfaces changed during reassignment");
                return;
            }
            root.emit("REASSIGN independent assignment OK");
            mover.screen = root.reassignedFrom;
            root.stepIndex = 5;
            settleTimer.restart();
            return;
        }
        case 5: {
            if (root.expectedOutputs < 2) {
                root.emit("DESTROY skipped (single output)");
                return;
            }
            const screens = root.connectedScreens();
            const victim = root.surfaces[root.surfaces.length - 1];
            root.destroyedScreen = victim.screen;
            root.surfaces.splice(root.surfaces.indexOf(victim), 1);
            victim.destroy();
            root.stepIndex = 6;
            settleTimer.restart();
            return;
        }
        case 6:
            if (!root.awaitState(root.remainingSurfacesSettled(root.connectedScreens())
                                     && root.destroyedScreen !== null
                                     && root.surfaceOn(root.destroyedScreen) === null,
                                 "remaining surfaces did not survive sibling destruction")) {
                return;
            }
            root.emit("DESTROY sibling survival OK");
            const replacement = probeSurfaceComponent.createObject(root, {
                                                                       "screen": root.destroyedScreen,
                                                                       "visible": true
                                                                   });
            replacement.objectName = "probe-replacement";
            root.surfaces.push(replacement);
            root.stepIndex = 7;
            settleTimer.restart();
            return;
        case 7:
            if (!root.awaitState(root.surfaceOn(root.destroyedScreen) !== null
                                     && root.surfaceOn(root.destroyedScreen).visible,
                                 "replacement surface did not appear on its screen")) {
                return;
            }
            root.emit("DESTROY recreation OK");
            root.stepIndex = 8;
            root.advance();
            return;
        case 8:
            for (let index = 0; index < root.surfaces.length; index += 1) {
                const surface = root.surfaces[index];
                const inner = surface.contentItem.children.length > 0
                              && surface.contentItem.children[0] !== null ? surface.contentItem
                    .children[0] : null;
                const dpr = inner !== null ? inner.Screen.devicePixelRatio : 0;
                root.emit("SCALE surface=" + surface.objectName + " dpr=" + dpr + " window="
                              + surface.width + "x" + surface.height + " screen="
                              + (surface.screen === null ? "?" : surface.screen.width + "x"
                                                         + surface.screen.height));
            }
            if (server === null) {
                root.fail("NotificationServer vanished during surface churn");
                return;
            }
            root.emit("SERVICE notification-server alive after churn");
            root.emit("DONE");
            return;
        default:
            root.fail("unknown step " + root.stepIndex);
        }
    }
}

import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    property var originalDisplays: []
    property var actions: []
    property var changedKeys: ({})
    property int actionIndex: 0
    property bool waiting: false
    property bool restoringAfterFailure: false
    property int finalExitCode: 0
    property string finalMessage: ""
    property var activeOriginToken: null
    property int confirmedWriteCount: 0

    BrightnessAdapter {
        id: brightness

        helperPath: Quickshell.env("NAGI_BRIGHTNESS_HELPER") ?? ""
    }

    function near(left, right) {
        return Math.abs(left - right) <= 0.001;
    }

    function targetFor(ratio) {
        return ratio <= 0.95 ? ratio + 0.05 : ratio - 0.05;
    }

    function start() {
        if (originalDisplays.length > 0 || !brightness.backendReady || !brightness.available) {
            return;
        }
        if (!brightness.supported || brightness.displays.length === 0) {
            console.warn("brightness live probe passed: PowerDevil reports no supported display");
            Qt.exit(0);
            return;
        }

        const originals = [];
        const requested = [];
        for (let index = 0; index < brightness.displays.length; index += 1) {
            const display = brightness.displays[index];
            originals.push({
                               "key": display.key,
                               "ratio": display.ratio
                           });
            requested.push({
                               "key": display.key,
                               "ratio": targetFor(display.ratio),
                               "restore": false
                           }, {
                               "key": display.key,
                               "ratio": display.ratio,
                               "restore": true
                           });
        }
        originalDisplays = originals;
        actions = requested;
        dispatchNext();
    }

    function dispatchNext() {
        if (waiting) {
            return;
        }
        if (actionIndex >= actions.length) {
            finish();
            return;
        }
        const action = actions[actionIndex];
        const display = brightness.displayForKey(action.key);
        if (display === null) {
            fail("PowerDevil display generation changed during live write");
            return;
        }
        if (near(display.ratio, action.ratio)) {
            completeAction(false);
            return;
        }

        activeOriginToken = {};
        waiting = true;
        stageTimeout.restart();
        if (!brightness.requestBrightness(action.key, action.ratio, activeOriginToken)) {
            stageTimeout.stop();
            waiting = false;
            fail("brightness adapter rejected a current live display write");
        }
    }

    function confirmed(sourceToken, initiatingSurfaceToken) {
        if (!waiting) {
            return;
        }
        const action = actions[actionIndex];
        if (sourceToken !== action.key) {
            return;
        }
        const display = brightness.displayForKey(action.key);
        if (display === null || !near(display.ratio, action.ratio)) {
            return;
        }
        if (initiatingSurfaceToken !== activeOriginToken) {
            fail("live confirmation did not correlate generated source context");
            return;
        }
        confirmedWriteCount += 1;
        completeAction(true);
    }

    function completeAction(wrote) {
        const action = actions[actionIndex];
        if (wrote) {
            if (action.restore) {
                delete changedKeys["$" + action.key];
            } else {
                changedKeys["$" + action.key] = true;
            }
        }
        waiting = false;
        stageTimeout.stop();
        activeOriginToken = null;
        actionIndex += 1;
        Qt.callLater(dispatchNext);
    }

    function restorationActions() {
        const restore = [];
        for (let index = 0; index < originalDisplays.length; index += 1) {
            const original = originalDisplays[index];
            if (changedKeys["$" + original.key] === true && brightness.displayForKey(original.key)
                    !== null) {
                restore.push({
                                 "key": original.key,
                                 "ratio": original.ratio,
                                 "restore": true
                             });
            }
        }
        return restore;
    }

    function fail(message) {
        if (restoringAfterFailure || originalDisplays.length === 0) {
            console.error("FAIL: " + message);
            Qt.exit(2);
            return;
        }
        restoringAfterFailure = true;
        finalExitCode = 2;
        finalMessage = message;
        waiting = false;
        stageTimeout.stop();
        actions = restorationActions();
        actionIndex = 0;
        dispatchNext();
    }

    function finish() {
        startupTimeout.stop();
        stageTimeout.stop();
        for (let index = 0; index < originalDisplays.length; index += 1) {
            const original = originalDisplays[index];
            const display = brightness.displayForKey(original.key);
            if (display === null || !near(display.ratio, original.ratio)) {
                fail("live PowerDevil logical brightness did not restore exactly");
                return;
            }
        }
        if (finalExitCode !== 0) {
            console.error("FAIL: " + finalMessage + " (brightness state restored)");
            Qt.exit(finalExitCode);
            return;
        }
        if (confirmedWriteCount === 0) {
            console.error("FAIL: live displays accepted no distinct brightness step");
            Qt.exit(2);
            return;
        }
        console.warn("brightness live confirmed-write probe passed and restored all displays");
        Qt.exit(0);
    }

    Connections {
        target: brightness

        function onAvailableChanged() {
            Qt.callLater(test.start);
        }

        function onBackendReadyChanged() {
            Qt.callLater(test.start);
        }

        function onConfirmedBrightnessChanged(sourceToken, sourceGeneration, revision,
                                              initiatingSurfaceToken) {
            test.confirmed(sourceToken, initiatingSurfaceToken);
        }

        function onRequestFinished(requestId, outcome) {
            if (!test.waiting || outcome === "pending" || outcome === "confirmed") {
                return;
            }
            if (outcome === "noop") {
                test.completeAction(false);
                return;
            }
            test.fail("PowerDevil brightness request failed: " + outcome);
        }
    }

    Timer {
        id: startupTimeout

        interval: 5000
        running: true
        onTriggered: test.fail("live PowerDevil discovery timed out")
    }

    Timer {
        id: stageTimeout

        interval: 5000
        onTriggered: {
            test.waiting = false;
            test.fail("live PowerDevil confirmation timed out");
        }
    }

    Component.onCompleted: Qt.callLater(start)
}

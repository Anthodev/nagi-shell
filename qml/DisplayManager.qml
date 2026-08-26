pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

Scope {
    id: root

    readonly property int revision: state.revision
    readonly property int activeDisplayCount: state.records.length
    readonly property int enabledDisplayCount: state.enabledCount()
    readonly property var fallbackScreen: state.fallbackScreen
    readonly property var rememberedDisplays: Object.freeze([])

    signal changeRejected(string reason)

    function activeDisplays() {
        const rows = [];
        for (let index = 0; index < state.records.length; index += 1) {
            const record = state.records[index];
            rows.push(Object.freeze({
                                        "connected": true,
                                        "enabled": record.enabled,
                                        "fallback": record.screen === state.fallbackScreen,
                                        "label": "Connected display " + (index + 1),
                                        "reliable": false,
                                        "screen": record.screen
                                    }));
        }
        return Object.freeze(rows);
    }

    function forgetRemembered(identity) {
        // Issue #70 proved that ShellScreen 0.3.x exposes no reliable identity.
        // Remembered rows remain empty until a future adapter supplies one.
        return false;
    }

    function isEnabled(screen) {
        const record = state.recordFor(screen);
        return record !== null && record.enabled;
    }

    function isFallback(screen) {
        return screen !== null && screen === state.fallbackScreen;
    }

    function requestEnabled(screen, enabled) {
        if (typeof enabled !== "boolean") {
            return false;
        }
        const record = state.recordFor(screen);
        if (record === null || record.enabled === enabled) {
            return record !== null;
        }
        if (!enabled && state.enabledCount() <= 1) {
            root.changeRejected("At least one island must remain enabled.");
            return false;
        }

        record.enabled = enabled;
        if (!enabled && state.fallbackScreen === screen) {
            state.fallbackScreen = state.firstEnabledScreen();
        } else if (enabled && state.fallbackScreen === null) {
            state.fallbackScreen = screen;
        }
        state.publish();
        return true;
    }

    function requestFallback(screen) {
        const record = state.recordFor(screen);
        if (record === null || !record.enabled) {
            root.changeRejected("The fallback must be an active enabled display.");
            return false;
        }
        if (state.fallbackScreen === screen) {
            return true;
        }
        state.fallbackScreen = screen;
        state.publish();
        return true;
    }

    function syncScreens() {
        state.syncScreens();
    }

    QtObject {
        id: state

        property var records: []
        property var fallbackScreen: null
        property int revision: 0

        function connected(screen) {
            for (let index = 0; index < Quickshell.screens.length; index += 1) {
                if (Quickshell.screens[index] === screen) {
                    return true;
                }
            }
            return false;
        }

        function enabledCount() {
            let count = 0;
            for (let index = 0; index < records.length; index += 1) {
                if (records[index].enabled) {
                    count += 1;
                }
            }
            return count;
        }

        function firstEnabledScreen() {
            for (let index = 0; index < records.length; index += 1) {
                if (records[index].enabled) {
                    return records[index].screen;
                }
            }
            return null;
        }

        function publish() {
            records = records.slice();
            revision += 1;
        }

        function recordFor(screen) {
            for (let index = 0; index < records.length; index += 1) {
                if (records[index].screen === screen) {
                    return records[index];
                }
            }
            return null;
        }

        function syncScreens() {
            const next = [];
            for (let index = 0; index < records.length; index += 1) {
                if (connected(records[index].screen)) {
                    next.push(records[index]);
                }
            }
            for (let index = 0; index < Quickshell.screens.length; index += 1) {
                const screen = Quickshell.screens[index];
                let known = false;
                for (let recordIndex = 0; recordIndex < next.length; recordIndex += 1) {
                    if (next[recordIndex].screen === screen) {
                        known = true;
                        break;
                    }
                }
                if (!known) {
                    // With no stable identity contract, every newly seen screen is
                    // a fresh session-only display and starts enabled.
                    next.push({
                                  "enabled": true,
                                  "screen": screen
                              });
                }
            }
            records = next;
            if (fallbackScreen === null || !connected(fallbackScreen) || !root.isEnabled(
                        fallbackScreen)) {
                fallbackScreen = firstEnabledScreen();
            }
            revision += 1;
        }
    }

    Connections {
        target: Quickshell

        function onScreensChanged() {
            state.syncScreens();
        }
    }

    Component.onCompleted: state.syncScreens()
}

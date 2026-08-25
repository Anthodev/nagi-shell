pragma Singleton

import Quickshell
import QtQuick

// Process-wide semantic icon policy. Nagi identity artwork uses a 24 px optical
// grid with 1.75 px rounded strokes. KDE theme icons are reserved for normalized
// operating-system conventions, while application-owned launcher, notification,
// and tray sources pass through untouched. Display sizes are exclusively the
// Theme.size icon scale (14/18/22 logical px).
Singleton {
    id: root

    readonly property string placeholderSource: assetSource("placeholder.svg")
    readonly property string iconSurface: "#080D16"
    property var _warned: ({})

    readonly property var _identityFiles: Object.freeze({
                                                            "back": "navigation-back.svg",
                                                            "launcher": "launcher.svg",
                                                            "history": "notification-bell.svg",
                                                            "tray": "tray.svg",
                                                            "session": "session.svg",
                                                            "restartShell": "restart-shell.svg",
                                                            "wifi": "wifi.svg",
                                                            "bluetooth": "bluetooth.svg",
                                                            "volumeHigh": "volume-high.svg",
                                                            "volumeLow": "volume-low.svg",
                                                            "volumeMuted": "volume-muted.svg",
                                                            "microphone": "microphone.svg",
                                                            "microphoneMuted":
                                                            "microphone-muted.svg",
                                                            "brightness": "brightness.svg",
                                                            "notification": "notification.svg",
                                                            "mediaPrevious": "media-previous.svg",
                                                            "mediaPlay": "media-play.svg",
                                                            "mediaPause": "media-pause.svg",
                                                            "mediaNext": "media-next.svg"
                                                        })
    readonly property var _systemIcons: Object.freeze({
                                                          "settings": "preferences-system",
                                                          "lock": "system-lock-screen",
                                                          "suspend": "system-suspend",
                                                          "logout": "system-log-out",
                                                          "restart": "system-reboot",
                                                          "powerOff": "system-shutdown"
                                                      })
    readonly property var _labels: Object.freeze({
                                                     "back": "Back",
                                                     "launcher": "Launcher",
                                                     "history": "Notification history",
                                                     "tray": "System tray",
                                                     "session": "Session",
                                                     "settings": "System Settings",
                                                     "restartShell": "Restart shell",
                                                     "wifi": "Wi-Fi",
                                                     "bluetooth": "Bluetooth",
                                                     "volumeHigh": "Volume",
                                                     "volumeLow": "Volume",
                                                     "volumeMuted": "Muted volume",
                                                     "microphone": "Microphone",
                                                     "microphoneMuted": "Muted microphone",
                                                     "brightness": "Brightness",
                                                     "notification": "Notification",
                                                     "mediaPrevious": "Previous track",
                                                     "mediaPlay": "Play",
                                                     "mediaPause": "Pause",
                                                     "mediaNext": "Next track",
                                                     "lock": "Lock",
                                                     "suspend": "Suspend",
                                                     "logout": "Log out",
                                                     "restart": "Restart",
                                                     "powerOff": "Power off"
                                                 })
    readonly property var _applicationMeanings: Object.freeze({
                                                                  "application": true,
                                                                  "notificationApplication": true,
                                                                  "trayApplication": true
                                                              })
    readonly property var _states: Object.freeze({
                                                     "normal": true,
                                                     "active": true,
                                                     "off": true,
                                                     "pending": true,
                                                     "attention": true,
                                                     "disabled": true,
                                                     "error": true
                                                 })

    function warnOnce(key, message) {
        if (root._warned[key] === true) {
            return;
        }
        root._warned[key] = true;
        console.warn("Nagi Icons: " + message);
    }

    function assetSource(file) {
        return "file://" + Quickshell.shellPath("assets/icons/nagi/" + file);
    }

    function sizeFor(scale) {
        if (scale === "sm") {
            return Theme.size.iconSizeSm;
        }
        if (scale === "lg") {
            return Theme.size.iconSizeLg;
        }
        return Theme.size.iconSizeMd;
    }

    function readableDynamicTint(candidate) {
        return Theme.hex(Theme.ensureContrast(candidate, root.iconSurface, 4.5, "#FFFFFF"));
    }

    function tintFor(state) {
        switch (state) {
        case "active":
        case "attention":
            return readableDynamicTint(Theme.snapshot.accent);
        case "pending":
            return Theme.color.warning;
        case "error":
            return Theme.color.danger;
        default:
            return Theme.color.textPrimary;
        }
    }

    function identityMeaning(meaning, state) {
        if (meaning === "wifi" && state === "off") {
            return "wifiOff";
        }
        if (meaning === "bluetooth" && state === "off") {
            return "bluetoothOff";
        }
        return meaning;
    }

    function identityFile(meaning, state) {
        const resolvedMeaning = identityMeaning(meaning, state);
        if (resolvedMeaning === "wifiOff") {
            return "wifi-off.svg";
        }
        if (resolvedMeaning === "bluetoothOff") {
            return "bluetooth-off.svg";
        }
        return root._identityFiles[resolvedMeaning] ?? "";
    }

    function fallback(meaning, state, reason) {
        root.warnOnce("resolution:" + reason,
                      "invalid semantic icon request; using the neutral placeholder");
        return Object.freeze({
                                 "meaning": meaning,
                                 "state": state,
                                 "kind": "placeholder",
                                 "source": root.placeholderSource,
                                 "tint": Theme.color.textPrimary,
                                 "tintable": true,
                                 "attention": false,
                                 "disabled": state === "disabled",
                                 "accessibleName": "Icon"
                             });
    }

    function resolve(meaning, state, applicationSource, applicationName) {
        const requestedState = state ?? "normal";
        if (typeof meaning !== "string" || meaning === "" || root._states[requestedState]
                !== true) {

            return fallback(String(meaning ?? ""), requestedState, "request");
        }

        if (root._applicationMeanings[meaning] === true) {
            if (typeof applicationSource !== "string" || applicationSource === "") {
                return fallback(meaning, requestedState, "application-source");
            }
            return Object.freeze({
                                     "meaning": meaning,
                                     "state": requestedState,
                                     "kind": "application",
                                     "source": applicationSource,
                                     "tint": "transparent",
                                     "tintable": false,
                                     "attention": requestedState === "attention",
                                     "disabled": requestedState === "disabled",
                                     "accessibleName": typeof applicationName === "string"
                                                       && applicationName !== "" ? applicationName :
                                                                                   "Application"
                                 });
        }

        const file = identityFile(meaning, requestedState);
        if (file !== "") {
            return Object.freeze({
                                     "meaning": meaning,
                                     "state": requestedState,
                                     "kind": "nagi",
                                     "source": assetSource(file),
                                     "tint": tintFor(requestedState),
                                     "tintable": true,
                                     "attention": requestedState === "attention",
                                     "disabled": requestedState === "disabled",
                                     "accessibleName": root._labels[meaning]
                                 });
        }

        const systemIcon = root._systemIcons[meaning] ?? "";
        if (systemIcon !== "") {
            const source = Quickshell.iconPath(systemIcon);
            if (source === "") {
                return fallback(meaning, requestedState, "system-theme");
            }
            return Object.freeze({
                                     "meaning": meaning,
                                     "state": requestedState,
                                     "kind": "system",
                                     "source": source,
                                     "tint": tintFor(requestedState),
                                     // preferences-system is commonly a full-color application
                                     // icon; colorizing its opaque plate destroys its identity.
                                     "tintable": meaning !== "settings",
                                     "attention": requestedState === "attention",
                                     "disabled": requestedState === "disabled",
                                     "accessibleName": root._labels[meaning]
                                 });
        }

        return fallback(meaning, requestedState, "meaning");
    }

    function reportLoadFailure(meaning, kind) {
        warnOnce("load:" + kind + ":" + meaning,
                 "an icon source failed to load; using the neutral placeholder");
    }
}

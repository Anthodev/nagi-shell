pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

// Presentation-wide reduced-motion preference.
//
// KDE exposes the user's animation speed as kdeglobals [KDE]
// AnimationDurationFactor; zero or less means animations are effectively
// disabled. The file is read once and watched afterwards, so preference
// changes arrive event-driven with no polling. Absent, unreadable, or
// malformed configuration keeps motion enabled rather than guessing.
Scope {
    id: motion

    // Verification seam following the injected-dependency pattern: tests
    // point this at a temporary settings file. Production leaves it unset.
    property string configPath: ""

    readonly property string resolvedPath: configPath !== "" ? configPath : (Quickshell.env(
                                                                                 "XDG_CONFIG_HOME")
                                                                             ?? "") !== ""
                                                               ? Quickshell.env("XDG_CONFIG_HOME")
                                                                 + "/kdeglobals" : Quickshell.env(
                                                                     "HOME") + "/.config/kdeglobals"

    // True when the confirmed animation factor disables motion. The binding
    // re-evaluates through textChanged after every load or reload.
    readonly property bool active: parseFactor(settings.text()) <= 0

    function parseFactor(content) {
        const fallback = 1;
        if (typeof content !== "string" || content.length === 0 || content.length > 1048576) {
            return fallback;
        }

        let inKdeGroup = false;
        const lines = content.split("\n");
        for (let index = 0; index < lines.length; index += 1) {
            const line = lines[index].trim();
            if (line.startsWith("[") && line.endsWith("]")) {
                inKdeGroup = line === "[KDE]";
                continue;
            }
            if (!inKdeGroup) {
                continue;
            }

            const separator = line.indexOf("=");
            if (separator <= 0 || line.slice(0, separator).trim() !== "AnimationDurationFactor") {
                continue;
            }

            const value = Number(line.slice(separator + 1).trim());
            return Number.isFinite(value) ? value : fallback;
        }

        return fallback;
    }

    FileView {
        id: settings

        path: motion.resolvedPath
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
    }
}

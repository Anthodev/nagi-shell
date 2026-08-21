import Quickshell
import QtQuick
import "qml"

// Gallery harness: renders every core primitive inside the real island
// surface and asserts their observable contracts (token resolution, state
// visuals driven by focus reasons, disabled flattening, progress clamping).
ShellRoot {
    id: test

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function traversalReaches(start, target) {
        let cursor = start;
        for (let hop = 0; hop < 8 && cursor !== null; hop += 1) {
            cursor = cursor.nextItemInFocusChain(true);
            if (cursor === target) {
                return true;
            }
        }
        return false;
    }

    function runChecks() {
        require(typeof Theme.color.surface !== "undefined", "color tokens resolve");
        require(typeof Theme.spacing.md === "number", "spacing tokens resolve");
        require(typeof Theme.radius.pill === "number", "radius tokens resolve");
        require(typeof Theme.type.body === "number", "typography tokens resolve");
        require(typeof Theme.size.controlHeightMd === "number", "sizing tokens resolve");
        require(typeof Theme.opacity.disabled === "number", "opacity tokens resolve");
        require(typeof Theme.motion.durationNormal === "number", "motion tokens resolve");

        require(String(primaryText.color) !== String(secondaryText.color),
                "primary tone differs from secondary");
        require(String(secondaryText.color) !== String(mutedText.color),
                "secondary tone differs from muted");
        require(String(primaryText.color) !== String(mutedText.color),
                "primary tone differs from muted");

        standardButton.forceActiveFocus(Qt.TabFocusReason);
        require(standardButton.activeFocus, "enabled button takes keyboard focus");
        require(standardButton.visualFocus, "keyboard focus reason drives the visible ring");
        accentButton.forceActiveFocus(Qt.MouseFocusReason);
        require(!standardButton.visualFocus, "focus loss clears the keyboard ring");
        require(accentButton.activeFocus && !accentButton.visualFocus,
                "pointer focus does not draw the keyboard ring");

        disabledButton.forceActiveFocus(Qt.TabFocusReason);
        require(!disabledButton.activeFocus, "disabled button refuses focus");
        require(!disabledButton.enabled, "disabled button reports the disabled state");
        require(String(disabledButton.background.color) === String(Theme.color.controlFill),
                "disabled button keeps the resting fill");

        require(traversalReaches(standardButton, accentButton),
                "keyboard traversal reaches the accent button");
        require(traversalReaches(accentButton, iconButton),
                "keyboard traversal reaches the icon button");

        determinateProgress.value = 1.7;
        require(determinateProgress.effectiveValue === 1, "progress clamps above the range");
        determinateProgress.value = -0.5;
        require(determinateProgress.effectiveValue === 0, "progress clamps below the range");
        determinateProgress.value = 0.4;

        require(indeterminateProgress.indeterminate, "indeterminate progress reports its mode");
        require(iconButton.implicitWidth === iconButton.implicitHeight,
                "icon button stays circular");
        console.log("island ui primitive tests passed");

        if (Quickshell.env("NAGI_UI_HOLD") === "1") {
            standardButton.forceActiveFocus(Qt.TabFocusReason);
            console.log("holding for visual inspection");
            return;
        }

        Qt.exit(0);
    }

    Component.onCompleted: Qt.callLater(test.runChecks)

    IslandStateCoordinator {
        id: coordinator
    }

    IslandSurface {
        id: surface

        coordinator: coordinator
        hostSurfaceGeneration: 0
        implicitWidth: 640
        implicitHeight: 360

        Column {
            anchors.centerIn: parent
            spacing: Theme.spacing.lg

            Row {
                spacing: Theme.spacing.xl

                IslandText {
                    id: primaryText

                    text: "Primary"
                    tone: "primary"
                }

                IslandText {
                    id: secondaryText

                    text: "Secondary"
                    tone: "secondary"
                    size: "caption"
                }

                IslandText {
                    id: mutedText

                    text: "Muted"
                    tone: "muted"
                    size: "caption"
                }
            }

            Row {
                spacing: Theme.spacing.md

                IslandButton {
                    id: standardButton

                    label: "Standard"
                }

                IslandButton {
                    id: accentButton

                    label: "Accent"
                    variant: "accent"
                }

                IslandButton {
                    label: "Danger"
                    variant: "danger"
                }

                IslandButton {
                    id: disabledButton

                    enabled: false
                    label: "Disabled"
                }
            }

            Row {
                spacing: Theme.spacing.md

                IslandIconButton {
                    id: iconButton

                    label: "Example action"
                    size: "md"
                    source: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16'><rect x='2' y='2' width='12' height='12' rx='3' fill='%23EFF3F8'/></svg>"
                }

                IslandIconButton {
                    enabled: false
                    label: "Disabled action"
                    size: "sm"
                    source: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16'><circle cx='8' cy='8' r='6' fill='%23B9C4D2'/></svg>"
                }

                IslandIconButton {
                    label: "Large action"
                    size: "lg"
                    source: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16'><path d='M3 13 L13 13 L8 4 Z' fill='%237AA2F7'/></svg>"
                }
            }

            IslandProgressBar {
                id: determinateProgress

                indeterminate: false
                label: "Determinate example"
                value: 0.4
                width: 240
            }

            IslandProgressBar {
                id: indeterminateProgress

                indeterminate: true
                label: "Indeterminate example"
                width: 240
            }
        }
    }
}

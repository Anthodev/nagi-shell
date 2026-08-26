pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root

    required property var settingsModel
    property bool reducedMotion: false
    property string validationText: ""

    clip: true
    contentWidth: width
    contentHeight: content.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {
        policy: root.contentHeight > root.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
    }

    function request(changes, continuous) {
        const appearance = Object.assign({}, settingsModel.snapshot.appearance, changes);
        const validation = settingsModel.appearanceValidationError(appearance);
        if (validation !== "") {
            validationText = validation;
            return false;
        }
        if (!settingsModel.updatePage("appearance", changes, continuous === true)) {
            validationText = settingsModel.errorMessage !== "" ? settingsModel.errorMessage :
                                                                 "The appearance change could not be applied.";
            return false;
        }
        validationText = "";
        return true;
    }

    ColumnLayout {
        id: content

        width: root.width - (root.contentHeight > root.height ? Theme.spacing.md : 0)
        spacing: Theme.spacing.md

        IslandText {
            text: "Appearance"
            size: "title"
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }

        IslandText {
            Layout.fillWidth: true
            text: "Choose one maintained semantic scheme. Nagi derives every component state from the same validated palette."
            size: "body"
            color: Theme.color.textSecondary
            wrapMode: Text.Wrap
        }

        SettingChoiceRow {
            Layout.fillWidth: true
            label: "Scheme"
            description: "Select the maintained surface and text foundation."
            value: root.settingsModel.snapshot.appearance.scheme
            choices: [
                {
                    "label": "Nagi Dark",
                    "value": "nagi-dark"
                },
                {
                    "label": "Nagi OLED",
                    "value": "nagi-oled"
                },
                {
                    "label": "Nagi Light",
                    "value": "nagi-light"
                },
                {
                    "label": "System",
                    "value": "system"
                },
                {
                    "label": "Custom",
                    "value": "custom"
                }
            ]
            writable: root.settingsModel.writable
            reducedMotion: root.reducedMotion
            onValueRequested: value => root.request({
                                                        "scheme": value
                                                    }, false)
        }

        SettingChoiceRow {
            Layout.fillWidth: true
            label: "Accent"
            description: "Use Nagi, KDE, the current wallpaper, or a validated custom accent."
            value: root.settingsModel.snapshot.appearance.accentMode
            choices: [
                {
                    "label": "Nagi",
                    "value": "nagi"
                },
                {
                    "label": "System",
                    "value": "system"
                },
                {
                    "label": "Wallpaper",
                    "value": "wallpaper"
                },
                {
                    "label": "Custom",
                    "value": "custom"
                }
            ]
            writable: root.settingsModel.writable
            reducedMotion: root.reducedMotion
            onValueRequested: value => root.request({
                                                        "accentMode": value
                                                    }, false)
        }

        SettingColorRow {
            Layout.fillWidth: true
            visible: root.settingsModel.snapshot.appearance.scheme === "custom"
            label: "Primary surface"
            description: "Custom base used to derive shallow surfaces and controls."
            value: root.settingsModel.snapshot.appearance.customSurface
            writable: root.settingsModel.writable
            validationText: root.validationText
            onValueRequested: value => root.request({
                                                        "customSurface": value
                                                    }, false)
        }

        SettingColorRow {
            Layout.fillWidth: true
            visible: root.settingsModel.snapshot.appearance.scheme === "custom"
            label: "Primary text"
            description: "Must retain readable contrast against the custom surface."
            value: root.settingsModel.snapshot.appearance.customText
            writable: root.settingsModel.writable
            validationText: root.validationText
            onValueRequested: value => root.request({
                                                        "customText": value
                                                    }, false)
        }

        SettingColorRow {
            Layout.fillWidth: true
            visible: root.settingsModel.snapshot.appearance.accentMode === "custom"
            label: "Custom accent"
            description: "State roles and readable foregrounds are derived from this input."
            value: root.settingsModel.snapshot.appearance.customAccent
            allowAlpha: true
            writable: root.settingsModel.writable
            validationText: root.validationText
            onValueRequested: value => root.request({
                                                        "customAccent": value
                                                    }, false)
        }

        SettingSliderRow {
            Layout.fillWidth: true
            label: "Surface opacity"
            description: "Readable outer-surface opacity from 85 to 100 percent."
            value: root.settingsModel.snapshot.appearance.surfaceOpacity
            from: 0.85
            to: 1
            stepSize: 0.01
            valueText: Math.round(value * 100) + "%"
            writable: root.settingsModel.writable
            onValueRequested: (value, continuous) => root.request({
                                                                      "surfaceOpacity": value
                                                                  }, continuous)
        }

        SettingSliderRow {
            Layout.fillWidth: true
            label: "Border intensity"
            description: "Adds bounded outer separation without changing component hierarchy."
            value: root.settingsModel.snapshot.appearance.borderIntensity
            from: 0
            to: 1
            stepSize: 0.1
            valueText: Math.round(value * 100) + "%"
            writable: root.settingsModel.writable
            onValueRequested: (value, continuous) => root.request({
                                                                      "borderIntensity": value
                                                                  }, continuous)
        }

        SettingToggleRow {
            Layout.fillWidth: true
            label: "Background blur"
            description:
            "Ask KWin for blur when its Wayland effect is available; otherwise keep the cheaper translucent surface."
            value: root.settingsModel.snapshot.appearance.blurEnabled
            writable: root.settingsModel.writable
            onValueRequested: value => root.request({
                                                        "blurEnabled": value
                                                    }, false)
        }

        SettingChoiceRow {
            Layout.fillWidth: true
            label: "Motion"
            description: "KDE accessibility preferences can only make this choice more restrictive."
            value: root.settingsModel.snapshot.appearance.motion
            choices: [
                {
                    "label": "Full",
                    "value": "full"
                },
                {
                    "label": "Reduced",
                    "value": "reduced"
                },
                {
                    "label": "Minimal",
                    "value": "minimal"
                }
            ]
            writable: root.settingsModel.writable
            reducedMotion: root.reducedMotion
            onValueRequested: value => root.request({
                                                        "motion": value
                                                    }, false)
        }

        SettingSliderRow {
            Layout.fillWidth: true
            label: "Outer radius"
            description: "Keep the island softly rectangular across compact and expanded states."
            value: root.settingsModel.snapshot.appearance.outerRadius
            from: 8
            to: 32
            stepSize: 2
            valueText: Math.round(value) + " px"
            writable: root.settingsModel.writable
            onValueRequested: (value, continuous) => root.request({
                                                                      "outerRadius": value
                                                                  }, continuous)
        }

        IslandText {
            Layout.fillWidth: true
            visible: root.validationText !== ""
            text: root.validationText
            size: "caption"
            color: Theme.color.danger
            wrapMode: Text.Wrap
            Accessible.role: Accessible.AlertMessage
            Accessible.name: text
        }

        SettingsResetActions {
            Layout.fillWidth: true
            pageId: "appearance"
            writable: root.settingsModel.writable
            errorText: root.settingsModel.status === "write-failed"
                       ? root.settingsModel.errorMessage : ""
            reducedMotion: root.reducedMotion
            onResetPageRequested: pageId => root.settingsModel.resetPage(pageId)
            onResetAllRequested: root.settingsModel.resetAll()
        }
    }
}

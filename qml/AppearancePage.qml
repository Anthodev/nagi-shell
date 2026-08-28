pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root

    required property var settingsModel
    property bool reducedMotion: false
    property string validationText: ""
    readonly property var installedFontFamilies: {
        const families = Qt.fontFamilies();
        const accepted = [];
        for (let index = 0; index < families.length; index += 1) {
            const family = families[index];
            if (settingsModel.boundedString(family, settingsModel.maximumFontFamilyBytes, false)) {
                accepted.push(family);
            }
        }
        accepted.sort((first, second) => first.localeCompare(second));
        return Object.freeze(accepted);
    }

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
    component TypographyScopeControls: ColumnLayout {
        id: scopeControl

        required property string scopeLabel
        required property string familyKey
        required property string sizeKey
        required property string selectorObjectName
        required property string sizeObjectName
        property bool separated: true

        Layout.fillWidth: true
        spacing: Theme.spacing.sm

        readonly property string configuredFamily: root.settingsModel.snapshot.appearance[familyKey]
        readonly property int selectedFamilyIndex: root.installedFontFamilies.indexOf(
                                                       configuredFamily)
        readonly property bool configuredFamilyInstalled: selectedFamilyIndex >= 0

        ControlCenterSectionHeading {
            objectName: scopeControl.selectorObjectName + "Section"
            text: scopeControl.scopeLabel
            separated: scopeControl.separated
        }

        ControlCenterSettingRow {
            id: fontFamilyRow
            Layout.fillWidth: true
            label: "Font family"
            description: scopeControl.configuredFamilyInstalled
                         ? "Choose from the font families installed on this system." :
                           "The configured family is unavailable. Choose an installed font to replace it."

            ComboBox {
                id: fontFamilySelector

                objectName: scopeControl.selectorObjectName
                width: 280
                implicitHeight: Theme.size.controlHeightLg
                model: root.installedFontFamilies
                currentIndex: scopeControl.selectedFamilyIndex
                displayText: currentIndex >= 0 ? currentText : scopeControl.configuredFamily
                                                 + " (unavailable)"
                enabled: root.settingsModel.writable && count > 0
                hoverEnabled: true
                focusPolicy: Qt.StrongFocus
                opacity: enabled ? 1 : Theme.opacity.disabled
                font.family: currentIndex >= 0 ? currentText : Theme.type.familyFor("controlCenter")
                font.pixelSize: Theme.type.sizeFor("controlCenter", "body")
                palette.button: Theme.color.controlFill
                palette.buttonText: Theme.color.textPrimary
                palette.base: Theme.color.surfaceOpaque
                palette.text: Theme.color.textPrimary
                palette.window: Theme.color.surfaceOpaque
                palette.windowText: Theme.color.textPrimary
                palette.highlight: Theme.snapshot.accent
                palette.highlightedText: Theme.snapshot.accentForeground
                palette.mid: Theme.color.surfaceBorder
                palette.dark: Theme.color.surfaceBorder
                Accessible.role: Accessible.ComboBox
                Accessible.name: scopeControl.scopeLabel + " font family"
                Accessible.description: fontFamilyRow.description
                onActivated: index => {
                    const changes = {};
                    changes[scopeControl.familyKey] = root.installedFontFamilies[index];
                    root.request(changes, false);
                }

                IslandFocusRing {
                    visible: fontFamilySelector.visualFocus
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    enabled: fontFamilySelector.enabled
                }
            }
        }

        SettingSliderRow {
            Layout.fillWidth: true
            objectName: scopeControl.sizeObjectName
            label: scopeControl.scopeLabel + " default size"
            description:
            "Sets body text from 11 to 18 px. Titles, captions, and muted text keep their semantic proportions."
            value: root.settingsModel.snapshot.appearance[scopeControl.sizeKey]
            from: root.settingsModel.minimumBaseFontSize
            to: root.settingsModel.maximumBaseFontSize
            stepSize: 1
            valueText: Math.round(value) + " px"
            writable: root.settingsModel.writable
            onValueRequested: (value, continuous) => {
                const changes = {};
                changes[scopeControl.sizeKey] = value;
                root.request(changes, continuous);
            }
        }
    }

    ColumnLayout {
        id: content

        width: Math.min(root.width - (root.contentHeight > root.height ? Theme.spacing.md : 0),
                        Theme.size.controlCenterContentMaximumWidth)
        spacing: Theme.spacing.md

        IslandText {
            text: "Appearance"
            objectName: "appearancePageTitle"
            size: "title"
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }

        IslandText {
            Layout.fillWidth: true
            text: "Set an installed family and default body size independently for each Nagi surface. Semantic text roles preserve their hierarchy."
            size: "body"
            color: Theme.color.textSecondary
            wrapMode: Text.Wrap
        }

        TypographyScopeControls {
            scopeLabel: "Idle island"
            familyKey: "idleFontFamily"
            sizeKey: "idleBaseFontSize"
            selectorObjectName: "appearanceIdleFontFamily"
            sizeObjectName: "appearanceIdleBaseFontSize"
            separated: false
        }

        TypographyScopeControls {
            scopeLabel: "Expanded island"
            familyKey: "expandedFontFamily"
            sizeKey: "expandedBaseFontSize"
            selectorObjectName: "appearanceExpandedFontFamily"
            sizeObjectName: "appearanceExpandedBaseFontSize"
        }

        TypographyScopeControls {
            scopeLabel: "Control Center"
            familyKey: "controlCenterFontFamily"
            sizeKey: "controlCenterBaseFontSize"
            selectorObjectName: "appearanceControlCenterFontFamily"
            sizeObjectName: "appearanceControlCenterBaseFontSize"
        }

        ControlCenterSectionHeading {
            objectName: "appearanceColorSection"
            text: "Color"
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

        ControlCenterSectionHeading {
            objectName: "appearanceSurfaceMotionSection"
            text: "Surface & motion"
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

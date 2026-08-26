pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root

    required property var settingsModel
    required property var media
    property bool reducedMotion: false
    property string failureText: ""

    readonly property var playerChoices: {
        const result = [
            {
                "label": "Automatic",
                "value": ""
            }
        ];
        const applications = media.availableApplications ?? [];
        let selectedPresent = settingsModel.snapshot.media.preferredApplication === "";
        for (let index = 0; index < applications.length; ++index) {
            result.push(applications[index]);
            selectedPresent = selectedPresent || applications[index].value
            === settingsModel.snapshot.media.preferredApplication;
        }
        if (!selectedPresent) {
            result.push({
                            "label": settingsModel.snapshot.media.preferredApplication
                                     + " (inactive)",
                            "value": settingsModel.snapshot.media.preferredApplication
                        });
        }
        return result;
    }
    readonly property string selectedPlayerValue: settingsModel.snapshot.media.playerPolicy
                                                  === "automatic" ? "" :
                                                                    settingsModel.snapshot.media.preferredApplication

    clip: true
    contentWidth: width
    contentHeight: content.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {
        policy: root.contentHeight > root.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
    }

    function request(changes) {
        if (settingsModel.updatePage("media", changes, false)) {
            failureText = "";
            return true;
        }
        failureText = settingsModel.errorMessage !== "" ? settingsModel.errorMessage :
                                                          "The media change could not be applied.";
        return false;
    }

    function selectedPlayerIndex() {
        for (let index = 0; index < playerChoices.length; ++index) {
            if (playerChoices[index].value === selectedPlayerValue) {
                return index;
            }
        }
        return 0;
    }

    ColumnLayout {
        id: content

        width: root.width - (root.contentHeight > root.height ? Theme.spacing.md : 0)
        spacing: Theme.spacing.md

        IslandText {
            text: "Media"
            size: "title"
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }

        IslandText {
            Layout.fillWidth: true
            text: "Choose where the one shared MPRIS selection appears. Disabling Media disconnects player observation and clears artwork and timing work."
            size: "body"
            color: Theme.color.textSecondary
            wrapMode: Text.Wrap
        }

        SettingToggleRow {
            Layout.fillWidth: true
            label: "Media integration"
            description: "Observe compatible MPRIS players for this session."
            value: root.settingsModel.snapshot.media.enabled
            writable: root.settingsModel.writable
            onValueRequested: value => root.request({
                                                        "enabled": value
                                                    })
        }

        SettingToggleRow {
            Layout.fillWidth: true
            label: "Compact media"
            description: "Show the selected track in Idle when available."
            value: root.settingsModel.snapshot.media.compactVisible
            writable: root.settingsModel.writable
            onValueRequested: value => root.request({
                                                        "compactVisible": value
                                                    })
        }

        SettingToggleRow {
            Layout.fillWidth: true
            label: "Dashboard media"
            description: "Show artwork, metadata, timing, and controls in Expanded."
            value: root.settingsModel.snapshot.media.dashboardVisible
            writable: root.settingsModel.writable
            onValueRequested: value => root.request({
                                                        "dashboardVisible": value
                                                    })
        }

        ControlCenterSettingRow {
            Layout.fillWidth: true
            label: "Player policy"
            description:
            "Automatic keeps the newest-playing policy. A preferred application wins while relevant and otherwise falls back automatically."

            ComboBox {
                id: playerPolicy

                model: root.playerChoices
                textRole: "label"
                valueRole: "value"
                currentIndex: root.selectedPlayerIndex()
                enabled: root.settingsModel.writable && root.settingsModel.snapshot.media.enabled
                Accessible.role: Accessible.ComboBox
                Accessible.name: "Media player policy"
                Accessible.description:
                "Automatic preserves recency; a relevant preferred application wins."
                onActivated: index => {
                    const value = root.playerChoices[index].value;
                    root.request(value === "" ? {
                                                    "playerPolicy": "automatic"
                                                } : {
                                     "playerPolicy": "preferred",
                                     "preferredApplication": value
                                 });
                }
            }
        }

        IslandText {
            Layout.fillWidth: true
            visible: !root.settingsModel.snapshot.media.enabled
            text: "Player selection is unavailable while the integration is disabled."
            size: "caption"
            color: Theme.color.textMuted
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        IslandText {
            Layout.fillWidth: true
            visible: root.failureText !== ""
            text: root.failureText
            size: "caption"
            color: Theme.color.danger
            wrapMode: Text.Wrap
            Accessible.role: Accessible.AlertMessage
            Accessible.name: text
        }

        SettingsResetActions {
            Layout.fillWidth: true
            pageId: "media"
            writable: root.settingsModel.writable
            errorText: root.settingsModel.status === "write-failed"
                       ? root.settingsModel.errorMessage : ""
            reducedMotion: root.reducedMotion
            onResetPageRequested: pageId => root.settingsModel.resetPage(pageId)
            onResetAllRequested: root.settingsModel.resetAll()
        }
    }
}

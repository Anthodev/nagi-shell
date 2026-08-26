pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root

    required property var settingsModel
    required property var clock
    property bool reducedMotion: false
    property string failureText: ""

    clip: true
    contentWidth: width
    contentHeight: content.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {
        policy: root.contentHeight > root.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
    }

    function request(changes) {
        if (settingsModel.updatePage("clock", changes, false)) {
            failureText = "";
            return true;
        }
        failureText = settingsModel.errorMessage !== "" ? settingsModel.errorMessage :
                                                          "The clock change could not be applied.";
        return false;
    }

    ColumnLayout {
        id: content

        width: root.width - (root.contentHeight > root.height ? Theme.spacing.md : 0)
        spacing: Theme.spacing.md

        IslandText {
            text: "Clock & Date"
            size: "title"
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }

        IslandText {
            Layout.fillWidth: true
            text: "One shared clock updates Idle, Expanded, and this preview. Timezone, network time, and the system clock remain managed by KDE."
            size: "body"
            color: Theme.color.textSecondary
            wrapMode: Text.Wrap
        }

        IslandPanel {
            Layout.fillWidth: true
            implicitHeight: previewColumn.implicitHeight + Theme.spacing.lg * 2
            color: Theme.color.controlFill

            ColumnLayout {
                id: previewColumn

                anchors.fill: parent
                anchors.margins: Theme.spacing.lg
                spacing: Theme.spacing.xs

                IslandText {
                    Layout.fillWidth: true
                    text: root.clock.text
                    size: "display"
                    horizontalAlignment: Text.AlignHCenter
                    Accessible.name: "Clock preview " + text
                }

                IslandText {
                    Layout.fillWidth: true
                    text: root.clock.dateText
                    size: "body"
                    color: Theme.color.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    Accessible.name: "Date preview " + text
                }
            }
        }

        SettingChoiceRow {
            Layout.fillWidth: true
            label: "Time format"
            description: "Follow the current locale or force a 12-hour or 24-hour clock."
            value: root.settingsModel.snapshot.clock.format
            choices: [
                {
                    "label": "Auto",
                    "value": "auto"
                },
                {
                    "label": "12-hour",
                    "value": "12h"
                },
                {
                    "label": "24-hour",
                    "value": "24h"
                }
            ]
            writable: root.settingsModel.writable
            reducedMotion: root.reducedMotion
            onValueRequested: value => root.request({
                                                        "format": value
                                                    })
        }

        SettingToggleRow {
            Layout.fillWidth: true
            label: "Show seconds"
            description:
            "Use the single shared second-level schedule while a Nagi surface is visible."
            value: root.settingsModel.snapshot.clock.showSeconds
            writable: root.settingsModel.writable
            onValueRequested: value => root.request({
                                                        "showSeconds": value
                                                    })
        }

        SettingToggleRow {
            Layout.fillWidth: true
            label: "Date in compact clock"
            description: "Show the configured date beside the mandatory compact clock."
            value: root.settingsModel.snapshot.clock.showIdleDate
            writable: root.settingsModel.writable
            onValueRequested: value => root.request({
                                                        "showIdleDate": value
                                                    })
        }

        SettingChoiceRow {
            Layout.fillWidth: true
            label: "Date format"
            description: "Choose one validated, locale-safe presentation pattern."
            value: root.settingsModel.snapshot.clock.dateFormat
            choices: [
                {
                    "label": "Full",
                    "value": "dddd, d MMMM"
                },
                {
                    "label": "Compact",
                    "value": "ddd, d MMM"
                },
                {
                    "label": "ISO",
                    "value": "yyyy-MM-dd"
                },
                {
                    "label": "Month first",
                    "value": "MM/dd/yyyy"
                },
                {
                    "label": "Day first",
                    "value": "dd/MM/yyyy"
                }
            ]
            writable: root.settingsModel.writable
            reducedMotion: root.reducedMotion
            onValueRequested: value => root.request({
                                                        "dateFormat": value
                                                    })
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
            pageId: "clock"
            writable: root.settingsModel.writable
            errorText: root.settingsModel.status === "write-failed"
                       ? root.settingsModel.errorMessage : ""
            reducedMotion: root.reducedMotion
            onResetPageRequested: pageId => root.settingsModel.resetPage(pageId)
            onResetAllRequested: root.settingsModel.resetAll()
        }
    }
}

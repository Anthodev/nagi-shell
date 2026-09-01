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
        failureText = settingsModel.errorMessage !== "" ? settingsModel.errorMessage : qsTr(
                                                              "The clock change could not be applied.");
        return false;
    }

    ColumnLayout {
        id: content

        width: Math.min(root.width - (root.contentHeight > root.height ? Theme.spacing.md : 0),
                        Theme.size.controlCenterContentMaximumWidth)
        spacing: Theme.spacing.md

        ControlCenterPageHeader {
            objectName: "clockPageHeader"
            Layout.fillWidth: true
            iconMeaning: "controlCenterClock"
            title: qsTr("Clock & Date")
            description: qsTr("Choose how Nagi displays the time and date.")
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
                    Accessible.name: qsTr("Clock preview: %1").arg(text)
                }

                IslandText {
                    Layout.fillWidth: true
                    text: root.clock.dateText
                    size: "body"
                    color: Theme.color.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    Accessible.name: qsTr("Date preview: %1").arg(text)
                }
            }
        }

        ControlCenterSectionHeading {
            objectName: "clockPresentationSection"
            text: qsTr("Presentation")
        }

        SettingChoiceRow {
            Layout.fillWidth: true
            label: qsTr("Time format")
            description: qsTr("Follow the current locale or force a 12-hour or 24-hour clock.")
            value: root.settingsModel.snapshot.clock.format
            choices: [
                {
                    "label": qsTr("Auto"),
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
            label: qsTr("Show seconds")
            description: qsTr(
                             "Use the single shared second-level schedule while a Nagi surface is visible.")
            value: root.settingsModel.snapshot.clock.showSeconds
            writable: root.settingsModel.writable
            onValueRequested: value => root.request({
                                                        "showSeconds": value
                                                    })
        }

        SettingToggleRow {
            Layout.fillWidth: true
            label: qsTr("Date in compact clock")
            description: qsTr("Show the configured date beside the mandatory compact clock.")
            value: root.settingsModel.snapshot.clock.showIdleDate
            writable: root.settingsModel.writable
            onValueRequested: value => root.request({
                                                        "showIdleDate": value
                                                    })
        }

        SettingChoiceRow {
            Layout.fillWidth: true
            label: qsTr("Date format")
            description: qsTr("Choose one validated, locale-safe presentation pattern.")
            value: root.settingsModel.snapshot.clock.dateFormat
            choices: [
                {
                    "label": qsTr("Full"),
                    "value": "dddd, d MMMM"
                },
                {
                    "label": qsTr("Compact"),
                    "value": "ddd, d MMM"
                },
                {
                    "label": "ISO",
                    "value": "yyyy-MM-dd"
                },
                {
                    "label": qsTr("Month first"),
                    "value": "MM/dd/yyyy"
                },
                {
                    "label": qsTr("Day first"),
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

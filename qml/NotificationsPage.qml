pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root

    required property var settingsModel
    required property var notificationService
    property bool reducedMotion: false
    property string failureText: ""

    clip: true
    contentWidth: width
    contentHeight: content.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {
        policy: root.contentHeight > root.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
    }

    function request(page, changes) {
        if (settingsModel.updatePage(page, changes, false)) {
            failureText = "";
            return true;
        }
        failureText = settingsModel.errorMessage !== "" ? settingsModel.errorMessage : qsTr(
                                                              "The notification change could not be applied.");
        return false;
    }
    function resetPageSettings() {
        const defaults = settingsModel.defaultSnapshot(0);
        if (!settingsModel.updatePage("notifications", Object.assign({}, defaults.notifications),
                                      false) || !settingsModel.updatePage("island", {
                                                                              "feedbackDuration":
                                                                              defaults.island.feedbackDuration
                                                                          }, false)) {
            failureText = settingsModel.errorMessage !== "" ? settingsModel.errorMessage : qsTr(
                                                                  "The notification defaults could not be restored.");
            return false;
        }
        failureText = "";
        return true;
    }

    ColumnLayout {
        id: content

        width: Math.min(root.width - (root.contentHeight > root.height ? Theme.spacing.md : 0),
                        Theme.size.controlCenterContentMaximumWidth)
        spacing: Theme.spacing.md

        ControlCenterPageHeader {
            objectName: "notificationsPageHeader"
            Layout.fillWidth: true
            iconMeaning: "controlCenterNotifications"
            title: qsTr("Notifications")
            description: qsTr(
                             "Choose when notification popups appear and what Nagi keeps in session history.")
        }

        ControlCenterSectionHeading {
            objectName: "notificationsPopupPolicySection"
            text: qsTr("Popup policy")
            separated: false
        }

        SettingToggleRow {
            Layout.fillWidth: true
            label: qsTr("Notification popups")
            description: qsTr("Allow notification transients on every eligible island.")
            value: root.settingsModel.snapshot.notifications.popupsEnabled
            writable: root.settingsModel.writable
            onValueRequested: value => root.request("notifications", {
                                                        "popupsEnabled": value
                                                    })
        }

        SettingToggleRow {
            Layout.fillWidth: true
            label: qsTr("Do Not Disturb")
            description: qsTr(
                             "Suppress normal and low-urgency notification popups while retaining eligible history.")
            value: root.settingsModel.snapshot.notifications.doNotDisturb
            writable: root.settingsModel.writable
            onValueRequested: value => root.request("notifications", {
                                                        "doNotDisturb": value
                                                    })
        }

        SettingChoiceRow {
            Layout.fillWidth: true
            label: qsTr("Critical notifications")
            description: qsTr(
                             "Let critical notifications bypass Do Not Disturb, or request total notification silence.")
            value: root.settingsModel.snapshot.notifications.criticalMode
            choices: [
                {
                    "label": qsTr("Bypass DND"),
                    "value": "bypass"
                },
                {
                    "label": qsTr("Total silence"),
                    "value": "silence"
                }
            ]
            writable: root.settingsModel.writable
            reducedMotion: root.reducedMotion
            onValueRequested: value => root.request("notifications", {
                                                        "criticalMode": value
                                                    })
        }

        ControlCenterSectionHeading {
            objectName: "notificationsFeedbackSection"
            text: qsTr("Feedback")
        }

        SettingChoiceRow {
            Layout.fillWidth: true
            label: qsTr("Feedback duration")
            description: qsTr(
                             "Scale visible feedback holds without changing freshness, queue, or retention limits.")
            value: root.settingsModel.snapshot.island.feedbackDuration
            choices: [
                {
                    "label": qsTr("Short"),
                    "value": "short"
                },
                {
                    "label": qsTr("Normal"),
                    "value": "normal"
                },
                {
                    "label": qsTr("Long"),
                    "value": "long"
                }
            ]
            writable: root.settingsModel.writable
            reducedMotion: root.reducedMotion
            onValueRequested: value => root.request("island", {
                                                        "feedbackDuration": value
                                                    })
        }

        ControlCenterSectionHeading {
            objectName: "notificationsIslandContentSection"
            text: qsTr("Island content")
        }

        SettingToggleRow {
            Layout.fillWidth: true
            label: qsTr("Dashboard recents")
            description: qsTr("Show the fixed bounded recent subset in Expanded.")
            value: root.settingsModel.snapshot.notifications.dashboardVisible
            writable: root.settingsModel.writable
            onValueRequested: value => root.request("notifications", {
                                                        "dashboardVisible": value
                                                    })
        }

        SettingToggleRow {
            Layout.fillWidth: true
            label: qsTr("History")
            description: qsTr("Show the session-only notification history route in the island.")
            value: root.settingsModel.snapshot.notifications.historyVisible
            writable: root.settingsModel.writable
            onValueRequested: value => root.request("notifications", {
                                                        "historyVisible": value
                                                    })
        }

        ControlCenterSectionHeading {
            objectName: "notificationsHistorySection"
            text: qsTr("History")
        }

        SettingActionRow {
            Layout.fillWidth: true
            label: qsTr("Clear history")
            description: qsTr(
                             "Forget every retained snapshot without closing live protocol notifications or writing to disk.")
            actionLabel: root.notificationService.historyCount === 0 ? qsTr("History empty") : qsTr(
                                                                           "Clear")
            actionVariant: "danger"
            writable: root.notificationService.historyCount > 0
            reducedMotion: root.reducedMotion
            onActionRequested: root.notificationService.clearHistory()
        }

        IslandText {
            Layout.fillWidth: true
            text: qsTr(
                      "Per-application rules and notification actions are unavailable. Actions remain capability-gated by the packaged Quickshell runtime.")
            size: "caption"
            tone: "muted"
            wrapMode: Text.Wrap
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
            pageId: "notifications"
            writable: root.settingsModel.writable
            errorText: root.settingsModel.status === "write-failed"
                       ? root.settingsModel.errorMessage : ""
            reducedMotion: root.reducedMotion
            onResetPageRequested: pageId => root.resetPageSettings()
            onResetAllRequested: root.settingsModel.resetAll()
        }
    }
}

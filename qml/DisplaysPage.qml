pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Flickable {
    id: root

    required property var displayController
    property string failureText: ""
    property bool reducedMotion: false

    clip: true
    contentWidth: width
    contentHeight: content.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Displays settings")
    ScrollBar.vertical: ScrollBar {
        policy: root.contentHeight > root.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
    }

    function activeRows() {
        if (!displayController)
            return [];
        const ignored = displayController.revision;
        return displayController.activeDisplays();
    }

    function requestEnabled(screen, enabled) {
        if (!displayController)
            return;
        if (displayController.setEnabled(screen, enabled)) {
            failureText = "";
            return;
        }
        failureText = displayController.lastFailure;
    }

    function requestFallback(screen) {
        if (!displayController)
            return;
        if (displayController.setFallback(screen)) {
            failureText = "";
            return;
        }
        failureText = displayController.lastFailure;
    }

    ColumnLayout {
        id: content

        width: Math.min(root.width - (root.contentHeight > root.height ? Theme.spacing.md : 0),
                        Theme.size.controlCenterContentMaximumWidth)
        spacing: Theme.spacing.sm

        ControlCenterPageHeader {
            objectName: "displaysPageHeader"
            Layout.fillWidth: true
            iconMeaning: "controlCenterDisplays"
            title: qsTr("Displays")
            description: qsTr(
                             "Choose which displays show Nagi and which enabled display receives global actions by default.")
        }
        ControlCenterSectionPanel {
            objectName: "displaysActiveSection"
            Layout.fillWidth: true
            text: qsTr("Active")
            separated: false
            Accessible.role: Accessible.List

            Repeater {
                id: activeRepeater

                model: root.activeRows()

                delegate: ControlCenterSettingRow {
                    id: activeRow

                    required property int index
                    required property var modelData

                    Layout.fillWidth: true
                    label: modelData.label
                    description: modelData.reliable ? qsTr("Remembered across sessions") : qsTr(
                                                          "Available for this session only")
                    controlPlacement: ControlCenterSettingRow.Auto
                    separatorVisible: index < activeRepeater.count - 1
                    Accessible.role: Accessible.ListItem

                    RowLayout {
                        spacing: Theme.spacing.sm

                        IslandButton {
                            label: activeRow.modelData.enabled ? qsTr("Disable island") : qsTr(
                                                                     "Enable island")
                            reducedMotion: root.reducedMotion
                            enabled: root.displayController && (!activeRow.modelData.enabled
                                                                || root.displayController.enabledDisplayCount
                                                                > 1)
                            onClicked: root.requestEnabled(activeRow.modelData.screen,
                                                           !activeRow.modelData.enabled)
                        }

                        IslandButton {
                            label: activeRow.modelData.fallback ? qsTr("Fallback") : qsTr(
                                                                      "Make fallback")
                            reducedMotion: root.reducedMotion
                            variant: activeRow.modelData.fallback ? "accent" : "standard"
                            enabled: activeRow.modelData.enabled && !activeRow.modelData.fallback
                            onClicked: root.requestFallback(activeRow.modelData.screen)
                        }
                    }
                }
            }
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

        ControlCenterSectionPanel {
            objectName: "displaysRememberedSection"
            Layout.fillWidth: true
            text: qsTr("Remembered")
            Accessible.role: Accessible.List

            IslandText {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing.md
                Layout.bottomMargin: Theme.spacing.md
                visible: !root.displayController
                         || root.displayController.rememberedDisplays.length === 0
                text: qsTr("No disconnected displays can be remembered reliably on this platform.")
                size: "body"
                tone: "muted"
                wrapMode: Text.Wrap
            }

            Repeater {
                id: rememberedRepeater

                model: root.displayController ? root.displayController.rememberedDisplays : []

                delegate: ControlCenterSettingRow {
                    id: rememberedRow

                    required property int index
                    required property var modelData

                    Layout.fillWidth: true
                    label: modelData.label
                    description: qsTr("Disconnected display")
                    controlPlacement: ControlCenterSettingRow.Inline
                    separatorVisible: index < rememberedRepeater.count - 1
                    Accessible.role: Accessible.ListItem

                    IslandButton {
                        label: qsTr("Forget")
                        reducedMotion: root.reducedMotion
                        variant: "danger"
                        Accessible.description: qsTr(
                                                    "Forget this disconnected display after confirmation")
                        onClicked: root.displayController.confirmForget(
                                       rememberedRow.modelData.identity)
                    }
                }
            }
        }
    }
}

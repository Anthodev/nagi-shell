pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property var displayController
    property string failureText: ""
    property bool reducedMotion: false

    spacing: Theme.spacing.md

    function activeRows() {
        const ignored = displayController.revision;
        return displayController.activeDisplays();
    }

    function requestEnabled(screen, enabled) {
        if (displayController.setEnabled(screen, enabled)) {
            failureText = "";
            return;
        }
        failureText = displayController.lastFailure;
    }

    function requestFallback(screen) {
        if (displayController.setFallback(screen)) {
            failureText = "";
            return;
        }
        failureText = displayController.lastFailure;
    }

    IslandText {
        text: "Displays"
        size: "title"
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }

    IslandText {
        Layout.fillWidth: true
        text: "Choose where Nagi islands are visible and which enabled display receives global actions when the pointer has no usable target."
        size: "body"
        color: Theme.color.textSecondary
        wrapMode: Text.Wrap
    }

    Repeater {
        model: root.activeRows()

        delegate: IslandPanel {
            id: activeRow

            required property var modelData

            Layout.fillWidth: true
            implicitHeight: rowLayout.implicitHeight + Theme.spacing.md * 2
            Accessible.role: Accessible.Grouping
            Accessible.name: modelData.label

            RowLayout {
                id: rowLayout

                anchors.fill: parent
                anchors.margins: Theme.spacing.md
                spacing: Theme.spacing.sm

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.xs

                    IslandText {
                        text: activeRow.modelData.label
                        size: "body"
                        font.weight: Theme.type.weightMedium
                    }

                    IslandText {
                        text: activeRow.modelData.reliable ? "Remembered across sessions" :
                                                             "Available for this session only"
                        size: "caption"
                        color: Theme.color.textMuted
                    }
                }

                IslandButton {
                    label: activeRow.modelData.enabled ? "Disable island" : "Enable island"
                    reducedMotion: root.reducedMotion
                    enabled: !activeRow.modelData.enabled
                             || root.displayController.enabledDisplayCount > 1
                    onClicked: root.requestEnabled(activeRow.modelData.screen,
                                                   !activeRow.modelData.enabled)
                }

                IslandButton {
                    label: activeRow.modelData.fallback ? "Fallback" : "Make fallback"
                    reducedMotion: root.reducedMotion
                    variant: activeRow.modelData.fallback ? "accent" : "standard"
                    enabled: activeRow.modelData.enabled && !activeRow.modelData.fallback
                    onClicked: root.requestFallback(activeRow.modelData.screen)
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

    IslandText {
        text: "Remembered"
        size: "title"
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }

    IslandText {
        Layout.fillWidth: true
        visible: root.displayController.rememberedDisplays.length === 0
        text: "No disconnected displays can be remembered reliably on this platform."
        size: "body"
        color: Theme.color.textMuted
        wrapMode: Text.Wrap
    }

    Repeater {
        model: root.displayController.rememberedDisplays

        delegate: IslandPanel {
            id: rememberedRow

            required property var modelData

            Layout.fillWidth: true
            implicitHeight: rememberedLayout.implicitHeight + Theme.spacing.md * 2

            RowLayout {
                id: rememberedLayout

                anchors.fill: parent
                anchors.margins: Theme.spacing.md

                IslandText {
                    Layout.fillWidth: true
                    text: rememberedRow.modelData.label
                    size: "body"
                }

                IslandButton {
                    label: "Forget"
                    reducedMotion: root.reducedMotion
                    variant: "danger"
                    Accessible.description: "Forget this disconnected display after confirmation"
                    onClicked: root.displayController.confirmForget(
                                   rememberedRow.modelData.identity)
                }
            }
        }
    }
}

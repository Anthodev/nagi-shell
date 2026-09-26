import QtQuick
import QtQuick.Layouts

ControlCenterSectionPanel {
    id: root

    required property string pageId
    property bool writable: true
    property string errorText: ""
    property bool resetAllConfirmationVisible: false
    property bool reducedMotion: false

    signal resetPageRequested(string pageId)
    signal resetAllRequested

    objectName: "settingsResetSection"
    text: qsTr("Reset")
    separated: true

    function requestPageReset() {
        if (!writable) {
            return false;
        }
        resetPageRequested(pageId);
        return true;
    }

    function restoreResetFocus() {
        if (root.visible && resetAllButton.visible && resetAllButton.enabled) {
            resetAllButton.forceActiveFocus(Qt.TabFocusReason);
        }
    }

    function beginResetAll() {
        if (!writable) {
            return false;
        }
        resetAllConfirmationVisible = true;
        if (root.visible && confirmResetAllButton.visible && confirmResetAllButton.enabled) {
            confirmResetAllButton.forceActiveFocus(Qt.TabFocusReason);
        }
        return true;
    }

    function cancelResetAll() {
        resetAllConfirmationVisible = false;
        restoreResetFocus();
    }

    function confirmResetAll() {
        if (!writable || !resetAllConfirmationVisible) {
            return false;
        }
        resetAllConfirmationVisible = false;
        resetAllRequested();
        restoreResetFocus();
        return true;
    }

    Item {
        id: resetActionsEntry

        Layout.fillWidth: true
        implicitHeight: Math.max(Theme.size.controlCenterSettingRowMinimumHeight,
                                 resetActionsLayout.implicitHeight + Theme.spacing.md * 2)

        ColumnLayout {
            id: resetActionsLayout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacing.sm

            RowLayout {
                spacing: Theme.spacing.sm

                IslandButton {
                    label: qsTr("Reset page")
                    enabled: root.writable
                    reducedMotion: root.reducedMotion
                    Accessible.description: qsTr("Restore this page to its default settings")
                    onClicked: root.requestPageReset()
                }

                IslandButton {
                    id: resetAllButton

                    label: root.resetAllConfirmationVisible ? qsTr("Cancel reset all") : qsTr(
                                                                  "Reset all settings")
                    variant: root.resetAllConfirmationVisible ? "standard" : "danger"
                    enabled: root.writable
                    reducedMotion: root.reducedMotion
                    Accessible.description: root.resetAllConfirmationVisible ? qsTr(
                                                                                   "Cancel the reset confirmation") :
                                                                               qsTr("Request confirmation before resetting every setting")
                    onClicked: root.resetAllConfirmationVisible ? root.cancelResetAll() :
                                                                  root.beginResetAll()
                }
            }

            IslandText {
                Layout.fillWidth: true
                visible: root.errorText !== ""
                text: root.errorText
                size: "caption"
                color: Theme.color.danger
                wrapMode: Text.Wrap
                Accessible.role: Accessible.AlertMessage
                Accessible.name: text
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            visible: root.resetAllConfirmationVisible
            height: Theme.size.hairlineWidth
            color: Theme.color.surfaceBorder
            opacity: 0.72
        }
    }

    Rectangle {
        id: confirmationEntry

        Layout.fillWidth: true
        visible: root.resetAllConfirmationVisible
        implicitHeight: confirmationLayout.implicitHeight + Theme.spacing.md * 2
        radius: 0
        color: Theme.color.dangerFill
        clip: true
        border.width: 0
        Accessible.role: Accessible.AlertMessage
        Accessible.name: qsTr("Confirm reset all settings")

        RowLayout {
            id: confirmationLayout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacing.md

            IslandText {
                Layout.fillWidth: true
                text: qsTr(
                          "Reset every Nagi setting to its default? Histories, credentials, paired devices, saved networks, caches, and user files are not removed.")
                size: "body"
                wrapMode: Text.Wrap
            }

            IslandButton {
                id: confirmResetAllButton

                label: qsTr("Confirm reset all")
                variant: "danger"
                reducedMotion: root.reducedMotion
                onClicked: root.confirmResetAll()
            }
        }
    }

    Keys.onEscapePressed: event => {
        if (root.resetAllConfirmationVisible) {
            root.cancelResetAll();
            event.accepted = true;
        }
    }
}

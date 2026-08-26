import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property string pageId
    property bool writable: true
    property string errorText: ""
    property bool resetAllConfirmationVisible: false
    property bool reducedMotion: false

    signal resetPageRequested(string pageId)
    signal resetAllRequested
    function requestPageReset() {
        if (!writable) {
            return false;
        }
        resetPageRequested(pageId);
        return true;
    }

    function beginResetAll() {
        if (!writable) {
            return false;
        }
        resetAllConfirmationVisible = true;
        return true;
    }

    function cancelResetAll() {
        resetAllConfirmationVisible = false;
    }

    function confirmResetAll() {
        if (!writable || !resetAllConfirmationVisible) {
            return false;
        }
        resetAllConfirmationVisible = false;
        resetAllRequested();
        return true;
    }

    spacing: Theme.spacing.sm
    Accessible.role: Accessible.Grouping
    Accessible.name: "Reset settings"

    RowLayout {
        spacing: Theme.spacing.sm

        IslandButton {
            label: "Reset page"
            enabled: root.writable
            reducedMotion: root.reducedMotion
            Accessible.description: "Restore this page to its default settings"
            onClicked: root.requestPageReset()
        }

        IslandButton {
            label: root.resetAllConfirmationVisible ? "Cancel reset all" : "Reset all settings"
            variant: root.resetAllConfirmationVisible ? "standard" : "danger"
            enabled: root.writable
            reducedMotion: root.reducedMotion
            Accessible.description: root.resetAllConfirmationVisible
                                    ? "Cancel the reset confirmation" :
                                      "Request confirmation before resetting every setting"
            onClicked: root.resetAllConfirmationVisible ? root.cancelResetAll() : root.beginResetAll(
                                                              )
        }
    }
    IslandPanel {
        Layout.fillWidth: true
        visible: root.resetAllConfirmationVisible
        implicitHeight: confirmationLayout.implicitHeight + Theme.spacing.md * 2
        color: Theme.color.dangerFill
        Accessible.role: Accessible.AlertMessage
        Accessible.name: "Confirm reset all settings"

        RowLayout {
            id: confirmationLayout

            anchors.fill: parent
            anchors.margins: Theme.spacing.md
            spacing: Theme.spacing.md

            IslandText {
                Layout.fillWidth: true
                text: "Reset every Nagi setting to its default? Histories, credentials, paired devices, saved networks, caches, and user files are not removed."
                size: "body"
                wrapMode: Text.Wrap
            }

            IslandButton {
                label: "Confirm reset all"
                variant: "danger"
                reducedMotion: root.reducedMotion
                onClicked: root.confirmResetAll()
            }
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

    Keys.onEscapePressed: event => {
        if (root.resetAllConfirmationVisible) {
            root.resetAllConfirmationVisible = false;
            event.accepted = true;
        }
    }
}

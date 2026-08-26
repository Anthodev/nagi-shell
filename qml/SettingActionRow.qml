import QtQuick

ControlCenterSettingRow {
    id: root

    property string actionLabel: ""
    property string actionVariant: "standard"
    property bool writable: true
    property bool reducedMotion: false

    signal actionRequested
    function requestAction() {
        if (!writable) {
            return false;
        }
        actionRequested();
        return true;
    }

    IslandButton {
        label: root.actionLabel
        variant: root.actionVariant
        enabled: root.writable
        reducedMotion: root.reducedMotion
        Accessible.description: root.description
        onClicked: root.requestAction()
    }
}

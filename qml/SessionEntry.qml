import QtQuick

IslandButton {
    id: entry

    signal openRequested

    label: qsTr("Session")
    Accessible.description: qsTr("Open lock, suspend, logout, reboot, and power-off actions")
    onClicked: openRequested()
}

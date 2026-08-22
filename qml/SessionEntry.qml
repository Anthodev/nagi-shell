import QtQuick

IslandButton {
    id: entry

    signal openRequested

    label: "Session"
    Accessible.description: "Open lock, suspend, logout, reboot, and power-off actions"
    onClicked: openRequested()
}

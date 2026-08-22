import QtQuick

IslandButton {
    id: entry

    signal openRequested

    label: "History"
    Accessible.description: "Open notification history"
    onClicked: openRequested()
}

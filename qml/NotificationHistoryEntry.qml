import QtQuick

IslandButton {
    id: entry

    signal openRequested

    label: qsTr("History")
    Accessible.description: qsTr("Open notification history")
    onClicked: openRequested()
}

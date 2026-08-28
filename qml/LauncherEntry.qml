import QtQuick

IslandButton {
    id: entry

    property bool shortcutAvailable: false
    property string activeShortcut: ""
    property bool preferredConflict: false

    signal openRequested

    readonly property string shortcutStatus: !shortcutAvailable ? qsTr("Shortcut unavailable") :
                                                                  activeShortcut !== ""
                                                                  ? activeShortcut : qsTr(
                                                                        "Shortcut unbound")

    label: qsTr("Launcher · %1").arg(shortcutStatus)
    Accessible.description: qsTr("Open the application launcher. %1").arg(shortcutStatus)
    onClicked: openRequested()
}

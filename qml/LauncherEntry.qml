import QtQuick

IslandButton {
    id: entry

    property bool shortcutAvailable: false
    property string activeShortcut: ""
    property bool preferredConflict: false

    signal openRequested

    readonly property string shortcutStatus: !shortcutAvailable ? "Shortcut unavailable" :
                                                                  activeShortcut !== ""
                                                                  ? activeShortcut :
                                                                    "Shortcut unbound"

    label: "Launcher · " + shortcutStatus
    Accessible.description: "Open the application launcher. " + shortcutStatus
    onClicked: openRequested()
}

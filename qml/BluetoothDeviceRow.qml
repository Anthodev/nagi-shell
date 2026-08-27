pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

IslandPanel {
    id: root

    required property var device
    property bool busy: false
    property bool reducedMotion: false

    signal pairRequested(int token)
    signal connectRequested(int token)
    signal disconnectRequested(int token)
    signal unpairRequested(int token, string name)

    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + Theme.spacing.lg * 2
    color: device.connected ? Theme.color.surfaceActive : Theme.color.controlFill
    Accessible.role: Accessible.ListItem
    Accessible.name: device.name + ", " + statusText() + signalDescription()

    function typeLabel() {
        if (device.type === "audio")
            return "Audio";
        if (device.type === "input")
            return "Input device";
        if (device.type === "phone")
            return "Phone";
        if (device.type === "computer")
            return "Computer";
        return "Bluetooth device";
    }

    function statusText() {
        if (device.connected)
            return "Connected";
        if (device.paired)
            return "Paired";
        return "Available";
    }

    function signalDescription() {
        return device.signal >= 0 ? ", signal " + device.signal + " percent" : "";
    }

    ColumnLayout {
        id: content

        anchors.fill: parent
        anchors.margins: Theme.spacing.lg
        spacing: Theme.spacing.sm

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.md

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.xs

                IslandText {
                    Layout.fillWidth: true
                    text: root.device.name
                    textFormat: Text.PlainText
                    size: "body"
                    elide: Text.ElideRight
                    Accessible.ignored: true
                }

                IslandText {
                    Layout.fillWidth: true
                    text: root.typeLabel() + (root.device.signal >= 0 ? " · " + root.device.signal
                                                                        + "%" : "")
                    textFormat: Text.PlainText
                    size: "caption"
                    color: Theme.color.textSecondary
                    elide: Text.ElideRight
                    Accessible.ignored: true
                }
            }

            IslandText {
                text: root.statusText()
                size: "caption"
                color: root.device.connected ? Theme.snapshot.accent : Theme.color.textSecondary
                Accessible.ignored: true
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.sm

            IslandButton {
                visible: root.device.pairable
                label: "Pair"
                reducedMotion: root.reducedMotion
                enabled: !root.busy
                Accessible.description: "Pair with " + root.device.name
                onClicked: root.pairRequested(root.device.token)
            }

            IslandButton {
                visible: root.device.connectable
                label: "Connect"
                reducedMotion: root.reducedMotion
                enabled: !root.busy
                Accessible.description: "Connect " + root.device.name
                onClicked: root.connectRequested(root.device.token)
            }

            IslandButton {
                visible: root.device.disconnectable
                label: "Disconnect"
                reducedMotion: root.reducedMotion
                enabled: !root.busy
                Accessible.description: "Disconnect " + root.device.name
                onClicked: root.disconnectRequested(root.device.token)
            }

            IslandButton {
                visible: root.device.unpairable
                label: "Unpair"
                variant: "danger"
                reducedMotion: root.reducedMotion
                enabled: !root.busy
                Accessible.description: "Remove the local pairing for " + root.device.name
                onClicked: root.unpairRequested(root.device.token, root.device.name)
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }
}

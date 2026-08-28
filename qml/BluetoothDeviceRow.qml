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
    Accessible.name: device.signal >= 0 ? qsTr("%1, %2, signal %3 percent").arg(device.name).arg(statusText(
                                                                                                     )).arg(device.signal) :
                                          qsTr("%1, %2").arg(device.name).arg(statusText())

    function typeLabel() {
        if (device.type === "audio")
            return qsTr("Audio");
        if (device.type === "input")
            return qsTr("Input device");
        if (device.type === "phone")
            return qsTr("Phone");
        if (device.type === "computer")
            return qsTr("Computer");
        return qsTr("Bluetooth device");
    }

    function statusText() {
        if (device.connected)
            return qsTr("Connected");
        if (device.paired)
            return qsTr("Paired");
        return qsTr("Available");
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
                    text: root.device.signal >= 0 ? qsTr("%1 · %2%").arg(root.typeLabel()).arg(
                                                        root.device.signal) : root.typeLabel()
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
                label: qsTr("Pair")
                reducedMotion: root.reducedMotion
                enabled: !root.busy
                Accessible.description: qsTr("Pair with %1").arg(root.device.name)
                onClicked: root.pairRequested(root.device.token)
            }

            IslandButton {
                visible: root.device.connectable
                label: qsTr("Connect")
                reducedMotion: root.reducedMotion
                enabled: !root.busy
                Accessible.description: qsTr("Connect %1").arg(root.device.name)
                onClicked: root.connectRequested(root.device.token)
            }

            IslandButton {
                visible: root.device.disconnectable
                label: qsTr("Disconnect")
                reducedMotion: root.reducedMotion
                enabled: !root.busy
                Accessible.description: qsTr("Disconnect %1").arg(root.device.name)
                onClicked: root.disconnectRequested(root.device.token)
            }

            IslandButton {
                visible: root.device.unpairable
                label: qsTr("Unpair")
                variant: "danger"
                reducedMotion: root.reducedMotion
                enabled: !root.busy
                Accessible.description: qsTr("Remove the local pairing for %1").arg(
                                            root.device.name)
                onClicked: root.unpairRequested(root.device.token, root.device.name)
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }
}

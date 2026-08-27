pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property string title
    required property var devices
    property bool busy: false
    property bool reducedMotion: false

    signal pairRequested(int token)
    signal connectRequested(int token)
    signal disconnectRequested(int token)
    signal unpairRequested(int token, string name)

    Layout.fillWidth: true
    visible: devices.length > 0
    spacing: Theme.spacing.sm
    Accessible.role: Accessible.List
    Accessible.name: title + " Bluetooth devices"

    IslandText {
        Layout.fillWidth: true
        text: root.title
        size: "heading"
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }

    Repeater {
        model: root.devices

        delegate: BluetoothDeviceRow {
            required property var modelData

            device: modelData
            busy: root.busy
            reducedMotion: root.reducedMotion
            onPairRequested: token => root.pairRequested(token)
            onConnectRequested: token => root.connectRequested(token)
            onDisconnectRequested: token => root.disconnectRequested(token)
            onUnpairRequested: (token, name) => root.unpairRequested(token, name)
        }
    }
}

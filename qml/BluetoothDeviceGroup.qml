pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

ControlCenterSectionPanel {
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
    text: root.title
    Accessible.role: Accessible.List
    Accessible.name: qsTr("%1 Bluetooth devices").arg(title)

    Repeater {
        id: deviceRepeater
        model: root.devices

        delegate: BluetoothDeviceRow {
            required property int index
            required property var modelData

            device: modelData
            separatorVisible: index < deviceRepeater.count - 1
            busy: root.busy
            reducedMotion: root.reducedMotion
            onPairRequested: token => root.pairRequested(token)
            onConnectRequested: token => root.connectRequested(token)
            onDisconnectRequested: token => root.disconnectRequested(token)
            onUnpairRequested: (token, name) => root.unpairRequested(token, name)
        }
    }
}

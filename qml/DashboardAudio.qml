pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Two aligned channel blocks keep confirmed audio state authoritative. Device
// buttons enter the dedicated selection subview.
FocusScope {
    id: root

    required property var audio

    readonly property bool outputWritable: audio !== null && audio.available
                                           && audio.outputAvailable
    readonly property bool inputWritable: audio !== null && audio.available && audio.inputAvailable
    readonly property string outputDeviceName: audio === null ? qsTr("Unavailable") :
                                                                audio.outputAvailable
                                                                ? audio.outputLabel :
                                                                  audio.outputDisplayLabel !== ""
                                                                  ? audio.outputDisplayLabel : qsTr(
                                                                        "Unavailable")
    readonly property string inputDeviceName: audio === null ? qsTr("Unavailable") :
                                                               audio.inputAvailable
                                                               ? audio.inputLabel :
                                                                 audio.inputDisplayLabel !== ""
                                                                 ? audio.inputDisplayLabel : qsTr(
                                                                       "Unavailable")

    implicitWidth: audioRow.implicitWidth
    implicitHeight: audioRow.implicitHeight
    Accessible.role: Accessible.Grouping
    Accessible.name: qsTr("Audio")
    signal deviceSelectionRequested

    function requestVolume(role, value, finalValue) {
        if (audio === null) {
            return false;
        }
        return role === "output" ? outputWritable && audio.requestOutputVolume(value, finalValue
                                                                               === true) : role
                                   === "input" ? inputWritable && audio.requestInputVolume(value,
                                                                                           finalValue
                                                                                           === true) :
                                                 false;
    }

    function toggleMute(role) {
        if (audio === null) {
            return false;
        }
        return role === "output" ? outputWritable && !audio.pendingOutputMute
                                   && audio.requestOutputMute(!audio.outputMuted) : role
                                   === "input" ? inputWritable && !audio.pendingInputMute
                                                 && audio.requestInputMute(!audio.inputMuted) :
                                                 false;
    }

    RowLayout {
        id: audioRow

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.spacing.lg

        ChannelBlock {
            objectName: "dashboardOutputSection"
            Layout.fillWidth: true
            Layout.preferredWidth: Theme.spacing.xxl * 9
            role: "output"
            deviceName: root.outputDeviceName
            writable: root.outputWritable
            volume: root.audio === null ? null : root.audio.outputVolume
            muted: root.audio !== null && root.audio.outputMuted
            overamplified: root.audio !== null && root.audio.outputOveramplified
            pendingVolume: root.audio !== null && root.audio.pendingOutputVolume
            pendingMute: root.audio !== null && root.audio.pendingOutputMute
            pendingSelection: root.audio !== null && root.audio.pendingOutputSelection
        }

        ChannelBlock {
            objectName: "dashboardInputSection"
            Layout.fillWidth: true
            Layout.preferredWidth: Theme.spacing.xxl * 9
            role: "input"
            deviceName: root.inputDeviceName
            writable: root.inputWritable
            volume: root.audio === null ? null : root.audio.inputVolume
            muted: root.audio !== null && root.audio.inputMuted
            overamplified: root.audio !== null && root.audio.inputOveramplified
            pendingVolume: root.audio !== null && root.audio.pendingInputVolume
            pendingMute: root.audio !== null && root.audio.pendingInputMute
            pendingSelection: root.audio !== null && root.audio.pendingInputSelection
        }
    }

    component ChannelBlock: ColumnLayout {
        id: channel

        required property string role
        required property string deviceName
        required property bool writable
        required property var volume
        required property bool muted
        required property bool overamplified
        required property bool pendingVolume
        required property bool pendingMute
        required property bool pendingSelection

        readonly property string channelLabel: role === "output" ? qsTr("Output") : qsTr("Input")
        readonly property string muteMeaning: role === "input" ? (muted ? "microphoneMuted" :
                                                                          "microphone") : (muted
                                                                                           ? "volumeMuted" :
                                                                                             "volumeHigh")
        readonly property string muteState: !writable ? "disabled" : pendingMute ? "pending" : muted
                                                                                   ? "off" : "normal"

        spacing: Theme.spacing.xs
        Accessible.role: Accessible.Grouping
        Accessible.name: qsTr("%1 audio").arg(channelLabel)

        RowLayout {
            Layout.fillWidth: true
            objectName: channel.role === "output" ? "dashboardOutputChannelRow" :
                                                    "dashboardInputChannelRow"
            spacing: Theme.spacing.sm

            DeviceButton {
                objectName: channel.role === "output" ? "dashboardOutputDeviceName" :
                                                        "dashboardInputDeviceName"
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                label: qsTr("%1 · %2").arg(channel.channelLabel).arg(channel.deviceName)
                pending: channel.pendingSelection
                onClicked: root.deviceSelectionRequested()
            }

            IslandText {
                objectName: channel.role === "output" ? "dashboardOutputPercentage" :
                                                        "dashboardInputPercentage"
                Layout.alignment: Qt.AlignVCenter
                text: volumeControl.percentageText
                textFormat: Text.PlainText
                tone: channel.pendingVolume || channel.pendingMute ? "secondary" : "muted"
                size: "caption"
                Accessible.name: qsTr("%1 confirmed volume %2").arg(channel.channelLabel).arg(text)
            }

            AbstractButton {
                id: muteButton

                objectName: channel.role === "output" ? "dashboardOutputMute" : "dashboardInputMute"
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Theme.size.controlHeightMd
                implicitHeight: Theme.size.controlHeightMd
                focusPolicy: Qt.StrongFocus
                hoverEnabled: true
                enabled: channel.writable && !channel.pendingMute
                Accessible.role: Accessible.Button
                Accessible.name: channel.muted ? qsTr("Unmute %1").arg(
                                                     channel.channelLabel.toLowerCase()) : qsTr(
                                                     "Mute %1").arg(channel.channelLabel.toLowerCase(
                                                                        ))
                onClicked: root.toggleMute(channel.role)

                background: Rectangle {
                    radius: Theme.radius.md
                    color: muteButton.pressed ? Theme.color.surfaceActive : muteButton.hovered
                                                ? Theme.color.surfaceHover : "transparent"
                }
                contentItem: Item {
                    IslandIcon {
                        objectName: channel.role === "output" ? "dashboardOutputMuteIcon" :
                                                                "dashboardInputMuteIcon"
                        anchors.centerIn: parent
                        meaning: channel.muteMeaning
                        semanticState: channel.muteState
                    }
                }
                IslandFocusRing {
                    visible: muteButton.visualFocus
                }
                ToolTip.delay: Theme.motion.durationSlow
                ToolTip.visible: hovered || visualFocus
                ToolTip.text: Accessible.name
            }
        }

        DashboardVolumeControl {
            id: volumeControl

            objectName: channel.role === "output" ? "dashboardOutputVolume" : "dashboardInputVolume"
            Layout.fillWidth: true
            label: channel.channelLabel
            available: channel.writable
            volume: channel.volume
            muted: channel.muted
            overamplified: channel.overamplified
            pendingVolume: channel.pendingVolume
            onVolumeRequested: (value, finalValue) => root.requestVolume(channel.role, value,
                                                                         finalValue)
        }
    }

    component DeviceButton: AbstractButton {
        id: control

        required property string label
        required property bool pending

        implicitHeight: Theme.size.controlHeightMd
        leftPadding: Theme.spacing.md
        rightPadding: Theme.spacing.md
        focusPolicy: Qt.StrongFocus
        hoverEnabled: true
        enabled: root.audio !== null && root.audio.available
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.description: qsTr("Open audio device selection")

        background: Rectangle {
            radius: Theme.radius.md
            color: control.pressed ? Theme.color.surfaceActive : control.hovered ? Theme.color.surfaceHover :
                                                                                   "transparent"
        }

        contentItem: IslandText {
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            text: control.label
            textFormat: Text.PlainText
            tone: control.pending ? "secondary" : "muted"
            size: "caption"
            elide: Text.ElideRight
        }

        IslandFocusRing {
            visible: control.visualFocus
        }
    }
}

import QtQuick
import QtQuick.Layouts

// Confirmed PipeWire default controls. Requests never replace the values shown
// by this view; pending state remains explicit until AudioAdapter confirms it.
FocusScope {
    id: root

    required property var audio

    readonly property bool outputWritable: audio !== null && audio.available
                                           && audio.outputAvailable
    readonly property bool inputWritable: audio !== null && audio.available && audio.inputAvailable
    readonly property string outputStatus: audio === null ? "Audio unavailable" :
                                                            audio.outputAvailable
                                                            ? "Current output · "
                                                              + audio.outputLabel :
                                                              audio.outputDisplayLabel !== ""
                                                              ? "Refreshing · last confirmed "
                                                                + audio.outputDisplayLabel :
                                                                "Audio output unavailable"

    implicitWidth: 340
    implicitHeight: 92

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

    IslandPanel {
        anchors.fill: parent
        radius: Theme.radius.lg
        color: Theme.color.controlFill
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing.md
        spacing: Theme.spacing.xs

        IslandText {
            Layout.fillWidth: true
            text: root.outputStatus
            textFormat: Text.PlainText
            tone: root.audio !== null && root.audio.pendingOutputSelection ? "secondary" : "muted"
            size: "caption"
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.md

            DashboardVolumeControl {
                objectName: "dashboardOutputVolume"
                Layout.fillWidth: true
                label: "Output"
                available: root.outputWritable
                volume: root.audio === null ? null : root.audio.outputVolume
                muted: root.audio !== null && root.audio.outputMuted
                overamplified: root.audio !== null && root.audio.outputOveramplified
                pendingVolume: root.audio !== null && root.audio.pendingOutputVolume
                pendingMute: root.audio !== null && root.audio.pendingOutputMute
                onVolumeRequested: (value, finalValue) => root.requestVolume("output", value,
                                                                             finalValue)
                onMuteRequested: muted => root.toggleMute("output")
            }

            DashboardVolumeControl {
                objectName: "dashboardInputVolume"
                Layout.fillWidth: true
                label: "Input"
                available: root.inputWritable
                volume: root.audio === null ? null : root.audio.inputVolume
                muted: root.audio !== null && root.audio.inputMuted
                overamplified: root.audio !== null && root.audio.inputOveramplified
                pendingVolume: root.audio !== null && root.audio.pendingInputVolume
                pendingMute: root.audio !== null && root.audio.pendingInputMute
                onVolumeRequested: (value, finalValue) => root.requestVolume("input", value,
                                                                             finalValue)
                onMuteRequested: muted => root.toggleMute("input")
            }
        }
    }
}

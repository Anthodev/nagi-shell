pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

// Quick controls consume only normalized adapters and the shared eligible-pin
// projection. No backend discovery, reconciliation, or presentation copy lives here.
FocusScope {
    id: root

    required property var connectivity
    required property var audio
    required property var applicationModel
    required property var tray

    readonly property int outputCount: audio === null ? 0 : audio.outputCandidates.length
    readonly property int pinCount: applicationModel === null ? 0 :
                                                                applicationModel.pinnedApplications.length
    readonly property string wifiState: connectivity === null || !connectivity.wifiAvailable
                                        ? "Unavailable" : connectivity.wifiEnabled ? "On" : "Off"
    readonly property string bluetoothState: connectivity === null ||
                                             !connectivity.bluetoothAvailable ? "Unavailable" :
                                                                                connectivity.bluetoothEnabled
                                                                                ? "On" : "Off"
    readonly property bool wifiFailureVisible: connectivity !== null && connectivity.wifiFailure
                                               !== "none"
    readonly property bool bluetoothFailureVisible: connectivity !== null
                                                    && connectivity.bluetoothFailure !== "none"

    implicitHeight: 100

    function toggleWifi() {
        return connectivity !== null && connectivity.wifiAvailable && !connectivity.wifiPending
                && connectivity.toggleWifi();
    }

    function toggleBluetooth() {
        return connectivity !== null && connectivity.bluetoothAvailable &&
                !connectivity.bluetoothPending && connectivity.toggleBluetooth();
    }

    function selectOutput(index) {
        if (audio === null || !audio.isSynchronized || audio.pendingOutputSelection || index < 0
                || index >= audio.outputCandidates.length) {
            return false;
        }
        const candidate = audio.outputCandidates[index];
        return candidate.isDefault ? true : audio.requestOutputSelection(candidate.endpointKey);
    }

    function reveal(flickable, item) {
        if (item.x < flickable.contentX) {
            flickable.contentX = item.x;
        } else if (item.x + item.width > flickable.contentX + flickable.width) {
            flickable.contentX = item.x + item.width - flickable.width;
        }
    }
    function launchPin(index) {
        if (applicationModel === null || applicationModel.launchPending || index < 0 || index
                >= applicationModel.pinnedApplications.length) {
            return 0;
        }
        return applicationModel.dispatchLaunch(applicationModel.pinnedApplications[index].id);
    }

    IslandPanel {
        anchors.fill: parent
        radius: Theme.radius.lg
        color: Theme.color.controlFill
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing.md
        spacing: Theme.spacing.sm

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.sm

            IslandButton {
                objectName: "dashboardWifi"
                label: "Wi-Fi · " + root.wifiState + (root.connectivity !== null
                                                      && root.connectivity.wifiPending
                                                      ? " · Pending" : root.wifiFailureVisible
                                                        ? " · Failed" : "")
                enabled: root.connectivity !== null && root.connectivity.wifiAvailable &&
                         !root.connectivity.wifiPending
                Accessible.description: "Toggle Wi-Fi. Confirmed state " + root.wifiState + (
                                            root.wifiFailureVisible ? ". Last request failed." : "")
                onClicked: root.toggleWifi()
            }

            IslandButton {
                objectName: "dashboardBluetooth"
                label: "Bluetooth · " + root.bluetoothState + (root.connectivity !== null
                                                               && root.connectivity.bluetoothPending
                                                               ? " · Pending" :
                                                                 root.bluetoothFailureVisible
                                                                 ? " · Failed" : "")
                enabled: root.connectivity !== null && root.connectivity.bluetoothAvailable &&
                         !root.connectivity.bluetoothPending
                Accessible.description: "Toggle Bluetooth. Confirmed state " + root.bluetoothState
                                        + (root.bluetoothFailureVisible ? ". Last request failed." :
                                                                          "")
                onClicked: root.toggleBluetooth()
            }

            IslandText {
                text: root.audio !== null && root.audio.pendingOutputSelection ? "Output · Pending" :
                                                                                 "Output"
                textFormat: Text.PlainText
                tone: root.audio !== null && root.audio.pendingOutputSelection ? "secondary" :
                                                                                 "muted"
                size: "caption"
            }

            Flickable {
                id: outputFlickable

                Layout.fillWidth: true
                Layout.preferredHeight: Theme.size.controlHeightMd
                contentWidth: outputRow.implicitWidth
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                Accessible.role: Accessible.List
                Accessible.name: "Audio outputs"

                Row {
                    id: outputRow

                    height: parent.height
                    spacing: Theme.spacing.sm

                    Repeater {
                        model: root.audio === null ? [] : root.audio.outputCandidates

                        delegate: IslandButton {
                            required property int index
                            required property var modelData
                            objectName: "dashboardOutputCandidate"

                            width: Math.min(180, implicitWidth)
                            label: modelData.label + (modelData.isDefault ? " · Current" : "")
                            enabled: root.audio !== null && root.audio.isSynchronized &&
                                     !root.audio.pendingOutputSelection && !modelData.isDefault
                            Accessible.description: modelData.isDefault ? modelData.label
                                                                          + ", confirmed current output" :
                                                                          "Select "
                                                                          + modelData.label
                            onActiveFocusChanged: {
                                if (activeFocus) {
                                    root.reveal(outputFlickable, this);
                                }
                            }
                            onClicked: root.selectOutput(index)
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.sm

            IslandText {
                visible: root.pinCount > 0
                text: "Pinned"
                textFormat: Text.PlainText
                tone: "muted"
                size: "caption"
            }

            Flickable {
                id: pinFlickable

                visible: root.pinCount > 0
                Layout.fillWidth: visible
                Layout.preferredHeight: Theme.size.controlHeightMd
                contentWidth: pinRow.implicitWidth
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                Accessible.role: Accessible.List
                Accessible.name: "Pinned applications"

                Row {
                    id: pinRow

                    height: parent.height
                    spacing: Theme.spacing.sm

                    Repeater {
                        model: root.applicationModel === null ? [] :
                                                                root.applicationModel.pinnedApplications

                        delegate: IslandButton {
                            required property int index
                            required property var modelData
                            objectName: "dashboardPinnedApplication"

                            width: Math.min(180, implicitWidth)
                            label: modelData.name
                            enabled: root.applicationModel !== null &&
                                     !root.applicationModel.launchPending
                            Accessible.description: "Launch pinned application " + modelData.name
                            onActiveFocusChanged: {
                                if (activeFocus) {
                                    root.reveal(pinFlickable, this);
                                }
                            }
                            onClicked: root.launchPin(index)
                        }
                    }
                }
            }

            TrayView {
                Layout.preferredWidth: visible && root.tray !== null ? Math.min(220,
                                                                                root.tray.itemCount
                                                                                * 40 + Theme.spacing.sm) :
                                                                       0
                adapter: root.tray
            }
        }
    }
}

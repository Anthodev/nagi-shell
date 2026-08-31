import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root

    required property var settingsModel
    required property var capabilities
    property string version: "0.1.0"
    property bool reducedMotion: false

    readonly property string diagnosticText: buildDiagnostic()
    contentWidth: width
    contentHeight: content.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("About Nagi Shell")

    function capabilityState(key) {
        return capabilities !== null && capabilities[key] === true ? qsTr("available") : qsTr(
                                                                         "unavailable");
    }

    function settingsState() {
        const labels = {
            "future": qsTr("newer schema"),
            "loading": qsTr("loading"),
            "ready": qsTr("ready"),
            "recovery": qsTr("recovery required"),
            "write-failed": qsTr("write failed")
        };
        return labels[settingsModel.status] ?? qsTr("unavailable");
    }

    function buildDiagnostic() {
        return [qsTr("Nagi Shell %1").arg(version), qsTr("Settings schema: %1").arg(
                    settingsModel.schemaVersion), qsTr("Settings state: %1").arg(settingsState()),
                qsTr("Display routing: %1").arg(capabilityState("displayRouting")), qsTr(
                    "Audio: %1").arg(capabilityState("audio")), qsTr("Media: %1").arg(
                    capabilityState("media")), qsTr("Wi-Fi: %1").arg(capabilityState("wifi")), qsTr(
                    "Bluetooth: %1").arg(capabilityState("bluetooth")), qsTr(
                    "Notifications: %1").arg(capabilityState("notifications")), qsTr(
                    "Weather: %1").arg(capabilityState("weather"))].join("\n");
    }

    ColumnLayout {
        id: content

        width: Math.min(root.width, Theme.size.controlCenterContentMaximumWidth)
        spacing: Theme.spacing.lg

        ControlCenterPageHeader {
            objectName: "aboutPageHeader"
            Layout.fillWidth: true
            iconMeaning: "controlCenterAbout"
            title: qsTr("About")
            description: qsTr("A context-aware desktop island and Control Center for KDE Plasma.")
        }

        IslandText {
            Layout.fillWidth: true
            text: qsTr("Nagi Shell %1").arg(root.version)
            size: "body"
            font.weight: Theme.type.weightSemibold
        }

        IslandPanel {
            Layout.fillWidth: true
            implicitHeight: linksLayout.implicitHeight + Theme.spacing.md * 2

            ColumnLayout {
                id: linksLayout

                anchors.fill: parent
                anchors.margins: Theme.spacing.md
                spacing: Theme.spacing.sm

                IslandText {
                    text: qsTr("Links and licenses")
                    size: "body"
                    font.weight: Theme.type.weightSemibold
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }

                RowLayout {
                    spacing: Theme.spacing.sm

                    IslandButton {
                        label: qsTr("Project source")
                        reducedMotion: root.reducedMotion
                        Accessible.description: qsTr("Open the Nagi Shell project website")
                        onClicked: Qt.openUrlExternally("https://github.com/Anthodev/nagi-shell")
                    }

                    IslandButton {
                        label: qsTr("Quickshell")
                        reducedMotion: root.reducedMotion
                        Accessible.description: qsTr("Open the Quickshell website")
                        onClicked: Qt.openUrlExternally("https://quickshell.org/")
                    }
                }

                IslandText {
                    Layout.fillWidth: true
                    text: qsTr(
                              "Project license: no license file is bundled in this installation. Third-party components retain their own licenses.")
                    size: "caption"
                    color: Theme.color.textSecondary
                    wrapMode: Text.Wrap
                }
            }
        }

        IslandPanel {
            Layout.fillWidth: true
            implicitHeight: diagnosticLayout.implicitHeight + Theme.spacing.md * 2

            ColumnLayout {
                id: diagnosticLayout

                anchors.fill: parent
                anchors.margins: Theme.spacing.md
                spacing: Theme.spacing.sm

                RowLayout {
                    Layout.fillWidth: true

                    IslandText {
                        Layout.fillWidth: true
                        text: qsTr("Safe diagnostic")
                        size: "body"
                        font.weight: Theme.type.weightSemibold
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    IslandButton {
                        label: qsTr("Copy diagnostic")
                        reducedMotion: root.reducedMotion
                        Accessible.description: qsTr("Copy the allowlisted capability diagnostic")
                        onClicked: {
                            diagnostic.selectAll();
                            diagnostic.copy();
                        }
                    }
                }

                IslandText {
                    Layout.fillWidth: true
                    text: qsTr(
                              "Contains only version, schema, and fixed capability states. It excludes network names, device and screen identity, location, paths, notification content, secrets, process IDs, and executables.")
                    size: "caption"
                    color: Theme.color.textSecondary
                    wrapMode: Text.Wrap
                }

                TextArea {
                    id: diagnostic

                    Layout.fillWidth: true
                    Layout.minimumHeight: Theme.spacing.xxl * 5
                    readOnly: true
                    selectByMouse: true
                    text: root.diagnosticText
                    color: Theme.color.textPrimary
                    selectionColor: Theme.snapshot.accent
                    selectedTextColor: Theme.snapshot.accentForeground
                    font.family: Theme.type.familyForItem(this)
                    font.pixelSize: Theme.type.sizeForItem(this, "caption")
                    wrapMode: TextEdit.NoWrap
                    Accessible.name: qsTr("Safe diagnostic text")
                    Accessible.description: qsTr("Read-only allowlisted diagnostic")

                    background: IslandPanel {
                        color: Theme.color.controlFill
                        border.color: diagnostic.activeFocus ? Theme.snapshot.focusRing :
                                                               Theme.color.surfaceBorder
                    }
                }
            }
        }
    }

    ScrollBar.vertical: ScrollBar {
        policy: root.contentHeight > root.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
    }
}

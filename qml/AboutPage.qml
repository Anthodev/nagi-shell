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
    Accessible.name: "About Nagi Shell"

    function capabilityState(key) {
        return capabilities !== null && capabilities[key] === true ? "available" : "unavailable";
    }

    function settingsState() {
        const allowed = ["loading", "ready", "write-failed", "recovery", "future"];
        return allowed.indexOf(settingsModel.status) === -1 ? "unavailable" : settingsModel.status;
    }

    function buildDiagnostic() {
        return ["Nagi Shell " + version, "Settings schema: " + settingsModel.schemaVersion,
                "Settings state: " + settingsState(), "Display routing: " + capabilityState(
                    "displayRouting"), "Audio: " + capabilityState("audio"), "Media: "
                + capabilityState("media"), "Wi-Fi: " + capabilityState("wifi"), "Bluetooth: "
                + capabilityState("bluetooth"), "Notifications: " + capabilityState("notifications"),
                "Weather: " + capabilityState("weather")].join("\n");
    }

    ColumnLayout {
        id: content

        width: Math.min(root.width, Theme.size.controlCenterContentMaximumWidth)
        spacing: Theme.spacing.lg

        IslandText {
            text: "About"
            size: "title"
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }

        IslandText {
            Layout.fillWidth: true
            text: "Nagi Shell " + root.version
            size: "body"
            font.weight: Theme.type.weightSemibold
        }

        IslandText {
            Layout.fillWidth: true
            text: "A context-aware desktop island and Control Center for KDE Plasma."
            size: "body"
            color: Theme.color.textSecondary
            wrapMode: Text.Wrap
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
                    text: "Links and licenses"
                    size: "body"
                    font.weight: Theme.type.weightSemibold
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }

                RowLayout {
                    spacing: Theme.spacing.sm

                    IslandButton {
                        label: "Project source"
                        reducedMotion: root.reducedMotion
                        Accessible.description: "Open the Nagi Shell project website"
                        onClicked: Qt.openUrlExternally("https://github.com/Anthodev/nagi-shell")
                    }

                    IslandButton {
                        label: "Quickshell"
                        reducedMotion: root.reducedMotion
                        Accessible.description: "Open the Quickshell website"
                        onClicked: Qt.openUrlExternally("https://quickshell.org/")
                    }
                }

                IslandText {
                    Layout.fillWidth: true
                    text: "Project license: no license file is bundled in this installation. Third-party components retain their own licenses."
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
                        text: "Safe diagnostic"
                        size: "body"
                        font.weight: Theme.type.weightSemibold
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    IslandButton {
                        label: "Copy diagnostic"
                        reducedMotion: root.reducedMotion
                        Accessible.description: "Copy the allowlisted capability diagnostic"
                        onClicked: {
                            diagnostic.selectAll();
                            diagnostic.copy();
                        }
                    }
                }

                IslandText {
                    Layout.fillWidth: true
                    text: "Contains only version, schema, and fixed capability states. It excludes network names, device and screen identity, location, paths, notification content, secrets, process IDs, and executables."
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
                    Accessible.name: "Safe diagnostic text"
                    Accessible.description: "Read-only allowlisted diagnostic"

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

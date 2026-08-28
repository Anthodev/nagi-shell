pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

IslandPanel {
    id: root

    required property var network
    property bool busy: false
    property bool reducedMotion: false

    signal connectRequested(int token, bool secretRequired)
    signal disconnectRequested
    signal forgetRequested(int token)

    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + Theme.spacing.lg * 2
    color: network.connected ? Theme.color.surfaceActive : Theme.color.controlFill
    Accessible.role: Accessible.ListItem
    Accessible.name: network.ssid + ", " + securityLabel() + ", signal " + network.strength
                     + " percent" + (network.connected ? ", connected" : "")

    function securityLabel() {
        if (network.security === "open")
            return "Open";
        if (network.security === "wpa-personal")
            return "WPA Personal";
        return "Enterprise or unsupported security";
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
                    text: root.network.ssid
                    textFormat: Text.PlainText
                    size: "body"
                    elide: Text.ElideRight
                    Accessible.ignored: true
                }

                IslandText {
                    Layout.fillWidth: true
                    text: root.securityLabel() + " · " + root.network.strength + "%" + (root.network.saved
                                                                                        ? " · Saved" :
                                                                                          "")
                    textFormat: Text.PlainText
                    size: "caption"
                    color: Theme.color.textSecondary
                    elide: Text.ElideRight
                    Accessible.ignored: true
                }
            }

            IslandText {
                visible: root.network.connected
                text: "Connected"
                size: "caption"
                color: Theme.snapshot.accent
                Accessible.ignored: true
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.sm

            IslandButton {
                label: root.network.connected ? "Disconnect" : "Connect"
                reducedMotion: root.reducedMotion
                enabled: !root.busy && (root.network.connected || root.network.connectable)
                Accessible.description: root.network.connected ? "Disconnect from this network" :
                                                                 "Connect to this network"
                onClicked: {
                    if (root.network.connected) {
                        root.disconnectRequested();
                    } else {
                        root.connectRequested(root.network.token, !root.network.saved
                                              && root.network.security === "wpa-personal");
                    }
                }
            }

            IslandButton {
                visible: root.network.saved
                label: "Forget"
                variant: "danger"
                reducedMotion: root.reducedMotion
                enabled: !root.busy && root.network.forgettable
                Accessible.description: root.network.forgettable ? "Forget this personal profile" :
                                                                   "System or administrator profile cannot be forgotten here"
                onClicked: root.forgetRequested(root.network.token)
            }

            Item {
                Layout.fillWidth: true
            }
        }

        IslandText {
            Layout.fillWidth: true
            visible: root.network.saved && !root.network.forgettable
            text: "This system or administrator profile remains managed by KDE."
            textFormat: Text.PlainText
            size: "caption"
            tone: "muted"
            wrapMode: Text.Wrap
            Accessible.name: text
        }

        IslandText {
            Layout.fillWidth: true
            visible: !root.network.connectable
            text: "Enterprise, certificate, and advanced profiles remain managed by KDE."
            textFormat: Text.PlainText
            size: "caption"
            tone: "muted"
            wrapMode: Text.Wrap
            Accessible.name: text
        }
    }
}

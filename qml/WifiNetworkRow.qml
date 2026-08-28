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
    Accessible.name: network.connected ? qsTr("%1, %2, signal %3 percent, connected").arg(
                                             network.ssid).arg(securityLabel()).arg(
                                             network.strength) : qsTr(
                                             "%1, %2, signal %3 percent").arg(network.ssid).arg(
                                             securityLabel()).arg(network.strength)

    function securityLabel() {
        if (network.security === "open")
            return qsTr("Open");
        if (network.security === "wpa-personal")
            return qsTr("WPA Personal");
        return qsTr("Enterprise or unsupported security");
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
                    text: root.network.saved ? qsTr("%1 · %2% · Saved").arg(root.securityLabel(
                                                                                )).arg(root.network.strength) :
                                               qsTr("%1 · %2%").arg(root.securityLabel()).arg(
                                                   root.network.strength)
                    textFormat: Text.PlainText
                    size: "caption"
                    color: Theme.color.textSecondary
                    elide: Text.ElideRight
                    Accessible.ignored: true
                }
            }

            IslandText {
                visible: root.network.connected
                text: qsTr("Connected")
                size: "caption"
                color: Theme.snapshot.accent
                Accessible.ignored: true
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.sm

            IslandButton {
                label: root.network.connected ? qsTr("Disconnect") : qsTr("Connect")
                reducedMotion: root.reducedMotion
                enabled: !root.busy && (root.network.connected || root.network.connectable)
                Accessible.description: root.network.connected ? qsTr(
                                                                     "Disconnect from this network") :
                                                                 qsTr("Connect to this network")
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
                label: qsTr("Forget")
                variant: "danger"
                reducedMotion: root.reducedMotion
                enabled: !root.busy && root.network.forgettable
                Accessible.description: root.network.forgettable ? qsTr(
                                                                       "Forget this personal profile") :
                                                                   qsTr("System or administrator profile cannot be forgotten here")
                onClicked: root.forgetRequested(root.network.token)
            }

            Item {
                Layout.fillWidth: true
            }
        }

        IslandText {
            Layout.fillWidth: true
            visible: root.network.saved && !root.network.forgettable
            text: qsTr("This system or administrator profile remains managed by KDE.")
            textFormat: Text.PlainText
            size: "caption"
            tone: "muted"
            wrapMode: Text.Wrap
            Accessible.name: text
        }

        IslandText {
            Layout.fillWidth: true
            visible: !root.network.connectable
            text: qsTr("Enterprise, certificate, and advanced profiles remain managed by KDE.")
            textFormat: Text.PlainText
            size: "caption"
            tone: "muted"
            wrapMode: Text.Wrap
            Accessible.name: text
        }
    }
}

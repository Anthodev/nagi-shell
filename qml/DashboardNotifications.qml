pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

// Read-only recent projection. The service owns ordering, replacement, age,
// retention, and the four-record bound; delegates retain no content copy.
FocusScope {
    id: root

    required property var service

    readonly property int rowCount: recentList.count
    readonly property bool empty: rowCount === 0

    implicitWidth: 300
    implicitHeight: 92

    IslandPanel {
        anchors.fill: parent
        radius: Theme.radius.lg
        color: Theme.color.controlFill
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing.md
        spacing: Theme.spacing.xs

        RowLayout {
            Layout.fillWidth: true

            IslandText {
                Layout.fillWidth: true
                text: "Recent notifications"
                textFormat: Text.PlainText
                font.weight: Theme.type.weightSemibold
            }

            IslandText {
                text: root.empty ? "None" : String(root.rowCount)
                textFormat: Text.PlainText
                tone: "muted"
                size: "caption"
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: recentList

                anchors.fill: parent
                clip: true
                interactive: false
                spacing: Theme.spacing.xs
                reuseItems: true
                model: root.service === null ? null : root.service.dashboardModel
                Accessible.role: Accessible.List
                Accessible.name: "Recent notifications"

                delegate: RowLayout {
                    id: row

                    required property var model

                    width: ListView.view.width
                    height: Math.max(Theme.type.body, summaryLabel.implicitHeight)
                    spacing: Theme.spacing.xs
                    Accessible.role: Accessible.ListItem
                    Accessible.name: String(model.summary)

                    IslandText {
                        text: String(row.model.appName)
                        textFormat: Text.PlainText
                        visible: text !== ""
                        tone: "muted"
                        size: "caption"
                        font.weight: Theme.type.weightMedium
                        elide: Text.ElideRight
                        Layout.maximumWidth: 92
                    }

                    IslandText {
                        id: summaryLabel

                        Layout.fillWidth: true
                        text: String(row.model.summary) !== "" ? String(row.model.summary) : String(
                                                                     row.model.body)
                        textFormat: Text.PlainText
                        tone: row.model.state === "expired" ? "muted" : "secondary"
                        elide: Text.ElideRight
                    }
                }
            }

            IslandText {
                anchors.centerIn: parent
                visible: root.empty
                text: root.service !== null && !root.service.serverOwned
                      ? "Notifications unavailable" : "No recent notifications"
                textFormat: Text.PlainText
                tone: "muted"
                size: "caption"
            }
        }
    }
}

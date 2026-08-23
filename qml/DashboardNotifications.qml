pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

// The normalized service owns ordering, replacement, age, retention, and the
// four-record dashboard bound; delegates retain no content copy.
FocusScope {
    id: root

    required property var service

    readonly property int rowCount: recentList.count
    readonly property bool empty: rowCount === 0
    readonly property int rowHeight: Theme.size.controlHeightSm

    implicitWidth: Theme.spacing.xxl * 18 + Theme.spacing.lg
    implicitHeight: notificationsColumn.implicitHeight
    Accessible.role: Accessible.Grouping
    Accessible.name: "Recent notifications"

    ColumnLayout {
        id: notificationsColumn

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.spacing.xs

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.empty ? root.rowHeight : recentList.contentHeight

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
                    height: root.rowHeight
                    spacing: Theme.spacing.sm
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
                        Layout.maximumWidth: Theme.spacing.xxl * 3
                    }

                    IslandText {
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
                text: "No notifications"
                textFormat: Text.PlainText
                tone: "muted"
                size: "caption"
            }
        }
    }
}

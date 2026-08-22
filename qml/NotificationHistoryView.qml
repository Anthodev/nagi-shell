pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

FocusScope {
    id: view

    required property var service
    required property real ownerEpoch

    readonly property int rowCount: historyList.count
    readonly property bool emptyStateVisible: emptyState.visible
    readonly property bool backFocused: backButton.activeFocus
    readonly property bool historyFocused: historyList.activeFocus
    readonly property int visibleActionCount: 0
    readonly property string currentRecordKey: selectedRecordKey
    readonly property bool currentRowUsesPlainText: historyList.currentItem === null
                                                    || historyList.currentItem.plainTextOnly

    property string selectedRecordKey: ""
    property int fallbackIndex: 0
    property bool restoreListFocus: true
    property bool selectionRestoreQueued: false

    signal cancelled(real ownerEpoch)

    function dismissRecord(recordKey, index) {
        if (service === null || recordKey === "") {
            return false;
        }

        fallbackIndex = Math.max(0, index);
        selectedRecordKey = "";
        restoreListFocus = true;
        return service.dismiss(recordKey);
    }

    function dismissCurrent() {
        if (historyList.currentItem === null) {
            return false;
        }
        return dismissRecord(historyList.currentItem.recordKey, historyList.currentIndex);
    }

    function focusCurrentRow(reason) {
        const expectedIndex = historyList.currentIndex;
        Qt.callLater(function () {
            if (expectedIndex === historyList.currentIndex && historyList.currentItem !== null) {
                historyList.currentItem.forceActiveFocus(reason);
            }
        });
    }

    function focusInitialControl() {
        restoreListFocus = true;
        if (historyList.count === 0) {
            backButton.forceActiveFocus(Qt.ShortcutFocusReason);
            return;
        }
        historyList.currentIndex = Math.max(0, historyList.currentIndex);
        historyList.positionViewAtIndex(historyList.currentIndex, ListView.Contain);
        focusCurrentRow(Qt.ShortcutFocusReason);
    }

    function focusRow(index, reason) {
        if (historyList.count === 0) {
            backButton.forceActiveFocus(reason);
            return;
        }
        historyList.currentIndex = Math.max(0, Math.min(index, historyList.count - 1));
        historyList.positionViewAtIndex(historyList.currentIndex, ListView.Contain);
        focusCurrentRow(reason);
    }

    function queueSelectionRestore() {
        if (selectionRestoreQueued) {
            return;
        }
        selectionRestoreQueued = true;
        Qt.callLater(function () {
            selectionRestoreQueued = false;
            restoreSelection();
        });
    }

    function requestBack() {
        cancelled(ownerEpoch);
    }

    function restoreSelection() {
        let nextIndex = -1;
        if (service !== null && selectedRecordKey !== "") {
            nextIndex = service.historyIndex(selectedRecordKey);
        }
        if (nextIndex < 0 && historyList.count > 0) {
            nextIndex = Math.min(fallbackIndex, historyList.count - 1);
        }
        historyList.currentIndex = nextIndex;

        if (nextIndex < 0) {
            selectedRecordKey = "";
            if (restoreListFocus) {
                backButton.forceActiveFocus(Qt.OtherFocusReason);
            }
            return;
        }

        historyList.positionViewAtIndex(nextIndex, ListView.Contain);
        if (restoreListFocus) {
            focusCurrentRow(Qt.OtherFocusReason);
        }
    }

    Keys.priority: Keys.BeforeItem
    Keys.onEscapePressed: event => {
        view.requestBack();
        event.accepted = true;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing.xl
        spacing: Theme.spacing.lg

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.md

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.xs

                IslandText {
                    text: "Notification history"
                    textFormat: Text.PlainText
                    size: "title"
                    font.weight: Theme.type.weightSemibold
                }

                IslandText {
                    text: "Newest first. Dismissed notifications are removed immediately."
                    textFormat: Text.PlainText
                    tone: "secondary"
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }

            IslandButton {
                id: backButton

                label: "Back"
                Accessible.description: "Return to the previous island state"
                onActiveFocusChanged: {
                    if (activeFocus) {
                        view.restoreListFocus = false;
                    }
                }
                onClicked: view.requestBack()
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: historyList

                anchors.fill: parent
                clip: true
                spacing: Theme.spacing.sm
                reuseItems: true
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationEnabled: false
                model: view.service === null ? null : view.service.historyModel
                Accessible.role: Accessible.List
                Accessible.name: "Notification history"

                delegate: FocusScope {
                    id: row

                    required property int index
                    required property var model

                    readonly property string recordKey: String(model.firstAdmissionSequence)
                    readonly property bool plainTextOnly: appNameLabel.textFormat
                                                          === Text.PlainText
                                                          && summaryLabel.textFormat
                                                          === Text.PlainText
                                                          && bodyLabel.textFormat === Text.PlainText

                    width: ListView.view.width
                    implicitHeight: cardContent.implicitHeight + Theme.spacing.md * 2
                    activeFocusOnTab: true
                    Accessible.role: Accessible.ListItem
                    Accessible.name: summaryLabel.text === "" ? appNameLabel.text :
                                                                summaryLabel.text

                    onActiveFocusChanged: {
                        if (activeFocus) {
                            historyList.currentIndex = index;
                            view.fallbackIndex = index;
                            view.selectedRecordKey = recordKey;
                            view.restoreListFocus = true;
                        }
                    }

                    Keys.priority: Keys.BeforeItem
                    Keys.onDeletePressed: event => {
                        view.dismissRecord(row.recordKey, row.index);
                        event.accepted = true;
                    }
                    Keys.onDownPressed: event => {
                        view.focusRow(row.index + 1, Qt.TabFocusReason);
                        event.accepted = true;
                    }
                    Keys.onUpPressed: event => {
                        view.focusRow(row.index - 1, Qt.BacktabFocusReason);
                        event.accepted = true;
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radius.md
                        color: row.activeFocus || rowHover.hovered ? Theme.color.controlFillHover :
                                                                     Theme.color.controlFill
                        border.width: Theme.size.hairlineWidth
                        border.color: row.activeFocus ? Theme.color.focusRing :
                                                        Theme.color.surfaceBorder
                    }

                    RowLayout {
                        id: cardContent

                        anchors.fill: parent
                        anchors.margins: Theme.spacing.md
                        spacing: Theme.spacing.md

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacing.xs

                            IslandText {
                                id: appNameLabel

                                text: String(row.model.appName)
                                textFormat: Text.PlainText
                                visible: text !== ""
                                tone: "secondary"
                                size: "caption"
                                font.weight: Theme.type.weightMedium
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            IslandText {
                                id: summaryLabel

                                text: String(row.model.summary)
                                textFormat: Text.PlainText
                                visible: text !== ""
                                font.weight: Theme.type.weightSemibold
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            IslandText {
                                id: bodyLabel

                                text: String(row.model.body)
                                textFormat: Text.PlainText
                                visible: text !== ""
                                tone: "secondary"
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            IslandText {
                                text: "Expired"
                                textFormat: Text.PlainText
                                visible: row.model.state === "expired"
                                tone: "muted"
                                size: "caption"
                            }
                        }

                        IslandButton {
                            id: dismissButton

                            label: "Dismiss"
                            visible: rowHover.hovered || row.activeFocus || activeFocus
                            Accessible.description: "Dismiss this notification"
                            Layout.alignment: Qt.AlignTop
                            onClicked: view.dismissRecord(row.recordKey, row.index)
                        }
                    }

                    HoverHandler {
                        id: rowHover
                    }
                }

                onCurrentIndexChanged: {
                    if (currentItem !== null) {
                        view.fallbackIndex = currentIndex;
                        view.selectedRecordKey = currentItem.recordKey;
                    }
                }
            }

            Column {
                id: emptyState

                anchors.centerIn: parent
                spacing: Theme.spacing.xs
                visible: historyList.count === 0

                IslandText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: view.service !== null && !view.service.serverOwned
                          ? "Notification history is unavailable." : "No notifications yet."
                    textFormat: Text.PlainText
                    font.weight: Theme.type.weightMedium
                }

                IslandText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: view.service !== null && !view.service.serverOwned
                          ? "Another notification service currently owns the session." :
                            "New notifications will appear here."
                    textFormat: Text.PlainText
                    tone: "secondary"
                    size: "caption"
                }
            }
        }
    }

    Connections {
        target: historyList.model
        ignoreUnknownSignals: true

        function onDataChanged() {
            view.queueSelectionRestore();
        }

        function onModelReset() {
            view.queueSelectionRestore();
        }

        function onRowsInserted() {
            view.queueSelectionRestore();
        }

        function onRowsRemoved() {
            view.queueSelectionRestore();
        }
    }

    Component.onCompleted: queueSelectionRestore()
}

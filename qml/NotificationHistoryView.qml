pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FocusScope {
    id: view

    required property var service
    required property real ownerEpoch
    property bool active: true
    property bool reducedMotion: false

    readonly property int maximumVisibleRows: 5
    readonly property int historyRowExtent: Theme.spacing.xxl * 4
    readonly property real contentWidth: Theme.spacing.xxl * 15

    readonly property bool historyScrollVisible: rowCount > maximumVisibleRows
    readonly property real historyViewportHeight: rowCount === 0 ? Theme.size.controlHeightLg :
                                                                   firstRowsExtent(Math.min(rowCount,
                                                                                            maximumVisibleRows))
    readonly property int rowCount: historyList.count
    readonly property bool emptyStateVisible: emptyState.visible
    readonly property bool backFocused: frame.backControl.activeFocus
    readonly property bool historyFocused: historyList.activeFocus
    readonly property int visibleActionCount: 0
    readonly property string currentRecordKey: selectedRecordKey
    readonly property bool currentRowUsesPlainText: historyList.currentItem === null
                                                    || historyList.currentItem.plainTextOnly

    property string selectedRecordKey: ""
    property int fallbackIndex: 0
    property bool restoreListFocus: true
    property bool selectionRestoreQueued: false
    implicitWidth: frame.implicitWidth
    implicitHeight: frame.implicitHeight
    visible: active
    component HistoryRowContent: RowLayout {
        required property var record
        property bool actionExposed: false
        readonly property bool plainTextOnly: appNameLabel.textFormat === Text.PlainText
                                              && summaryLabel.textFormat === Text.PlainText
                                              && bodyLabel.textFormat === Text.PlainText
        readonly property string accessibleName: summaryLabel.text === "" ? appNameLabel.text :
                                                                            summaryLabel.text

        signal dismissRequested

        spacing: Theme.spacing.md

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.xs

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.sm

                IslandText {
                    id: appNameLabel

                    Layout.fillWidth: true
                    text: record === null || record === undefined ? "" : String(record.appName
                                                                                ?? "")

                    textFormat: Text.PlainText
                    visible: text !== ""
                    tone: "secondary"
                    size: "caption"
                    font.weight: Theme.type.weightMedium
                    elide: Text.ElideRight
                }

                IslandText {
                    text: record !== null && record !== undefined && record.state === "expired"
                          ? "Expired" : "Recent"
                    textFormat: Text.PlainText
                    tone: "muted"
                    size: "caption"
                }
            }

            IslandText {
                id: summaryLabel

                Layout.fillWidth: true
                text: record === null || record === undefined ? "" : String(record.summary ?? "")
                textFormat: Text.PlainText
                visible: text !== ""
                font.weight: Theme.type.weightSemibold
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            IslandText {
                id: bodyLabel

                Layout.fillWidth: true
                text: record === null || record === undefined ? "" : String(record.body ?? "")
                textFormat: Text.PlainText
                visible: text !== ""
                tone: "secondary"
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }
        }

        IslandButton {
            label: "Dismiss"
            opacity: actionExposed ? 1 : 0
            enabled: actionExposed
            Accessible.ignored: !actionExposed
            Accessible.description: "Dismiss this notification"
            Layout.alignment: Qt.AlignTop
            onClicked: dismissRequested()
        }
    }

    signal cancelled(real ownerEpoch)
    function firstRowsExtent(count) {
        return count * historyRowExtent;
    }

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
            frame.backControl.forceActiveFocus(Qt.ShortcutFocusReason);
            return;
        }
        historyList.currentIndex = Math.max(0, historyList.currentIndex);
        historyList.positionViewAtIndex(historyList.currentIndex, ListView.Contain);
        focusCurrentRow(Qt.ShortcutFocusReason);
    }

    function focusRow(index, reason) {
        if (historyList.count === 0) {
            frame.backControl.forceActiveFocus(reason);
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
                frame.backControl.forceActiveFocus(Qt.OtherFocusReason);
            }
            return;
        }

        historyList.positionViewAtIndex(nextIndex, ListView.Contain);
        if (restoreListFocus) {
            focusCurrentRow(Qt.OtherFocusReason);
        }
    }

    // Escape is owned by the shared frame.

    SubviewFrame {
        id: frame

        anchors.fill: parent
        active: view.active
        title: "Notification history"
        reducedMotion: view.reducedMotion
        initialFocusItem: historyList.currentItem
        onBackRequested: view.requestBack()
        onEscapePressed: view.requestBack()

        Item {
            implicitWidth: view.contentWidth
            implicitHeight: view.historyViewportHeight
            width: implicitWidth
            height: implicitHeight
            ListView {
                id: historyList

                anchors.fill: parent
                clip: view.historyScrollVisible
                interactive: view.historyScrollVisible
                cacheBuffer: Theme.spacing.xxl * 20
                spacing: 0
                reuseItems: true
                keyNavigationEnabled: false
                model: view.service === null ? null : view.service.historyModel
                Accessible.role: Accessible.List
                Accessible.name: "Notification history"

                delegate: FocusScope {
                    id: row

                    required property int index
                    required property var model

                    readonly property string recordKey: String(model.firstAdmissionSequence)
                    readonly property bool plainTextOnly: rowContent.plainTextOnly

                    width: ListView.view.width
                    implicitHeight: view.historyRowExtent
                    activeFocusOnTab: true
                    Accessible.role: Accessible.ListItem
                    Accessible.name: rowContent.accessibleName

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
                        if (row.index === 0) {
                            frame.backControl.forceActiveFocus(Qt.BacktabFocusReason);
                        } else {
                            view.focusRow(row.index - 1, Qt.BacktabFocusReason);
                        }
                        event.accepted = true;
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: row.activeFocus ? Theme.color.surfaceActive : rowHover.hovered
                                                 ? Theme.color.surfaceHover : "transparent"
                        radius: Theme.radius.md
                    }

                    HistoryRowContent {
                        id: rowContent

                        anchors.fill: parent
                        anchors.margins: Theme.spacing.md
                        record: row.model
                        actionExposed: rowHover.hovered || row.activeFocus || activeFocus
                        onDismissRequested: view.dismissRecord(row.recordKey, row.index)
                    }

                    IslandFocusRing {
                        visible: row.activeFocus
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: Theme.size.hairlineWidth
                        color: Theme.color.surfaceBorder
                        visible: row.index < historyList.count - 1
                    }

                    HoverHandler {
                        id: rowHover
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    objectName: "notificationHistoryScrollBar"
                    policy: view.historyScrollVisible ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                }

                onCurrentIndexChanged: {
                    if (currentItem !== null) {
                        view.fallbackIndex = currentIndex;
                        view.selectedRecordKey = currentItem.recordKey;
                    }
                }
            }

            IslandText {
                id: emptyState

                anchors.centerIn: parent
                visible: historyList.count === 0
                text: view.service !== null && !view.service.serverOwned
                      ? "Notification history unavailable" : "No notifications yet"
                textFormat: Text.PlainText
                tone: "secondary"
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

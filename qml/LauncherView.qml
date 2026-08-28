pragma ComponentBehavior: Bound

import Quickshell
import QtQuick.Controls
import QtQuick
import QtQuick.Layouts

FocusScope {
    id: view

    required property var applicationModel
    required property real ownerEpoch
    property bool active: true
    property bool reducedMotion: false
    property alias query: searchInput.text
    readonly property var normalizedSearchIndex: buildSearchIndex()
    readonly property int maximumVisibleResults: 5
    readonly property int resultRowExtent: Theme.size.controlHeightLg
    readonly property int resultRowSpacing: Theme.spacing.xs
    readonly property real resultViewportHeight: resultCount === 0 ? Theme.size.controlHeightMd :
                                                                     Math.min(resultCount,
                                                                              maximumVisibleResults)
                                                                     * resultRowExtent + Math.max(0,
                                                                                                  Math.min(resultCount,
                                                                                                           maximumVisibleResults)
                                                                                                  - 1) * resultRowSpacing
    readonly property bool resultScrollVisible: resultCount > maximumVisibleResults
    readonly property bool resultScrollBarActive: resultScrollBar.policy !== ScrollBar.AlwaysOff
    readonly property real contentWidth: Theme.spacing.xxl * 15

    readonly property var rows: buildRows(searchInput.text)
    readonly property int resultCount: rows.length
    readonly property string selectedId: selectedApplication() === null ? "" : selectedApplication(
                                                                              ).id
    readonly property string selectedName: selectedApplication() === null ? "" : selectedApplication(
                                                                                ).name
    readonly property bool searchFocused: searchInput.activeFocus
    readonly property bool emptyStateVisible: emptyState.visible
    readonly property alias searchFieldItem: searchField
    readonly property alias resultViewportItem: resultViewport
    readonly property alias resultListItem: resultList

    property string retainedSelectionId: ""
    property int pendingLaunchRequestId: 0
    property string launchFailure: ""
    property string pinStatus: ""
    implicitWidth: frame.implicitWidth
    implicitHeight: frame.implicitHeight
    visible: active

    signal cancelled(real ownerEpoch)
    signal launchDispatched(int requestId, real ownerEpoch)

    function normalizeText(value) {
        return String(value ?? "").normalize("NFKD").toLocaleLowerCase().replace(/[\u0300-\u036f]/g,
                                                                                 "").trim().replace(
                    /\s+/g, " ");
    }

    function buildSearchIndex() {
        const indexById = {};
        if (applicationModel === null || applicationModel === undefined) {
            return indexById;
        }
        for (let index = 0; index < applicationModel.applications.length; ++index) {
            const application = applicationModel.applications[index];
            const keywords = [];
            for (let keywordIndex = 0; keywordIndex < application.keywords.length; ++keywordIndex) {
                keywords.push(normalizeText(application.keywords[keywordIndex]));
            }
            indexById[application.id] = {
                "name": normalizeText(application.name),
                "keywords": keywords
            };
        }
        return indexById;
    }

    function matchQuality(application, normalizedQuery) {
        const indexed = normalizedSearchIndex[application.id];
        if (indexed === undefined) {
            return -1;
        }
        const name = indexed.name;
        if (name === normalizedQuery) {
            return 0;
        }
        if (name.startsWith(normalizedQuery)) {
            return 1;
        }
        if ((" " + name).indexOf(" " + normalizedQuery) !== -1) {
            return 2;
        }
        if (name.indexOf(normalizedQuery) !== -1) {
            return 3;
        }

        let best = -1;
        for (let index = 0; index < indexed.keywords.length; ++index) {
            const keyword = indexed.keywords[index];
            const quality = keyword === normalizedQuery ? 4 : keyword.startsWith(normalizedQuery) ? 5 :
                                                                                                    keyword.indexOf(
                                                                                                        normalizedQuery)
                                                                                                    !== -1 ? 6 :
                                                                                                             -1;
            if (quality !== -1 && (best === -1 || quality < best)) {
                best = quality;
            }
        }
        return best;
    }

    function compareSearchRows(left, right) {
        if (left.quality !== right.quality) {
            return left.quality - right.quality;
        }
        const leftPinned = left.pinIndex >= 0;
        const rightPinned = right.pinIndex >= 0;
        if (leftPinned !== rightPinned) {
            return leftPinned ? -1 : 1;
        }
        if (leftPinned && left.pinIndex !== right.pinIndex) {
            return left.pinIndex - right.pinIndex;
        }
        const leftRecent = left.recencyIndex >= 0;
        const rightRecent = right.recencyIndex >= 0;
        if (leftRecent !== rightRecent) {
            return leftRecent ? -1 : 1;
        }
        if (leftRecent && left.recencyIndex !== right.recencyIndex) {
            return left.recencyIndex - right.recencyIndex;
        }
        if (left.application.nameOrder !== right.application.nameOrder) {
            return left.application.nameOrder - right.application.nameOrder;
        }
        return left.application.idOrder - right.application.idOrder;
    }

    function buildRows(query) {
        if (applicationModel === null || applicationModel === undefined ||
                !applicationModel.initialized) {
            return [];
        }

        const normalizedQuery = normalizeText(query);
        const pinIndex = {};
        const recencyIndex = {};
        for (let index = 0; index < applicationModel.pinIds.length; ++index) {
            pinIndex[applicationModel.pinIds[index]] = index;
        }
        for (let index = 0; index < applicationModel.recencyIds.length; ++index) {
            recencyIndex[applicationModel.recencyIds[index]] = index;
        }

        if (normalizedQuery === "") {
            const result = [];
            for (let index = 0; index < applicationModel.pinnedApplications.length; ++index) {
                result.push({
                                "application": applicationModel.pinnedApplications[index],
                                "section": index === 0 ? qsTr("Pinned") : "",
                                "pinIndex": pinIndex[applicationModel.pinnedApplications[index].id],
                                "recencyIndex":
                                recencyIndex[applicationModel.pinnedApplications[index].id] ?? -1
                            });
            }
            for (let index = 0; index < applicationModel.recentApplications.length; ++index) {
                result.push({
                                "application": applicationModel.recentApplications[index],
                                "section": index === 0 ? qsTr("Recent") : "",
                                "pinIndex": -1,
                                "recencyIndex":
                                recencyIndex[applicationModel.recentApplications[index].id]
                            });
            }
            return result;
        }

        const matches = [];
        for (let index = 0; index < applicationModel.applications.length; ++index) {
            const application = applicationModel.applications[index];
            const quality = matchQuality(application, normalizedQuery);
            if (quality === -1) {
                continue;
            }
            const candidate = {
                "application": application,
                "quality": quality,
                "pinIndex": pinIndex[application.id] ?? -1,
                "recencyIndex": recencyIndex[application.id] ?? -1
            };
            let insertionIndex = 0;
            while (insertionIndex < matches.length && compareSearchRows(matches[insertionIndex],
                                                                        candidate) <= 0) {
                insertionIndex += 1;
            }
            if (insertionIndex < 8) {
                matches.splice(insertionIndex, 0, candidate);
                if (matches.length > 8) {
                    matches.pop();
                }
            }
        }
        return matches;
    }

    function selectedApplication() {
        if (resultList.currentIndex < 0 || resultList.currentIndex >= rows.length) {
            return null;
        }
        return rows[resultList.currentIndex].application;
    }

    function restoreSelection() {
        let index = -1;
        if (retainedSelectionId !== "") {
            for (let candidate = 0; candidate < rows.length; ++candidate) {
                if (rows[candidate].application.id === retainedSelectionId) {
                    index = candidate;
                    break;
                }
            }
        }
        resultList.currentIndex = index >= 0 ? index : rows.length > 0 ? 0 : -1;
        if (resultList.currentIndex >= 0) {
            retainedSelectionId = rows[resultList.currentIndex].application.id;
            resultList.positionViewAtIndex(resultList.currentIndex, ListView.Contain);
        } else {
            retainedSelectionId = "";
        }
    }

    function selectIndex(index) {
        if (rows.length === 0) {
            resultList.currentIndex = -1;
            retainedSelectionId = "";
            return;
        }
        resultList.currentIndex = Math.max(0, Math.min(index, rows.length - 1));
        retainedSelectionId = rows[resultList.currentIndex].application.id;
        resultList.positionViewAtIndex(resultList.currentIndex, ListView.Contain);
    }

    function selectRelative(offset) {
        selectIndex((resultList.currentIndex < 0 ? 0 : resultList.currentIndex) + offset);
    }

    function focusRow(index, reason) {
        selectIndex(index);
        Qt.callLater(function () {
            if (resultList.currentItem !== null) {
                resultList.currentItem.forceActiveFocus(reason);
            }
        });
    }

    function focusInitialControl() {
        searchInput.forceActiveFocus(Qt.ShortcutFocusReason);
        searchInput.selectAll();
    }

    function requestCancellation() {
        cancelled(ownerEpoch);
    }

    function launchSelected() {
        const application = selectedApplication();
        if (application === null || pendingLaunchRequestId !== 0) {
            return false;
        }
        launchFailure = "";
        const requestId = applicationModel.dispatchLaunch(application.id);
        if (requestId <= 0) {
            launchFailure = qsTr("Application is no longer available.");
            applicationModel.captureDiscoveryGeneration();
            return false;
        }
        pendingLaunchRequestId = requestId;
        launchDispatched(requestId, ownerEpoch);
        return true;
    }

    function toggleSelectedPin() {
        const application = selectedApplication();
        if (application === null || applicationModel.pinMutationPending) {
            return false;
        }
        pinStatus = "";
        const pinned = applicationModel.pinIds.indexOf(application.id) !== -1;
        const accepted = pinned ? applicationModel.unpin(application.id) : applicationModel.pin(
                                      application.id);
        if (!accepted) {
            pinStatus = applicationModel.pinFailure === "limit" ? qsTr(
                                                                      "The eight-pin limit is full.") :
                                                                  qsTr("Pin change is unavailable.");
        }
        return accepted;
    }

    function moveSelectedPin(offset) {
        const application = selectedApplication();
        if (application === null || applicationModel.pinMutationPending) {
            return false;
        }
        const index = applicationModel.pinIds.indexOf(application.id);
        if (index < 0 || index + offset < 0 || index + offset >= applicationModel.pinIds.length) {
            return false;
        }
        pinStatus = "";
        return applicationModel.movePin(application.id, index + offset);
    }

    onRowsChanged: Qt.callLater(restoreSelection)

    // Escape is owned by the shared frame so every interactive view restores identically.

    Connections {
        target: view.applicationModel
        ignoreUnknownSignals: true

        function onLaunchAccepted(requestId, desktopFileId) {
            if (requestId === view.pendingLaunchRequestId) {
                view.pendingLaunchRequestId = 0;
            }
        }

        function onLaunchRejected(requestId, category) {
            if (requestId !== view.pendingLaunchRequestId) {
                return;
            }
            view.pendingLaunchRequestId = 0;
            view.launchFailure = category === "ineligible" ? qsTr(
                                                                 "Application is no longer available.") :
                                                             qsTr("Application could not be launched.");
        }

        function onPinCommitted(desktopFileId) {
            view.pinStatus = qsTr("Pinned.");
        }

        function onPinRemoved(desktopFileId) {
            view.pinStatus = qsTr("Unpinned.");
        }

        function onPinReordered(desktopFileId) {
            view.pinStatus = qsTr("Pin order saved.");
        }

        function onPinMutationFailed(category) {
            view.pinStatus = qsTr("Pin changes could not be saved.");
        }
    }

    SubviewFrame {
        id: frame

        anchors.fill: parent
        active: view.active
        title: qsTr("Applications")
        reducedMotion: view.reducedMotion
        initialFocusItem: searchInput
        onBackRequested: view.requestCancellation()
        onEscapePressed: view.requestCancellation()

        Item {
            implicitWidth: view.contentWidth
            implicitHeight: launcherContent.implicitHeight
            width: implicitWidth
            height: implicitHeight
            ColumnLayout {
                id: launcherContent

                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Theme.spacing.md

                Rectangle {
                    id: searchField
                    Layout.fillWidth: true
                    implicitHeight: Theme.size.controlHeightLg
                    radius: Theme.radius.md
                    color: Theme.color.controlFill
                    border.width: Theme.size.hairlineWidth
                    border.color: searchInput.activeFocus ? Theme.snapshot.focusRing :
                                                            Theme.color.surfaceBorder

                    IslandText {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacing.md
                        text: qsTr("Search applications")
                        textFormat: Text.PlainText
                        tone: "muted"
                        verticalAlignment: Text.AlignVCenter
                        visible: searchInput.text === ""
                    }

                    TextInput {
                        id: searchInput

                        anchors.fill: parent
                        leftPadding: Theme.spacing.md
                        rightPadding: Theme.spacing.md
                        color: Theme.color.textPrimary
                        selectionColor: Theme.snapshot.accent
                        selectedTextColor: Theme.snapshot.accentForeground
                        font.pixelSize: Theme.type.body
                        font.family: Theme.type.family
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        activeFocusOnTab: true
                        inputMethodHints: Qt.ImhNoPredictiveText
                        Accessible.role: Accessible.EditableText
                        Accessible.name: qsTr("Search applications")
                        KeyNavigation.backtab: frame.backControl

                        onTextChanged: {
                            view.retainedSelectionId = "";
                            view.launchFailure = "";
                            Qt.callLater(view.restoreSelection);
                        }

                        Keys.priority: Keys.BeforeItem
                        Keys.onDownPressed: event => {
                            view.focusRow(resultList.currentIndex < 0 ? 0 : resultList.currentIndex,
                                          Qt.TabFocusReason);
                            event.accepted = true;
                        }
                        Keys.onUpPressed: event => {
                            view.selectRelative(-1);
                            event.accepted = true;
                        }
                        Keys.onReturnPressed: event => {
                            view.launchSelected();
                            event.accepted = true;
                        }
                        Keys.onEnterPressed: event => {
                            view.launchSelected();
                            event.accepted = true;
                        }
                    }
                }

                Item {
                    id: resultViewport
                    Layout.fillWidth: true
                    implicitHeight: view.resultViewportHeight

                    ListView {
                        id: resultList

                        anchors.fill: parent
                        clip: view.resultScrollVisible
                        interactive: view.resultScrollVisible
                        spacing: view.resultRowSpacing
                        reuseItems: true
                        keyNavigationEnabled: false
                        model: view.rows
                        currentIndex: view.rows.length > 0 ? 0 : -1
                        Accessible.role: Accessible.List
                        Accessible.name: qsTr("Application results")

                        delegate: FocusScope {
                            id: row

                            required property int index
                            required property var modelData

                            readonly property var application: modelData.application
                            readonly property bool selected: ListView.isCurrentItem
                            readonly property int storedPinIndex:
                            view.applicationModel.pinIds.indexOf(application.id)
                            readonly property real labelLaneWidth: labelColumn.width
                            readonly property real primaryLabelWidth: primaryLabel.width
                            readonly property real metadataLabelWidth: metadataLabel.width
                            readonly property real pinActionRightEdge: pinAction.mapToItem(row,
                                                                                           pinAction.width,
                                                                                           0).x
                            readonly property bool pinned: storedPinIndex >= 0

                            width: ListView.view.width
                            implicitHeight: view.resultRowExtent
                            activeFocusOnTab: true
                            Accessible.role: Accessible.ListItem
                            Accessible.name: application.name
                            Accessible.description: pinned ? qsTr("Pinned application") : qsTr(
                                                                 "Application")

                            onActiveFocusChanged: {
                                if (activeFocus) {
                                    view.selectIndex(index);
                                }
                            }

                            Keys.priority: Keys.BeforeItem
                            Keys.onDownPressed: event => {
                                view.focusRow(index + 1, Qt.TabFocusReason);
                                event.accepted = true;
                            }
                            Keys.onUpPressed: event => {
                                if (index === 0) {
                                    searchInput.forceActiveFocus(Qt.BacktabFocusReason);
                                } else {
                                    view.focusRow(index - 1, Qt.BacktabFocusReason);
                                }
                                event.accepted = true;
                            }
                            Keys.onReturnPressed: event => {
                                view.launchSelected();
                                event.accepted = true;
                            }
                            Keys.onEnterPressed: event => {
                                view.launchSelected();
                                event.accepted = true;
                            }
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_P && (event.modifiers
                                                               & Qt.ControlModifier)) {
                                    view.toggleSelectedPin();
                                    event.accepted = true;
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.radius.md
                                color: row.selected ? Theme.color.surfaceActive : hover.hovered
                                                      ? Theme.color.surfaceHover : "transparent"
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacing.md
                                anchors.rightMargin: Theme.spacing.sm
                                spacing: Theme.spacing.md

                                IslandIcon {
                                    objectName: "launcherApplicationIcon"
                                    Layout.preferredWidth: Theme.size.iconSizeLg
                                    Layout.preferredHeight: Theme.size.iconSizeLg
                                    meaning: "application"
                                    size: "lg"
                                    applicationSource: row.application.icon === "" ? "" :
                                                                                     Quickshell.iconPath(
                                                                                         row.application.icon)
                                    applicationName: row.application.name
                                }

                                ColumnLayout {
                                    id: labelColumn
                                    Layout.fillWidth: true
                                    spacing: 0

                                    IslandText {
                                        id: primaryLabel
                                        text: row.application.name
                                        textFormat: Text.PlainText
                                        font.weight: Theme.type.weightSemibold
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    IslandText {
                                        id: metadataLabel
                                        text: (row.modelData.section ?? "") !== ""
                                              ? row.modelData.section : row.pinned ? qsTr("Pinned") :
                                                                                     qsTr("Application")
                                        textFormat: Text.PlainText
                                        tone: "secondary"
                                        size: "caption"
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                IslandButton {
                                    id: pinAction
                                    label: row.pinned ? qsTr("Unpin") : qsTr("Pin")
                                    visible: row.selected || row.activeFocus || activeFocus
                                             || hover.hovered
                                    enabled: !view.applicationModel.pinMutationPending
                                    Accessible.description: (row.pinned ? qsTr("Unpin ") : qsTr(
                                                                              "Pin "))
                                                            + row.application.name
                                    onClicked: {
                                        view.selectIndex(row.index);
                                        view.toggleSelectedPin();
                                    }
                                }

                                IslandButton {
                                    label: qsTr("Earlier")
                                    visible: row.pinned && (row.selected || row.activeFocus
                                                            || activeFocus || hover.hovered)
                                    enabled: !view.applicationModel.pinMutationPending
                                             && row.storedPinIndex > 0
                                    Accessible.description: qsTr(
                                                                "Move %1 earlier in pinned applications").arg(
                                                                row.application.name)
                                    onClicked: {
                                        view.selectIndex(row.index);
                                        view.moveSelectedPin(-1);
                                    }
                                }

                                IslandButton {
                                    label: qsTr("Later")
                                    visible: row.pinned && (row.selected || row.activeFocus
                                                            || activeFocus || hover.hovered)
                                    enabled: !view.applicationModel.pinMutationPending
                                             && row.storedPinIndex >= 0 && row.storedPinIndex
                                             < view.applicationModel.pinIds.length - 1
                                    Accessible.description: qsTr(
                                                                "Move %1 later in pinned applications").arg(
                                                                row.application.name)
                                    onClicked: {
                                        view.selectIndex(row.index);
                                        view.moveSelectedPin(1);
                                    }
                                }
                            }

                            IslandFocusRing {
                                visible: row.activeFocus
                            }

                            HoverHandler {
                                id: hover
                            }

                            TapHandler {
                                acceptedButtons: Qt.LeftButton
                                onTapped: {
                                    view.selectIndex(row.index);
                                    row.forceActiveFocus(Qt.MouseFocusReason);
                                }
                                onDoubleTapped: view.launchSelected()
                            }
                        }

                        ScrollBar.vertical: ScrollBar {
                            id: resultScrollBar
                            objectName: "launcherResultScrollBar"
                            policy: view.resultScrollVisible ? ScrollBar.AlwaysOn :
                                                               ScrollBar.AlwaysOff
                        }
                    }

                    IslandText {
                        id: emptyState

                        anchors.centerIn: parent
                        visible: view.applicationModel === null || !view.applicationModel.available
                                 || view.rows.length === 0
                        text: view.applicationModel === null || !view.applicationModel.available
                              ? qsTr("Applications unavailable") : searchInput.text === "" ? qsTr(
                                                                                                 "No pinned or recent applications") :
                                                                                             qsTr("No matches")
                        textFormat: Text.PlainText
                        tone: "secondary"
                    }
                }

                IslandText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: view.launchFailure !== "" ? view.launchFailure : view.pinStatus
                    textFormat: Text.PlainText
                    color: view.launchFailure !== "" || view.applicationModel.pinFailure
                           === "write" ? Theme.color.danger : Theme.color.textSecondary
                    size: "caption"
                    elide: Text.ElideRight
                }
            }
        }
    }
}

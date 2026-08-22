pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

FocusScope {
    id: view

    required property var applicationModel
    required property real ownerEpoch
    property alias query: searchInput.text
    readonly property var normalizedSearchIndex: buildSearchIndex()

    readonly property var rows: buildRows(searchInput.text)
    readonly property int resultCount: rows.length
    readonly property string selectedId: selectedApplication() === null ? "" : selectedApplication(
                                                                              ).id
    readonly property string selectedName: selectedApplication() === null ? "" : selectedApplication(
                                                                                ).name
    readonly property bool searchFocused: searchInput.activeFocus
    readonly property bool emptyStateVisible: emptyState.visible

    property string retainedSelectionId: ""
    property int pendingLaunchRequestId: 0
    property string launchFailure: ""
    property string pinStatus: ""

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
                                "section": index === 0 ? "Pinned" : "",
                                "pinIndex": pinIndex[applicationModel.pinnedApplications[index].id],
                                "recencyIndex":
                                recencyIndex[applicationModel.pinnedApplications[index].id] ?? -1
                            });
            }
            for (let index = 0; index < applicationModel.recentApplications.length; ++index) {
                result.push({
                                "application": applicationModel.recentApplications[index],
                                "section": index === 0 ? "Recent" : "",
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
            launchFailure = "Application is no longer available.";
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
            pinStatus = applicationModel.pinFailure === "limit" ? "The eight-pin limit is full." :
                                                                  "Pin change is unavailable.";
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

    Keys.priority: Keys.BeforeItem
    Keys.onEscapePressed: event => {
        requestCancellation();
        event.accepted = true;
    }

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
            view.launchFailure = category === "ineligible" ? "Application is no longer available." :
                                                             "Application could not be launched.";
        }

        function onPinCommitted(desktopFileId) {
            view.pinStatus = "Pinned.";
        }

        function onPinRemoved(desktopFileId) {
            view.pinStatus = "Unpinned.";
        }

        function onPinReordered(desktopFileId) {
            view.pinStatus = "Pin order saved.";
        }

        function onPinMutationFailed(category) {
            view.pinStatus = "Pin changes could not be saved.";
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing.xl
        spacing: Theme.spacing.md

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.md

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.xs

                IslandText {
                    text: "Applications"
                    textFormat: Text.PlainText
                    size: "title"
                    font.weight: Theme.type.weightSemibold
                }

                IslandText {
                    text: "Search installed applications by name or keyword."
                    textFormat: Text.PlainText
                    tone: "secondary"
                }
            }

            IslandButton {
                id: backButton

                label: "Back"
                Accessible.description: "Cancel the launcher and restore the previous island state"
                onClicked: view.requestCancellation()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.size.controlHeightLg
            radius: Theme.radius.md
            color: Theme.color.controlFill
            border.width: Theme.size.hairlineWidth
            border.color: searchInput.activeFocus ? Theme.color.focusRing :
                                                    Theme.color.surfaceBorder

            IslandText {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacing.md
                text: "Search applications"
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
                selectionColor: Theme.color.accent
                selectedTextColor: Theme.color.accentForeground
                font.pixelSize: Theme.type.body
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                activeFocusOnTab: true
                inputMethodHints: Qt.ImhNoPredictiveText
                Accessible.role: Accessible.EditableText
                Accessible.name: "Search applications"

                onTextChanged: {
                    view.retainedSelectionId = "";
                    view.launchFailure = "";
                    Qt.callLater(view.restoreSelection);
                }

                Keys.priority: Keys.BeforeItem
                Keys.onDownPressed: event => {
                    view.selectRelative(1);
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
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: resultList

                anchors.fill: parent
                clip: true
                spacing: Theme.spacing.sm
                reuseItems: true
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationEnabled: false
                model: view.rows
                currentIndex: view.rows.length > 0 ? 0 : -1
                Accessible.role: Accessible.List
                Accessible.name: "Application results"

                delegate: FocusScope {
                    id: row

                    required property int index
                    required property var modelData

                    readonly property var application: modelData.application
                    readonly property bool selected: ListView.isCurrentItem
                    readonly property int storedPinIndex: view.applicationModel.pinIds.indexOf(
                                                              application.id)
                    readonly property bool pinned: storedPinIndex >= 0

                    width: ListView.view.width
                    implicitHeight: content.implicitHeight + Theme.spacing.md * 2
                    activeFocusOnTab: true
                    Accessible.role: Accessible.ListItem
                    Accessible.name: application.name
                    Accessible.description: pinned ? "Pinned application" : "Application"

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
                        view.focusRow(index - 1, Qt.BacktabFocusReason);
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
                        if (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier)) {
                            view.toggleSelectedPin();
                            event.accepted = true;
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radius.md
                        color: row.selected || row.activeFocus || hover.hovered
                               ? Theme.color.controlFillHover : Theme.color.controlFill
                        border.width: Theme.size.hairlineWidth
                        border.color: row.activeFocus ? Theme.color.focusRing : row.selected
                                                        ? Theme.color.accent :
                                                          Theme.color.surfaceBorder
                    }

                    RowLayout {
                        id: content

                        anchors.fill: parent
                        anchors.margins: Theme.spacing.md
                        spacing: Theme.spacing.md

                        IconImage {
                            Layout.preferredWidth: Theme.size.iconSizeLg
                            Layout.preferredHeight: Theme.size.iconSizeLg
                            source: Quickshell.iconPath(row.application.icon === ""
                                                        ? "application-x-executable" :
                                                          row.application.icon)
                            implicitSize: Theme.size.iconSizeLg
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacing.xs

                            IslandText {
                                text: row.application.name
                                textFormat: Text.PlainText
                                font.weight: Theme.type.weightSemibold
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            IslandText {
                                text: (row.modelData.section ?? "") !== "" ? row.modelData.section :
                                                                             row.pinned ? "Pinned" :
                                                                                          "Application"
                                textFormat: Text.PlainText
                                tone: "secondary"
                                size: "caption"
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        IslandButton {
                            label: row.pinned ? "Unpin" : "Pin"
                            visible: row.selected || row.activeFocus || activeFocus || hover.hovered
                            enabled: !view.applicationModel.pinMutationPending
                            Accessible.description: (row.pinned ? "Unpin " : "Pin ")
                                                    + row.application.name
                            onClicked: {
                                view.selectIndex(row.index);
                                view.toggleSelectedPin();
                            }
                        }

                        IslandButton {
                            label: "Earlier"
                            visible: row.pinned && (row.selected || row.activeFocus || activeFocus
                                                    || hover.hovered)
                            enabled: !view.applicationModel.pinMutationPending
                                     && row.storedPinIndex > 0
                            Accessible.description: "Move " + row.application.name
                                                    + " earlier in pinned applications"
                            onClicked: {
                                view.selectIndex(row.index);
                                view.moveSelectedPin(-1);
                            }
                        }

                        IslandButton {
                            label: "Later"
                            visible: row.pinned && (row.selected || row.activeFocus || activeFocus
                                                    || hover.hovered)
                            enabled: !view.applicationModel.pinMutationPending
                                     && row.storedPinIndex >= 0 && row.storedPinIndex
                                     < view.applicationModel.pinIds.length - 1
                            Accessible.description: "Move " + row.application.name
                                                    + " later in pinned applications"
                            onClicked: {
                                view.selectIndex(row.index);
                                view.moveSelectedPin(1);
                            }
                        }
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
            }

            Column {
                id: emptyState

                anchors.centerIn: parent
                spacing: Theme.spacing.xs
                visible: view.applicationModel === null || !view.applicationModel.available
                         || view.rows.length === 0

                IslandText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: view.applicationModel === null || !view.applicationModel.available
                          ? "Applications are unavailable." : searchInput.text === ""
                            ? "No pinned or recent applications." : "No matching applications."
                    textFormat: Text.PlainText
                    tone: "secondary"
                }
            }
        }

        IslandText {
            Layout.fillWidth: true
            visible: text !== ""
            text: view.launchFailure !== "" ? view.launchFailure : view.pinStatus
            textFormat: Text.PlainText
            color: view.launchFailure !== "" || view.applicationModel.pinFailure === "write"
                   ? Theme.color.danger : Theme.color.textSecondary
            size: "caption"
            elide: Text.ElideRight
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FocusScope {
    id: view

    required property var adapter
    required property real ownerEpoch
    property var applicationModel: null
    property var easyEffectsStatus: null
    property bool active: true
    property bool reducedMotion: false
    property real maximumViewportWidth: Number.POSITIVE_INFINITY
    property real maximumViewportHeight: Number.POSITIVE_INFINITY

    readonly property string easyEffectsDesktopId: "com.github.wwmm.easyeffects.desktop"
    readonly property var outputCandidates: adapter === null ? [] : adapter.outputCandidates
    readonly property var inputCandidates: adapter === null ? [] : adapter.inputCandidates
    readonly property bool outputPending: adapter !== null && adapter.pendingOutputSelection
    readonly property bool inputPending: adapter !== null && adapter.pendingInputSelection
    readonly property bool pipelinesVisible: candidateCount > 0 || outputInternalDefault
                                             || inputInternalDefault
    readonly property bool selectionPending: outputPending || inputPending
    readonly property int candidateCount: outputCandidates.length + inputCandidates.length
    readonly property real columnGap: Theme.spacing.lg
    readonly property real singleColumnWidth: Math.max(Theme.size.audioEmptyContentMinimumWidth,
                                                       outputSection.naturalWidth,
                                                       inputSection.naturalWidth)
    readonly property real twoColumnWidth: singleColumnWidth * 2 + columnGap
    readonly property bool twoColumnLayout: maximumViewportWidth >= 572
    readonly property real naturalContentWidth: !pipelinesVisible
                                                ? Theme.size.audioEmptyContentMinimumWidth :
                                                  twoColumnLayout ? twoColumnWidth :
                                                                    singleColumnWidth
    readonly property bool backFocused: frame.backControl.activeFocus
    readonly property bool outputInternalDefault: adapter !== null
                                                  && adapter.outputEasyEffectsInternalDefault
                                                  === true
    readonly property bool inputInternalDefault: adapter !== null
                                                 && adapter.inputEasyEffectsInternalDefault === true
    readonly property bool easyEffectsAvailable: {
        if (applicationModel === null || applicationModel === undefined
            || applicationModel.available !== true || typeof applicationModel.eligible
            !== "function") {
            return false;
        }
        const discoveryGeneration = applicationModel.applications;
        return discoveryGeneration !== undefined && applicationModel.eligible(easyEffectsDesktopId)
        === true;
    }
    readonly property bool presetStatusRefreshing: easyEffectsStatus !== null && easyEffectsStatus
                                                   !== undefined && easyEffectsStatus.refreshing
                                                   === true
    readonly property bool presetStatusReady: easyEffectsStatus !== null && easyEffectsStatus
                                              !== undefined && easyEffectsStatus.ready === true
    readonly property bool presetLoadPending: easyEffectsStatus !== null && easyEffectsStatus
                                              !== undefined && easyEffectsStatus.loadPending
                                              === true
    readonly property var outputPresetCandidates: easyEffectsStatus !== null && easyEffectsStatus
                                                  !== undefined && Array.isArray(
                                                      easyEffectsStatus.outputPresets)
                                                  ? easyEffectsStatus.outputPresets : []
    readonly property var inputPresetCandidates: easyEffectsStatus !== null && easyEffectsStatus
                                                 !== undefined && Array.isArray(
                                                     easyEffectsStatus.inputPresets)
                                                 ? easyEffectsStatus.inputPresets : []

    property string openRole: ""
    property int easyEffectsLaunchRequestId: 0
    property string easyEffectsLaunchFailure: ""
    property real presetStatusOwnerEpoch: 0
    readonly property var openDropdown: openRole === "output" ? outputSection : openRole
                                                                === "input" ? inputSection :
                                                                              openRole
                                                                              === "preset-output"
                                                                              ? outputPresetRow :
                                                                                openRole
                                                                                === "preset-input"
                                                                                ? inputPresetRow :
                                                                                  null

    implicitWidth: frame.implicitWidth
    implicitHeight: frame.implicitHeight
    visible: active

    signal cancelled(real ownerEpoch)
    function popupOverlayPosition(control, popupWidth, popupHeight) {
        const below = control.mapToItem(contentRoot, 0, control.height + Theme.spacing.xs);
        const above = control.mapToItem(contentRoot, 0, -popupHeight - Theme.spacing.xs);
        const maximumX = Math.max(0, contentRoot.width - popupWidth);
        const maximumY = Math.max(0, contentRoot.height - popupHeight);
        const preferredY = below.y + popupHeight <= contentRoot.height ? below.y : above.y >= 0
                                                                         ? above.y : maximumY;
        return Qt.point(Math.max(0, Math.min(maximumX, below.x)), Math.max(0, Math.min(maximumY,
                                                                                       preferredY)));
    }

    function failureText(failure) {
        if (failure === "removed") {
            return qsTr("The selected device is no longer available.");
        }
        if (failure === "rejected" || failure === "diverged") {
            return qsTr("PipeWire kept a different device selected.");
        }
        if (failure === "timeout") {
            return qsTr("PipeWire did not confirm the device change.");
        }
        if (failure === "unavailable" || failure === "bridge-unavailable") {
            return qsTr("Audio device selection is unavailable.");
        }
        if (failure !== "none") {
            return qsTr("The audio device could not be selected.");
        }
        return "";
    }
    function presetStatusText(state, name) {
        if (state === "lastLoaded" && typeof name === "string" && name !== "") {
            return name;
        }
        if (state === "none") {
            return qsTr("None reported");
        }
        if ((easyEffectsStatus !== null && easyEffectsStatus.interested === true) && (state
                                                                                      === "unknown"
                                                                                      || presetStatusRefreshing)) {
            return qsTr("Reading…");
        }
        if (state === "timeout") {
            return qsTr("Read timed out");
        }
        return qsTr("Status unavailable");
    }

    function syncPresetStatusInterest() {
        const shouldActivate = active && easyEffectsAvailable && easyEffectsStatus !== null
              && easyEffectsStatus !== undefined && typeof easyEffectsStatus.activate
              === "function" && typeof easyEffectsStatus.deactivate === "function";
        if (shouldActivate && presetStatusOwnerEpoch !== ownerEpoch) {
            if (presetStatusOwnerEpoch > 0) {
                easyEffectsStatus.deactivate(presetStatusOwnerEpoch);
            }
            presetStatusOwnerEpoch = easyEffectsStatus.activate(ownerEpoch) ? ownerEpoch : 0;
        } else if (!shouldActivate && presetStatusOwnerEpoch > 0) {
            easyEffectsStatus.deactivate(presetStatusOwnerEpoch);
            presetStatusOwnerEpoch = 0;
        }
    }

    function refreshPresetStatus() {
        return presetStatusOwnerEpoch > 0 && easyEffectsStatus !== null
                && typeof easyEffectsStatus.refresh === "function" && easyEffectsStatus.refresh(
                    presetStatusOwnerEpoch);
    }

    function canLoadPreset(pipeline, name) {
        const candidates = pipeline === "output" ? outputPresetCandidates : pipeline === "input"
                                                   ? inputPresetCandidates : [];
        return presetStatusOwnerEpoch > 0 && presetStatusReady && !presetStatusRefreshing &&
                !presetLoadPending && candidates.indexOf(name) !== -1;
    }

    function requestPresetLoad(pipeline, name) {
        return canLoadPreset(pipeline, name) && typeof easyEffectsStatus.loadPreset === "function"
                && easyEffectsStatus.loadPreset(presetStatusOwnerEpoch, pipeline, name);
    }

    function presetLoadFailureText(pipeline) {
        if (easyEffectsStatus === null || easyEffectsStatus === undefined
                || easyEffectsStatus.loadPipeline !== pipeline || easyEffectsStatus.loadPending) {
            return "";
        }
        if (easyEffectsStatus.loadState === "mismatch") {
            return qsTr("EasyEffects did not confirm that preset.");
        }
        if (easyEffectsStatus.loadState === "timeout") {
            return qsTr("Preset confirmation timed out.");
        }
        if (easyEffectsStatus.loadState === "invalid") {
            return qsTr("The preset name or response was invalid.");
        }
        if (easyEffectsStatus.loadState === "unavailable") {
            return qsTr("EasyEffects preset control is unavailable.");
        }
        return "";
    }

    function focusInitialControl() {
        const target = outputSection.control.enabled ? outputSection.control :
                                                       inputSection.control.enabled
                                                       ? inputSection.control :
                                                         outputPresetRow.control.enabled
                                                         ? outputPresetRow.control :
                                                           inputPresetRow.control.enabled
                                                           ? inputPresetRow.control :
                                                             easyEffectsOpenButton.visible
                                                             && easyEffectsOpenButton.enabled
                                                             ? easyEffectsOpenButton : null;
        if (target !== null) {
            target.forceActiveFocus(Qt.ShortcutFocusReason);
            return true;
        }
        return frame.focusInitialControl();
    }

    function requestSelection(role, endpointKey) {
        if (adapter === null || selectionPending) {
            return false;
        }
        openRole = "";
        return role === "output" ? adapter.requestOutputSelection(endpointKey) : role === "input"
                                   ? adapter.requestInputSelection(endpointKey) : false;
    }

    function openEasyEffects() {
        easyEffectsLaunchFailure = "";
        if (!easyEffectsAvailable || applicationModel === null
                || typeof applicationModel.dispatchLaunch !== "function") {
            return false;
        }
        const requestId = applicationModel.dispatchLaunch(easyEffectsDesktopId);
        if (!Number.isInteger(requestId) || requestId <= 0) {
            easyEffectsLaunchFailure = qsTr("EasyEffects could not be opened.");
            return false;
        }
        easyEffectsLaunchRequestId = requestId;
        return true;
    }

    onEasyEffectsAvailableChanged: syncPresetStatusInterest()
    onEasyEffectsStatusChanged: syncPresetStatusInterest()
    onOwnerEpochChanged: syncPresetStatusInterest()
    onSelectionPendingChanged: {
        if (selectionPending) {
            openRole = "";
        }
    }
    onActiveChanged: {
        if (!active) {
            openRole = "";
            easyEffectsLaunchRequestId = 0;
            easyEffectsLaunchFailure = "";
            outputPresetRow.closePopup();
            inputPresetRow.closePopup();
        }
        syncPresetStatusInterest();
    }

    Connections {
        target: view.applicationModel
        ignoreUnknownSignals: true

        function onLaunchAccepted(requestId, desktopFileId) {
            if (requestId === view.easyEffectsLaunchRequestId && desktopFileId
                    === view.easyEffectsDesktopId) {
                view.easyEffectsLaunchRequestId = 0;
                view.easyEffectsLaunchFailure = "";
            }
        }

        function onLaunchRejected(requestId, category) {
            if (requestId === view.easyEffectsLaunchRequestId) {
                view.easyEffectsLaunchRequestId = 0;
                view.easyEffectsLaunchFailure = qsTr("EasyEffects could not be opened.");
            }
        }
    }
    Component.onCompleted: syncPresetStatusInterest()
    Component.onDestruction: {
        if (presetStatusOwnerEpoch > 0 && easyEffectsStatus !== null
            && typeof easyEffectsStatus.deactivate === "function") {
            easyEffectsStatus.deactivate(presetStatusOwnerEpoch);
        }
    }

    SubviewFrame {
        id: frame
        objectName: "audioSubviewFrame"

        anchors.fill: parent
        active: view.active
        title: qsTr("Audio devices")
        preferredViewportWidth: view.twoColumnLayout ? 572 : 278
        preferredViewportHeight: 360
        maximumViewportWidth: view.maximumViewportWidth
        maximumViewportHeight: view.maximumViewportHeight
        initialFocusItem: outputSection.control.enabled ? outputSection.control :
                                                          inputSection.control.enabled
                                                          ? inputSection.control :
                                                            outputPresetRow.control.enabled
                                                            ? outputPresetRow.control :
                                                              inputPresetRow.control.enabled
                                                              ? inputPresetRow.control :
                                                                easyEffectsOpenButton.visible
                                                                && easyEffectsOpenButton.enabled
                                                                ? easyEffectsOpenButton : null
        onBackRequested: view.cancelled(view.ownerEpoch)
        onEscapePressed: view.cancelled(view.ownerEpoch)

        Item {
            id: contentRoot
            objectName: "audioContentRoot"

            implicitWidth: view.naturalContentWidth
            implicitHeight: audioContent.implicitHeight
            width: Math.max(implicitWidth, parent.width)
            height: Math.max(implicitHeight, parent.height)

            ColumnLayout {
                id: audioContent
                objectName: "audioContent"

                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Theme.spacing.lg

                Item {
                    id: pipelineGrid
                    objectName: "audioPipelineGrid"

                    Layout.fillWidth: true
                    implicitHeight: !view.pipelinesVisible ? 0 : view.twoColumnLayout ? Math.max(
                                                                                            outputSection.implicitHeight,
                                                                                            inputSection.implicitHeight) :
                                                                                        outputSection.implicitHeight
                                                                                        + Theme.spacing.lg
                                                                                        + inputSection.implicitHeight
                    visible: view.pipelinesVisible

                    DeviceDropdown {
                        id: outputSection
                        objectName: "audioOutputSection"
                        x: 0
                        y: 0
                        width: view.twoColumnLayout ? Math.max(0, (parent.width - view.columnGap)
                                                               / 2) : parent.width
                        title: qsTr("Output device")
                        role: "output"
                        meaning: "volumeHigh"
                        candidates: view.outputCandidates
                        pending: view.outputPending
                        internalDefault: view.outputInternalDefault
                    }

                    DeviceDropdown {
                        id: inputSection
                        objectName: "audioInputSection"
                        x: view.twoColumnLayout ? outputSection.width + view.columnGap : 0
                        y: view.twoColumnLayout ? 0 : outputSection.height + Theme.spacing.lg
                        width: view.twoColumnLayout ? outputSection.width : parent.width
                        title: qsTr("Input device")
                        role: "input"
                        meaning: "microphone"
                        candidates: view.inputCandidates
                        pending: view.inputPending
                        internalDefault: view.inputInternalDefault
                    }
                }

                IslandText {
                    objectName: "audioEmptyMessage"
                    Layout.fillWidth: true
                    visible: view.adapter === null || !view.adapter.available
                             || view.candidateCount === 0
                    text: view.adapter === null || !view.adapter.available ? qsTr(
                                                                                 "Audio devices unavailable") :
                                                                             qsTr("No selectable audio devices")
                    textFormat: Text.PlainText
                    tone: "secondary"
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }

                IslandText {
                    objectName: "audioSelectionFailure"
                    Layout.fillWidth: true
                    readonly property string message: view.adapter === null ? "" : view.failureText(
                                                                                  view.adapter.failure)
                    visible: !view.selectionPending && message !== ""
                    text: message
                    textFormat: Text.PlainText
                    color: Theme.color.danger
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }

                Rectangle {
                    id: easyEffectsCapability
                    objectName: "audioEasyEffectsCapability"

                    Layout.fillWidth: true
                    implicitHeight: easyEffectsContent.implicitHeight + Theme.spacing.md * 2
                    visible: view.easyEffectsAvailable
                    radius: Theme.radius.md
                    color: Theme.color.controlFill

                    ColumnLayout {
                        id: easyEffectsContent

                        anchors.fill: parent
                        anchors.margins: Theme.spacing.md
                        spacing: Theme.spacing.sm

                        IslandText {
                            Layout.fillWidth: true
                            text: qsTr("EasyEffects presets")
                            textFormat: Text.PlainText
                            font.weight: Theme.type.weightMedium
                            Accessible.role: Accessible.Heading
                            Accessible.name: text
                        }

                        IslandText {
                            Layout.fillWidth: true
                            text: qsTr("Choose a local preset for each EasyEffects pipeline.")
                            textFormat: Text.PlainText
                            tone: "secondary"
                            size: "caption"
                            wrapMode: Text.Wrap
                            Accessible.role: Accessible.StaticText
                            Accessible.name: text
                        }

                        PresetDropdown {
                            id: outputPresetRow
                            objectName: "audioEasyEffectsOutputPreset"
                            pipeline: "output"
                            label: qsTr("Output preset")
                            currentName: view.easyEffectsStatus === null ? "" :
                                                                           view.easyEffectsStatus.outputName
                            statusValue: view.presetStatusText(view.easyEffectsStatus === null
                                                               ? "unknown" :
                                                                 view.easyEffectsStatus.outputState,
                                                               currentName)
                            candidates: view.outputPresetCandidates
                            listState: view.easyEffectsStatus === null ? "unknown" :
                                                                         view.easyEffectsStatus.outputPresetsState
                        }

                        PresetDropdown {
                            id: inputPresetRow
                            objectName: "audioEasyEffectsInputPreset"
                            pipeline: "input"
                            label: qsTr("Input preset")
                            currentName: view.easyEffectsStatus === null ? "" :
                                                                           view.easyEffectsStatus.inputName
                            statusValue: view.presetStatusText(view.easyEffectsStatus === null
                                                               ? "unknown" :
                                                                 view.easyEffectsStatus.inputState,
                                                               currentName)
                            candidates: view.inputPresetCandidates
                            listState: view.easyEffectsStatus === null ? "unknown" :
                                                                         view.easyEffectsStatus.inputPresetsState
                        }

                        IslandText {
                            Layout.fillWidth: true
                            visible: view.easyEffectsLaunchFailure !== ""
                            text: view.easyEffectsLaunchFailure
                            textFormat: Text.PlainText
                            color: Theme.color.danger
                            size: "caption"
                            wrapMode: Text.Wrap
                            Accessible.role: Accessible.StaticText
                            Accessible.name: text
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacing.sm

                            Item {
                                Layout.fillWidth: true
                            }

                            IslandButton {
                                id: easyEffectsRefreshButton
                                objectName: "audioRefreshEasyEffectsStatus"
                                label: view.presetStatusRefreshing ? qsTr("Reading…") : qsTr(
                                                                         "Refresh")
                                reducedMotion: view.reducedMotion
                                enabled: view.presetStatusReady && !view.presetStatusRefreshing &&
                                         !view.presetLoadPending && view.presetStatusOwnerEpoch > 0
                                Accessible.name: qsTr("Refresh EasyEffects preset status")
                                onClicked: view.refreshPresetStatus()
                            }

                            IslandButton {
                                id: easyEffectsOpenButton
                                objectName: "audioOpenEasyEffects"
                                label: view.easyEffectsLaunchRequestId > 0 ? qsTr("Opening…") : qsTr(
                                                                                 "Open EasyEffects")
                                reducedMotion: view.reducedMotion
                                enabled: view.easyEffectsLaunchRequestId === 0
                                Accessible.name: qsTr("Open EasyEffects")
                                onClicked: view.openEasyEffects()
                            }
                        }
                    }
                }
            }
            Rectangle {
                id: dropdownOverlay
                readonly property var controller: view.openDropdown
                readonly property bool presetItems: controller !== null && controller.isPreset
                readonly property point overlayPosition: controller === null ? Qt.point(0, 0) : view.popupOverlayPosition(
                                                                                   controller.control,
                                                                                   width, height)

                objectName: controller === null ? "audioDropdownOverlay" :
                                                  controller.popupObjectName
                x: overlayPosition.x
                y: overlayPosition.y
                z: 10
                width: controller === null ? 0 : controller.control.width
                height: controller === null ? 0 : Math.min(5, controller.candidates.length)
                                              * Theme.size.controlHeightMd + Theme.spacing.xs * 2
                visible: controller !== null && controller.popupOpen
                radius: Theme.radius.md
                color: Theme.color.surface
                border.width: Theme.size.hairlineWidth
                border.color: Theme.color.surfaceBorder
                clip: true

                ListView {
                    id: popupList

                    anchors.fill: parent
                    anchors.margins: Theme.spacing.xs
                    model: dropdownOverlay.visible ? dropdownOverlay.controller.candidates : null
                    currentIndex: -1
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    keyNavigationEnabled: false
                    Accessible.role: Accessible.List
                    Accessible.name: dropdownOverlay.controller === null ? "" :
                                                                           dropdownOverlay.controller.popupAccessibleName

                    ScrollBar.vertical: ScrollBar {
                        policy: popupList.contentHeight > popupList.height ? ScrollBar.AlwaysOn :
                                                                             ScrollBar.AlwaysOff
                    }

                    delegate: AbstractButton {
                        id: popupItem
                        required property int index
                        required property var modelData
                        readonly property string itemLabel: dropdownOverlay.controller === null
                                                            || modelData === null || modelData
                                                            === undefined ? "" :
                                                                            dropdownOverlay.presetItems
                                                                            || typeof modelData
                                                                            !== "object" ? String(
                                                                                               modelData) :
                                                                                           typeof modelData.label
                                                                                           === "string"
                                                                                           ? modelData.label :
                                                                                             ""
                        readonly property bool selected: dropdownOverlay.controller !== null && (
                                                             dropdownOverlay.presetItems
                                                             ? modelData
                                                               === dropdownOverlay.controller.currentName :
                                                               modelData.isDefault === true)

                        width: popupList.width
                        height: Theme.size.controlHeightMd
                        focusPolicy: Qt.StrongFocus
                        hoverEnabled: true
                        enabled: dropdownOverlay.controller !== null
                                 && dropdownOverlay.controller.itemsEnabled
                        Accessible.role: Accessible.ListItem
                        Accessible.name: itemLabel
                        Accessible.description: dropdownOverlay.controller === null ? "" :
                                                                                      dropdownOverlay.controller.itemDescription(
                                                                                          modelData)
                        onActiveFocusChanged: {
                            if (activeFocus && dropdownOverlay.controller !== null) {
                                dropdownOverlay.controller.highlightedIndex = index;
                                popupList.currentIndex = index;
                                popupList.positionViewAtIndex(index, ListView.Contain);
                            }
                        }
                        onClicked: {
                            if (dropdownOverlay.controller !== null) {
                                dropdownOverlay.controller.highlightedIndex = index;
                                dropdownOverlay.controller.selectHighlighted();
                            }
                        }
                        Keys.onPressed: event => {
                            if (dropdownOverlay.controller !== null) {
                                dropdownOverlay.controller.handlePopupKey(event);
                            }
                        }

                        background: Rectangle {
                            radius: Theme.radius.sm
                            color: popupItem.selected ? Theme.color.surfaceActive :
                                                        popupItem.pressed
                                                        ? Theme.snapshot.controlFillPressed :
                                                          popupItem.hovered
                                                          || popupItem.visualFocus
                                                          ? Theme.snapshot.controlFillHover :
                                                            "transparent"
                        }

                        contentItem: RowLayout {
                            spacing: Theme.spacing.sm

                            IslandText {
                                Layout.fillWidth: true
                                text: popupItem.itemLabel
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                            }

                            IslandText {
                                visible: popupItem.selected
                                text: dropdownOverlay.controller === null ? "" :
                                                                            dropdownOverlay.controller.selectedLabel
                                textFormat: Text.PlainText
                                color: Theme.snapshot.accent
                                size: "caption"
                                font.weight: Theme.type.weightMedium
                            }
                        }

                        IslandFocusRing {
                            visible: popupItem.visualFocus
                        }
                    }
                }
            }
        }
    }

    component PresetDropdown: ColumnLayout {
        id: presetRow

        required property string pipeline
        required property string label
        required property string currentName
        required property string statusValue
        required property var candidates
        required property string listState
        readonly property string role: "preset-" + pipeline
        readonly property bool isPreset: true
        readonly property string popupObjectName: "audioEasyEffects" + (pipeline === "output"
                                                                        ? "Output" : "Input")
                                                  + "PresetPopup"
        readonly property string popupAccessibleName: label
        readonly property string selectedLabel: qsTr("Last loaded")
        readonly property bool itemsEnabled: !view.presetLoadPending
        readonly property bool popupOpen: view.openRole === role
        readonly property bool pending: view.presetLoadPending
                                        && view.easyEffectsStatus.loadPipeline === pipeline
        readonly property int currentPresetIndex: candidates.indexOf(currentName)
        readonly property alias control: presetButton
        property int highlightedIndex: currentPresetIndex >= 0 ? currentPresetIndex : 0

        Layout.fillWidth: true
        spacing: Theme.spacing.xs

        function boundedIndex(index) {
            return Math.max(0, Math.min(candidates.length - 1, index));
        }
        function focusHighlighted() {
            if (!popupOpen || candidates.length === 0) {
                return;
            }
            highlightedIndex = boundedIndex(highlightedIndex);
            popupList.currentIndex = highlightedIndex;
            popupList.positionViewAtIndex(highlightedIndex, ListView.Contain);
            Qt.callLater(() => {
                if (popupList.currentItem !== null) {
                    popupList.currentItem.forceActiveFocus(Qt.ShortcutFocusReason);
                }
            });
        }

        function openPopup(index) {
            if (!presetButton.enabled) {
                return;
            }
            view.openRole = role;
            highlightedIndex = boundedIndex(index >= 0 ? index : currentPresetIndex >= 0
                                                         ? currentPresetIndex : 0);
            focusHighlighted();
        }
        function closePopup() {
            if (popupOpen) {
                view.openRole = "";
            }
        }
        function itemDescription(item) {
            return item === currentName ? qsTr("Last loaded preset") : qsTr("Load preset");
        }
        function selectHighlighted() {
            if (highlightedIndex < 0 || highlightedIndex >= candidates.length) {
                return false;
            }
            const accepted = view.requestPresetLoad(pipeline, candidates[highlightedIndex]);
            if (accepted) {
                view.openRole = "";
                presetButton.forceActiveFocus(Qt.ShortcutFocusReason);
            }
            return accepted;
        }
        function handlePopupKey(event) {
            if (event.key === Qt.Key_Escape) {
                closePopup();
                presetButton.forceActiveFocus(Qt.ShortcutFocusReason);
                event.accepted = true;
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                highlightedIndex = boundedIndex(highlightedIndex + (event.key === Qt.Key_Down ? 1 :
                                                                                                -1));
                focusHighlighted();
                event.accepted = true;
            } else if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
                highlightedIndex = event.key === Qt.Key_Home ? 0 : Math.max(0, candidates.length
                                                                            - 1);
                focusHighlighted();
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key
                       === Qt.Key_Space) {
                selectHighlighted();
                event.accepted = true;
            }
        }

        onCandidatesChanged: {
            highlightedIndex = boundedIndex(currentPresetIndex >= 0 ? currentPresetIndex :
                                                                      highlightedIndex);
            if (candidates.length === 0) {
                closePopup();
            } else if (popupOpen) {
                focusHighlighted();
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.sm

            IslandText {
                Layout.fillWidth: true
                text: presetRow.label
                textFormat: Text.PlainText
                size: "caption"
                tone: "secondary"
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            IslandText {
                Layout.maximumWidth: Theme.spacing.xxl * 5
                text: presetRow.statusValue
                textFormat: Text.PlainText
                size: "caption"
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
                Accessible.role: Accessible.StaticText
                Accessible.name: qsTr("%1, last loaded: %2").arg(presetRow.label).arg(text)
            }
        }

        AbstractButton {
            id: presetButton
            objectName: "audioEasyEffects" + (presetRow.pipeline === "output" ? "Output" : "Input")
                        + "PresetDropdown"

            Layout.fillWidth: true
            implicitHeight: Theme.size.controlHeightMd
            leftPadding: Theme.spacing.md
            rightPadding: Theme.spacing.md
            focusPolicy: Qt.StrongFocus
            hoverEnabled: true
            enabled: presetRow.candidates.length > 0 && view.presetStatusReady &&
                     !view.presetStatusRefreshing && !view.presetLoadPending
            Accessible.role: Accessible.ComboBox
            Accessible.name: presetRow.label
            Accessible.description: contentLabel.text + (presetRow.popupOpen ? ", expanded" :
                                                                               ", collapsed")
            onClicked: presetRow.popupOpen ? presetRow.closePopup() : presetRow.openPopup(
                                                 presetRow.currentPresetIndex)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                    presetRow.openPopup(presetRow.currentPresetIndex >= 0
                                        ? presetRow.currentPresetIndex : event.key === Qt.Key_Down
                                          ? 0 : presetRow.candidates.length - 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key
                           === Qt.Key_Space) {
                    presetRow.popupOpen ? presetRow.closePopup() : presetRow.openPopup(
                                              presetRow.currentPresetIndex);
                    event.accepted = true;
                }
            }

            background: Rectangle {
                radius: Theme.radius.md
                color: presetButton.pressed ? Theme.snapshot.controlFillPressed :
                                              presetButton.hovered
                                              ? Theme.snapshot.controlFillHover :
                                                Theme.color.surfaceActive
                border.width: Theme.size.hairlineWidth
                border.color: Theme.color.surfaceBorder
            }

            contentItem: RowLayout {
                spacing: Theme.spacing.sm

                IslandText {
                    id: contentLabel
                    Layout.fillWidth: true
                    text: presetRow.pending ? qsTr("Applying…") : view.presetStatusRefreshing
                                              || presetRow.listState === "unknown" ? qsTr(
                                                                                         "Reading presets…") :
                                                                                     presetRow.candidates.length
                                                                                     === 0 ? qsTr(
                                                                                                 "No presets found") :
                                                                                             presetRow.currentPresetIndex
                                                                                             >= 0 ? presetRow.currentName :
                                                                                                    qsTr("Choose a preset")
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                }
                IslandIcon {
                    meaning: "dropdown"
                    size: "sm"
                    rotation: presetRow.popupOpen ? 180 : 0
                }
            }

            IslandFocusRing {
                visible: presetButton.visualFocus
            }
        }

        IslandText {
            Layout.fillWidth: true
            readonly property string message: view.presetLoadFailureText(presetRow.pipeline)
            visible: message !== ""
            text: message
            textFormat: Text.PlainText
            color: Theme.color.danger
            size: "caption"
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        IslandText {
            Layout.fillWidth: true
            visible: presetRow.listState === "truncated"
            text: qsTr("Showing the first available presets. Refine them in EasyEffects if needed.")
            textFormat: Text.PlainText
            tone: "secondary"
            size: "caption"
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }
    }

    component DeviceDropdown: ColumnLayout {
        id: section

        required property string title
        required property string role
        required property string meaning
        required property var candidates
        required property bool pending
        required property bool internalDefault
        readonly property bool isPreset: false
        readonly property string popupObjectName: "audio" + (role === "output" ? "Output" : "Input")
                                                  + "Popup"
        readonly property string popupAccessibleName: title
        readonly property string selectedLabel: qsTr("Selected")
        readonly property bool itemsEnabled: !view.selectionPending
        readonly property real maximumLabelWidth: Theme.spacing.xxl * 7
        readonly property real naturalWidth: Math.max(Theme.size.audioEmptyContentMinimumWidth,
                                                      Theme.spacing.md * 3 + Theme.size.iconSizeMd
                                                      + maximumLabelWidth)
        readonly property int confirmedIndex: {
            for (let index = 0; index < candidates.length; ++index) {
                if (candidates[index].isDefault === true) {
                    return index;
                }
            }
            return -1;
        }
        readonly property string confirmedLabel: confirmedIndex >= 0
                                                 ? candidates[confirmedIndex].label :
                                                   internalDefault ? qsTr("Choose a device") :
                                                                     candidates.length > 0 ? qsTr(
                                                                                                 "Choose a device") :
                                                                                             qsTr("No eligible devices")
        readonly property bool popupOpen: view.openRole === role
        readonly property alias control: dropdownButton
        property int highlightedIndex: confirmedIndex >= 0 ? confirmedIndex : 0
        property string typePrefix: ""

        implicitWidth: naturalWidth
        spacing: Theme.spacing.sm

        function boundedIndex(index) {
            return Math.max(0, Math.min(candidates.length - 1, index));
        }

        function focusHighlighted() {
            if (!popupOpen || candidates.length === 0) {
                return;
            }
            highlightedIndex = boundedIndex(highlightedIndex);
            popupList.currentIndex = highlightedIndex;
            popupList.positionViewAtIndex(highlightedIndex, ListView.Contain);
            Qt.callLater(() => {
                if (popupList.currentItem !== null) {
                    popupList.currentItem.forceActiveFocus(Qt.ShortcutFocusReason);
                }
            });
        }

        function openPopup(index) {
            if (!dropdownButton.enabled) {
                return;
            }
            view.openRole = role;
            highlightedIndex = boundedIndex(index >= 0 ? index : confirmedIndex >= 0
                                                         ? confirmedIndex : 0);
            focusHighlighted();
        }

        function closePopup() {
            if (popupOpen) {
                view.openRole = "";
            }
            typePrefix = "";
            dropdownButton.forceActiveFocus(Qt.ShortcutFocusReason);
        }
        function itemDescription(item) {
            if (item.isDefault) {
                return role === "output" ? qsTr("Confirmed current output device") : qsTr(
                                               "Confirmed current input device");
            }
            return role === "output" ? qsTr("Select as output device") : qsTr(
                                           "Select as input device");
        }

        function selectHighlighted() {
            if (highlightedIndex < 0 || highlightedIndex >= candidates.length) {
                return;
            }
            const endpointKey = candidates[highlightedIndex].endpointKey;
            view.requestSelection(role, endpointKey);
            dropdownButton.forceActiveFocus(Qt.ShortcutFocusReason);
        }

        function typeNavigate(text) {
            if (typeof text !== "string" || text.length !== 1 || text < " ") {
                return false;
            }
            typePrefix += text.toLocaleLowerCase();
            typeReset.restart();
            const start = highlightedIndex < 0 ? 0 : highlightedIndex + 1;
            for (let offset = 0; offset < candidates.length; ++offset) {
                const index = (start + offset) % candidates.length;
                if (candidates[index].label.toLocaleLowerCase().startsWith(typePrefix)) {
                    highlightedIndex = index;
                    focusHighlighted();
                    return true;
                }
            }
            typePrefix = text.toLocaleLowerCase();
            for (let index = 0; index < candidates.length; ++index) {
                if (candidates[index].label.toLocaleLowerCase().startsWith(typePrefix)) {
                    highlightedIndex = index;
                    focusHighlighted();
                    return true;
                }
            }
            return false;
        }

        function handlePopupKey(event) {
            if (event.key === Qt.Key_Escape) {
                closePopup();
                event.accepted = true;
            } else if (event.key === Qt.Key_Down) {
                highlightedIndex = boundedIndex(highlightedIndex + 1);
                focusHighlighted();
                event.accepted = true;
            } else if (event.key === Qt.Key_Up) {
                highlightedIndex = boundedIndex(highlightedIndex - 1);
                focusHighlighted();
                event.accepted = true;
            } else if (event.key === Qt.Key_Home) {
                highlightedIndex = 0;
                focusHighlighted();
                event.accepted = true;
            } else if (event.key === Qt.Key_End) {
                highlightedIndex = Math.max(0, candidates.length - 1);
                focusHighlighted();
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key
                       === Qt.Key_Space) {
                selectHighlighted();
                event.accepted = true;
            } else if (typeNavigate(event.text)) {
                event.accepted = true;
            }
        }

        onCandidatesChanged: {
            highlightedIndex = boundedIndex(confirmedIndex >= 0 ? confirmedIndex :
                                                                  highlightedIndex);
            if (candidates.length === 0 && popupOpen) {
                view.openRole = "";
            }
        }
        onPopupOpenChanged: {
            if (!popupOpen) {
                typePrefix = "";
                typeReset.stop();
            }
        }

        Timer {
            id: typeReset
            interval: 700
            onTriggered: section.typePrefix = ""
        }

        RowLayout {
            Layout.fillWidth: true

            IslandText {
                Layout.fillWidth: true
                text: section.title
                textFormat: Text.PlainText
                font.weight: Theme.type.weightSemibold
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }

            IslandText {
                visible: section.pending
                text: qsTr("Confirming…")
                textFormat: Text.PlainText
                tone: "secondary"
                size: "caption"
                Accessible.role: Accessible.StaticText
                Accessible.name: qsTr("%1 selection pending").arg(section.title)
            }
        }

        AbstractButton {
            id: dropdownButton
            objectName: "audio" + (section.role === "output" ? "Output" : "Input") + "Dropdown"

            Layout.fillWidth: true
            implicitWidth: section.naturalWidth
            implicitHeight: Theme.size.controlHeightLg
            leftPadding: Theme.spacing.md
            rightPadding: Theme.spacing.md
            focusPolicy: Qt.StrongFocus
            hoverEnabled: true
            enabled: section.candidates.length > 0 && !view.selectionPending
            Accessible.role: Accessible.ComboBox
            Accessible.name: section.title
            Accessible.description: section.confirmedLabel + (section.popupOpen ? ", expanded" :
                                                                                  ", collapsed")
            onClicked: section.popupOpen ? section.closePopup() : section.openPopup(
                                               section.confirmedIndex)

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Down || event.key === Qt.Key_Up || event.key
                        === Qt.Key_Home || event.key === Qt.Key_End) {
                    section.openPopup(event.key === Qt.Key_End ? section.candidates.length - 1 :
                                                                 event.key === Qt.Key_Up ? Math.max(
                                                                                               0, section.confirmedIndex
                                                                                               - 1) : section.confirmedIndex);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key
                           === Qt.Key_Space) {
                    section.popupOpen ? section.closePopup() : section.openPopup(
                                            section.confirmedIndex);
                    event.accepted = true;
                } else if (section.typeNavigate(event.text)) {
                    section.openPopup(section.highlightedIndex);
                    event.accepted = true;
                }
            }

            background: Rectangle {
                radius: Theme.radius.md
                color: dropdownButton.pressed ? Theme.snapshot.controlFillPressed :
                                                dropdownButton.hovered
                                                ? Theme.snapshot.controlFillHover :
                                                  Theme.color.surfaceActive
            }

            contentItem: RowLayout {
                spacing: Theme.spacing.md

                IslandIcon {
                    meaning: section.meaning
                    semanticState: section.pending ? "pending" : section.confirmedIndex >= 0
                                                     ? "active" : "normal"
                }

                IslandText {
                    Layout.fillWidth: true
                    Layout.maximumWidth: section.maximumLabelWidth
                    text: section.confirmedLabel
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                }
                IslandIcon {
                    meaning: "dropdown"
                    size: "sm"
                    rotation: section.popupOpen ? 180 : 0
                }
            }

            IslandFocusRing {
                visible: dropdownButton.visualFocus
            }
        }

        IslandText {
            objectName: "audio" + (section.role === "output" ? "Output" : "Input")
                        + "InternalDefaultWarning"
            Layout.fillWidth: true
            visible: section.internalDefault
            text: qsTr("EasyEffects is the current %1. Choose another device to change it.").arg(
                      section.role === "output" ? qsTr("output") : qsTr("input"))
            textFormat: Text.PlainText
            color: Theme.color.warning
            size: "caption"
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }
    }
}

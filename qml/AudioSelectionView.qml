pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FocusScope {
    id: view

    required property var adapter
    required property real ownerEpoch
    property bool active: true
    property bool reducedMotion: false

    readonly property var outputCandidates: adapter === null ? [] : adapter.outputCandidates
    readonly property var inputCandidates: adapter === null ? [] : adapter.inputCandidates
    readonly property bool outputPending: adapter !== null && adapter.pendingOutputSelection
    readonly property bool inputPending: adapter !== null && adapter.pendingInputSelection
    readonly property bool selectionPending: outputPending || inputPending
    readonly property int candidateCount: outputCandidates.length + inputCandidates.length
    readonly property real columnGap: Theme.spacing.lg
    readonly property int visibleColumnCount: (outputCandidates.length > 0 ? 1 : 0) + (
                                                  inputCandidates.length > 0 ? 1 : 0)
    readonly property real naturalColumnWidth: Math.max(outputCandidates.length > 0
                                                        ? outputSection.naturalWidth : 0,
                                                        inputCandidates.length > 0
                                                        ? inputSection.naturalWidth : 0)
    readonly property real naturalContentWidth: visibleColumnCount === 0
                                                ? Theme.size.audioEmptyContentMinimumWidth :
                                                  naturalColumnWidth * visibleColumnCount
                                                  + columnGap * Math.max(0, visibleColumnCount - 1)
    readonly property bool backFocused: frame.backControl.activeFocus

    implicitWidth: frame.implicitWidth
    implicitHeight: frame.implicitHeight
    visible: active

    signal cancelled(real ownerEpoch)

    function failureText(failure) {
        if (failure === "removed") {
            return "The selected device is no longer available.";
        }
        if (failure === "rejected" || failure === "diverged") {
            return "PipeWire kept a different device selected.";
        }
        if (failure === "timeout") {
            return "PipeWire did not confirm the device change.";
        }
        if (failure === "unavailable" || failure === "bridge-unavailable") {
            return "Audio device selection is unavailable.";
        }
        if (failure !== "none") {
            return "The audio device could not be selected.";
        }
        return "";
    }

    function focusInitialControl() {
        const target = outputSection.candidateRepeater.count > 0
              ? outputSection.candidateRepeater.itemAt(0) : inputSection.candidateRepeater.count
                > 0 ? inputSection.candidateRepeater.itemAt(0) : null;
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
        return role === "output" ? adapter.requestOutputSelection(endpointKey) : role === "input"
                                   ? adapter.requestInputSelection(endpointKey) : false;
    }

    SubviewFrame {
        id: frame
        objectName: "audioSubviewFrame"

        anchors.fill: parent
        active: view.active
        title: "Audio devices"
        reducedMotion: view.reducedMotion
        initialFocusItem: outputSection.candidateRepeater.count > 0
                          ? outputSection.candidateRepeater.itemAt(0) :
                            inputSection.candidateRepeater.count > 0
                            ? inputSection.candidateRepeater.itemAt(0) : null
        onBackRequested: view.cancelled(view.ownerEpoch)
        onEscapePressed: view.cancelled(view.ownerEpoch)

        Item {
            id: contentRoot

            objectName: "audioContentRoot"
            implicitWidth: view.naturalContentWidth
            width: Math.max(implicitWidth, parent.width)
            height: audioContent.implicitHeight

            ColumnLayout {
                id: audioContent
                objectName: "audioContent"

                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Theme.spacing.lg

                RowLayout {
                    objectName: "audioColumnRow"
                    Layout.fillWidth: true
                    spacing: view.columnGap

                    CandidateSection {
                        id: outputSection
                        objectName: "audioOutputSection"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        title: "Output"
                        role: "output"
                        meaning: "volumeHigh"
                        candidates: view.outputCandidates
                        pending: view.outputPending
                        // The section exposes its actual delegate repeater for focus entry.
                    }

                    CandidateSection {
                        id: inputSection
                        objectName: "audioInputSection"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        title: "Input"
                        role: "input"
                        meaning: "microphone"
                        candidates: view.inputCandidates
                        pending: view.inputPending
                        // The section exposes its actual delegate repeater for focus entry.
                    }
                }

                IslandText {
                    objectName: "audioEmptyMessage"
                    Layout.fillWidth: true
                    visible: view.adapter === null || !view.adapter.available
                             || view.candidateCount === 0
                    text: view.adapter === null || !view.adapter.available
                          ? "Audio devices unavailable" : "No selectable audio devices"
                    textFormat: Text.PlainText
                    tone: "secondary"
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }

                IslandText {
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
            }
        }
    }

    component CandidateSection: ColumnLayout {
        id: section

        required property string title
        required property string role
        required property string meaning
        required property var candidates
        required property bool pending
        readonly property real maximumLabelWidth: Theme.spacing.xxl * 6
        readonly property real selectedLabelWidth: captionMetrics.advanceWidth("Selected")
        readonly property real pendingLabelWidth: captionMetrics.advanceWidth("Confirming…")
        readonly property real headerNaturalWidth: bodyMetrics.advanceWidth(title)
                                                   + Theme.spacing.md + pendingLabelWidth
        readonly property real naturalWidth: Math.max(headerNaturalWidth, widestCandidateWidth())

        function candidateNaturalWidth(label) {
            const boundedLabelWidth = Math.min(maximumLabelWidth, bodyMetrics.advanceWidth(label));
            return Theme.spacing.md * 2 + Theme.size.iconSizeMd + Theme.spacing.md
                    + boundedLabelWidth + Theme.spacing.md + selectedLabelWidth;
        }

        function widestCandidateWidth() {
            let width = 0;
            for (let index = 0; index < candidates.length; ++index) {
                width = Math.max(width, candidateNaturalWidth(candidates[index].label));
            }
            return width;
        }

        FontMetrics {
            id: bodyMetrics

            font.family: Theme.type.family
            font.pixelSize: Theme.type.body
        }

        FontMetrics {
            id: captionMetrics

            font.family: Theme.type.family
            font.pixelSize: Theme.type.caption
        }
        readonly property alias candidateRepeater: candidateRepeater
        implicitWidth: naturalWidth

        spacing: Theme.spacing.sm
        visible: candidates.length > 0

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
                text: "Confirming…"
                textFormat: Text.PlainText
                tone: "secondary"
                size: "caption"
                Accessible.role: Accessible.StaticText
                Accessible.name: section.title + " selection pending"
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.xs

            Repeater {
                id: candidateRepeater
                model: section.candidates

                delegate: AbstractButton {
                    id: candidateButton

                    required property int index
                    required property var modelData
                    objectName: "audio" + (section.role === "output" ? "Output" : "Input")
                                + "Candidate"

                    implicitWidth: section.candidateNaturalWidth(modelData.label)
                    leftPadding: Theme.spacing.md
                    rightPadding: Theme.spacing.md
                    Layout.fillWidth: true
                    implicitHeight: Theme.size.controlHeightLg
                    focusPolicy: Qt.StrongFocus
                    hoverEnabled: true
                    enabled: !view.selectionPending
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.label
                    Accessible.description: modelData.isDefault ? "Confirmed current "
                                                                  + section.role : "Select as "
                                                                  + section.role
                    onClicked: view.requestSelection(section.role, modelData.endpointKey)

                    background: Rectangle {
                        radius: Theme.radius.md
                        color: candidateButton.modelData.isDefault ? Theme.color.surfaceActive :
                                                                     candidateButton.pressed
                                                                     ? Theme.snapshot.controlFillPressed :
                                                                       candidateButton.hovered
                                                                       ? Theme.color.surfaceHover :
                                                                         "transparent"
                    }

                    contentItem: RowLayout {
                        spacing: Theme.spacing.md

                        IslandIcon {
                            meaning: section.meaning
                            semanticState: candidateButton.modelData.isDefault ? "active" :
                                                                                 section.pending
                                                                                 ? "pending" :
                                                                                   "normal"
                        }

                        IslandText {
                            Layout.maximumWidth: section.maximumLabelWidth
                            Layout.fillWidth: true
                            text: candidateButton.modelData.label
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                        }

                        IslandText {
                            visible: candidateButton.modelData.isDefault
                            text: "Selected"
                            textFormat: Text.PlainText
                            color: Theme.snapshot.accent
                            size: "caption"
                            font.weight: Theme.type.weightMedium
                        }
                    }

                    IslandFocusRing {
                        visible: candidateButton.visualFocus
                    }
                }
            }
        }
    }
}

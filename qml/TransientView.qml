pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import QtQuick.Layouts

// Shared rendering path for every short-lived takeover. The coordinator retains
// only source identity; normalized presentation data is resolved by the owning
// adapter or service for the exact selected source version.
Item {
    id: view

    required property string kind
    required property var presentation
    required property int surfaceGeneration
    required property real ownerEpoch
    required property real ownerRevision

    property bool active: true
    property real transitionProgress: 1
    property bool transitionManaged: false

    readonly property real boundedTransitionProgress: Math.min(1, Math.max(0, transitionProgress))
    readonly property bool notification: currentLayer.notification
    readonly property bool workspace: currentLayer.workspace
    readonly property string primaryText: currentLayer.primaryText
    readonly property string detailText: currentLayer.detailText
    readonly property string bodyText: currentLayer.bodyText
    readonly property string valueText: currentLayer.valueText
    readonly property real progressValue: currentLayer.progressValue
    readonly property bool showProgress: currentLayer.showProgress
    readonly property bool showValue: currentLayer.showValue
    readonly property int workspacePosition: currentLayer.workspacePosition
    readonly property int workspaceCount: currentLayer.workspaceCount
    readonly property int workspaceProjectedPosition: currentLayer.workspaceProjectedPosition
    readonly property string workspaceDisplayText: currentLayer.workspaceDisplayText
    readonly property bool workspaceUsesCustomName: currentLayer.workspaceUsesCustomName
    readonly property string iconMeaning: currentLayer.iconMeaning
    readonly property string applicationIconSource: currentLayer.applicationIconSource
    readonly property bool committed: state.committed
    readonly property bool replacementActive: state.replacementActive
    readonly property real incomingOpacity: currentLayer.opacity
    readonly property real outgoingOpacity: outgoingLoader.active ? outgoingLoader.opacity : 0
    readonly property bool semanticIconLoaded: currentLayer.semanticIconLoaded
    readonly property bool semanticIconTinted: currentLayer.semanticIconTinted
    readonly property bool semanticIconFallback: currentLayer.semanticIconFallback
    readonly property real contentCenterX: currentLayer.contentCenterX
    readonly property real workspaceIndicatorCenterX: currentLayer.workspaceIndicatorCenterX
    readonly property Item workspaceBadgeItem: currentLayer.workspaceBadgeItem
    readonly property real compactNaturalWidth: currentLayer.compactNaturalWidth

    signal visiblyCommitted(int surfaceGeneration, real ownerEpoch, real ownerRevision)

    implicitWidth: currentLayer.implicitWidth
    implicitHeight: currentLayer.implicitHeight
    visible: active

    Accessible.ignored: !active
    Accessible.name: currentLayer.accessibleName

    function validPresentation(value) {
        return value !== null && value !== undefined && typeof value === "object" && !Array.isArray(
                    value);
    }

    // Producers own truncation. The view rejects an over-bound projection
    // rather than copying it into a second presentation payload.
    function validatedText(value, maximumLength, fallback) {
        return typeof value === "string" && value.length > 0 && value.length <= maximumLength
                ? value : fallback;
    }

    function normalizedProgress(value) {
        if (typeof value !== "number" || !Number.isFinite(value)) {
            return -1;
        }
        return Math.min(1, Math.max(0, value));
    }

    function resolveApplicationIcon(value) {
        if (value === "") {
            return "";
        }
        if (value.startsWith("/")) {
            return "file://" + value;
        }
        if (value.startsWith("file:")) {
            return value;
        }
        return Quickshell.iconPath(value, true);
    }

    function workspacePart(workspace, valueText, countPart) {
        if (!workspace || valueText === "") {
            return 0;
        }

        let position = 0;
        let count = 0;
        let parsingCount = false;
        let positionDigits = false;
        let countDigits = false;
        for (let index = 0; index < valueText.length; index += 1) {
            const code = valueText.charCodeAt(index);
            if (code === 47 && !parsingCount && positionDigits) {
                parsingCount = true;
            } else if (code >= 48 && code <= 57) {
                if (parsingCount) {
                    count = count * 10 + code - 48;
                    countDigits = true;
                } else {
                    position = position * 10 + code - 48;
                    positionDigits = true;
                }
            } else if (code !== 32 && code !== 9) {
                return 0;
            }
        }
        if (!positionDigits || !countDigits || position < 1 || count < 1 || position > count
                || count > 32) {
            return 0;
        }
        return countPart ? count : position;
    }

    function workspaceNamePosition(workspace, primaryText) {
        if (!workspace || primaryText === "") {
            return 0;
        }

        const match = /^Desktop\s+(\d+)$/.exec(primaryText);
        if (match === null) {
            return 0;
        }

        const position = Number(match[1]);
        return Number.isInteger(position) && position >= 1 && position <= 32 ? position : 0;
    }

    function twoDigitPosition(position) {
        return position < 10 ? "0" + position : String(position);
    }

    function workspaceFallbackName(workspace, primaryText) {
        if (!workspace || primaryText === "") {
            return qsTr("Workspace");
        }
        return /^Desktop\s+\d+$/.test(primaryText) ? qsTr("Workspace") : primaryText;
    }

    function clearOutgoing() {
        state.outgoingKind = "";
        state.outgoingPresentation = null;
        state.outgoingSurfaceGeneration = 0;
        state.outgoingOwnerEpoch = 0;
        state.outgoingOwnerRevision = 0;
        state.replacementActive = false;
    }

    function setCurrentFromInput() {
        state.currentKind = kind;
        state.currentPresentation = presentation;
        state.currentSurfaceGeneration = surfaceGeneration;
        state.currentOwnerEpoch = ownerEpoch;
        state.currentOwnerRevision = ownerRevision;
    }

    function currentOwnerMatchesInput() {
        return state.currentSurfaceGeneration === surfaceGeneration && state.currentKind === kind
                && state.currentOwnerEpoch === ownerEpoch;
    }

    function commitCurrent() {
        if (!active || state.currentSurfaceGeneration <= 0 || state.committed) {
            return false;
        }
        state.committed = true;
        visiblyCommitted(state.currentSurfaceGeneration, state.currentOwnerEpoch,
                         state.currentOwnerRevision);
        return true;
    }

    function prepareTransition(generation, epoch, revision) {
        if (!state.componentReady || !active || !validPresentation(presentation) || generation
                !== surfaceGeneration || epoch !== ownerEpoch || revision !== ownerRevision) {
            return false;
        }

        const replacingOwner = state.currentSurfaceGeneration > 0 && (
                  state.currentSurfaceGeneration !== generation || state.currentKind !== kind
                  || state.currentOwnerEpoch !== epoch);
        if (replacingOwner) {
            state.outgoingKind = state.currentKind;
            state.outgoingPresentation = state.currentPresentation;
            state.outgoingSurfaceGeneration = state.currentSurfaceGeneration;
            state.outgoingOwnerEpoch = state.currentOwnerEpoch;
            state.outgoingOwnerRevision = state.currentOwnerRevision;
            state.replacementActive = true;
        } else {
            clearOutgoing();
        }
        setCurrentFromInput();
        state.committed = false;
        return true;
    }

    function finishTransition(generation, epoch, revision) {
        if (!active || generation !== state.currentSurfaceGeneration || epoch
                !== state.currentOwnerEpoch || revision !== state.currentOwnerRevision) {
            return false;
        }

        clearOutgoing();
        return commitCurrent();
    }

    function cancelStaleTransition() {
        clearOutgoing();
        state.committed = false;
    }

    function syncBoundPresentation() {
        if (!state.componentReady || !active || !validPresentation(presentation)) {
            return;
        }

        if (transitionManaged) {
            if (currentOwnerMatchesInput()) {
                state.currentPresentation = presentation;
                state.currentOwnerRevision = ownerRevision;
            }
            return;
        }

        const changed = !currentOwnerMatchesInput() || state.currentOwnerRevision !== ownerRevision
              || state.currentPresentation !== presentation;
        if (!changed && state.committed) {
            return;
        }

        clearOutgoing();
        setCurrentFromInput();
        state.committed = false;
        commitCurrent();
    }

    function queueBoundPresentationSync() {
        if (state.componentReady) {
            boundPresentationSync.restart();
        }
    }

    onActiveChanged: {
        if (!active) {
            state.committed = false;
        } else {
            queueBoundPresentationSync();
        }
    }
    onKindChanged: queueBoundPresentationSync()
    onOwnerEpochChanged: queueBoundPresentationSync()
    onOwnerRevisionChanged: queueBoundPresentationSync()
    onPresentationChanged: queueBoundPresentationSync()
    onSurfaceGenerationChanged: queueBoundPresentationSync()
    onTransitionManagedChanged: queueBoundPresentationSync()

    Timer {
        id: boundPresentationSync

        interval: 0
        repeat: false
        onTriggered: view.syncBoundPresentation()
    }
    Component.onCompleted: {
        state.componentReady = true;
        syncBoundPresentation();
    }

    QtObject {
        id: state

        property bool committed: false
        property bool componentReady: false
        property bool replacementActive: false

        property string currentKind: ""
        property var currentPresentation: null
        property int currentSurfaceGeneration: 0
        property real currentOwnerEpoch: 0
        property real currentOwnerRevision: 0

        property string outgoingKind: ""
        property var outgoingPresentation: null
        property int outgoingSurfaceGeneration: 0
        property real outgoingOwnerEpoch: 0
        property real outgoingOwnerRevision: 0
    }

    component PresentationLayer: Item {
        id: layer

        required property string presentationKind
        required property var presentationSnapshot
        property bool renderActive: true

        readonly property bool notification: presentationKind === "notification"
        readonly property bool workspace: presentationKind === "workspace"
        readonly property string primaryText: view.validatedText(presentationSnapshot.primary, 256,
                                                                 "")
        readonly property string detailText: view.validatedText(presentationSnapshot.detail, 1024,
                                                                "")
        readonly property string bodyText: notification ? view.validatedText(
                                                              presentationSnapshot.body, 4096, "") :
                                                          ""
        readonly property string valueText: view.validatedText(presentationSnapshot.value, 64, "")
        readonly property string appIconName: notification ? view.validatedText(
                                                                 presentationSnapshot.appIconName,
                                                                 512, "") : ""
        readonly property real progressValue: view.normalizedProgress(presentationSnapshot.progress)
        readonly property bool showProgress: (presentationKind === "volume" || presentationKind
                                              === "brightness") && progressValue >= 0
        readonly property bool showValue: valueText !== "" && (!showProgress || progressValue >= 0) &&
                                          !workspace
        readonly property int workspacePosition: view.workspacePart(workspace, valueText, false)
        readonly property int workspaceCount: view.workspacePart(workspace, valueText, true)
        readonly property int workspaceProjectedPosition: workspacePosition > 0 ? workspacePosition :
                                                                                  view.workspaceNamePosition(
                                                                                      workspace,
                                                                                      primaryText)
        readonly property string workspaceDisplayText: workspaceProjectedPosition > 0
                                                       ? view.twoDigitPosition(
                                                             workspaceProjectedPosition) :
                                                         view.workspaceFallbackName(workspace,
                                                                                    primaryText)
        readonly property bool workspaceUsesCustomName: workspace && workspacePosition === 0
                                                        && workspaceProjectedPosition === 0
                                                        && primaryText !== "" && !
                                                        /^Desktop\s+\d+$/.test(primaryText)
        readonly property string iconMeaning: notification ? "notificationApplication" :
                                                             presentationKind === "brightness"
                                                             ? "brightness" : presentationKind
                                                               === "gamingPerformance"
                                                               ? "gamingPerformance" :
                                                                 progressValue <= 0 ? "volumeMuted" :
                                                                                      progressValue
                                                                                      <= 0.33 ? "volumeLow" :
                                                                                                "volumeHigh"
        readonly property string applicationIconSource: view.resolveApplicationIcon(appIconName)
        readonly property bool semanticIconLoaded: semanticIconLoader.item !== null
        readonly property bool semanticIconTinted: semanticIconLoader.item !== null
                                                   && semanticIconLoader.item.tinted
        readonly property bool semanticIconFallback: semanticIconLoader.item !== null
                                                     && semanticIconLoader.item.showingFallback
        readonly property real contentCenterX: workspace ? workspaceContent.x + workspaceBadge.x
                                                           + workspaceBadge.width / 2 :
                                                           contentLayout.x + contentColumn.x
                                                           + primaryLabel.x + primaryLabel.width / 2
        readonly property real workspaceIndicatorCenterX: workspaceContent.x + workspaceIndicator.x
                                                          + workspaceIndicator.width / 2
        readonly property alias workspaceBadgeItem: workspaceBadge
        readonly property real compactNaturalWidth: contentLayout.implicitWidth + Theme.spacing.lg
                                                    * 2
        readonly property string accessibleName: workspace ? [workspaceDisplayText,
                                                              detailText].filter(text => text
                                                                                         !== "").join(
                                                                 ", ") : [primaryText, detailText,
                                                                          bodyText, valueText].filter(
                                                                 text => text !== "").join(", ")

        implicitWidth: notification ? Theme.size.islandTransientNotificationWidth : Math.min(
                                          Theme.size.islandTransientCompactWidth, Math.max(
                                              Theme.size.islandTransientCompactMinimumWidth,
                                              compactNaturalWidth))
        implicitHeight: notification ? Math.max(Theme.size.islandTransientNotificationHeight,
                                                contentLayout.implicitHeight + Theme.spacing.md
                                                * 2) : Theme.size.islandTransientCompactHeight

        Accessible.ignored: true

        RowLayout {
            id: contentLayout

            anchors.fill: parent
            anchors.leftMargin: Theme.spacing.lg
            anchors.rightMargin: Theme.spacing.lg
            anchors.topMargin: layer.notification ? Theme.spacing.md : Theme.spacing.sm
            anchors.bottomMargin: layer.notification ? Theme.spacing.md : Theme.spacing.sm
            spacing: layer.workspace ? 0 : Theme.spacing.md

            Loader {
                id: semanticIconLoader

                Layout.preferredWidth: active ? Theme.size.iconSizeLg : 0
                Layout.preferredHeight: active ? Theme.size.iconSizeLg : 0
                Layout.maximumWidth: active ? Theme.size.iconSizeLg : 0
                active: layer.renderActive && !layer.workspace
                visible: active

                sourceComponent: Component {
                    IslandIcon {
                        meaning: layer.iconMeaning
                        size: "lg"
                        applicationSource: layer.notification ? layer.applicationIconSource : ""
                        applicationName: layer.notification ? layer.primaryText : ""
                    }
                }
            }

            ColumnLayout {
                id: contentColumn

                Layout.fillWidth: true
                Layout.alignment: layer.workspace ? Qt.AlignHCenter | Qt.AlignVCenter :
                                                    Qt.AlignVCenter
                Layout.minimumWidth: layer.workspace ? Math.max(0, layer.width - Theme.spacing.lg
                                                                * 2) : 0
                Layout.preferredWidth: layer.workspace ? Layout.minimumWidth : -1
                Layout.maximumWidth: Math.max(0, layer.width - Theme.spacing.lg * 2)
                spacing: Theme.spacing.xs

                IslandText {
                    id: primaryLabel

                    Layout.fillWidth: true
                    visible: !layer.notification && !workspaceBadge.visible
                    text: layer.workspace ? layer.workspaceDisplayText : layer.primaryText
                    textFormat: Text.PlainText
                    size: "body"
                    font.weight: Theme.type.weightMedium
                    elide: Text.ElideRight
                    horizontalAlignment: layer.workspace ? Text.AlignHCenter : Text.AlignLeft
                }

                IslandText {
                    Layout.fillWidth: true
                    visible: layer.notification
                    text: layer.primaryText
                    textFormat: Text.PlainText
                    tone: "secondary"
                    size: "caption"
                    elide: Text.ElideRight
                }

                IslandText {
                    Layout.fillWidth: true
                    visible: layer.notification && layer.detailText !== ""
                    text: layer.detailText
                    textFormat: Text.PlainText
                    size: "title"
                    font.weight: Theme.type.weightSemibold
                    elide: Text.ElideRight
                }

                IslandProgressBar {
                    Layout.fillWidth: true
                    visible: layer.showProgress
                    value: layer.progressValue
                    label: layer.primaryText
                }

                IslandText {
                    Layout.fillWidth: true
                    visible: !layer.notification && !layer.workspace && layer.detailText !== ""
                    text: layer.detailText
                    textFormat: Text.PlainText
                    tone: "secondary"
                    size: "caption"
                    elide: Text.ElideRight
                }

                IslandText {
                    Layout.fillWidth: true
                    visible: layer.notification && layer.bodyText !== ""
                    text: layer.bodyText
                    textFormat: Text.PlainText
                    tone: "secondary"
                    size: "body"
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            IslandText {
                visible: layer.showValue
                Layout.maximumWidth: visible ? Theme.size.islandTransientValueMaximumWidth : 0
                text: layer.valueText
                textFormat: Text.PlainText
                font.weight: Theme.type.weightSemibold
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
        }
        ColumnLayout {
            id: workspaceContent

            anchors.centerIn: parent
            width: implicitWidth
            height: implicitHeight
            visible: layer.workspace
            spacing: Theme.spacing.xs

            Item {
                id: workspaceBadgeRow

                Layout.fillWidth: true
                implicitHeight: Theme.size.islandWorkspaceIndicatorHeight
                visible: layer.workspaceProjectedPosition > 0

                Item {
                    id: workspaceBadge

                    anchors.centerIn: parent
                    width: Theme.size.islandWorkspaceIndicatorWidth
                    height: Theme.size.islandWorkspaceIndicatorHeight

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radius.sm
                        color: Theme.color.surfaceActive
                    }

                    IslandText {
                        anchors.centerIn: parent
                        text: layer.workspaceDisplayText
                        tone: "primary"
                        size: "body"
                        font.weight: Theme.type.weightMedium
                    }
                }
            }

            RowLayout {
                id: workspaceIndicator

                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.spacing.xs / 2

                Repeater {
                    model: layer.workspaceCount

                    delegate: Rectangle {
                        required property int index

                        implicitWidth: Theme.spacing.sm
                        implicitHeight: Theme.spacing.xs
                        radius: Theme.radius.sm
                        color: index + 1 === layer.workspacePosition ? Theme.snapshot.accent :
                                                                       Theme.color.surfaceActive
                    }
                }
            }
        }
    }

    Loader {
        id: outgoingLoader

        anchors.fill: parent
        active: state.replacementActive
        visible: active
        opacity: 1 - view.boundedTransitionProgress
        z: 2

        sourceComponent: PresentationLayer {
            presentationKind: state.outgoingKind
            presentationSnapshot: state.outgoingPresentation ?? ({})
            renderActive: outgoingLoader.visible
        }
    }

    PresentationLayer {
        id: currentLayer

        anchors.fill: parent
        presentationKind: state.currentKind
        presentationSnapshot: state.currentPresentation ?? ({})
        renderActive: view.active
        opacity: state.replacementActive && outgoingLoader.item !== null
                 ? view.boundedTransitionProgress : 1
        z: 1
    }
}

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
    property bool reducedMotion: false

    readonly property bool notification: kind === "notification"
    readonly property bool workspace: kind === "workspace"
    readonly property string primaryText: validatedText(presentation.primary, 256, "")
    readonly property string detailText: validatedText(presentation.detail, 1024, "")
    readonly property string bodyText: notification ? validatedText(presentation.body, 4096, "") :
                                                      ""
    readonly property string valueText: validatedText(presentation.value, 64, "")
    readonly property string appIconName: notification ? validatedText(presentation.appIconName, 512,
                                                                       "") : ""
    readonly property real progressValue: normalizedProgress(presentation.progress)
    readonly property bool showProgress: (kind === "volume" || kind === "brightness")
                                         && progressValue >= 0
    readonly property bool showValue: valueText !== "" && (!showProgress || progressValue >= 0) &&
                                      !workspace
    readonly property int workspacePosition: workspacePart(false)
    readonly property int workspaceCount: workspacePart(true)
    readonly property int workspaceProjectedPosition: workspacePosition > 0 ? workspacePosition :
                                                                              workspaceNamePosition(
                                                                                  )
    readonly property string workspaceDisplayText: workspaceProjectedPosition > 0 ? twoDigitPosition(
                                                                                        workspaceProjectedPosition) :
                                                                                    workspaceFallbackName(
                                                                                        )
    readonly property bool workspaceUsesCustomName: workspace && workspacePosition === 0
                                                    && workspaceProjectedPosition === 0
                                                    && workspaceDisplayText !== "Workspace"
    readonly property string iconMeaning: notification ? "notificationApplication" : kind
                                                         === "brightness" ? "brightness" : kind
                                                                            === "gamingPerformance"
                                                                            ? "gamingPerformance" :
                                                                              progressValue <= 0
                                                                              ? "volumeMuted" :
                                                                                progressValue
                                                                                <= 0.33 ? "volumeLow" :
                                                                                          "volumeHigh"
    readonly property string applicationIconSource: resolveApplicationIcon(appIconName)
    readonly property bool committed: state.committed
    readonly property bool entryAnimationRunning: entryAnimation.running
    readonly property bool semanticIconLoaded: semanticIconLoader.item !== null
    readonly property bool semanticIconTinted: semanticIconLoader.item !== null
                                               && semanticIconLoader.item.tinted
    readonly property bool semanticIconFallback: semanticIconLoader.item !== null
                                                 && semanticIconLoader.item.showingFallback
    readonly property real contentCenterX: contentLayout.x + contentColumn.x + (
                                               workspaceBadge.visible ? workspaceBadge.x
                                                                        + workspaceBadge.width / 2 :
                                                                        primaryLabel.x
                                                                        + primaryLabel.width / 2)
    readonly property real workspaceIndicatorCenterX: contentLayout.x + contentColumn.x
                                                      + workspaceIndicator.x
                                                      + workspaceIndicator.width / 2
    readonly property alias workspaceBadgeItem: workspaceBadge
    readonly property real compactNaturalWidth: contentLayout.implicitWidth + Theme.spacing.lg * 2

    signal visiblyCommitted(int surfaceGeneration, real ownerEpoch, real ownerRevision)

    implicitWidth: notification ? Theme.size.islandTransientNotificationWidth : Math.min(
                                      Theme.size.islandTransientCompactWidth, Math.max(
                                          Theme.size.islandTransientCompactMinimumWidth,
                                          compactNaturalWidth))
    implicitHeight: notification ? Math.max(Theme.size.islandTransientNotificationHeight,
                                            contentLayout.implicitHeight + Theme.spacing.md * 2) :
                                   Theme.size.islandTransientCompactHeight
    visible: active

    Accessible.name: workspace ? [workspaceDisplayText, detailText].filter(text => text !== "").join(
                                     ", ") : [primaryText, detailText, bodyText, valueText].filter(
                                     text => text !== "").join(", ")

    function beginEntry() {
        if (!state.componentReady) {
            return;
        }

        state.entrySerial += 1;
        state.committed = false;
        entryAnimation.stop();
        opacity = reducedMotion ? 1 : 0;
        entryOffset.y = reducedMotion ? 0 : -Theme.spacing.xs;
        if (!active) {
            return;
        }

        entryAnimation.restart();
    }

    // Producers own truncation. The view rejects an over-bound projection
    // rather than copying it into a second presentation payload.
    function validatedText(value, maximumLength, fallback) {
        return typeof value === "string" && value.length > 0 && value.length <= maximumLength
                ? value : fallback;
    }

    function finishEntry(serial) {
        if (!active || serial !== state.entrySerial || state.committed) {
            return;
        }
        opacity = 1;
        entryOffset.y = 0;
        state.committed = true;
        visiblyCommitted(surfaceGeneration, ownerEpoch, ownerRevision);
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

    function workspacePart(countPart) {
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

    function workspaceNamePosition() {
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

    function workspaceFallbackName() {
        if (!workspace || primaryText === "") {
            return "Workspace";
        }
        return /^Desktop\s+\d+$/.test(primaryText) ? "Workspace" : primaryText;
    }

    onActiveChanged: beginEntry()
    onOwnerEpochChanged: beginEntry()
    onOwnerRevisionChanged: beginEntry()
    onReducedMotionChanged: beginEntry()
    onSurfaceGenerationChanged: beginEntry()

    Component.onCompleted: state.componentReady = true

    QtObject {
        id: state

        property bool committed: false
        property bool componentReady: false
        property int entrySerial: 0
    }

    transform: Translate {
        id: entryOffset
    }

    RowLayout {
        id: contentLayout

        anchors.fill: parent
        anchors.leftMargin: Theme.spacing.lg
        anchors.rightMargin: Theme.spacing.lg
        anchors.topMargin: view.notification ? Theme.spacing.md : Theme.spacing.sm
        anchors.bottomMargin: view.notification ? Theme.spacing.md : Theme.spacing.sm
        spacing: Theme.spacing.md

        Loader {
            id: semanticIconLoader

            Layout.preferredWidth: active ? Theme.size.iconSizeLg : 0
            Layout.preferredHeight: active ? Theme.size.iconSizeLg : 0
            active: view.active && !view.workspace
            visible: active

            sourceComponent: Component {
                IslandIcon {
                    meaning: view.iconMeaning
                    size: "lg"
                    applicationSource: view.notification ? view.applicationIconSource : ""
                    applicationName: view.notification ? view.primaryText : ""
                }
            }
        }

        ColumnLayout {
            id: contentColumn

            Layout.fillWidth: !view.workspace
            Layout.alignment: view.workspace ? Qt.AlignHCenter | Qt.AlignVCenter : Qt.AlignVCenter
            Layout.maximumWidth: Math.max(0, view.width - Theme.spacing.lg * 2)
            spacing: Theme.spacing.xs

            Item {
                id: workspaceBadge

                Layout.preferredWidth: Theme.size.islandWorkspaceIndicatorWidth
                Layout.preferredHeight: Theme.size.islandWorkspaceIndicatorHeight
                Layout.alignment: Qt.AlignHCenter
                visible: view.workspace && view.workspaceProjectedPosition > 0

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radius.sm
                    color: Theme.color.surfaceActive
                }

                IslandText {
                    anchors.centerIn: parent
                    text: view.workspaceDisplayText
                    tone: "primary"
                    size: "body"
                    font.weight: Theme.type.weightMedium
                }
            }

            IslandText {
                id: primaryLabel
                Layout.fillWidth: true
                visible: !view.notification && !workspaceBadge.visible
                text: view.workspace ? view.workspaceDisplayText : view.primaryText
                textFormat: Text.PlainText
                size: "body"
                font.weight: Theme.type.weightMedium
                elide: Text.ElideRight
                horizontalAlignment: view.workspace ? Text.AlignHCenter : Text.AlignLeft
            }

            IslandText {
                Layout.fillWidth: true
                visible: view.notification
                text: view.primaryText
                textFormat: Text.PlainText
                tone: "secondary"
                size: "caption"
                elide: Text.ElideRight
            }

            IslandText {
                Layout.fillWidth: true
                visible: view.notification && view.detailText !== ""
                text: view.detailText
                textFormat: Text.PlainText
                size: "title"
                font.weight: Theme.type.weightSemibold
                elide: Text.ElideRight
            }

            IslandProgressBar {
                Layout.fillWidth: true
                visible: view.showProgress
                value: view.progressValue
                label: view.primaryText
            }

            RowLayout {
                id: workspaceIndicator
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.spacing.xs / 2

                Repeater {
                    model: view.workspaceCount

                    delegate: Rectangle {
                        required property int index

                        implicitWidth: Theme.spacing.sm
                        implicitHeight: Theme.spacing.xs
                        radius: Theme.radius.sm
                        color: index + 1 === view.workspacePosition ? Theme.snapshot.accent :
                                                                      Theme.color.surfaceActive
                    }
                }
            }

            IslandText {
                Layout.fillWidth: true
                visible: !view.notification && !view.workspace && view.detailText !== ""
                text: view.detailText
                textFormat: Text.PlainText
                tone: "secondary"
                size: "caption"
                elide: Text.ElideRight
            }

            IslandText {
                Layout.fillWidth: true
                visible: view.notification && view.bodyText !== ""
                text: view.bodyText
                textFormat: Text.PlainText
                tone: "secondary"
                size: "body"
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        IslandText {
            Layout.maximumWidth: Theme.size.islandTransientValueMaximumWidth
            visible: view.showValue
            text: view.valueText
            textFormat: Text.PlainText
            font.weight: Theme.type.weightSemibold
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }
    }

    ParallelAnimation {
        id: entryAnimation

        NumberAnimation {
            target: view
            property: "opacity"
            from: 0
            to: 1
            duration: view.reducedMotion ? 0 : Theme.motion.durationNormal
            easing.type: Theme.motion.easingExpansion
        }

        NumberAnimation {
            target: entryOffset
            property: "y"
            from: view.reducedMotion ? 0 : -Theme.spacing.xs
            to: 0
            duration: view.reducedMotion ? 0 : Theme.motion.durationNormal
            easing.type: Theme.motion.easingExpansion
        }

        onFinished: view.finishEntry(state.entrySerial)
    }
}

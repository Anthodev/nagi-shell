pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Widgets
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
    readonly property string iconName: normalizedIconName(presentation.iconName)
    readonly property string primaryText: boundedText(presentation.primary, 256, "")
    readonly property string detailText: boundedText(presentation.detail, 512, "")
    readonly property string valueText: boundedText(presentation.value, 64, "")
    readonly property real progressValue: normalizedProgress(presentation.progress)
    readonly property bool showProgress: (kind === "volume" || kind === "brightness")
                                         && progressValue >= 0
    readonly property bool committed: state.committed
    readonly property bool entryAnimationRunning: entryAnimation.running

    signal visiblyCommitted(int surfaceGeneration, real ownerEpoch, real ownerRevision)

    implicitWidth: notification ? Theme.size.islandTransientNotificationWidth :
                                  Theme.size.islandTransientCompactWidth
    implicitHeight: notification ? Theme.size.islandTransientNotificationHeight :
                                   Theme.size.islandTransientCompactHeight
    visible: active

    Accessible.role: Accessible.StaticText
    Accessible.name: [primaryText, detailText, valueText].filter(text => text !== "").join(", ")

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

    function boundedText(value, maximumLength, fallback) {
        if (typeof value !== "string" || value.length === 0) {
            return fallback;
        }
        return value.slice(0, maximumLength);
    }

    function fallbackIconName() {
        if (kind === "notification") {
            return "preferences-desktop-notification-symbolic";
        }
        if (kind === "volume") {
            return "audio-volume-high-symbolic";
        }
        if (kind === "brightness") {
            return "display-brightness-symbolic";
        }
        return "preferences-desktop-virtual-symbolic";
    }
    function normalizedIconName(value) {
        if (typeof value === "string" && value.length > 0 && value.length <= 128 &&
                /^[A-Za-z0-9._+-]+$/.test(value)) {
            return value;
        }
        return fallbackIconName();
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
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing.lg
        anchors.rightMargin: Theme.spacing.lg
        anchors.topMargin: view.notification ? Theme.spacing.md : Theme.spacing.sm
        anchors.bottomMargin: view.notification ? Theme.spacing.md : Theme.spacing.sm
        spacing: Theme.spacing.md

        IconImage {
            Layout.preferredWidth: Theme.size.iconSizeLg
            Layout.preferredHeight: Theme.size.iconSizeLg
            source: Quickshell.iconPath(view.iconName)
            implicitSize: Theme.size.iconSizeLg
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.xs

            IslandText {
                Layout.fillWidth: true
                text: view.primaryText
                textFormat: Text.PlainText
                size: view.notification ? "title" : "body"
                font.weight: Theme.type.weightMedium
                elide: Text.ElideRight
            }

            IslandProgressBar {
                Layout.fillWidth: true
                visible: view.showProgress
                value: view.progressValue
                label: view.primaryText
            }

            IslandText {
                Layout.fillWidth: true
                visible: view.detailText !== ""
                text: view.detailText
                textFormat: Text.PlainText
                tone: "secondary"
                size: view.notification ? "body" : "caption"
                elide: Text.ElideRight
            }
        }

        IslandText {
            Layout.maximumWidth: Theme.size.islandTransientValueMaximumWidth
            visible: view.valueText !== ""
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
            easing.type: Theme.motion.easingStandard
        }

        NumberAnimation {
            target: entryOffset
            property: "y"
            from: -Theme.spacing.xs
            to: 0
            duration: view.reducedMotion ? 0 : Theme.motion.durationNormal
            easing.type: Theme.motion.easingStandard
        }

        onFinished: view.finishEntry(state.entrySerial)
    }
}

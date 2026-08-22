import Quickshell
import QtQuick

PanelWindow {
    id: surface

    required property var coordinator
    required property int hostSurfaceGeneration

    // Normalized idle data sources. Null keeps the matching block collapsed,
    // so harnesses can mount the surface without the full adapter set.
    property var virtualDesktops: null
    property var clock: null
    property var weather: null
    property var media: null
    property bool reducedMotion: false

    readonly property int ownerKind: coordinator.ownerKind
    readonly property real ownerEpoch: coordinator.ownerEpoch
    readonly property real ownerRevision: coordinator.revision
    readonly property int focusTarget: coordinator.focusTarget
    readonly property real focusRequestSerial: coordinator.focusRequestSerial
    readonly property int edgeInset: Theme.spacing.sm
    readonly property int preferredHeight: Theme.size.islandIdleHeight
    readonly property int idleContentWidth: idleContent.visible ? idleContent.implicitWidth :
                                                                  Theme.size.islandIdleWidth

    function acknowledgePresentation(generation, epoch, contentRevision) {
        if (generation <= 0 || hostSurfaceGeneration !== generation) {
            return;
        }

        coordinator.acknowledgeVisible(generation, epoch, contentRevision);
    }

    function queuePresentationAcknowledgement() {
        const generation = hostSurfaceGeneration;
        const epoch = ownerEpoch;
        const contentRevision = ownerRevision;
        Qt.callLater(function () {
            surface.acknowledgePresentation(generation, epoch, contentRevision);
        });
    }

    function safeLogicalSize(preferredSize, screenSize) {
        if (screenSize <= 0) {
            return preferredSize;
        }

        return Math.min(preferredSize, Math.max(1, screenSize - edgeInset * 2));
    }

    Component.onCompleted: queuePresentationAcknowledgement()
    onHostSurfaceGenerationChanged: queuePresentationAcknowledgement()

    Connections {
        target: surface.coordinator

        function onOwnerEpochChanged() {
            surface.queuePresentationAcknowledgement();
        }

        function onRevisionChanged() {
            surface.queuePresentationAcknowledgement();
        }
    }

    // Leave screen unassigned at creation so Qt selects the startup primary/default output.
    anchors.top: true
    color: "transparent"
    exclusiveZone: 0
    implicitHeight: safeLogicalSize(preferredHeight, screen === null ? 0 : screen.height)
    implicitWidth: safeLogicalSize(Math.max(Theme.size.islandIdleWidth, idleContentWidth), screen
                                   === null ? 0 : screen.width)

    Behavior on implicitWidth {
        NumberAnimation {
            duration: surface.reducedMotion ? 0 : Theme.motion.durationFast
            easing.type: Theme.motion.easingStandard
        }
    }
    margins.top: edgeInset

    IslandPanel {
        anchors.fill: parent
    }

    IdleIsland {
        id: idleContent

        anchors.centerIn: parent
        visible: surface.ownerKind === surface.coordinator.ownerIdle
        virtualDesktops: surface.virtualDesktops
        clock: surface.clock
        weather: surface.weather
        media: surface.media
        reducedMotion: surface.reducedMotion
    }
}

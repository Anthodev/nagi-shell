import Quickshell
import QtQuick

PanelWindow {
    id: surface

    required property var coordinator
    required property int hostSurfaceGeneration

    readonly property int ownerKind: coordinator.ownerKind
    readonly property real ownerEpoch: coordinator.ownerEpoch
    readonly property real ownerRevision: coordinator.revision
    readonly property int focusTarget: coordinator.focusTarget
    readonly property real focusRequestSerial: coordinator.focusRequestSerial
    readonly property int edgeInset: 8
    readonly property int preferredHeight: 36
    readonly property int preferredWidth: 120

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
    implicitWidth: safeLogicalSize(preferredWidth, screen === null ? 0 : screen.width)
    margins.top: edgeInset

    Rectangle {
        anchors.fill: parent
        color: "#f5080d16"
        radius: height / 2

        border.color: "#263448"
        border.width: 1
    }
}

pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

// Expanded media presentation. It consumes only MediaAdapter's normalized
// contract; artwork stays bounded and local to this card.
FocusScope {
    id: root

    required property var media

    readonly property bool timingVisible: media !== null && media.position !== null
                                          && media.duration !== null
    readonly property string artworkRequest: artwork.source.toString()
    readonly property bool controlsPending: media !== null && media.pendingAction !== "none"

    implicitWidth: 340
    implicitHeight: 132

    function formatTime(seconds) {
        if (typeof seconds !== "number" || !Number.isFinite(seconds) || seconds < 0) {
            return "";
        }
        const whole = Math.floor(seconds);
        const minutes = Math.floor(whole / 60);
        const remainder = whole % 60;
        return minutes + ":" + (remainder < 10 ? "0" : "") + remainder;
    }

    function previous() {
        return media !== null && media.canPrevious && !controlsPending ? media.previous() :
                                                                         "rejected";
    }

    function togglePlayback() {
        return media !== null && media.canTogglePlayback && !controlsPending ? media.togglePlayback(
                                                                                   ) : "rejected";
    }

    function next() {
        return media !== null && media.canNext && !controlsPending ? media.next() : "rejected";
    }

    IslandPanel {
        anchors.fill: parent
        radius: Theme.radius.lg
        color: Theme.color.controlFill
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing.md
        spacing: Theme.spacing.md

        Rectangle {
            Layout.preferredWidth: 92
            Layout.preferredHeight: 92
            Layout.alignment: Qt.AlignVCenter
            radius: Theme.radius.md
            color: Theme.color.progressTrack
            clip: true

            IconImage {
                anchors.centerIn: parent
                implicitSize: Theme.size.iconSizeLg
                source: Quickshell.iconPath("audio-x-generic-symbolic")
                visible: artwork.status !== Image.Ready
            }

            Image {
                id: artwork

                anchors.fill: parent
                asynchronous: true
                cache: true
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: root.media === null ? 0 : root.media.artworkMaximumWidth
                source: root.visible && root.media !== null && root.media.artworkStatus === "ready"
                        && root.media.artworkSource !== "" ? root.media.artworkSource : ""
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.spacing.xs

            IslandText {
                Layout.fillWidth: true
                text: root.media === null ? "" : root.media.title !== "" ? root.media.title :
                                                                           root.media.playerName
                textFormat: Text.PlainText
                size: "title"
                font.weight: Theme.type.weightSemibold
                elide: Text.ElideRight
            }

            IslandText {
                Layout.fillWidth: true
                text: root.media === null ? "" : root.media.artist !== "" ? root.media.artist :
                                                                            root.media.album
                textFormat: Text.PlainText
                tone: "secondary"
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.sm

                IslandIconButton {
                    objectName: "dashboardMediaPrevious"
                    size: "sm"
                    source: Quickshell.iconPath("media-skip-backward-symbolic")
                    label: "Previous track"
                    enabled: root.media !== null && root.media.canPrevious && !root.controlsPending
                    onClicked: root.previous()
                }

                IslandIconButton {
                    objectName: "dashboardMediaToggle"
                    size: "sm"
                    source: Quickshell.iconPath(root.media !== null && root.media.playbackState
                                                === "playing" ? "media-playback-pause-symbolic" :
                                                                "media-playback-start-symbolic")
                    label: root.media !== null && root.media.playbackState === "playing" ? "Pause" :
                                                                                           "Play"

                    enabled: root.media !== null && root.media.canTogglePlayback &&
                             !root.controlsPending
                    onClicked: root.togglePlayback()
                }

                IslandIconButton {
                    objectName: "dashboardMediaNext"
                    size: "sm"
                    source: Quickshell.iconPath("media-skip-forward-symbolic")
                    label: "Next track"
                    enabled: root.media !== null && root.media.canNext && !root.controlsPending
                    onClicked: root.next()
                }

                IslandText {
                    Layout.fillWidth: true
                    text: root.controlsPending ? "Request pending" : root.media === null ? "" :
                                                                                           root.media.playbackState
                                                                                           === "playing"
                                                                                           ? "Playing" :
                                                                                             root.media.playbackState
                                                                                             === "paused"
                                                                                             ? "Paused" :
                                                                                               "Stopped"
                    textFormat: Text.PlainText
                    tone: root.controlsPending ? "secondary" : "muted"
                    size: "caption"
                    horizontalAlignment: Text.AlignRight
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.timingVisible
                spacing: Theme.spacing.sm

                IslandProgressBar {
                    Layout.fillWidth: true
                    value: root.media === null || root.media.duration === null || root.media.duration
                           <= 0 ? 0 : root.media.position / root.media.duration
                    label: "Playback position"
                }

                IslandText {
                    text: root.formatTime(root.media === null ? null : root.media.position) + " / "
                          + root.formatTime(root.media === null ? null : root.media.duration)
                    textFormat: Text.PlainText
                    tone: "muted"
                    size: "caption"
                }
            }
        }
    }
}

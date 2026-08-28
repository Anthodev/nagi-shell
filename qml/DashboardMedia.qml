pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Expanded media consumes only the normalized adapter contract. Artwork and
// reliable timing work disappear when the region is hidden or unsupported.
FocusScope {
    id: root

    required property var media

    readonly property bool controlsPending: media !== null && media.pendingAction !== "none"
    readonly property bool timingReliable: media !== null && (typeof media.timingReliable
                                                              === "boolean" ? media.timingReliable :
                                                                              media.position
                                                                              !== null
                                                                              && media.duration
                                                                              !== null)
    readonly property bool timingVisible: timingReliable && typeof media.position === "number"
                                          && Number.isFinite(media.position)
                                          && typeof media.duration === "number" && Number.isFinite(
                                              media.duration) && media.duration > 0
    readonly property string artworkRequest: artwork.source.toString()
    readonly property int artworkExtent: Theme.spacing.xxl * 3

    implicitWidth: mediaRow.implicitWidth
    implicitHeight: mediaRow.implicitHeight

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

    RowLayout {
        id: mediaRow

        spacing: Theme.spacing.md

        Rectangle {
            Layout.preferredWidth: root.artworkExtent
            Layout.preferredHeight: root.artworkExtent
            Layout.alignment: Qt.AlignVCenter
            radius: Theme.radius.md
            color: Theme.color.surfaceActive
            clip: true

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
            Layout.preferredWidth: Theme.spacing.xxl * 7
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

                AbstractButton {
                    id: previousButton

                    objectName: "dashboardMediaPrevious"
                    implicitWidth: Theme.size.controlHeightMd
                    implicitHeight: Theme.size.controlHeightMd
                    focusPolicy: Qt.StrongFocus
                    hoverEnabled: true
                    enabled: root.media !== null && root.media.canPrevious && !root.controlsPending
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Previous track")
                    onClicked: root.previous()

                    background: Rectangle {
                        radius: Theme.radius.md
                        color: previousButton.pressed ? Theme.color.surfaceActive :
                                                        previousButton.hovered
                                                        ? Theme.color.surfaceHover : "transparent"
                    }
                    contentItem: Item {
                        IslandIcon {
                            anchors.centerIn: parent
                            meaning: "mediaPrevious"
                        }
                    }
                    IslandFocusRing {
                        visible: previousButton.visualFocus
                    }
                    ToolTip.delay: Theme.motion.durationSlow
                    ToolTip.visible: hovered || visualFocus
                    ToolTip.text: qsTr("Previous track")
                }

                AbstractButton {
                    id: playbackButton

                    objectName: "dashboardMediaToggle"
                    implicitWidth: Theme.size.controlHeightMd
                    implicitHeight: Theme.size.controlHeightMd
                    focusPolicy: Qt.StrongFocus
                    hoverEnabled: true
                    enabled: root.media !== null && root.media.canTogglePlayback &&
                             !root.controlsPending
                    Accessible.role: Accessible.Button
                    Accessible.name: root.media !== null && root.media.playbackState === "playing"
                                     ? qsTr("Pause") : qsTr("Play")
                    onClicked: root.togglePlayback()

                    background: Rectangle {
                        radius: Theme.radius.md
                        color: playbackButton.pressed ? Theme.color.surfaceActive :
                                                        playbackButton.hovered
                                                        ? Theme.color.surfaceHover : "transparent"
                    }
                    contentItem: Item {
                        IslandIcon {
                            anchors.centerIn: parent
                            meaning: root.media !== null && root.media.playbackState === "playing"
                                     ? "mediaPause" : "mediaPlay"
                        }
                    }
                    IslandFocusRing {
                        visible: playbackButton.visualFocus
                    }
                    ToolTip.delay: Theme.motion.durationSlow
                    ToolTip.visible: hovered || visualFocus
                    ToolTip.text: root.media !== null && root.media.playbackState === "playing"
                                  ? qsTr("Pause") : qsTr("Play")
                }

                AbstractButton {
                    id: nextButton

                    objectName: "dashboardMediaNext"
                    implicitWidth: Theme.size.controlHeightMd
                    implicitHeight: Theme.size.controlHeightMd
                    focusPolicy: Qt.StrongFocus
                    hoverEnabled: true
                    enabled: root.media !== null && root.media.canNext && !root.controlsPending
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Next track")
                    onClicked: root.next()

                    background: Rectangle {
                        radius: Theme.radius.md
                        color: nextButton.pressed ? Theme.color.surfaceActive : nextButton.hovered
                                                    ? Theme.color.surfaceHover : "transparent"
                    }
                    contentItem: Item {
                        IslandIcon {
                            anchors.centerIn: parent
                            meaning: "mediaNext"
                        }
                    }
                    IslandFocusRing {
                        visible: nextButton.visualFocus
                    }
                    ToolTip.delay: Theme.motion.durationSlow
                    ToolTip.visible: hovered || visualFocus
                    ToolTip.text: qsTr("Next track")
                }

                IslandText {
                    Layout.fillWidth: true
                    text: root.controlsPending ? qsTr("Pending") : root.media === null ? "" :
                                                                                         root.media.playbackState

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
                    value: root.media.position / root.media.duration
                    label: qsTr("Playback position")
                }

                IslandText {
                    text: root.formatTime(root.media.position) + " / " + root.formatTime(
                              root.media.duration)

                    textFormat: Text.PlainText
                    tone: "muted"
                    size: "caption"
                }
            }
        }
    }
}

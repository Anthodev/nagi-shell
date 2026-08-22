pragma ComponentBehavior: Bound

import QtQuick

// Compact Idle composition: workspace, time, optional weather, optional
// active media, in that order, on the island pill.
//
// Every block consumes only normalized adapter state and collapses
// completely when unavailable, so the width always follows the visible
// content and no block reserves a gap. Blocks are laid out with explicit
// bindings instead of a positioner: positioners do not reliably recompute
// their implicit size when a child's visibility or width flips after
// completion, which would leave the live island at a stale width. The
// composition is display-only: it exposes nothing focusable and dispatches
// no actions.
//
// Adapter inputs are duck-typed on their normalized public contracts:
//   - virtualDesktops: available, currentName, currentPosition
//   - clock: text
//   - weather: available, stale, temperatureC, condition, dayPhase
//   - media: available, artist, title
// Null inputs mean the integration is absent and the block stays collapsed.
// Stale weather keeps the last valid content because the adapter keeps
// available true during the bounded stale window.
Item {
    id: idle

    property var virtualDesktops: null
    property var clock: null
    property var weather: null
    property var media: null
    property bool reducedMotion: false

    readonly property int contentPadding: Theme.spacing.lg
    readonly property int contentGap: Theme.spacing.md

    readonly property bool workspaceAvailable: virtualDesktops !== null
                                               && virtualDesktops.available === true
    readonly property string workspaceText: {
        if (!workspaceAvailable) {
            return "";
        }

        const name = typeof virtualDesktops.currentName === "string"
        ? virtualDesktops.currentName.trim() : "";
        if (name !== "") {
            return name;
        }

        const position = virtualDesktops.currentPosition;
        return Number.isInteger(position) && position >= 0 ? String(position + 1) : "";
    }
    readonly property bool workspaceVisible: workspaceAvailable && workspaceText !== ""

    readonly property bool weatherAvailable: weather !== null && weather.available === true
    readonly property string temperatureText: weatherAvailable ? Math.round(weather.temperatureC)
                                                                 + "°" : ""

    readonly property bool mediaAvailable: media !== null && media.available === true
    readonly property string mediaSummary: composeMediaSummary()

    implicitWidth: contentPadding * 2 + contentRow.implicitWidth
    implicitHeight: Theme.size.islandIdleHeight

    // Verification seams: the live blocks, for collapse and order assertions.
    readonly property alias workspaceBlock: workspaceLabel
    readonly property alias clockBlock: clockLabel
    readonly property alias weatherBlock: weatherGroup
    readonly property alias mediaBlock: mediaText

    // Trailing edge after the given blocks: every visible block contributes
    // its width plus one gap. Invisible blocks contribute nothing, so
    // collapsing content closes the gap behind it.
    function offsetAfter(blocks) {
        let offset = 0;
        for (let index = 0; index < blocks.length; index += 1) {
            if (blocks[index].visible) {
                offset += blocks[index].width + contentGap;
            }
        }
        return offset;
    }

    function composeMediaSummary() {
        if (!mediaAvailable) {
            return "";
        }

        const artist = typeof media.artist === "string" ? media.artist.trim() : "";
        const title = typeof media.title === "string" ? media.title.trim() : "";
        if (artist !== "" && title !== "") {
            return artist + " — " + title;
        }
        if (title !== "") {
            return title;
        }
        if (artist !== "") {
            return artist;
        }
        // A selected player without meaningful metadata collapses too.
        return "";
    }

    Item {
        id: contentRow

        implicitWidth: Math.max(0, idle.offsetAfter([workspaceLabel, clockLabel, weatherGroup,
                                                     mediaText]) - idle.contentGap)
        implicitHeight: idle.implicitHeight

        IslandText {
            id: workspaceLabel

            x: 0
            anchors.verticalCenter: parent.verticalCenter
            visible: idle.workspaceVisible
            text: idle.workspaceText
            tone: "secondary"
            width: Math.min(implicitWidth, Theme.size.islandIdleWorkspaceMaximumWidth)
            elide: Text.ElideRight
        }

        IslandText {
            id: clockLabel

            x: idle.offsetAfter([workspaceLabel])
            anchors.verticalCenter: parent.verticalCenter
            text: idle.clock !== null ? idle.clock.text : ""
            font.weight: Theme.type.weightMedium
        }

        Item {
            id: weatherGroup

            x: idle.offsetAfter([workspaceLabel, clockLabel])
            anchors.verticalCenter: parent.verticalCenter
            visible: idle.weatherAvailable
            implicitWidth: weatherGlyph.implicitWidth + Theme.spacing.xs
                           + temperatureLabel.implicitWidth
            implicitHeight: temperatureLabel.implicitHeight

            WeatherGlyph {
                id: weatherGlyph

                anchors.verticalCenter: parent.verticalCenter
                condition: idle.weather !== null ? idle.weather.condition : "unknown"
                dayPhase: idle.weather !== null ? idle.weather.dayPhase : "day"
            }

            IslandText {
                id: temperatureLabel

                x: weatherGlyph.implicitWidth + Theme.spacing.xs
                anchors.verticalCenter: parent.verticalCenter
                text: idle.temperatureText
                tone: "secondary"
            }
        }

        IdleMediaText {
            id: mediaText

            x: idle.offsetAfter([workspaceLabel, clockLabel, weatherGroup])
            anchors.verticalCenter: parent.verticalCenter
            visible: idle.mediaAvailable && idle.mediaSummary !== ""
            summary: idle.mediaSummary
            maximumWidth: Theme.size.islandIdleMediaMaximumWidth
            scrolling: idle.visible && visible
            reducedMotion: idle.reducedMotion
        }
    }
}

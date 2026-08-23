pragma ComponentBehavior: Bound

import QtQuick

// Compact Idle composition: workspace, time, optional weather, optional
// active media, in that order.
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
//   - virtualDesktops: available, currentPosition
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

    readonly property int contentPadding: Theme.spacing.xl
    readonly property int contentGap: Theme.spacing.xl
    readonly property int boundaryWidth: contentGap * 2 + Theme.size.hairlineWidth
    readonly property int boundaryHeight: Theme.size.islandSeparatorHeight
    readonly property int workspaceIndicatorWidth: Theme.size.islandWorkspaceIndicatorWidth
    readonly property int workspaceIndicatorHeight: Theme.size.islandWorkspaceIndicatorHeight
    readonly property int weatherGap: Theme.spacing.sm
    readonly property int weatherLabelGap: Theme.spacing.xs
    readonly property int verticalPadding: Theme.spacing.sm

    // Height formula: caption + body tight bounds, their semantic gap, and
    // two vertical paddings, clamped to the 44–48 px contract. This covers the
    // tallest two-line group. The published Theme token remains the surface
    // baseline; a later typeface may raise the local height only when required.
    readonly property int metricsContentHeight: Math.ceil(bodyMetrics.tightBoundingRect.height
                                                          + weatherLabelGap
                                                          + captionMetrics.tightBoundingRect.height)
    readonly property int derivedContentHeight: Math.max(44, Math.min(48, metricsContentHeight
                                                                      + verticalPadding * 2))
    readonly property int resolvedHeight: Math.max(44, Math.min(48, Math.max(Theme.size.islandIdleHeight,
                                                                             derivedContentHeight)))

    readonly property bool workspaceAvailable: virtualDesktops !== null
                                               && virtualDesktops.available === true
    readonly property string workspaceText: {
        if (!workspaceAvailable) {
            return "";
        }

        const position = virtualDesktops.currentPosition;
        if (!Number.isInteger(position) || position < 0) {
            return "";
        }

        const displayPosition = position + 1;
        return displayPosition < 10 ? "0" + displayPosition : String(displayPosition);
    }
    readonly property bool workspaceVisible: workspaceText !== ""
    readonly property bool clockVisible: clock !== null && typeof clock.text === "string"
                                         && clock.text !== ""

    readonly property bool weatherAvailable: weather !== null && weather.available === true
    readonly property string temperatureText: weatherAvailable ? Math.round(weather.temperatureC)
                                                                 + "°" : ""
    readonly property string weatherCaptionText: composeWeatherCaption()

    readonly property bool mediaAvailable: media !== null && media.available === true
    readonly property string mediaSummary: composeMediaSummary()

    implicitWidth: contentPadding * 2 + contentRow.implicitWidth
    implicitHeight: resolvedHeight

    // Verification seams: visible groups and their collapse-aware boundaries.
    readonly property alias workspaceBlock: workspaceIndicator
    readonly property alias workspaceLabelItem: workspaceLabel
    readonly property alias workspaceBoundary: workspaceSeparator
    readonly property alias clockBlock: clockLabel
    readonly property alias clockBoundary: clockSeparator
    readonly property alias weatherBlock: weatherGroup
    readonly property alias weatherBoundary: weatherSeparator
    readonly property alias weatherIcon: weatherGlyph
    readonly property alias temperatureBlock: temperatureLabel
    readonly property alias weatherConditionBlock: weatherConditionLabel
    readonly property alias mediaBlock: mediaText

    // Invisible groups and boundaries consume no space. Each visible separator
    // owns its two optical gaps, preventing optional groups from leaving an
    // orphan rule or a residual gap.
    function offsetAfter(blocks) {
        let offset = 0;
        for (let index = 0; index < blocks.length; index += 1) {
            if (blocks[index].visible) {
                offset += blocks[index].width;
            }
        }
        return offset;
    }

    function composeWeatherCaption() {
        if (!weatherAvailable) {
            return "";
        }

        let condition = "Unknown";
        switch (weather.condition) {
        case "clear":
            condition = "Clear";
            break;
        case "mostlyClear":
            condition = "Mostly clear";
            break;
        case "partlyCloudy":
            condition = "Partly cloudy";
            break;
        case "cloudy":
            condition = "Cloudy";
            break;
        case "fog":
            condition = "Fog";
            break;
        case "rain":
            condition = "Rain";
            break;
        case "sleet":
            condition = "Sleet";
            break;
        case "snow":
            condition = "Snow";
            break;
        case "thunderstorm":
            condition = "Thunderstorm";
            break;
        }

        let phase = "Day";
        if (weather.dayPhase === "night") {
            phase = "Night";
        } else if (weather.dayPhase === "polartwilight") {
            phase = "Twilight";
        }
        return condition + " · " + phase;
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

    TextMetrics {
        id: bodyMetrics

        text: "Ag"
        font.pixelSize: Theme.type.body
        font.family: Theme.type.family
    }

    TextMetrics {
        id: captionMetrics

        text: "Ag"
        font.pixelSize: Theme.type.caption
        font.family: Theme.type.family
    }

    component GroupSeparator: Item {
        width: idle.boundaryWidth
        height: idle.implicitHeight

        Rectangle {
            anchors.centerIn: parent
            width: Theme.size.hairlineWidth
            height: idle.boundaryHeight
            radius: Theme.size.hairlineWidth / 2
            color: Theme.color.textMuted
            opacity: Theme.opacity.disabled
        }
    }

    Item {
        id: contentRow
        x: idle.contentPadding

        implicitWidth: idle.offsetAfter([workspaceIndicator, workspaceSeparator, clockLabel,
                                         clockSeparator, weatherGroup, weatherSeparator, mediaText])
        implicitHeight: idle.implicitHeight

        Item {
            id: workspaceIndicator

            x: 0
            anchors.verticalCenter: parent.verticalCenter
            visible: idle.workspaceVisible
            width: idle.workspaceIndicatorWidth
            height: idle.workspaceIndicatorHeight

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius.sm
                color: Theme.color.surfaceActive
            }

            IslandText {
                id: workspaceLabel

                anchors.centerIn: parent
                text: idle.workspaceText
                tone: "primary"
                size: "body"
                font.weight: Theme.type.weightMedium
            }
        }

        GroupSeparator {
            id: workspaceSeparator

            x: idle.offsetAfter([workspaceIndicator])
            visible: workspaceIndicator.visible && (clockLabel.visible || weatherGroup.visible
                                                    || mediaText.visible)
        }

        IslandText {
            id: clockLabel

            x: idle.offsetAfter([workspaceIndicator, workspaceSeparator])
            anchors.verticalCenter: parent.verticalCenter
            visible: idle.clockVisible
            text: visible ? idle.clock.text : ""
            size: "body"
            font.weight: Theme.type.weightMedium
        }

        GroupSeparator {
            id: clockSeparator

            x: idle.offsetAfter([workspaceIndicator, workspaceSeparator, clockLabel])
            visible: clockLabel.visible && (weatherGroup.visible || mediaText.visible)
        }

        Item {
            id: weatherGroup

            x: idle.offsetAfter([workspaceIndicator, workspaceSeparator, clockLabel,
                                 clockSeparator])
            anchors.verticalCenter: parent.verticalCenter
            visible: idle.weatherAvailable
            implicitWidth: weatherGlyph.implicitWidth + idle.weatherGap
                           + weatherLabels.implicitWidth
            implicitHeight: Math.max(weatherGlyph.implicitHeight, weatherLabels.implicitHeight)

            WeatherGlyph {
                id: weatherGlyph

                anchors.verticalCenter: parent.verticalCenter
                condition: idle.weather !== null ? idle.weather.condition : "unknown"
                dayPhase: idle.weather !== null ? idle.weather.dayPhase : "day"
            }

            Item {
                id: weatherLabels

                x: weatherGlyph.implicitWidth + idle.weatherGap
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: Math.max(temperatureLabel.implicitWidth,
                                        weatherConditionLabel.implicitWidth)
                implicitHeight: temperatureLabel.implicitHeight + idle.weatherLabelGap
                                + weatherConditionLabel.implicitHeight

                IslandText {
                    id: temperatureLabel

                    text: idle.temperatureText
                    tone: "secondary"
                    size: "body"
                    font.weight: Theme.type.weightMedium
                }

                IslandText {
                    id: weatherConditionLabel

                    y: temperatureLabel.implicitHeight + idle.weatherLabelGap
                    text: idle.weatherCaptionText
                    tone: "muted"
                    size: "caption"
                    font.weight: Theme.type.weightRegular
                }
            }
        }

        GroupSeparator {
            id: weatherSeparator

            x: idle.offsetAfter([workspaceIndicator, workspaceSeparator, clockLabel, clockSeparator,
                                 weatherGroup])
            visible: weatherGroup.visible && mediaText.visible
        }

        IdleMediaText {
            id: mediaText

            x: idle.offsetAfter([workspaceIndicator, workspaceSeparator, clockLabel, clockSeparator,
                                 weatherGroup, weatherSeparator])
            anchors.verticalCenter: parent.verticalCenter
            visible: idle.mediaAvailable && idle.mediaSummary !== ""
            summary: idle.mediaSummary
            maximumWidth: Theme.size.islandIdleMediaMaximumWidth
            scrolling: idle.visible && visible
            reducedMotion: idle.reducedMotion
        }
    }
}

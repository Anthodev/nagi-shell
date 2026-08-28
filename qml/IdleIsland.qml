pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

// Compact Idle composition: workspace, gaming status, time, optional weather,
// optional active media, in that order.
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
//   - gamingPerformance: active
//   - weather: available, stale, temperatureC, condition, dayPhase
//   - media: available, artist, title
// Null inputs mean the integration is absent and the block stays collapsed.
// Stale weather keeps the last valid content because the adapter keeps
// available true during the bounded stale window.
Item {
    id: idle
    readonly property string nagiTypographyScope: "idle"

    property var virtualDesktops: null
    property var clock: null
    property var weather: null
    property var media: null
    property var gamingPerformance: null
    property bool reducedMotion: false
    property bool showWorkspace: true
    property bool showWeather: true
    property bool showMedia: true

    signal weatherRequested

    readonly property int contentPadding: Theme.size.islandCompactPadding
    readonly property int contentGap: Theme.size.islandCompactPadding
    readonly property int boundaryWidth: contentGap * 2 + Theme.size.hairlineWidth
    readonly property int boundaryHeight: Theme.size.islandSeparatorHeight
    readonly property int workspaceIndicatorWidth: Theme.size.islandWorkspaceIndicatorWidth
    readonly property int workspaceIndicatorHeight: Theme.size.islandWorkspaceIndicatorHeight
    readonly property int weatherGap: Theme.spacing.sm
    readonly property int weatherLabelGap: Theme.spacing.xs
    readonly property int clockDateGap: Theme.spacing.md
    readonly property int verticalPadding: Theme.spacing.sm
    readonly property string gamingPerformanceTooltip: qsTr("Gaming performance active")

    // Height follows the tallest single-line text metric plus semantic vertical
    // padding, clamped to the 44–48 px contract. The published Theme token
    // remains the stable baseline; a later typeface may raise the local height
    // only when required.
    readonly property int metricsContentHeight: Math.ceil(Math.max(
                                                              bodyMetrics.tightBoundingRect.height,
                                                              captionMetrics.tightBoundingRect.height))
    readonly property int derivedContentHeight: Math.max(44, Math.min(48, metricsContentHeight
                                                                      + verticalPadding * 2))
    readonly property int resolvedHeight: Math.max(44, Math.min(48, Math.max(Theme.size.islandIdleHeight,
                                                                             derivedContentHeight)))

    readonly property bool workspaceAvailable: showWorkspace && virtualDesktops !== null
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
    readonly property bool idleDateVisible: clockVisible && clock.showIdleDate === true
                                            && typeof clock.dateText === "string" && clock.dateText
                                            !== ""
    readonly property bool gamingPerformanceVisible: gamingPerformance !== null
                                                     && gamingPerformance.active === true
    readonly property bool weatherAvailable: showWeather && weather !== null && weather.available
                                             === true
    readonly property string temperatureText: weatherAvailable ? Math.round(weather.temperatureC)
                                                                 + "°" : ""
    readonly property string weatherCaptionText: composeWeatherCaption()

    readonly property bool mediaAvailable: showMedia && media !== null && media.available === true
    readonly property string mediaSummary: composeMediaSummary()

    implicitWidth: contentPadding * 2 + contentRow.implicitWidth
    implicitHeight: resolvedHeight

    // Verification seams: visible groups and their collapse-aware boundaries.
    readonly property alias workspaceBlock: workspaceIndicator
    readonly property alias workspaceLabelItem: workspaceLabel
    readonly property alias workspaceBoundary: workspaceSeparator
    readonly property alias gamingPerformanceBlock: gamingPerformanceBadge
    readonly property alias gamingBadgeIcon: gamingPerformanceIcon
    readonly property alias gamingPerformanceBoundary: gamingPerformanceSeparator
    readonly property alias clockBlock: clockLabel
    readonly property alias clockGroupBlock: clockGroup
    readonly property alias clockDateBlock: clockDateLabel
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

        let condition = qsTr("Unknown");
        switch (weather.condition) {
        case "clear":
            condition = qsTr("Clear");
            break;
        case "mostlyClear":
            condition = qsTr("Mostly clear");
            break;
        case "partlyCloudy":
            condition = qsTr("Partly cloudy");
            break;
        case "cloudy":
            condition = qsTr("Cloudy");
            break;
        case "fog":
            condition = qsTr("Fog");
            break;
        case "rain":
            condition = qsTr("Rain");
            break;
        case "sleet":
            condition = qsTr("Sleet");
            break;
        case "snow":
            condition = qsTr("Snow");
            break;
        case "thunderstorm":
            condition = qsTr("Thunderstorm");
            break;
        }

        let phase = qsTr("Day");
        if (weather.dayPhase === "night") {
            phase = qsTr("Night");
        } else if (weather.dayPhase === "polartwilight") {
            phase = qsTr("Twilight");
        }
        return qsTr("%1 · %2").arg(condition).arg(phase);
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
        font.pixelSize: Theme.type.sizeFor("idle", "body")
        font.family: Theme.type.familyFor("idle")
    }

    TextMetrics {
        id: captionMetrics

        text: "Ag"
        font.pixelSize: Theme.type.sizeFor("idle", "caption")
        font.family: Theme.type.familyFor("idle")
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

        implicitWidth: idle.offsetAfter([workspaceIndicator, workspaceSeparator,
                                         gamingPerformanceBadge, gamingPerformanceSeparator,
                                         clockGroup, clockSeparator, weatherGroup, weatherSeparator,
                                         mediaText])
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
            visible: workspaceIndicator.visible && (gamingPerformanceBadge.visible
                                                    || clockGroup.visible || weatherGroup.visible
                                                    || mediaText.visible)
        }

        Item {
            id: gamingPerformanceBadge

            x: idle.offsetAfter([workspaceIndicator, workspaceSeparator])
            anchors.verticalCenter: parent.verticalCenter
            visible: idle.gamingPerformanceVisible
            width: gamingPerformanceIcon.implicitWidth
            height: gamingPerformanceIcon.implicitHeight
            Accessible.role: Accessible.StaticText
            Accessible.name: qsTr("Gaming performance indicator active")
            Accessible.description: qsTr("Passive status badge. No action is available.")
            ToolTip.visible: gamingPerformanceHover.hovered
            ToolTip.delay: 500
            ToolTip.text: idle.gamingPerformanceTooltip
            IslandIcon {
                id: gamingPerformanceIcon

                anchors.centerIn: parent
                meaning: "gamingPerformance"
                semanticState: "active"
                size: "md"
            }

            HoverHandler {
                id: gamingPerformanceHover
            }
        }

        GroupSeparator {
            id: gamingPerformanceSeparator

            x: idle.offsetAfter([workspaceIndicator, workspaceSeparator, gamingPerformanceBadge])
            visible: gamingPerformanceBadge.visible && (clockGroup.visible || weatherGroup.visible
                                                        || mediaText.visible)
        }

        Item {
            id: clockGroup

            x: idle.offsetAfter([workspaceIndicator, workspaceSeparator, gamingPerformanceBadge,
                                 gamingPerformanceSeparator])
            anchors.verticalCenter: parent.verticalCenter
            visible: idle.clockVisible
            implicitWidth: clockLabel.implicitWidth + (clockDateLabel.visible ? idle.clockDateGap
                                                                                + clockDateLabel.implicitWidth :
                                                                                0)
            implicitHeight: Math.max(clockLabel.implicitHeight, clockDateLabel.implicitHeight)

            IslandText {
                id: clockLabel

                anchors.verticalCenter: parent.verticalCenter
                text: clockGroup.visible ? idle.clock.text : ""
                size: "body"
                font.weight: Theme.type.weightMedium
            }

            IslandText {
                id: clockDateLabel

                x: clockLabel.implicitWidth + idle.clockDateGap
                anchors.verticalCenter: parent.verticalCenter
                visible: idle.idleDateVisible
                text: visible ? idle.clock.dateText : ""
                size: "body"
                font.weight: Theme.type.weightMedium
            }
        }

        GroupSeparator {
            id: clockSeparator

            x: idle.offsetAfter([workspaceIndicator, workspaceSeparator, gamingPerformanceBadge,
                                 gamingPerformanceSeparator, clockGroup])
            visible: clockGroup.visible && (weatherGroup.visible || mediaText.visible)
        }

        AbstractButton {
            id: weatherGroup

            x: idle.offsetAfter([workspaceIndicator, workspaceSeparator, gamingPerformanceBadge,
                                 gamingPerformanceSeparator, clockGroup, clockSeparator])
            anchors.verticalCenter: parent.verticalCenter
            visible: idle.weatherAvailable
            implicitWidth: weatherGlyph.implicitWidth + idle.weatherGap
                           + weatherLabels.implicitWidth
            implicitHeight: Math.max(weatherGlyph.implicitHeight, weatherLabels.implicitHeight)
            focusPolicy: Qt.NoFocus
            hoverEnabled: true
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Open detailed weather for %1, %2").arg(idle.temperatureText).arg(
                                 idle.weatherCaptionText)
            onClicked: idle.weatherRequested()

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
                implicitWidth: temperatureLabel.implicitWidth + idle.weatherLabelGap
                               + weatherConditionLabel.implicitWidth
                implicitHeight: Math.max(temperatureLabel.implicitHeight,
                                         weatherConditionLabel.implicitHeight)

                IslandText {
                    id: temperatureLabel

                    anchors.verticalCenter: parent.verticalCenter
                    text: idle.temperatureText
                    tone: "secondary"
                    size: "body"
                    font.weight: Theme.type.weightMedium
                }

                IslandText {
                    id: weatherConditionLabel

                    x: temperatureLabel.implicitWidth + idle.weatherLabelGap
                    anchors.verticalCenter: parent.verticalCenter
                    text: idle.weatherCaptionText
                    tone: "muted"
                    size: "caption"
                    font.weight: Theme.type.weightRegular
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: Qt.PointingHandCursor
                enabled: weatherGroup.enabled
            }
        }

        GroupSeparator {
            id: weatherSeparator

            x: idle.offsetAfter([workspaceIndicator, workspaceSeparator, gamingPerformanceBadge,
                                 gamingPerformanceSeparator, clockGroup, clockSeparator,
                                 weatherGroup])
            visible: weatherGroup.visible && mediaText.visible
        }

        IdleMediaText {
            id: mediaText

            x: idle.offsetAfter([workspaceIndicator, workspaceSeparator, gamingPerformanceBadge,
                                 gamingPerformanceSeparator, clockGroup, clockSeparator,
                                 weatherGroup, weatherSeparator])
            anchors.verticalCenter: parent.verticalCenter
            visible: idle.mediaAvailable && idle.mediaSummary !== ""
            summary: idle.mediaSummary
            maximumWidth: Theme.size.islandIdleMediaMaximumWidth
        }
    }
}

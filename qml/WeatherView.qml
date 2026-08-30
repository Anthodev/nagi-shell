pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FocusScope {
    id: view

    required property var adapter
    required property real ownerEpoch
    property bool active: true
    property bool reducedMotion: false
    property real maximumViewportWidth: Number.POSITIVE_INFINITY
    property real maximumViewportHeight: Number.POSITIVE_INFINITY

    readonly property bool hasModel: adapter !== null && adapter.model !== null
    readonly property var current: hasModel ? adapter.current : null
    readonly property var hourly: active && hasModel ? adapter.hourly : []
    readonly property var daily: active && hasModel ? adapter.daily : []

    implicitWidth: frame.implicitWidth
    implicitHeight: frame.implicitHeight
    visible: active

    signal cancelled(real ownerEpoch)

    function conditionText(condition) {
        if (condition === "clear")
            return qsTr("Clear");
        if (condition === "mostlyClear")
            return qsTr("Mostly clear");
        if (condition === "partlyCloudy")
            return qsTr("Partly cloudy");
        if (condition === "cloudy")
            return qsTr("Cloudy");
        if (condition === "fog")
            return qsTr("Fog");
        if (condition === "rain")
            return qsTr("Rain");
        if (condition === "sleet")
            return qsTr("Sleet");
        if (condition === "snow")
            return qsTr("Snow");
        if (condition === "thunderstorm")
            return qsTr("Thunderstorm");
        return qsTr("Unknown conditions");
    }

    function temperatureSuffix(unit) {
        return unit === "fahrenheit" ? "°F" : "°C";
    }

    function windSuffix(unit) {
        if (unit === "mph")
            return "mph";
        if (unit === "ms")
            return "m/s";
        return "km/h";
    }

    function ageText() {
        if (adapter === null || !Number.isFinite(adapter.lastUpdatedAgeMs)) {
            return qsTr("Update time unavailable");
        }
        const minutes = Math.max(0, Math.floor(adapter.lastUpdatedAgeMs / 60000));
        if (minutes < 1)
            return qsTr("Updated just now");
        if (minutes === 1)
            return qsTr("Updated 1 minute ago");
        if (minutes < 60)
            return qsTr("Updated %1 minutes ago").arg(minutes);
        const hours = Math.floor(minutes / 60);
        return hours === 1 ? qsTr("Updated 1 hour ago") : qsTr("Updated %1 hours ago").arg(hours);
    }

    function failureText() {
        if (adapter === null || adapter.failure === "unconfigured")
            return qsTr("Configure Weather in the Control Center.");
        if (adapter.failure === "throttled")
            return qsTr("The provider is limiting requests. Nagi will retry later.");
        if (adapter.failure === "permanent")
            return qsTr(
                        "This location is unavailable. Confirm another location in the Control Center.");
        if (adapter.failure === "transient")
            return qsTr("Weather could not refresh. Cached data remains available when safe.");
        if (adapter.failure === "stale")
            return qsTr("Cached weather expired. Try again later or confirm the location.");
        return qsTr("Weather is temporarily unavailable.");
    }

    function focusInitialControl() {
        if (refreshButton.visible && refreshButton.enabled) {
            refreshButton.forceActiveFocus(Qt.ShortcutFocusReason);
            return true;
        }
        return frame.focusInitialControl();
    }

    SubviewFrame {
        id: frame
        objectName: "weatherSubviewFrame"

        anchors.fill: parent
        active: view.active
        title: view.hasModel ? view.adapter.model.location : qsTr("Weather")
        preferredViewportWidth: 576
        preferredViewportHeight: 360
        maximumViewportWidth: view.maximumViewportWidth
        maximumViewportHeight: view.maximumViewportHeight
        initialFocusItem: refreshButton.visible && refreshButton.enabled ? refreshButton : null
        onBackRequested: view.cancelled(view.ownerEpoch)
        onEscapePressed: view.cancelled(view.ownerEpoch)

        Item {
            id: contentRoot

            implicitWidth: 576
            width: Math.max(implicitWidth, parent.width)
            height: content.implicitHeight

            ColumnLayout {
                id: content

                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Theme.spacing.lg

                IslandPanel {
                    Layout.fillWidth: true
                    implicitHeight: currentLayout.implicitHeight + Theme.spacing.lg * 2
                    color: Theme.color.controlFill
                    visible: view.hasModel

                    RowLayout {
                        id: currentLayout

                        anchors.fill: parent
                        anchors.margins: Theme.spacing.lg
                        spacing: Theme.spacing.lg

                        WeatherGlyph {
                            condition: view.current === null ? "unknown" : view.current.condition
                            dayPhase: view.current === null ? "day" : view.current.dayPhase
                            implicitWidth: Theme.spacing.xxl * 2
                            implicitHeight: implicitWidth
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacing.xs

                            IslandText {
                                text: view.current === null ? "" : Math.round(
                                                                  view.current.temperature)
                                                              + view.temperatureSuffix(
                                                                  view.current.temperatureUnit)
                                size: "display"
                                Accessible.name: qsTr("Current temperature: %1").arg(text)
                            }

                            IslandText {
                                Layout.fillWidth: true
                                text: view.current === null ? "" : view.conditionText(
                                                                  view.current.condition)
                                size: "body"
                                color: Theme.color.textSecondary
                                wrapMode: Text.Wrap
                            }

                            IslandText {
                                Layout.fillWidth: true
                                text: view.ageText() + (view.adapter !== null && view.adapter.stale
                                                        ? " · Stale" : "")
                                size: "caption"
                                color: view.adapter !== null && view.adapter.stale
                                       ? Theme.color.warning : Theme.color.textMuted
                                Accessible.name: text
                            }
                        }

                        ColumnLayout {
                            spacing: Theme.spacing.xs

                            IslandText {
                                text: view.current === null ? "" : qsTr(
                                                                  "Feels like %1 (calculated)").arg(
                                                                  Math.round(
                                                                      view.current.feelsLike)
                                                                  + view.temperatureSuffix(
                                                                      view.current.temperatureUnit))
                                size: "caption"
                                color: Theme.color.textSecondary
                                Accessible.name: text
                            }

                            IslandText {
                                text: view.current === null ? "" : qsTr("Humidity %1%").arg(
                                                                  Math.round(view.current.humidity))
                                size: "caption"
                                color: Theme.color.textSecondary
                                Accessible.name: text
                            }

                            IslandText {
                                text: view.current === null ? "" : qsTr("Wind %1 %2").arg(Math.round(
                                                                                              view.current.wind)).arg(
                                                                  view.windSuffix(
                                                                      view.current.windUnit))
                                size: "caption"
                                color: Theme.color.textSecondary
                                Accessible.name: text
                            }
                        }
                    }
                }

                IslandText {
                    Layout.fillWidth: true
                    visible: !view.hasModel
                    text: view.failureText()
                    size: "body"
                    color: Theme.color.textSecondary
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.AlertMessage
                    Accessible.name: text
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.md

                    IslandText {
                        Layout.fillWidth: true
                        text: qsTr("Next 12 hours")
                        size: "title"
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    IslandButton {
                        id: refreshButton

                        visible: view.adapter !== null
                        enabled: view.adapter !== null && view.adapter.manualRefreshAvailable
                        label: view.adapter !== null && view.adapter.refreshInFlight ? qsTr(
                                                                                           "Refreshing…") :
                                                                                       qsTr("Refresh")
                        reducedMotion: view.reducedMotion
                        Accessible.description: enabled ? qsTr("Refresh weather now") : qsTr(
                                                              "Refresh is cooling down")
                        onClicked: view.adapter.manualRefresh()
                    }
                }

                Item {
                    id: hourlyViewport
                    objectName: "weatherHourlyViewport"

                    Layout.fillWidth: true
                    implicitHeight: Theme.spacing.xxl * 3
                    visible: view.hourly.length > 0

                    ListView {
                        id: hourlyList
                        objectName: "weatherHourlyList"

                        anchors.fill: parent
                        orientation: ListView.Horizontal
                        spacing: Theme.spacing.sm
                        model: view.hourly
                        currentIndex: count > 0 ? 0 : -1
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        interactive: contentWidth > width
                        activeFocusOnTab: interactive
                        keyNavigationEnabled: false
                        Accessible.role: Accessible.List
                        Accessible.name: qsTr("Hourly forecast")
                        Accessible.description: interactive ? qsTr(
                                                                  "Use Left and Right to browse the hourly forecast") :
                                                              ""

                        function revealIndex(index) {
                            if (count <= 0) {
                                currentIndex = -1;
                                return;
                            }
                            currentIndex = Math.max(0, Math.min(count - 1, index));
                            positionViewAtIndex(currentIndex, ListView.Contain);
                        }

                        onActiveFocusChanged: {
                            if (activeFocus && currentIndex >= 0) {
                                positionViewAtIndex(currentIndex, ListView.Contain);
                            }
                        }
                        onCountChanged: revealIndex(currentIndex < 0 ? 0 : currentIndex)

                        Keys.priority: Keys.BeforeItem
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Left) {
                                revealIndex(currentIndex - 1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Right) {
                                revealIndex(currentIndex + 1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Home) {
                                revealIndex(0);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_End) {
                                revealIndex(count - 1);
                                event.accepted = true;
                            }
                        }

                        ScrollBar.horizontal: ScrollBar {
                            id: hourlyScrollBar
                            objectName: "weatherHourlyScrollBar"
                            policy: hourlyList.contentWidth > hourlyList.width ? ScrollBar.AlwaysOn :
                                                                                 ScrollBar.AlwaysOff
                        }

                        delegate: ForecastCard {
                            required property var modelData

                            width: Math.max(Theme.spacing.xxl * 2, implicitWidth)
                            height: implicitHeight
                            heading: Qt.formatTime(new Date(modelData.forecastEpoch), "HH:mm")
                            condition: modelData.condition
                            dayPhase: modelData.dayPhase
                            temperature: Math.round(modelData.temperature) + view.temperatureSuffix(
                                             modelData.temperatureUnit)
                        }
                    }

                    IslandFocusRing {
                        controlRadius: Theme.radius.md
                        visible: hourlyList.activeFocus
                    }
                }

                IslandText {
                    Layout.fillWidth: true
                    visible: view.hourly.length === 0
                    text: qsTr("Hourly forecast unavailable")
                    size: "caption"
                    tone: "muted"
                }

                IslandText {
                    Layout.fillWidth: true
                    text: qsTr("Next 5 days")
                    size: "title"
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }

                RowLayout {
                    id: dailyRow
                    Layout.fillWidth: true
                    visible: view.daily.length > 0
                    spacing: Theme.spacing.sm
                    Accessible.role: Accessible.List
                    Accessible.name: qsTr("Daily forecast")

                    Repeater {
                        model: view.daily

                        delegate: ForecastCard {
                            required property var modelData

                            heading: Qt.formatDate(new Date(modelData.dateEpoch), "ddd")
                            condition: modelData.condition
                            dayPhase: modelData.dayPhase
                            temperature: Math.round(modelData.minimumTemperature) + "–" + Math.round(
                                             modelData.maximumTemperature) + view.temperatureSuffix(
                                             modelData.temperatureUnit)
                        }
                    }
                }

                IslandText {
                    Layout.fillWidth: true
                    visible: view.daily.length === 0
                    text: qsTr("Daily forecast unavailable")
                    size: "caption"
                    tone: "muted"
                }

                IslandText {
                    Layout.fillWidth: true
                    text: qsTr("Weather data from MET Norway · NLOD 2.0 / CC BY 4.0")
                    size: "caption"
                    tone: "muted"
                    wrapMode: Text.Wrap
                    Accessible.name: text
                }
            }
        }
    }

    component ForecastCard: IslandPanel {
        id: card
        required property string heading
        required property string condition
        required property string dayPhase
        required property string temperature

        Layout.fillWidth: true
        Layout.minimumWidth: Theme.spacing.xxl * 2
        implicitHeight: cardContent.implicitHeight + Theme.spacing.md * 2
        color: Theme.color.controlFill
        Accessible.role: Accessible.ListItem
        Accessible.name: qsTr("%1, %2, %3").arg(heading).arg(view.conditionText(condition)).arg(
                             temperature)

        ColumnLayout {
            id: cardContent

            anchors.fill: parent
            anchors.margins: Theme.spacing.md
            spacing: Theme.spacing.xs

            IslandText {
                Layout.fillWidth: true
                text: card.heading
                size: "caption"
                horizontalAlignment: Text.AlignHCenter
            }

            WeatherGlyph {
                Layout.alignment: Qt.AlignHCenter
                condition: card.condition
                dayPhase: card.dayPhase
            }

            IslandText {
                Layout.fillWidth: true
                text: card.temperature
                size: "body"
                horizontalAlignment: Text.AlignHCenter
                font.weight: Theme.type.weightMedium
            }
        }
    }
}

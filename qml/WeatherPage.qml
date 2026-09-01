pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root

    required property var settingsModel
    required property var weather
    required property var locationSearch
    property bool reducedMotion: false
    property bool privacyAccepted: settingsModel.snapshot.weather.consent
    property string failureText: ""

    readonly property bool lookupAllowed: visible && privacyAccepted
    readonly property bool configured: settingsModel.snapshot.weather.enabled
                                       && settingsModel.snapshot.weather.consent
                                       && settingsModel.snapshot.weather.locationLabel !== ""

    clip: true
    contentWidth: width
    contentHeight: content.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {
        policy: root.contentHeight > root.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
    }

    Component.onDestruction: locationSearch.clear()
    onLookupAllowedChanged: {
        if (!lookupAllowed) {
            locationSearch.clear();
        }
    }

    function request(changes) {
        if (settingsModel.updatePage("weather", changes, false)) {
            failureText = "";
            return true;
        }
        failureText = settingsModel.errorMessage !== "" ? settingsModel.errorMessage : qsTr(
                                                              "The Weather change could not be applied.");
        return false;
    }

    function search() {
        failureText = "";
        if (!privacyAccepted) {
            failureText = qsTr("Accept the privacy notice before searching.");
            return false;
        }
        if (!locationSearch.search(searchInput.text)) {
            failureText = locationSearch.failure === "invalid-query" ? qsTr(
                                                                           "Enter at least two city or postal characters.") :
                                                                       qsTr("Location search is currently unavailable.");
            return false;
        }
        return true;
    }

    function confirm(result) {
        if (result === null || typeof result !== "object") {
            return false;
        }
        const accepted = request({
                                     "enabled": true,
                                     "consent": true,
                                     "locationLabel": result.label,
                                     "latitude": result.latitude,
                                     "longitude": result.longitude
                                 });
        if (accepted) {
            searchInput.text = "";
            locationSearch.clear();
        }
        return accepted;
    }

    function disableWeather() {
        const accepted = request({
                                     "enabled": false,
                                     "consent": false,
                                     "locationLabel": "",
                                     "latitude": null,
                                     "longitude": null
                                 });
        if (accepted) {
            privacyAccepted = false;
            searchInput.text = "";
            locationSearch.clear();
        }
        return accepted;
    }

    function lookupFailureText() {
        if (locationSearch.failure === "no-results")
            return qsTr("No matching city or postal location was found.");
        if (locationSearch.failure === "throttled" || locationSearch.failure === "rate-limited")
            return qsTr("Location search is rate limited. Wait before trying again.");
        if (locationSearch.failure === "timeout")
            return qsTr("Location search timed out. Try again.");
        if (locationSearch.failure !== "none")
            return qsTr("Location search is unavailable. Try again later.");
        return "";
    }

    ColumnLayout {
        id: content

        width: Math.min(root.width - (root.contentHeight > root.height ? Theme.spacing.md : 0),
                        Theme.size.controlCenterContentMaximumWidth)
        spacing: Theme.spacing.md

        ControlCenterPageHeader {
            objectName: "weatherPageHeader"
            Layout.fillWidth: true
            iconMeaning: "controlCenterWeather"
            title: qsTr("Weather")
            description: qsTr("Configure opt-in weather forecasts for one confirmed location.")
        }

        IslandPanel {
            Layout.fillWidth: true
            implicitHeight: privacyColumn.implicitHeight + Theme.spacing.lg * 2
            color: Theme.color.controlFill

            ColumnLayout {
                id: privacyColumn

                anchors.fill: parent
                anchors.margins: Theme.spacing.lg
                spacing: Theme.spacing.sm

                IslandText {
                    Layout.fillWidth: true
                    text: qsTr("Privacy before configuration")
                    size: "title"
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }

                IslandText {
                    Layout.fillWidth: true
                    text: qsTr(
                              "A manual search sends the submitted city or postal text and your IP address to Open-Meteo. If that service is unavailable, Nagi may send the same submitted search to the configured Nominatim endpoint. After confirmation, forecasts send your IP address and four-decimal coordinates directly to MET Norway. Nagi stores only the confirmed label and coordinates; it keeps no search history and never uses IP geolocation or automatic location tracking.")
                    textFormat: Text.PlainText
                    size: "body"
                    color: Theme.color.textSecondary
                    wrapMode: Text.Wrap
                    Accessible.name: text
                }
            }
        }

        SettingToggleRow {
            Layout.fillWidth: true
            label: qsTr("I understand the Weather privacy disclosure")
            description: qsTr(
                             "Required before a manual city or postal search. This choice is saved only with a confirmed location.")
            value: root.privacyAccepted
            writable: root.settingsModel.writable
            onValueRequested: value => {
                root.privacyAccepted = value;
                if (!value) {
                    root.locationSearch.clear();
                }
            }
        }

        IslandPanel {
            Layout.fillWidth: true
            implicitHeight: locationColumn.implicitHeight + Theme.spacing.lg * 2
            color: Theme.color.controlFill
            visible: root.configured

            ColumnLayout {
                id: locationColumn

                anchors.fill: parent
                anchors.margins: Theme.spacing.lg
                spacing: Theme.spacing.sm

                IslandText {
                    Layout.fillWidth: true
                    text: root.settingsModel.snapshot.weather.locationLabel
                    size: "title"
                    wrapMode: Text.Wrap
                    Accessible.name: qsTr("Confirmed Weather location: %1").arg(text)
                }

                IslandText {
                    Layout.fillWidth: true
                    text: root.weather !== null && root.weather.available ? Math.round(
                                                                                root.weather.current.temperature)
                                                                            + (root.weather.current.temperatureUnit
                                                                               === "fahrenheit"
                                                                               ? "°F" : "°C") + (
                                                                                root.weather.stale
                                                                                ? " · stale" :
                                                                                  " · current") :
                                                                            qsTr("Forecast unavailable")
                    size: "body"
                    color: Theme.color.textSecondary
                    Accessible.name: qsTr("Weather preview: %1").arg(text)
                }

                IslandButton {
                    label: qsTr("Disable and clear Weather")
                    variant: "danger"
                    reducedMotion: root.reducedMotion
                    enabled: root.settingsModel.writable
                    Accessible.description: qsTr(
                                                "Stop requests and clear the confirmed location and cache")
                    onClicked: root.disableWeather()
                }
            }
        }

        ControlCenterSectionHeading {
            objectName: "weatherLocationSection"
            Layout.fillWidth: true
            text: root.configured ? qsTr("Replace location") : qsTr("Choose a location")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.sm

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Theme.size.controlHeightMd
                radius: Theme.radius.md
                color: Theme.color.controlFill
                border.width: Theme.size.hairlineWidth
                border.color: searchInput.activeFocus ? Theme.snapshot.focusRing :
                                                        Theme.color.surfaceBorder
                opacity: root.lookupAllowed ? 1 : Theme.opacity.disabled

                IslandText {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacing.md
                    text: qsTr("City or postal code")
                    tone: "muted"
                    verticalAlignment: Text.AlignVCenter
                    visible: searchInput.text === ""
                }

                TextInput {
                    id: searchInput

                    anchors.fill: parent
                    leftPadding: Theme.spacing.md
                    rightPadding: Theme.spacing.md
                    enabled: root.lookupAllowed && !root.locationSearch.inFlight
                    color: Theme.color.textPrimary
                    selectionColor: Theme.snapshot.accent
                    selectedTextColor: Theme.snapshot.accentForeground
                    font.pixelSize: Theme.type.sizeForItem(this, "body")
                    font.family: Theme.type.familyForItem(this)
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    activeFocusOnTab: true
                    inputMethodHints: Qt.ImhNoPredictiveText
                    maximumLength: 128
                    Accessible.role: Accessible.EditableText
                    Accessible.name: qsTr("City or postal location")
                    Keys.onReturnPressed: event => {
                        root.search();
                        event.accepted = true;
                    }
                    Keys.onEnterPressed: event => {
                        root.search();
                        event.accepted = true;
                    }
                }
            }

            IslandButton {
                label: root.locationSearch.inFlight ? qsTr("Searching…") : qsTr("Search")
                reducedMotion: root.reducedMotion
                enabled: root.lookupAllowed && !root.locationSearch.inFlight
                         && searchInput.text.trim().length >= 2
                onClicked: root.search()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.locationSearch.results.length > 0
            spacing: Theme.spacing.sm
            Accessible.role: Accessible.List
            Accessible.name: qsTr("Location search results")

            Repeater {
                model: root.visible ? root.locationSearch.results : []

                delegate: IslandButton {
                    required property var modelData

                    Layout.fillWidth: true
                    label: modelData.label
                    reducedMotion: root.reducedMotion
                    Accessible.role: Accessible.ListItem
                    Accessible.description: qsTr("Use this location and enable Weather")
                    onClicked: root.confirm(modelData)
                }
            }
        }

        IslandText {
            Layout.fillWidth: true
            visible: root.lookupFailureText() !== ""
            text: root.lookupFailureText()
            size: "caption"
            color: Theme.color.danger
            wrapMode: Text.Wrap
            Accessible.role: Accessible.AlertMessage
            Accessible.name: text
        }

        IslandText {
            Layout.fillWidth: true
            text: root.locationSearch.attribution
            size: "caption"
            tone: "muted"
            wrapMode: Text.Wrap
            Accessible.name: text
        }

        ControlCenterSectionHeading {
            objectName: "weatherForecastPreferencesSection"
            text: qsTr("Forecast preferences")
        }

        SettingChoiceRow {
            Layout.fillWidth: true
            label: qsTr("Temperature")
            description: qsTr("Follow the locale or override temperature independently.")
            value: root.settingsModel.snapshot.weather.temperatureUnit
            choices: [
                {
                    "label": qsTr("Locale"),
                    "value": "auto"
                },
                {
                    "label": qsTr("Celsius"),
                    "value": "celsius"
                },
                {
                    "label": qsTr("Fahrenheit"),
                    "value": "fahrenheit"
                }
            ]
            writable: root.settingsModel.writable
            reducedMotion: root.reducedMotion
            onValueRequested: value => root.request({
                                                        "temperatureUnit": value
                                                    })
        }

        SettingChoiceRow {
            Layout.fillWidth: true
            label: qsTr("Wind speed")
            description: qsTr("Follow the locale or override wind independently.")
            value: root.settingsModel.snapshot.weather.windUnit
            choices: [
                {
                    "label": qsTr("Locale"),
                    "value": "auto"
                },
                {
                    "label": "km/h",
                    "value": "kmh"
                },
                {
                    "label": "mph",
                    "value": "mph"
                },
                {
                    "label": "m/s",
                    "value": "ms"
                }
            ]
            writable: root.settingsModel.writable
            reducedMotion: root.reducedMotion
            onValueRequested: value => root.request({
                                                        "windUnit": value
                                                    })
        }

        SettingChoiceRow {
            Layout.fillWidth: true
            label: qsTr("Refresh preference")
            description: qsTr(
                             "Provider cache expiry, minimum gaps, throttling, Retry-After, and backoff always take precedence.")
            value: root.settingsModel.snapshot.weather.refreshPreset
            choices: [
                {
                    "label": "15 minutes",
                    "value": "15m"
                },
                {
                    "label": "30 minutes",
                    "value": "30m"
                },
                {
                    "label": "1 hour",
                    "value": "1h"
                },
                {
                    "label": "3 hours",
                    "value": "3h"
                }
            ]
            writable: root.settingsModel.writable
            reducedMotion: root.reducedMotion
            onValueRequested: value => root.request({
                                                        "refreshPreset": value
                                                    })
        }

        IslandText {
            Layout.fillWidth: true
            visible: root.failureText !== ""
            text: root.failureText
            size: "caption"
            color: Theme.color.danger
            wrapMode: Text.Wrap
            Accessible.role: Accessible.AlertMessage
            Accessible.name: text
        }

        SettingsResetActions {
            Layout.fillWidth: true
            pageId: "weather"
            writable: root.settingsModel.writable
            errorText: root.settingsModel.status === "write-failed"
                       ? root.settingsModel.errorMessage : ""
            reducedMotion: root.reducedMotion
            onResetPageRequested: pageId => {
                if (root.settingsModel.resetPage(pageId)) {
                    root.privacyAccepted = false;
                    root.locationSearch.clear();
                }
            }
            onResetAllRequested: {
                if (root.settingsModel.resetAll()) {
                    root.privacyAccepted = false;
                    root.locationSearch.clear();
                }
            }
        }

        IslandText {
            Layout.fillWidth: true
            text: qsTr(
                      "Forecasts: MET Norway (NLOD 2.0 / CC BY 4.0). Search: GeoNames/Open-Meteo (CC BY 4.0), or OpenStreetMap contributors (ODbL) when the Nominatim fallback is active.")
            size: "caption"
            tone: "muted"
            wrapMode: Text.Wrap
            Accessible.name: text
        }
    }
}

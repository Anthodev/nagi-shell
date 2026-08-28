pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root

    required property var settingsModel
    property bool reducedMotion: false
    property bool gamingPerformanceAvailable: false
    property string failureText: ""

    clip: true
    contentWidth: width
    contentHeight: content.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {
        policy: root.contentHeight > root.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
    }

    function request(changes, continuous) {
        if (settingsModel.updatePage("island", changes, continuous === true)) {
            failureText = "";
            return true;
        }
        failureText = settingsModel.errorMessage !== "" ? settingsModel.errorMessage :
                                                          "The island change could not be applied.";
        return false;
    }

    ColumnLayout {
        id: content

        width: root.width - (root.contentHeight > root.height ? Theme.spacing.md : 0)
        spacing: Theme.spacing.md

        IslandText {
            text: "Island"
            size: "title"
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }

        IslandText {
            Layout.fillWidth: true
            text: "Tune the shared compact metrics and adaptive expanded bounds. Content order and the screen-safe layout remain fixed."
            size: "body"
            color: Theme.color.textSecondary
            wrapMode: Text.Wrap
        }

        SettingSliderRow {
            Layout.fillWidth: true
            label: "Compact height"
            description: "Metrics-aware target between 44 and 48 logical pixels."
            value: root.settingsModel.snapshot.island.compactHeight
            from: 44
            to: 48
            stepSize: 1
            valueText: Math.round(value) + " px"
            writable: root.settingsModel.writable
            onValueRequested: (value, continuous) => root.request({
                                                                      "compactHeight": value
                                                                  }, continuous)
        }

        SettingSliderRow {
            Layout.fillWidth: true
            label: "Compact padding"
            description: "Side padding and group rhythm from 16 to 32 logical pixels."
            value: root.settingsModel.snapshot.island.compactPadding
            from: 16
            to: 32
            stepSize: 4
            valueText: Math.round(value) + " px"
            writable: root.settingsModel.writable
            onValueRequested: (value, continuous) => root.request({
                                                                      "compactPadding": value
                                                                  }, continuous)
        }

        SettingSliderRow {
            Layout.fillWidth: true
            label: "Expanded width limit"
            description:
            "Maximum fraction of the current screen; natural content may remain smaller."
            value: root.settingsModel.snapshot.island.expandedWidthPercent
            from: 0.6
            to: 1
            stepSize: 0.05
            valueText: Math.round(value * 100) + "%"
            writable: root.settingsModel.writable
            onValueRequested: (value, continuous) => root.request({
                                                                      "expandedWidthPercent": value
                                                                  }, continuous)
        }

        SettingSliderRow {
            Layout.fillWidth: true
            label: "Expanded height limit"
            description:
            "Maximum fraction of the current screen with existing content bounds preserved."
            value: root.settingsModel.snapshot.island.expandedHeightPercent
            from: 0.6
            to: 1
            stepSize: 0.05
            valueText: Math.round(value * 100) + "%"
            writable: root.settingsModel.writable
            onValueRequested: (value, continuous) => root.request({
                                                                      "expandedHeightPercent": value
                                                                  }, continuous)
        }

        IslandText {
            text: "Feedback"
            size: "title"
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }

        SettingToggleRow {
            id: gamingPerformanceToggle
            objectName: "gamingPerformanceToggle"

            Layout.fillWidth: true
            label: "Gaming performance indicator"
            description: !value ? "Observer, feedback, and badge are disabled." :
                                  root.gamingPerformanceAvailable
                                  ? "Show passive system-status feedback and a static badge while GameMode clients or the performance power profile are active." :
                                    "No supported Gaming Performance backend is currently available."
            value: root.settingsModel.snapshot.island.gamingIndicator
            writable: root.settingsModel.writable
            onValueRequested: value => root.request({
                                                        "gamingIndicator": value
                                                    }, false)
        }
        IslandText {
            text: "Compact content"
            size: "title"
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }

        IslandText {
            Layout.fillWidth: true
            text: "Clock is always visible. Optional content keeps the fixed order Workspace → Gaming Performance → Clock → Weather → Media and collapses when unavailable."
            size: "body"
            color: Theme.color.textSecondary
            wrapMode: Text.Wrap
        }

        SettingToggleRow {
            Layout.fillWidth: true
            label: "Workspace"
            description: "Show the current two-digit workspace position before Clock."
            value: root.settingsModel.snapshot.island.showWorkspace
            writable: root.settingsModel.writable
            onValueRequested: value => root.request({
                                                        "showWorkspace": value
                                                    }, false)
        }

        SettingToggleRow {
            Layout.fillWidth: true
            label: "Weather"
            description:
            "Show compact weather when the Weather integration is configured and enabled."
            value: root.settingsModel.snapshot.island.showWeather
            writable: root.settingsModel.writable
            onValueRequested: value => root.request({
                                                        "showWeather": value
                                                    }, false)
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
            pageId: "island"
            writable: root.settingsModel.writable
            errorText: root.settingsModel.status === "write-failed"
                       ? root.settingsModel.errorMessage : ""
            reducedMotion: root.reducedMotion
            onResetPageRequested: pageId => root.settingsModel.resetPage(pageId)
            onResetAllRequested: root.settingsModel.resetAll()
        }
    }
}

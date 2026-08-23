import QtQuick
import QtQuick.Layouts
import QtQuick.Window

// Presentation-only Expanded composition. Regions disappear with their injected
// content, and geometry follows the mounted rows within the current screen.
FocusScope {
    id: dashboard

    property Component mediaContent: null
    property Component clockContent: null
    property Component quickControlsContent: null
    property Component audioContent: null
    property Component notificationsContent: null
    property Component navigationContent: null

    readonly property bool mediaReady: mediaRegion.ready
    readonly property string primaryRowMode: mediaReady ? "media-and-clock" : "clock-only"
    readonly property int loadedRegionCount: (mediaRegion.ready ? 1 : 0) + (clockRegion.ready ? 1 :
                                                                                                0) + (quickControlsRegion.ready
                                                                                                      ? 1 : 0)
                                             + (audioRegion.ready ? 1 : 0) + (
                                                 notificationsRegion.ready ? 1 : 0) + (
                                                 navigationRegion.ready ? 1 : 0)
    readonly property bool primaryRowReady: mediaRegion.ready || clockRegion.ready
    readonly property int mainRowCount: (primaryRowReady ? 1 : 0) + (quickControlsRegion.ready ? 1 :
                                                                                                 0) + (audioRegion.ready
                                                                                                       ? 1 : 0)
                                        + (notificationsRegion.ready ? 1 : 0)
    readonly property real primaryRowWidth: mediaRegion.implicitWidth + (mediaRegion.ready
                                                                         && clockRegion.ready
                                                                         ? Theme.spacing.lg : 0)
                                            + clockRegion.implicitWidth
    readonly property real primaryRowHeight: Math.max(mediaRegion.implicitHeight,
                                                      clockRegion.implicitHeight)
    readonly property real mainContentWidth: Math.max(primaryRowWidth,
                                                      quickControlsRegion.implicitWidth,
                                                      audioRegion.implicitWidth,
                                                      notificationsRegion.implicitWidth)
    readonly property real mainContentHeight: primaryRowHeight + quickControlsRegion.implicitHeight
                                              + audioRegion.implicitHeight
                                              + notificationsRegion.implicitHeight + Math.max(0,
                                                                                              mainRowCount
                                                                                              - 1) * Theme.spacing.lg
    readonly property real naturalWidth: Theme.spacing.xl * 2 + mainContentWidth + (
                                             navigationRegion.ready ? Theme.spacing.lg
                                                                      + navigationRegion.implicitWidth :
                                                                      0)
    readonly property real naturalHeight: Theme.spacing.xl * 2 + Math.max(mainContentHeight,
                                                                          navigationRegion.implicitHeight)
    readonly property real availableWidth: Screen.desktopAvailableWidth > 0 ? Math.max(1,
                                                                                       Screen.desktopAvailableWidth
                                                                                       - Theme.spacing.sm
                                                                                       * 2) : naturalWidth
    readonly property real availableHeight: Screen.desktopAvailableHeight > 0 ? Math.max(1,
                                                                                         Screen.desktopAvailableHeight
                                                                                         - Theme.spacing.sm
                                                                                         * 2) : naturalHeight

    implicitWidth: Math.min(naturalWidth, availableWidth)
    implicitHeight: Math.min(naturalHeight, availableHeight)
    clip: true

    signal closeRequested

    function focusInitialControl() {
        const first = dashboard.nextItemInFocusChain(true);
        if (first !== null && first !== dashboard) {
            first.forceActiveFocus(Qt.ShortcutFocusReason);
        }
    }

    Keys.priority: Keys.BeforeItem
    Keys.onEscapePressed: event => {
        dashboard.closeRequested();
        event.accepted = true;
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing.xl
        spacing: Theme.spacing.lg

        ColumnLayout {
            Layout.alignment: Qt.AlignTop | Qt.AlignLeft
            Layout.preferredWidth: dashboard.mainContentWidth
            spacing: Theme.spacing.lg

            Item {
                id: primaryRow
                objectName: "dashboardPrimaryRow"

                Layout.fillWidth: true
                Layout.preferredHeight: dashboard.primaryRowHeight

                DashboardRegion {
                    id: mediaRegion

                    objectName: "dashboardMediaRegion"
                    content: dashboard.mediaContent
                    active: dashboard.visible
                    width: implicitWidth
                    height: implicitHeight
                }

                DashboardRegion {
                    id: clockRegion

                    objectName: "dashboardClockRegion"
                    content: dashboard.clockContent
                    active: dashboard.visible
                    x: dashboard.mediaReady ? primaryRow.width - width : (primaryRow.width - width)
                                              / 2
                    width: implicitWidth
                    height: implicitHeight
                }
            }

            DashboardRegion {
                id: quickControlsRegion

                objectName: "dashboardQuickControlsRegion"
                content: dashboard.quickControlsContent
                active: dashboard.visible
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                Layout.alignment: Qt.AlignLeft
            }

            DashboardRegion {
                id: audioRegion

                objectName: "dashboardAudioRegion"
                content: dashboard.audioContent
                active: dashboard.visible
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                Layout.alignment: Qt.AlignLeft
            }

            DashboardRegion {
                id: notificationsRegion

                objectName: "dashboardNotificationsRegion"
                content: dashboard.notificationsContent
                active: dashboard.visible
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                Layout.alignment: Qt.AlignLeft
            }
        }

        DashboardRegion {
            id: navigationRegion

            objectName: "dashboardNavigationRegion"
            content: dashboard.navigationContent
            active: dashboard.visible
            Layout.preferredWidth: implicitWidth
            Layout.preferredHeight: Math.max(implicitHeight, dashboard.mainContentHeight)
            Layout.alignment: Qt.AlignTop | Qt.AlignRight
        }
    }
}

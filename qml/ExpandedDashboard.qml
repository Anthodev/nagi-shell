import QtQuick
import QtQuick.Controls
import QtQuick.Window

// Presentation-only Expanded composition. The three semantic stages share one
// content-driven field; utility content fills that field without owning it.
// The glance stage keeps Idle's clock-before-media reading with equal clock
// and media columns. Without media, the clock/status spine owns the centered
// main-content axis while Commands remains an independent centered stage.
FocusScope {
    id: dashboard
    objectName: "expandedDashboard"

    property Component mediaContent: null
    property Component clockContent: null
    property Component statusContent: null
    property Component quickControlsContent: null
    property Component audioContent: null
    property Component notificationsContent: null
    property Component navigationContent: null
    property var gamingPerformance: null
    property bool gamingIndicatorEnabled: true
    property bool active: true
    property bool retainMatchedPresentation: false
    property bool externalClockPresentation: false
    property bool externalMediaPresentation: false
    property real maximumViewportWidth: Number.POSITIVE_INFINITY
    property real maximumViewportHeight: Number.POSITIVE_INFINITY

    readonly property bool mediaReady: mediaRegion.ready
    readonly property bool gamingContentAvailable: active && gamingIndicatorEnabled
                                                   && gamingPerformance !== null
                                                   && gamingPerformance.active === true
    readonly property bool gamingReady: gamingContentAvailable && gamingRegion.ready
    readonly property string glanceMode: mediaReady ? "media" : "clock"
    readonly property int semanticStageCount: 3
    readonly property int loadedRegionCount: (mediaRegion.ready ? 1 : 0) + (clockRegion.ready ? 1 :
                                                                                                0) + (statusRegion.ready
                                                                                                      ? 1 : 0)
                                             + (gamingReady ? 1 : 0) + (quickControlsRegion.ready
                                                                        ? 1 : 0) + (
                                                 audioRegion.ready ? 1 : 0) + (
                                                 notificationsRegion.ready ? 1 : 0) + (
                                                 navigationRegion.ready ? 1 : 0)
    readonly property bool ready: active && (mediaContent === null || mediaRegion.ready) && (clockContent
                                                                                             === null
                                                                                             || clockRegion.ready)
                                  && (statusContent === null || statusRegion.ready) && (
                                      !gamingContentAvailable || gamingReady) && (
                                      quickControlsContent === null || quickControlsRegion.ready)
                                  && (audioContent === null || audioRegion.ready) && (
                                      notificationsContent === null || notificationsRegion.ready)
                                  && (navigationContent === null || navigationRegion.ready)
    readonly property bool glanceReady: mediaRegion.ready || clockRegion.ready
                                        || statusRegion.ready || gamingReady
    readonly property bool commandsReady: quickControlsRegion.ready
    readonly property bool instrumentsFeedReady: audioRegion.ready || notificationsRegion.ready
    readonly property real spineNaturalWidth: Math.max(clockRegion.implicitWidth,
                                                       statusRegion.implicitWidth)
    readonly property real mediaNaturalWidth: mediaRegion.implicitWidth
    readonly property real commandsNaturalWidth: quickControlsRegion.implicitWidth
    readonly property real glanceColumnWidth: mediaReady ? Math.max(spineNaturalWidth,
                                                                    mediaNaturalWidth) :
                                                           spineNaturalWidth
    readonly property real glanceColumnGap: mediaReady && spineNaturalWidth > 0
                                            && mediaNaturalWidth > 0 ? Theme.spacing.xl : 0
    readonly property real gamingBadgeGap: gamingReady && spineNaturalWidth > 0 ? Theme.spacing.md :
                                                                                  0
    readonly property real gamingBadgeSpan: gamingReady ? gamingBadgeGap
                                                          + gamingRegion.implicitWidth : 0
    readonly property real mediaGlanceWidth: mediaReady ? glanceColumnWidth * 2 + glanceColumnGap
                                                          + gamingBadgeSpan : 0
    readonly property real centeredSpineMinimumWidth: spineNaturalWidth + gamingBadgeSpan * 2
    readonly property real mainContentWidth: mediaReady ? mediaGlanceWidth : Math.max(
                                                              centeredSpineMinimumWidth,
                                                              commandsNaturalWidth)
    readonly property real navigationSpan: navigationRegion.ready ? Theme.spacing.lg
                                                                    + navigationRegion.implicitWidth :
                                                                    0
    readonly property real mainContentHeight: stageColumn.implicitHeight
    readonly property real naturalWidth: Theme.spacing.xl * 2 + mainContentWidth + navigationSpan
    readonly property real naturalHeight: Theme.spacing.xl * 2 + mainContentHeight
    readonly property real availableWidth: Number.isFinite(maximumViewportWidth) ? Math.max(1,
                                                                                            maximumViewportWidth) :
                                                                                   naturalWidth
    readonly property real availableHeight: Number.isFinite(maximumViewportHeight) ? Math.max(1,
                                                                                              maximumViewportHeight) :
                                                                                     naturalHeight
    readonly property real boundedWidth: Math.max(1, Math.min(naturalWidth, availableWidth))
    readonly property real boundedHeight: Math.max(1, Math.min(naturalHeight, availableHeight))
    readonly property real renderedMainContentWidth: mainContentWidth
    readonly property real glanceSpineX: glanceSpine.x
    readonly property real glanceSpineWidth: glanceSpine.width
    readonly property real glanceMediaX: mediaRegion.x
    readonly property real glanceMediaWidth: mediaRegion.width
    readonly property real glanceGamingX: gamingRegion.x
    readonly property real glanceGamingWidth: gamingRegion.width
    readonly property real commandsBlockX: quickControlsRegion.x
    readonly property real commandsBlockWidth: quickControlsRegion.width
    readonly property real clockStatusAxisX: stageColumn.x + glanceSpineX + glanceSpineWidth / 2
                                             - contentViewport.contentX
    readonly property bool horizontalOverflow: naturalWidth > width + 0.5
    readonly property bool verticalOverflow: naturalHeight > height + 0.5
    readonly property Item viewportItem: contentViewport
    readonly property Item clockPresentationItem: {
        if (!clockRegion.ready || clockRegion.item === null) {
            return null;
        }
        const bounds = clockRegion.item.clockBoundsItem;
        return bounds === undefined ? null : bounds;
    }
    readonly property Item mediaPresentationItem: mediaRegion.item

    implicitWidth: naturalWidth
    implicitHeight: naturalHeight
    clip: true

    signal closeRequested

    function focusInitialControl() {
        const first = dashboard.nextItemInFocusChain(true);
        if (first === null || first === dashboard) {
            return false;
        }
        first.forceActiveFocus(Qt.ShortcutFocusReason);
        revealItem(first);
        return true;
    }

    function isContentDescendant(item) {
        let candidate = item;
        while (candidate !== null && candidate !== undefined) {
            if (candidate === contentCanvas) {
                return true;
            }
            candidate = candidate.parent;
        }
        return false;
    }

    function revealItem(item) {
        if (item === null || item === undefined || !isContentDescendant(item)) {
            return false;
        }
        const topLeft = item.mapToItem(contentCanvas, 0, 0);
        const right = topLeft.x + item.width;
        const bottom = topLeft.y + item.height;
        if (topLeft.x < contentViewport.contentX) {
            contentViewport.contentX = Math.max(0, topLeft.x);
        } else if (right > contentViewport.contentX + contentViewport.width) {
            contentViewport.contentX = Math.max(0, Math.min(contentViewport.contentWidth
                                                            - contentViewport.width, right
                                                            - contentViewport.width));
        }
        if (topLeft.y < contentViewport.contentY) {
            contentViewport.contentY = Math.max(0, topLeft.y);
        } else if (bottom > contentViewport.contentY + contentViewport.height) {
            contentViewport.contentY = Math.max(0, Math.min(contentViewport.contentHeight
                                                            - contentViewport.height, bottom
                                                            - contentViewport.height));
        }
        return true;
    }

    function itemVisibleInViewport(item) {
        if (item === null || item === undefined || !isContentDescendant(item)) {
            return false;
        }
        const topLeft = item.mapToItem(contentViewport, 0, 0);
        return topLeft.x >= -1 && topLeft.y >= -1 && topLeft.x + item.width
                <= contentViewport.width + 1 && topLeft.y + item.height <= contentViewport.height
                + 1;
    }

    Keys.priority: Keys.BeforeItem
    Keys.onEscapePressed: event => {
        dashboard.closeRequested();
        event.accepted = true;
    }

    Component {
        id: gamingBadgeContent

        Item {
            objectName: "dashboardGamingPerformanceBadge"
            implicitWidth: gamingPerformanceIcon.implicitWidth
            implicitHeight: gamingPerformanceIcon.implicitHeight
            focus: false
            Accessible.role: Accessible.StaticText
            Accessible.name: qsTr("Gaming performance indicator active")
            Accessible.description: qsTr("Passive status badge. No action is available.")
            ToolTip.visible: gamingPerformanceHover.hovered
            ToolTip.delay: Theme.motion.durationSlow
            ToolTip.text: qsTr("Gaming performance active")

            IslandIcon {
                id: gamingPerformanceIcon

                objectName: "dashboardGamingPerformanceIcon"
                anchors.centerIn: parent
                meaning: "gamingPerformance"
                semanticState: "active"
                size: "md"
            }

            HoverHandler {
                id: gamingPerformanceHover
            }
        }
    }

    Flickable {
        id: contentViewport

        objectName: "dashboardContentViewport"
        anchors.fill: parent
        contentWidth: contentCanvas.width
        contentHeight: contentCanvas.height
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: dashboard.horizontalOverflow && dashboard.verticalOverflow
                            ? Flickable.HorizontalAndVerticalFlick : dashboard.horizontalOverflow
                              ? Flickable.HorizontalFlick : Flickable.VerticalFlick
        interactive: dashboard.horizontalOverflow || dashboard.verticalOverflow
        clip: true

        ScrollBar.horizontal: ScrollBar {
            policy: dashboard.horizontalOverflow ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
        }
        ScrollBar.vertical: ScrollBar {
            policy: dashboard.verticalOverflow ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
        }

        Item {
            id: contentCanvas

            objectName: "dashboardContentCanvas"
            width: dashboard.naturalWidth
            height: dashboard.naturalHeight

            Column {
                id: stageColumn

                objectName: "dashboardStageColumn"
                x: Theme.spacing.xl
                y: Theme.spacing.xl
                width: dashboard.mainContentWidth
                height: implicitHeight
                spacing: Theme.spacing.xl

                Item {
                    id: glanceStage

                    readonly property real columnWidth: dashboard.glanceColumnWidth
                    readonly property real spineWidth: dashboard.mediaReady ? columnWidth : Math.min(
                                                                                  width, dashboard.spineNaturalWidth)
                    readonly property real spineX: dashboard.mediaReady ? 0 : Math.max(0, (width
                                                                                           - spineWidth)
                                                                                       / 2)
                    readonly property real mediaX: dashboard.mediaReady ? spineX + spineWidth
                                                                          + dashboard.glanceColumnGap :
                                                                          0
                    readonly property real mediaWidth: dashboard.mediaReady ? columnWidth : 0
                    readonly property real gamingAnchorX: dashboard.mediaReady ? mediaX
                                                                                 + mediaWidth :
                                                                                 spineX + spineWidth
                    readonly property real gamingX: dashboard.gamingReady ? gamingAnchorX
                                                                            + dashboard.gamingBadgeGap :
                                                                            gamingAnchorX

                    objectName: "dashboardGlanceStage"
                    width: stageColumn.width
                    height: implicitHeight
                    implicitHeight: Math.max(mediaRegion.implicitHeight, glanceSpine.implicitHeight,
                                             gamingRegion.implicitHeight)
                    visible: dashboard.glanceReady
                    Accessible.role: Accessible.Grouping
                    Accessible.name: qsTr("Glance")

                    // Declared ahead of the spine so the established keyboard focus
                    // chain (media transport first) survives the visual clock-first order.
                    DashboardRegion {
                        id: mediaRegion

                        objectName: "dashboardMediaRegion"
                        content: dashboard.mediaContent
                        active: dashboard.active || dashboard.retainMatchedPresentation
                        presentationExcluded: dashboard.externalMediaPresentation
                        x: glanceStage.mediaX
                        y: Math.round((glanceStage.height - height) / 2)
                        width: glanceStage.mediaWidth
                        height: implicitHeight
                    }

                    Item {
                        id: glanceSpine

                        objectName: "dashboardGlanceSpine"
                        x: glanceStage.spineX
                        width: glanceStage.spineWidth
                        height: implicitHeight
                        implicitHeight: clockRegion.implicitHeight + statusRegion.implicitHeight + (
                                            clockRegion.implicitHeight > 0
                                            && statusRegion.implicitHeight > 0 ? Theme.spacing.md :
                                                                                 0)

                        DashboardRegion {
                            id: clockRegion

                            objectName: "dashboardClockRegion"
                            content: dashboard.clockContent
                            active: dashboard.active || dashboard.retainMatchedPresentation
                            presentationExcluded: dashboard.externalClockPresentation
                            width: glanceSpine.width
                            height: implicitHeight
                        }

                        DashboardRegion {
                            id: statusRegion

                            objectName: "dashboardStatusRegion"
                            content: dashboard.statusContent
                            active: dashboard.active
                            y: clockRegion.height + (clockRegion.implicitHeight > 0
                                                     && implicitHeight > 0 ? Theme.spacing.md : 0)
                            width: glanceSpine.width
                            height: implicitHeight
                        }
                    }

                    DashboardRegion {
                        id: gamingRegion

                        objectName: "dashboardGamingRegion"
                        content: dashboard.gamingContentAvailable ? gamingBadgeContent : null
                        active: dashboard.active
                        x: glanceStage.gamingX
                        y: dashboard.mediaReady ? Math.round((glanceStage.height - height) / 2) :
                                                  Math.round(((clockRegion.ready
                                                               ? clockRegion.height :
                                                                 glanceSpine.implicitHeight)
                                                              - height) / 2)
                        width: dashboard.gamingReady ? implicitWidth : 0
                        height: dashboard.gamingReady ? implicitHeight : 0
                    }
                }

                Item {
                    id: commandsStage

                    objectName: "dashboardCommandsStage"
                    width: stageColumn.width
                    height: implicitHeight
                    implicitHeight: quickControlsRegion.implicitHeight
                    visible: dashboard.commandsReady
                    Accessible.role: Accessible.Grouping
                    Accessible.name: qsTr("Commands")

                    DashboardRegion {
                        id: quickControlsRegion

                        objectName: "dashboardQuickControlsRegion"
                        content: dashboard.quickControlsContent
                        active: dashboard.active
                        x: dashboard.mediaReady ? 0 : Math.max(0, (commandsStage.width - width) / 2)
                        width: dashboard.mediaReady ? commandsStage.width : Math.min(implicitWidth,
                                                                                     commandsStage.width)
                        height: implicitHeight
                    }
                }

                Item {
                    id: instrumentsFeedStage

                    readonly property real regionGap: audioRegion.implicitHeight > 0
                                                      && notificationsRegion.implicitHeight > 0
                                                      ? Theme.spacing.lg : 0

                    objectName: "dashboardInstrumentsFeedStage"
                    width: stageColumn.width
                    height: implicitHeight
                    implicitHeight: audioRegion.implicitHeight + regionGap
                                    + notificationsRegion.implicitHeight
                    visible: dashboard.instrumentsFeedReady
                    Accessible.role: Accessible.Grouping
                    Accessible.name: qsTr("Audio and recent notifications")

                    DashboardRegion {
                        id: audioRegion

                        objectName: "dashboardAudioRegion"
                        content: dashboard.audioContent
                        active: dashboard.active
                        width: instrumentsFeedStage.width
                        height: implicitHeight
                    }

                    DashboardRegion {
                        id: notificationsRegion

                        objectName: "dashboardNotificationsRegion"
                        content: dashboard.notificationsContent
                        active: dashboard.active
                        y: audioRegion.height + instrumentsFeedStage.regionGap
                        width: instrumentsFeedStage.width
                        height: implicitHeight
                    }
                }
            }

            DashboardRegion {
                id: navigationRegion

                objectName: "dashboardNavigationRegion"
                content: dashboard.navigationContent
                active: dashboard.active
                x: stageColumn.x + stageColumn.width + Theme.spacing.lg
                y: stageColumn.y + glanceStage.y
                width: implicitWidth
                height: dashboard.instrumentsFeedReady ? stageColumn.y + instrumentsFeedStage.y
                                                         + instrumentsFeedStage.height - y :
                                                         stageColumn.height
            }
        }
    }

    Connections {
        target: dashboard.Window.window
        enabled: dashboard.active
        ignoreUnknownSignals: true

        function onActiveFocusItemChanged() {
            dashboard.revealItem(dashboard.Window.window.activeFocusItem);
        }
    }
}

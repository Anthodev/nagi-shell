import Quickshell
import Quickshell.Io
import QtQuick
import "qml"

// Idle composition harness: mounts the idle island against fake normalized
// adapters and asserts the observable composition contracts (content order,
// width-follows-content, gapless collapse, stale preservation, bounded media
// overflow, reduced-motion fallback, and the reduced-motion preference
// watcher).
//
// Dynamic scenarios settle through short timers so animation and file-watch
// state reach their steady values. The preference fixture is reset to a
// sentinel first because FileView skips writes whose content equals the
// current file and never emits saved() for them. Runs headless; the exit
// code is the only verdict.
ShellRoot {
    id: test

    property string pendingMotionStage: ""
    property int weatherRequests: 0

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function requireDisplayOnly(item) {
        require(item.focus !== true, "idle item unexpectedly requests focus");
        if ("activeFocusOnTab" in item) {
            require(item.activeFocusOnTab !== true, "idle item unexpectedly enters tab focus");
        }
        const visualChildren = item.children;
        for (let index = 0; index < visualChildren.length; index += 1) {
            requireDisplayOnly(visualChildren[index]);
        }
    }

    function horizontalCenter(item, island) {
        return item.mapToItem(island, item.width / 2, 0).x;
    }

    function requireEdgeSymmetry(island, trailingBoundary, trailingBlock, label) {
        const leadingRuleCenter = horizontalCenter(island.workspaceBoundary, island);
        const expectedWorkspaceCenter = leadingRuleCenter / 2;
        require(Math.abs(horizontalCenter(island.workspaceBlock, island) - expectedWorkspaceCenter)
                <= 1, label + " workspace center is midway between the left edge and first rule");

        const trailingRuleCenter = horizontalCenter(trailingBoundary, island);
        const expectedTrailingCenter = (trailingRuleCenter + island.implicitWidth) / 2;
        require(Math.abs(horizontalCenter(trailingBlock, island) - expectedTrailingCenter) <= 1,
                label + " trailing content center is midway between the last rule and right edge");
    }

    // Settled instances: order, width math, collapse geometry, stale
    // preservation, bounded overflow, and the reduced-motion fallback.
    function phaseOne() {
        require(typeof Theme.size.islandIdleMediaMaximumWidth === "number", "idle tokens resolve");
        require(outerSilhouette.radius === Theme.radius.outer && outerSilhouette.border.width === 0,
                "Idle outer surface uses the shared soft rectangle without an outline");
        require(islandFull.implicitHeight >= 44 && islandFull.implicitHeight <= 48,
                "font-metric idle height stays within 44–48 logical pixels");
        require(islandFull.implicitHeight === islandFull.resolvedHeight
                && islandFull.resolvedHeight >= Theme.size.islandIdleHeight
                && islandFull.derivedContentHeight === Math.max(44, Math.min(48,
                                                                             islandFull.metricsContentHeight
                                                                             + islandFull.verticalPadding
                                                                             * 2)), "idle height follows the documented metric and semantic-padding formula");
        require(islandFull.contentPadding === Theme.size.islandCompactPadding
                && islandFull.contentGap === Theme.size.islandCompactPadding
                && islandFull.boundaryWidth === Theme.size.islandCompactPadding * 2
                + Theme.size.hairlineWidth && islandFull.boundaryWidth
                === islandFull.contentGap * 2 + Theme.size.hairlineWidth
                && islandFull.boundaryHeight === Theme.size.islandSeparatorHeight
                && islandFull.workspaceIndicatorWidth === Theme.size.islandWorkspaceIndicatorWidth
                && islandFull.workspaceIndicatorHeight === Theme.size.islandWorkspaceIndicatorHeight
                && islandFull.weatherGap === Theme.spacing.sm
                && islandFull.weatherLabelGap === Theme.spacing.xs,
                "Idle groups use shared workspace and separator geometry tokens");
        require(islandFull.workspaceLabelItem.font.pixelSize === Theme.type.body
                && islandFull.workspaceLabelItem.font.weight === Theme.type.weightMedium
                && islandFull.clockBlock.font.pixelSize === Theme.type.body
                && islandFull.clockBlock.font.weight === Theme.type.weightMedium
                && islandFull.temperatureBlock.font.pixelSize === Theme.type.body
                && islandFull.temperatureBlock.font.weight === Theme.type.weightMedium,
                "primary Idle values use the body/medium typography hierarchy");
        require(islandFull.weatherConditionBlock.font.pixelSize === Theme.type.caption
                && islandFull.weatherConditionBlock.font.weight === Theme.type.weightRegular,
                "secondary weather context uses caption/regular typography");
        require(islandFull.weatherIcon.Accessible.ignored,
                "the restrained weather glyph stays decorative");
        requireDisplayOnly(islandFull);
        require(islandGaming.gamingPerformanceBlock.visible
                && islandGaming.gamingBadgeIcon.meaning === "gamingPerformance"
                && islandGaming.gamingPerformanceBlock.Accessible.name
                === "Gaming performance indicator active"
                && islandGaming.gamingPerformanceTooltip === "Gaming performance active"
                && !islandGaming.gamingPerformanceBlock.focus
                && !("clicked" in islandGaming.gamingPerformanceBlock),
                "active gaming state renders one static accessible badge without an action");
        require(!islandNoGaming.gamingPerformanceBlock.visible
                && !islandNoGaming.gamingPerformanceBoundary.visible
                && islandGaming.implicitWidth - islandNoGaming.implicitWidth
                === islandGaming.gamingPerformanceBlock.width + islandGaming.boundaryWidth,
                "inactive gaming state removes its badge and one separator exactly");
        require(islandFull.workspaceBlock.visible, "workspace renders when available");
        require(islandFull.workspaceText === "02" && islandFull.workspaceLabelItem.text === "02"
                && islandFull.workspaceLabelItem.text !== fullDesktops.currentName,
                "workspace renders a two-digit position indicator, never the desktop name");
        require(islandFull.workspaceBlock.width === islandFull.workspaceIndicatorWidth
                && islandFull.workspaceBlock.height === islandFull.workspaceIndicatorHeight,
                "workspace position uses the compact rectangular indicator geometry");
        require(islandFull.clockBlock.text === "13:45", "clock renders normalized time text");
        require(!islandFull.clockDateBlock.visible && islandFull.clockGroupBlock.width
                === islandFull.clockBlock.width,
                "disabled Idle date leaves no separator or residual gap");
        require(islandWithDate.clockDateBlock.visible && islandWithDate.clockDateBlock.text
                === "Monday, 24 August" && islandWithDate.clockDateGap === Theme.spacing.md
                && islandWithDate.clockDateBlock.font.pixelSize
                === islandWithDate.clockBlock.font.pixelSize
                && islandWithDate.clockDateBlock.font.weight
                === islandWithDate.clockBlock.font.weight && islandWithDate.clockDateBlock.color
                === islandWithDate.clockBlock.color && islandWithDate.clockGroupBlock.width
                === islandWithDate.clockBlock.width + islandWithDate.clockDateGap
                + islandWithDate.clockDateBlock.width,
                "enabled Idle date matches the time typography and keeps its semantic gap");
        require(islandFull.temperatureText === "24°", "temperature renders rounded Celsius");
        require(islandFull.weatherCaptionText === "Clear · Day",
                "weather renders normalized condition and day phase context");
        require(islandFull.weatherBlock.Accessible.role === Accessible.Button,
                "compact Weather exposes one accessible detail action");
        islandFull.weatherBlock.clicked();
        require(weatherRequests === 1,
                "activating compact Weather requests its detailed subview once");
        require(islandFull.mediaSummary === "Artist — Track", "media renders the selected summary");
        require(islandFull.workspaceBlock.x < islandFull.workspaceBoundary.x
                && islandFull.workspaceBoundary.x < islandFull.clockGroupBlock.x
                && islandFull.clockGroupBlock.x < islandFull.clockBoundary.x
                && islandFull.clockBoundary.x < islandFull.weatherBlock.x
                && islandFull.weatherBlock.x < islandFull.weatherBoundary.x
                && islandFull.weatherBoundary.x < islandFull.mediaBlock.x,
                "idle content keeps workspace, time, weather, media order with visible boundaries");
        require(islandFull.workspaceBoundary.visible && islandFull.clockBoundary.visible
                && islandFull.weatherBoundary.visible,
                "each visible group transition renders one restrained separator");
        const firstEdge = islandFull.workspaceBlock.mapToItem(islandFull, 0, 0).x;
        const lastEdge = islandFull.mediaBlock.mapToItem(islandFull, islandFull.mediaBlock.width,
                                                         0).x;
        require(islandFull.contentPadding === Theme.spacing.xl && firstEdge
                === islandFull.contentPadding && islandFull.implicitWidth - lastEdge
                === islandFull.contentPadding, "Idle content uses balanced 24 px edge padding");
        requireEdgeSymmetry(islandFull, islandFull.weatherBoundary, islandFull.mediaBlock,
                            "full Idle");
        require(islandFull.implicitWidth === islandFull.contentPadding * 2
                + islandFull.workspaceBlock.width + islandFull.clockGroupBlock.width
                + islandFull.weatherBlock.width + islandFull.mediaBlock.width
                + islandFull.boundaryWidth * 3,
                "idle width follows groups, boundaries, and symmetric edge padding exactly");
        require(islandFull.implicitHeight === Theme.size.islandIdleHeight,
                "current font metrics preserve the published Idle height token");
        require(!islandFull.mediaBlock.overflowing
                && islandFull.mediaBlock.labelItem.elide === Text.ElideRight,
                "fitting media stays settled on the static text path");

        require(!islandNoWeather.weatherBlock.visible, "unavailable weather collapses");
        require(islandFull.implicitWidth - islandNoWeather.implicitWidth
                === islandFull.weatherBlock.width + islandFull.boundaryWidth,
                "collapsed weather frees its block and one boundary");
        require(islandNoWeather.clockBoundary.visible && !islandNoWeather.weatherBoundary.visible
                && islandNoWeather.mediaBlock.x === islandNoWeather.clockBoundary.x
                + islandNoWeather.clockBoundary.width,
                "media follows the clock with one boundary and no orphan weather separator");
        require(islandNoWeather.implicitWidth === islandNoWeather.contentPadding * 2
                + islandNoWeather.workspaceBlock.width + islandNoWeather.clockGroupBlock.width
                + islandNoWeather.mediaBlock.width + islandNoWeather.boundaryWidth * 2,
                "weather-free geometry contains exactly three groups and two boundaries");
        requireEdgeSymmetry(islandNoWeather, islandNoWeather.clockBoundary,
                            islandNoWeather.mediaBlock, "weather-free Idle");

        require(!islandNoMedia.mediaBlock.visible, "unavailable media collapses");
        require(islandFull.implicitWidth - islandNoMedia.implicitWidth
                === islandFull.mediaBlock.width + islandFull.boundaryWidth,
                "collapsed media frees its block and trailing boundary");
        require(!islandNoMedia.weatherBoundary.visible,
                "missing media leaves no orphan separator after weather");
        require(islandNoMedia.implicitWidth === islandNoMedia.contentPadding * 2
                + islandNoMedia.workspaceBlock.width + islandNoMedia.clockGroupBlock.width
                + islandNoMedia.weatherBlock.width + islandNoMedia.boundaryWidth * 2,
                "media-free geometry contains exactly three groups and two boundaries");
        requireEdgeSymmetry(islandNoMedia, islandNoMedia.clockBoundary, islandNoMedia.weatherBlock,
                            "media-free Idle");

        require(!islandNoWeatherNoMedia.weatherBlock.visible &&
                !islandNoWeatherNoMedia.mediaBlock.visible,
                "weather and media collapse together when both are unavailable");
        require(islandNoWeatherNoMedia.workspaceBoundary.visible &&
                !islandNoWeatherNoMedia.clockBoundary.visible &&
                !islandNoWeatherNoMedia.weatherBoundary.visible,
                "only the required workspace/time boundary survives optional collapse");
        require(islandNoWeatherNoMedia.implicitWidth === islandNoWeatherNoMedia.contentPadding * 2
                + islandNoWeatherNoMedia.workspaceBlock.width
                + islandNoWeatherNoMedia.clockGroupBlock.width
                + islandNoWeatherNoMedia.boundaryWidth,
                "collapsing optional groups leaves required groups and one boundary");
        require(islandNoWeatherNoMedia.clockGroupBlock.x
                === islandNoWeatherNoMedia.workspaceBoundary.x
                + islandNoWeatherNoMedia.workspaceBoundary.width,
                "required groups preserve order without optional-content residue");
        requireEdgeSymmetry(islandNoWeatherNoMedia, islandNoWeatherNoMedia.workspaceBoundary,
                            islandNoWeatherNoMedia.clockGroupBlock, "required-only Idle");
        require(!islandHiddenOptional.workspaceBlock.visible
                && !islandHiddenOptional.weatherBlock.visible
                && !islandHiddenOptional.mediaBlock.visible
                && islandHiddenOptional.clockBlock.visible
                && islandHiddenOptional.implicitWidth === islandHiddenOptional.contentPadding * 2
                + islandHiddenOptional.clockGroupBlock.width,
                "visibility settings collapse optional groups while Clock remains mandatory");
        require(islandFull.implicitHeight === islandNoWeather.implicitHeight
                && islandFull.implicitHeight === islandNoMedia.implicitHeight
                && islandFull.implicitHeight === islandNoWeatherNoMedia.implicitHeight,
                "Idle height is stable across optional-content combinations");

        // Stale weather keeps the last valid content without churn.
        pendingStaleWidth = islandFull.implicitWidth;
        islandFullWeather.stale = true;
        require(islandFull.weatherBlock.visible, "stale weather stays visible");
        require(islandFull.temperatureText === "24°", "stale weather keeps the temperature");
        staleTimer.start();
    }

    property real pendingStaleWidth: 0
    property real pendingWithMedia: 0
    property real pendingMediaWidth: 0

    function staleStage() {
        require(islandFull.implicitWidth === pendingStaleWidth,
                "stale weather causes no layout churn");

        // Media lifecycle: stopped media clears text and space, recovery restores.
        require(islandMediaLifecycle.mediaBlock.visible, "playing media renders");
        pendingWithMedia = islandMediaLifecycle.implicitWidth;
        pendingMediaWidth = islandMediaLifecycle.mediaBlock.width;
        lifecycleMedia.available = false;
        collapseTimer.start();
    }

    function collapsedStage() {
        require(!islandMediaLifecycle.mediaBlock.visible, "stopped media collapses");
        require(islandMediaLifecycle.mediaSummary === "", "stopped media clears its summary");
        require(islandMediaLifecycle.mediaBlock.labelItem.x === 0,
                "cleared media retains the static text position");
        require(islandMediaLifecycle.implicitHeight === Theme.size.islandIdleHeight,
                "content changes do not alter the font-derived Idle height");
        require(pendingWithMedia - islandMediaLifecycle.implicitWidth === pendingMediaWidth
                + islandMediaLifecycle.boundaryWidth,
                "stopped media frees its content and boundary");
        lifecycleMedia.available = true;
        recoveryTimer.start();
    }

    function recoveredStage() {
        require(islandMediaLifecycle.mediaBlock.visible && islandMediaLifecycle.implicitWidth
                === pendingWithMedia, "recovered media restores its space");

        // Bounded overflow: the island caps width and keeps Idle event-driven.
        require(islandOverflow.mediaBlock.overflowing, "long media reports overflow");
        require(islandOverflow.implicitWidth <= islandOverflow.contentPadding * 2
                + islandOverflow.workspaceBlock.width + islandOverflow.clockGroupBlock.width
                + islandOverflow.weatherBlock.width + Theme.size.islandIdleMediaMaximumWidth
                + islandOverflow.boundaryWidth * 3,
                "overflowing media stays inside the island width cap");
        require(islandOverflow.mediaBlock.labelItem.elide === Text.ElideRight
                && islandOverflow.mediaBlock.labelItem.x === 0,
                "overflowing media uses a settled static ellipsis");

        // Reduced motion preserves the same static presentation.
        require(islandStatic.mediaBlock.overflowing, "static scenario overflows too");
        require(islandStatic.mediaBlock.labelItem.elide === Text.ElideRight
                && islandStatic.mediaBlock.labelItem.x === 0,
                "reduced motion preserves the static ellipsis");

        console.warn("idle composition stage one passed");
        phaseTwoTimer.start();
    }

    function phaseTwo() {
        require(islandOverflow.mediaBlock.labelItem.x === 0
                && islandOverflow.mediaBlock.labelItem.elide === Text.ElideRight,
                "visible overflowing media creates no recurring motion");

        // The watched reduced-motion preference still drives surface motion.
        pendingMotionStage = "reduced";
        motionWriter.setText("[KDE]\nAnimationDurationFactor=0\n");
    }

    function motionReducedStage() {
        require(motion.minimalMotion, "zero animation factor enables minimal motion");
        require(islandWatched.reducedMotion, "the watched preference reaches the island");
        require(islandWatched.mediaBlock.labelItem.elide === Text.ElideRight
                && islandWatched.mediaBlock.labelItem.x === 0,
                "watched preference preserves settled Idle media");

        pendingMotionStage = "restored";
        motionWriter.setText("[KDE]\nAnimationDurationFactor=1\n");
    }

    function motionRestoredStage() {
        require(!motion.minimalMotion, "normal animation factor re-enables motion");
        require(islandWatched.mediaBlock.labelItem.elide === Text.ElideRight
                && islandWatched.mediaBlock.labelItem.x === 0,
                "normal motion settings do not create an Idle animation loop");
        console.warn("idle composition tests passed");
        Qt.exit(0);
    }

    Component.onCompleted: {
        // Reset the watched fixture so every staged write changes content;
        // the empty pending stage makes onSaved ignore this priming write.
        pendingMotionStage = "";
        motionWriter.setText("__reset__\n");
        Qt.callLater(test.phaseOne);
    }

    Timer {
        id: staleTimer

        interval: 40
        repeat: false
        onTriggered: test.staleStage()
    }

    Timer {
        id: collapseTimer

        interval: 40
        repeat: false
        onTriggered: test.collapsedStage()
    }

    Timer {
        id: recoveryTimer

        interval: 40
        repeat: false
        onTriggered: test.recoveredStage()
    }

    Timer {
        id: phaseTwoTimer

        interval: 40
        repeat: false
        onTriggered: test.phaseTwo()
    }

    Timer {
        id: motionTimer

        interval: 140
        repeat: false
        onTriggered: test.pendingMotionStage === "reduced" ? test.motionReducedStage() :
                                                             test.motionRestoredStage()
    }

    component FakeClock: QtObject {
        property string text: "13:45"
        property string dateText: "Monday, 24 August"
        property bool showIdleDate: false
    }

    component FakeDesktops: QtObject {
        property bool available: true
        property string currentName: "Desktop 2"
        property int currentPosition: 1
    }

    component FakeWeather: QtObject {
        property bool available: true
        property bool stale: false
        property real temperatureC: 24
        property string condition: "clear"
        property string dayPhase: "day"
    }

    component FakeMedia: QtObject {
        property bool available: true
        property string artist: "Artist"
        property string title: "Track"
    }

    component FakeGamingPerformance: QtObject {
        property bool active: true
    }

    KdeAppearanceAdapter {
        id: motion

        configPath: Quickshell.cacheDir + "/idle-motion-kdeglobals"
    }

    FileView {
        id: motionWriter

        path: motion.configPath
        atomicWrites: true
        printErrors: false
        onSaved: {
            if (test.pendingMotionStage === "") {
                return;
            }
            motionTimer.restart();
        }
    }

    FakeDesktops {
        id: fullDesktops
    }

    FakeWeather {
        id: islandFullWeather
    }

    FakeMedia {
        id: lifecycleMedia
    }

    FakeMedia {
        id: overflowMedia

        artist: "A Very Long Artist Name That Keeps Going And Going"
        title: "An Extremely Long Track Title That Certainly Will Not Fit The Compact Island Pill"
    }

    IdleIsland {
        id: islandFull

        virtualDesktops: fullDesktops
        clock: FakeClock {}
        weather: islandFullWeather
        media: FakeMedia {}
        onWeatherRequested: test.weatherRequests += 1
    }

    IdleIsland {
        id: islandGaming

        virtualDesktops: fullDesktops
        gamingPerformance: FakeGamingPerformance {}
        clock: FakeClock {}
    }

    IdleIsland {
        id: islandNoGaming

        virtualDesktops: fullDesktops
        gamingPerformance: FakeGamingPerformance {
            active: false
        }
        clock: FakeClock {}
    }

    IdleIsland {
        id: islandNoWeather

        virtualDesktops: fullDesktops
        clock: FakeClock {}
        weather: FakeWeather {
            available: false
        }
        media: FakeMedia {}
    }

    IdleIsland {
        id: islandNoMedia

        virtualDesktops: fullDesktops
        clock: FakeClock {}
        weather: FakeWeather {}
        media: FakeMedia {
            available: false
        }
    }

    IdleIsland {
        id: islandNoWeatherNoMedia

        virtualDesktops: fullDesktops
        clock: FakeClock {}
        weather: FakeWeather {
            available: false
        }
        media: FakeMedia {
            available: false
        }
    }

    IdleIsland {
        id: islandHiddenOptional

        virtualDesktops: fullDesktops
        clock: FakeClock {}
        weather: FakeWeather {}
        media: FakeMedia {}
        showWorkspace: false
        showWeather: false
        showMedia: false
    }
    IdleIsland {
        id: islandWithDate

        virtualDesktops: fullDesktops
        clock: FakeClock {
            showIdleDate: true
        }
        weather: FakeWeather {
            available: false
        }
        media: FakeMedia {
            available: false
        }
    }

    IdleIsland {
        id: islandMediaLifecycle

        virtualDesktops: fullDesktops
        clock: FakeClock {}
        weather: FakeWeather {}
        media: lifecycleMedia
    }

    IdleIsland {
        id: islandOverflow

        virtualDesktops: fullDesktops
        clock: FakeClock {}
        weather: FakeWeather {}
        media: overflowMedia
    }

    IdleIsland {
        id: islandStatic

        virtualDesktops: fullDesktops
        clock: FakeClock {}
        weather: FakeWeather {}
        media: overflowMedia
        reducedMotion: true
    }

    IslandPanel {
        id: outerSilhouette

        radius: Theme.radius.outer
        visible: false
    }

    IdleIsland {
        id: islandWatched

        virtualDesktops: fullDesktops
        clock: FakeClock {}
        weather: FakeWeather {}
        media: overflowMedia
        reducedMotion: motion.minimalMotion
    }
}

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

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    // Settled instances: order, width math, collapse geometry, stale
    // preservation, bounded overflow, and the reduced-motion fallback.
    function phaseOne() {
        require(typeof Theme.size.islandIdleMediaMaximumWidth === "number", "idle tokens resolve");

        require(islandFull.workspaceBlock.visible, "workspace renders when available");
        require(islandFull.workspaceText === "Work", "workspace renders the current desktop name");
        require(islandFull.temperatureText === "24°", "temperature renders rounded Celsius");
        require(islandFull.mediaSummary === "Artist — Track", "media renders the selected summary");
        require(islandFull.workspaceBlock.x < islandFull.clockBlock.x
                && islandFull.clockBlock.x < islandFull.weatherBlock.x
                && islandFull.weatherBlock.x < islandFull.mediaBlock.x,
                "idle content keeps workspace, time, weather, media order");
        require(islandFull.implicitWidth === islandFull.contentPadding * 2
                + islandFull.workspaceBlock.width + islandFull.clockBlock.width
                + islandFull.weatherBlock.width + islandFull.mediaBlock.width
                + islandFull.contentGap * 3,
                "idle width follows the visible content exactly");
        require(islandFull.implicitHeight === Theme.size.islandIdleHeight,
                "idle height stays on the compact pill token");
        require(!islandFull.mediaBlock.overflowing, "fitting media stays static");

        require(!islandNoWeather.weatherBlock.visible, "unavailable weather collapses");
        require(islandFull.implicitWidth - islandNoWeather.implicitWidth
                === islandFull.weatherBlock.width + islandFull.contentGap,
                "collapsed weather frees its block and one gap");
        require(islandNoWeather.mediaBlock.x === islandNoWeather.clockBlock.x
                + islandNoWeather.clockBlock.width + islandNoWeather.contentGap,
                "media closes up behind the clock with no reserved gap");

        require(!islandNoMedia.mediaBlock.visible, "unavailable media collapses");
        require(islandFull.implicitWidth - islandNoMedia.implicitWidth
                === islandFull.mediaBlock.width + islandFull.contentGap,
                "collapsed media frees its block and one gap");

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
        require(!islandMediaLifecycle.mediaBlock.marqueeRunning,
                "cleared media performs no marquee work");
        require(pendingWithMedia - islandMediaLifecycle.implicitWidth === pendingMediaWidth
                + islandMediaLifecycle.contentGap,
                "stopped media frees its space");
        lifecycleMedia.available = true;
        recoveryTimer.start();
    }

    function recoveredStage() {
        require(islandMediaLifecycle.mediaBlock.visible
                && islandMediaLifecycle.implicitWidth === pendingWithMedia,
                "recovered media restores its space");

        // Bounded overflow: the island width caps and the marquee arms.
        require(islandOverflow.mediaBlock.overflowing, "long media reports overflow");
        require(islandOverflow.implicitWidth <= islandOverflow.contentPadding * 2
                + islandOverflow.workspaceBlock.width + islandOverflow.clockBlock.width
                + islandOverflow.weatherBlock.width
                + Theme.size.islandIdleMediaMaximumWidth + islandOverflow.contentGap * 3,
                "overflowing media stays inside the island width cap");
        require(!islandOverflow.reducedMotion, "motion is allowed before the factor says otherwise");
        require(islandOverflow.mediaBlock.labelItem.elide === Text.ElideNone,
                "moving media does not elide");

        // Reduced-motion media renders a static ellipsis with no marquee.
        require(islandStatic.mediaBlock.overflowing, "static scenario overflows too");
        require(!islandStatic.mediaBlock.marqueeRunning, "reduced motion keeps the marquee stopped");
        require(islandStatic.mediaBlock.labelItem.elide === Text.ElideRight,
                "reduced motion renders a static ellipsis");

        console.warn("idle composition stage one passed");
        phaseTwoTimer.start();
    }

    function phaseTwo() {
        // The armed marquee runs only while visible, overflowing, and allowed.
        require(islandOverflow.mediaBlock.marqueeRunning,
                "overflowing visible media marquees after the delay");

        islandOverflow.reducedMotion = true;
        require(!islandOverflow.mediaBlock.marqueeRunning, "reduced motion stops a running marquee");
        require(islandOverflow.mediaBlock.labelItem.x === 0, "stopped marquee resets its offset");
        islandOverflow.reducedMotion = false;

        islandOverflow.visible = false;
        require(!islandOverflow.mediaBlock.marqueeRunning, "hidden media performs no marquee work");
        islandOverflow.visible = true;

        // The watched reduced-motion preference drives the same fallback.
        pendingMotionStage = "reduced";
        motionWriter.setText("[KDE]\nAnimationDurationFactor=0\n");
    }

    function motionReducedStage() {
        require(motion.active, "zero animation factor enables reduced motion");
        require(islandWatched.reducedMotion, "the watched preference reaches the island");
        require(islandWatched.mediaBlock.labelItem.elide === Text.ElideRight,
                "watched preference renders the static ellipsis");
        require(!islandWatched.mediaBlock.marqueeRunning, "watched preference stops the marquee");

        pendingMotionStage = "restored";
        motionWriter.setText("[KDE]\nAnimationDurationFactor=1\n");
    }

    function motionRestoredStage() {
        require(!motion.active, "normal animation factor re-enables motion");
        require(islandWatched.mediaBlock.marqueeRunning,
                "marquee resumes after the preference returns");
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

        interval: 50
        repeat: false
        onTriggered: test.pendingMotionStage === "reduced" ? test.motionReducedStage() : test.motionRestoredStage()
    }

    component FakeClock: QtObject {
        property string text: "13:45"
    }

    component FakeDesktops: QtObject {
        property bool available: true
        property string currentName: "Work"
        property int currentPosition: 0
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

    ReducedMotion {
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

    IdleIsland {
        id: islandWatched

        virtualDesktops: fullDesktops
        clock: FakeClock {}
        weather: FakeWeather {}
        media: overflowMedia
        reducedMotion: motion.active
    }
}

import Quickshell
import QtQuick
import QtQuick.Controls
import QtTest
import "qml"

ShellRoot {
    id: test

    property int stage: 0
    property bool tallContent: false
    property int escapeCount: 0
    property int backCount: 0

    function fail(message) {
        console.error("FAIL: " + message);
        Qt.exit(1);
        throw new Error(message);
    }

    function require(condition, message) {
        if (!condition) {
            fail(message);
        }
    }

    function findObject(root, objectName) {
        if (root === null || root === undefined) {
            return null;
        }
        if (root.objectName === objectName) {
            return root;
        }
        const children = root.children ?? [];
        for (let index = 0; index < children.length; ++index) {
            const match = findObject(children[index], objectName);
            if (match !== null) {
                return match;
            }
        }
        return null;
    }

    function runChecks() {
        if (stage === 0) {
            if (frame.animationsRunning) {
                retry.restart();
                return;
            }

            const backIcon = frame.backControl.contentItem.children[0];
            require(backIcon.resolvedKind === "nagi" && backIcon.resolvedSource.endsWith(
                        "/assets/icons/nagi/navigation-back.svg"),
                    "Back uses the Nagi navigation-back semantic icon");
            require(frame.motionDuration === Theme.motion.durationNormal && frame.motionDuration
                    === 120, "internal subview motion uses the short 120 ms duration");
            require(frame.titleControl.text === "Applications" && frame.titleControl.visible,
                    "the single-line semantic title renders");
            require(frame.titleControl.maximumLineCount === 1 && frame.titleControl.font.pixelSize
                    === Theme.type.title, "the title uses Theme.type.title semantics");
            require(frame.backControl.Accessible.name === "Back" && frame.backControl.ToolTip.text
                    === "Back" && backIcon.Accessible.name === "Back",
                    "Back exposes stable control, tooltip, and icon accessibility names");

            require(!frame.scrolling && !frame.contentOverflow,
                    "sparse content does not enable scrolling");
            require(frame.boundedContentHeight === sparseContent.height && sparseContent.height
                    === 40, "sparse content remains content-sized rather than stretching");

            frame.initialFocusItem = searchField;
            require(frame.focusInitialControl() && searchField.activeFocus,
                    "the initial-focus override receives entry focus");

            const escapesBefore = escapeCount;
            keyDriver.pressEscape();
            require(escapeCount === escapesBefore + 1,
                    "Escape emits exactly once for one key press");
            keyDriver.pressEscape();
            require(escapeCount === escapesBefore + 2,
                    "each Escape press emits exactly one signal");

            frame.initialFocusItem = null;
            require(frame.focusInitialControl() && frame.backControl.activeFocus,
                    "Back is the default initial focus target");
            require(frame.backControl.ToolTip.visible === (frame.backControl.hovered
                                                           || frame.backControl.visualFocus),
                    "Back tooltip visibility follows hover or visual focus");
            const backFocusRing = findObject(frame.backControl, "islandFocusRing");
            require(backFocusRing !== null && backFocusRing.controlRadius
                    === frame.backControl.background.radius && backFocusRing.radius
                    === frame.backControl.background.radius + Theme.size.focusRingGap
                    && frame.backControl.background.radius === Theme.radius.md,
                    "Back focus ring follows its medium owner curve");
            keyDriver.pressTab();
            require(searchField.activeFocus, "default tab order proceeds from Back to content");

            frame.backControl.clicked();
            require(backCount === 1, "Back activation emits backRequested once");

            tallContent = true;
            stage = 1;
            Qt.callLater(runChecks);
            return;
        }

        if (stage === 1) {
            require(frame.contentImplicitHeight === sparseContent.height,
                    "content measurement follows content-height changes");
            require(frame.boundedContentHeight === frame.maximumContentHeight && frame.scrolling
                    && frame.contentOverflow,
                    "overflowing content is bounded and enables vertical scrolling");

            require(frame.entryOffset === Theme.spacing.xl,
                    "entry uses the shared directional offset");

            frame.width = 220;
            rightControl.forceActiveFocus(Qt.TabFocusReason);
            stage = 2;
            Qt.callLater(runChecks);
            return;
        }

        if (stage === 2) {
            const viewport = findObject(frame, "subviewContentViewport");
            require(frame.horizontalOverflow && frame.scrolling && viewport !== null && frame.clip
                    && viewport.clip, "wide content is bounded and clipped inside a narrow frame");
            require(viewport.width === frame.width - Theme.spacing.lg * 2 && viewport.contentWidth
                    === sparseContent.implicitWidth,
                    "the horizontal viewport is capped while natural content width is preserved");
            require(viewport.contentX > 0 && rightControl.x + rightControl.width
                    <= viewport.contentX + viewport.width,
                    "keyboard focus reveals the offscreen right control");
            require(viewport.contentX <= viewport.contentWidth - viewport.width,
                    "horizontal focus reveal remains within Flickable bounds");

            frame.reducedMotion = true;
            require(frame.motionDuration === 0,
                    "reduced motion makes internal transitions synchronous");
            frame.active = false;
            require(!frame.animationsRunning,
                    "inactive reduced-motion frames have no recurring animation work");

            console.log("subview frame tests passed");
            Qt.exit(0);
        }
    }

    Window {
        id: window

        visible: true
        width: 480
        height: 320
        color: Theme.color.surface

        SubviewFrame {
            id: frame

            width: 420
            title: "Applications"
            active: true
            maximumContentHeight: 100
            onBackRequested: test.backCount += 1
            onEscapePressed: test.escapeCount += 1

            Item {
                id: sparseContent

                implicitWidth: 360
                implicitHeight: test.tallContent ? 240 : 40
                width: implicitWidth
                height: implicitHeight

                TextField {
                    id: searchField

                    width: 180
                    height: 40
                    placeholderText: "Search applications"
                    Accessible.name: "Search applications"
                }

                Button {
                    id: rightControl

                    x: 280
                    width: 80
                    height: 40
                    text: "Right"
                }
            }
        }
    }

    TestCase {
        id: keyDriver

        name: "Subview frame keyboard driver"
        when: false

        function pressEscape() {
            keyClick(Qt.Key_Escape);
        }

        function pressTab() {
            keyClick(Qt.Key_Tab);
        }
    }

    Timer {
        id: retry

        interval: 10
        onTriggered: test.runChecks()
    }

    Timer {
        interval: 10000
        running: true
        onTriggered: test.fail("subview frame test timed out")
    }

    Component.onCompleted: Qt.callLater(runChecks)
}

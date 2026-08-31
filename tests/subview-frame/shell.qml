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
        const viewport = findObject(frame, "subviewContentViewport");
        require(viewport !== null, "the shared bounded viewport is mounted");

        if (stage === 0) {
            const backIcon = frame.backControl.contentItem.children[0];
            require(backIcon.resolvedKind === "nagi" && backIcon.resolvedSource.endsWith(
                        "/assets/icons/nagi/navigation-back.svg"),
                    "Back uses the Nagi navigation-back semantic icon");
            require(frame.titleControl.text === "Applications" && frame.titleControl.visible,
                    "the single-line semantic title renders");
            require(frame.titleControl.typographyScope === "expanded"
                    && frame.titleControl.font.family === Theme.type.familyFor("expanded")
                    && frame.titleControl.maximumLineCount === 1
                    && frame.titleControl.font.pixelSize === Theme.type.sizeFor("expanded", "title"),
                    "the title uses the expanded semantic typography scope");
            require(frame.backControl.Accessible.name === "Back" && frame.backControl.ToolTip.text
                    === "Back" && backIcon.Accessible.name === "Back",
                    "Back exposes stable control, tooltip, and icon accessibility names");
            require(frame.resolvedViewportWidth === 220 && frame.resolvedViewportHeight === 90
                    && frame.actualViewportWidth === 220 && frame.actualViewportHeight === 90,
                    "preferred viewport intent resolves independently on both axes");
            require(frame.implicitWidth === Theme.size.islandSubviewMinimumWidth
                    && frame.implicitHeight === 166,
                    "the resolved viewport publishes one stable outer envelope");
            require(!frame.scrolling && !frame.horizontalOverflow && !frame.verticalOverflow
                    && !viewport.interactive,
                    "sparse natural content keeps both scrollbar axes disabled");
            require(viewport.contentWidth === 220 && viewport.contentHeight === 90,
                    "sparse content is hosted inside the resolved viewport envelope");

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

            frame.width = 200;
            frame.height = 130;
            stage = 1;
            Qt.callLater(test.runChecks);
            return;
        }

        if (stage === 1) {
            require(frame.resolvedViewportWidth === 220 && frame.resolvedViewportHeight === 90
                    && frame.actualViewportWidth === 168 && frame.actualViewportHeight === 54,
                    "assigned morph geometry clips the actual viewport without changing intent");
            require(!frame.horizontalOverflow && !frame.verticalOverflow && !viewport.interactive,
                    "assigned outer shrink cannot flash natural-content scrollbars");
            require(viewport.clip && !viewport.interactive,
                    "temporary outer clipping remains inert when natural content fits intent");

            tallContent = true;
            frame.width = frame.implicitWidth;
            frame.height = frame.implicitHeight;
            bottomRightControl.forceActiveFocus(Qt.TabFocusReason);
            stage = 2;
            Qt.callLater(test.runChecks);
            return;
        }

        if (stage === 2) {
            require(frame.contentImplicitWidth === 360 && frame.contentImplicitHeight === 240
                    && frame.resolvedViewportWidth === 220 && frame.resolvedViewportHeight === 90
                    && frame.actualViewportWidth === 220 && frame.actualViewportHeight === 90,
                    "natural overflow leaves the preferred and actual envelopes stable");
            require(frame.horizontalOverflow && frame.verticalOverflow && frame.scrolling
                    && viewport.clip && viewport.interactive,
                    "natural overflow deterministically enables both bounded scrollbar axes");
            require(viewport.contentWidth === 360 && viewport.contentHeight === 240
                    && viewport.contentX > 0 && viewport.contentY > 0,
                    "keyboard focus reveals an offscreen control on both axes");
            require(bottomRightControl.x + bottomRightControl.width
                    <= viewport.contentX + viewport.width
                    && bottomRightControl.y + bottomRightControl.height
                    <= viewport.contentY + viewport.height
                    && viewport.contentX <= viewport.contentWidth - viewport.width
                    && viewport.contentY <= viewport.contentHeight - viewport.height,
                    "focus reveal remains inside both Flickable bounds");

            frame.active = false;
            require(!frame.visible,
                    "inactive frames synchronously leave presentation without hidden motion work");

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

            width: implicitWidth
            height: implicitHeight
            title: "Applications"
            active: true
            preferredViewportWidth: 240
            preferredViewportHeight: 100
            maximumViewportWidth: 220
            maximumViewportHeight: 90
            onBackRequested: test.backCount += 1
            onEscapePressed: test.escapeCount += 1

            Item {
                id: sparseContent

                implicitWidth: test.tallContent ? 360 : 180
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

                Button {
                    id: bottomRightControl

                    x: 280
                    y: 200
                    width: 80
                    height: 40
                    text: "Bottom right"
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

        running: true
        repeat: false
        onTriggered: test.runChecks()
    }

    Timer {
        interval: 10000
        running: true
        onTriggered: test.fail("subview frame test timed out")
    }

}

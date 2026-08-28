import QtQuick
import QtQuick.Controls

FocusScope {
    id: frame

    default property alias content: contentHost.children
    property string title: ""
    property bool active: false
    property Item initialFocusItem: null
    property real maximumContentWidth: width > 0 ? Math.max(0, width - Theme.spacing.lg * 2) :
                                                   contentImplicitWidth
    property real maximumContentHeight: parent !== null && parent.height > 0 ? Math.max(0, parent.height
                                                                                        - headerHeight
                                                                                        - Theme.spacing.lg
                                                                                        * 2 - Theme.spacing.md) :
                                                                               contentImplicitHeight
    property bool reducedMotion: false
    readonly property Item contentItem: contentHost.children.length === 0 ? null :
                                                                            contentHost.children[0]

    signal backRequested
    signal escapePressed

    readonly property real contentImplicitWidth: contentItem === null ? 0 :
                                                                        contentItem.implicitWidth
                                                                        > 0 ? contentItem.implicitWidth :
                                                                              contentItem.width
    readonly property real contentImplicitHeight: contentItem === null ? 0 :
                                                                         contentItem.implicitHeight
                                                                         > 0 ? contentItem.implicitHeight :
                                                                               contentItem.height
    readonly property real boundedContentWidth: Math.min(contentImplicitWidth, Math.max(0,
                                                                                        maximumContentWidth))
    readonly property real boundedContentHeight: Math.min(contentImplicitHeight, Math.max(0,
                                                                                          maximumContentHeight))
    readonly property bool horizontalOverflow: contentImplicitWidth > boundedContentWidth
    readonly property bool contentOverflow: contentImplicitHeight > boundedContentHeight
    readonly property bool scrolling: horizontalOverflow || contentOverflow
    readonly property real translationDistance: reducedMotion ? 0 : Theme.spacing.xl
    readonly property real entryOffset: translationDistance
    readonly property int motionDuration: reducedMotion ? 0 : Theme.motion.durationNormal
    readonly property bool animationsRunning: _entryAnimation.running
    readonly property int headerHeight: Theme.size.controlHeightMd
    readonly property Item backControl: backButton
    readonly property Item titleControl: titleLabel
    readonly property real headerImplicitWidth: backButton.width + headerRow.spacing
                                                + titleLabel.implicitWidth

    property bool _componentReady: false

    property Item _visual: Item {
        parent: frame
        width: frame.width
        height: frame.height

        Row {
            id: headerRow

            x: Theme.spacing.lg
            y: Theme.spacing.lg
            width: Math.max(0, frame.width - Theme.spacing.lg * 2)
            height: frame.headerHeight
            spacing: Theme.spacing.md

            AbstractButton {
                id: backButton

                objectName: "subviewBackButton"
                width: Theme.size.controlHeightMd
                height: Theme.size.controlHeightMd
                focusPolicy: Qt.StrongFocus
                hoverEnabled: true
                Accessible.role: Accessible.Button
                Accessible.name: "Back"
                onClicked: frame.backRequested()

                background: Rectangle {
                    radius: Theme.radius.md
                    color: backButton.pressed ? Theme.snapshot.controlFillPressed :
                                                backButton.hovered
                                                ? Theme.snapshot.controlFillHover : "transparent"
                }

                contentItem: Item {
                    IslandIcon {
                        anchors.centerIn: parent
                        meaning: "back"
                        size: "md"
                    }
                }

                IslandFocusRing {
                    visible: backButton.visualFocus
                }

                ToolTip.delay: Theme.motion.durationSlow
                ToolTip.visible: hovered || visualFocus
                ToolTip.text: "Back"
                KeyNavigation.tab: frame.initialFocusItem
            }

            IslandText {
                id: titleLabel

                objectName: "subviewTitle"
                width: Math.max(0, headerRow.width - backButton.width - headerRow.spacing)
                height: headerRow.height
                text: frame.title
                size: "title"
                font.weight: Theme.type.weightSemibold
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                maximumLineCount: 1
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
        }

        Flickable {
            id: contentViewport

            objectName: "subviewContentViewport"
            x: Theme.spacing.lg
            y: Theme.spacing.lg + frame.headerHeight + Theme.spacing.md
            width: frame.boundedContentWidth
            height: frame.boundedContentHeight
            contentWidth: frame.contentImplicitWidth
            contentHeight: frame.contentImplicitHeight
            boundsBehavior: Flickable.StopAtBounds
            interactive: frame.scrolling
            clip: frame.scrolling

            Item {
                id: contentHost

                objectName: "subviewContentHost"
                width: frame.contentImplicitWidth
                height: frame.contentImplicitHeight
            }
        }

        ScrollBar {
            id: horizontalContentScrollBar

            x: contentViewport.x
            y: contentViewport.y + contentViewport.height - height
            width: contentViewport.width
            orientation: Qt.Horizontal
            policy: frame.horizontalOverflow ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            size: contentViewport.visibleArea.widthRatio
            position: contentViewport.visibleArea.xPosition
            active: pressed || hovered || contentViewport.movingHorizontally

            contentItem: Rectangle {
                implicitHeight: Theme.spacing.xs
                radius: Theme.radius.sm
                color: Theme.color.textMuted
            }

            onPositionChanged: {
                if (pressed) {
                    contentViewport.contentX = position * contentViewport.contentWidth;
                }
            }
        }

        ScrollBar {
            id: contentScrollBar

            x: contentViewport.x + contentViewport.width - width
            y: contentViewport.y
            height: contentViewport.height
            orientation: Qt.Vertical
            policy: frame.contentOverflow ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            size: contentViewport.visibleArea.heightRatio
            position: contentViewport.visibleArea.yPosition
            active: pressed || hovered || contentViewport.movingVertically

            contentItem: Rectangle {
                implicitWidth: Theme.spacing.xs
                radius: Theme.radius.sm
                color: Theme.color.textMuted
            }

            onPositionChanged: {
                if (pressed) {
                    contentViewport.contentY = position * contentViewport.contentHeight;
                }
            }
        }
    }

    property ParallelAnimation _entryAnimation: ParallelAnimation {
        NumberAnimation {
            target: frame._visual
            property: "x"
            to: 0
            duration: frame.motionDuration
            easing.type: Theme.motion.easingStandard
        }
        NumberAnimation {
            target: frame._visual
            property: "opacity"
            to: 1
            duration: frame.motionDuration
            easing.type: Theme.motion.easingStandard
        }
    }

    implicitWidth: Math.max(Theme.size.islandSubviewMinimumWidth, headerImplicitWidth
                            + Theme.spacing.lg * 2, contentImplicitWidth + Theme.spacing.lg * 2)
    implicitHeight: Theme.spacing.lg + headerHeight + Theme.spacing.md + contentImplicitHeight
                    + Theme.spacing.lg
    visible: active
    clip: true

    function _prepareInitialFocus() {
        const target = initialFocusItem !== null ? initialFocusItem : backButton;
        target.focus = true;
        return target;
    }

    function focusInitialControl() {
        if (!active) {
            return false;
        }
        _prepareInitialFocus().forceActiveFocus(Qt.TabFocusReason);
        return true;
    }

    function _isContentDescendant(item) {
        let candidate = item;
        while (candidate !== null && candidate !== undefined) {
            if (candidate === contentHost) {
                return true;
            }
            candidate = candidate.parent;
        }
        return false;
    }

    function _revealFocusedItem(item) {
        if (item === null || item === undefined || !_isContentDescendant(item)) {
            return;
        }

        const topLeft = item.mapToItem(contentHost, 0, 0);
        const right = topLeft.x + item.width;
        const bottom = topLeft.y + item.height;
        if (topLeft.x < contentViewport.contentX) {
            contentViewport.contentX = Math.max(0, topLeft.x);
        } else if (right > contentViewport.contentX + contentViewport.width) {
            contentViewport.contentX = Math.min(contentViewport.contentWidth - contentViewport.width,
                                                right - contentViewport.width);
        }
        if (topLeft.y < contentViewport.contentY) {
            contentViewport.contentY = Math.max(0, topLeft.y);
        } else if (bottom > contentViewport.contentY + contentViewport.height) {
            contentViewport.contentY = Math.min(contentViewport.contentHeight
                                                - contentViewport.height, bottom
                                                - contentViewport.height);
        }
    }

    function _beginEntry() {
        if (!active) {
            _settleHidden();
            return;
        }
        _visual.x = entryOffset;
        _visual.opacity = 0;
        if (reducedMotion) {
            _visual.x = 0;
            _visual.opacity = 1;
            return;
        }
        _entryAnimation.restart();
    }

    function _settleHidden() {
        _entryAnimation.stop();
        _visual.x = 0;
        _visual.opacity = 0;
    }

    Component.onCompleted: {
        _componentReady = true;
        if (active) {
            _prepareInitialFocus();
            _beginEntry();
        } else {
            _settleHidden();
        }
    }

    onActiveChanged: {
        if (!_componentReady) {
            return;
        }
        if (active) {
            _prepareInitialFocus();
            _beginEntry();
        } else {
            _settleHidden();
        }
    }

    onReducedMotionChanged: {
        if (reducedMotion && active) {
            _entryAnimation.stop();
            _visual.x = 0;
            _visual.opacity = 1;
        }
    }

    Connections {
        target: frame.Window.window
        ignoreUnknownSignals: true

        function onActiveFocusItemChanged() {
            frame._revealFocusedItem(frame.Window.window.activeFocusItem);
        }
    }

    Keys.priority: Keys.BeforeItem
    Keys.onEscapePressed: event => {
        event.accepted = true;
        frame.escapePressed();
    }
}

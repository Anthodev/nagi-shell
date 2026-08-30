import QtQuick
import QtQuick.Controls

FocusScope {
    id: frame

    default property alias content: contentHost.children
    property string title: ""
    property bool active: false
    property Item initialFocusItem: null
    property real preferredViewportWidth: 0
    property real preferredViewportHeight: 0
    property real maximumViewportWidth: Number.POSITIVE_INFINITY
    property real maximumViewportHeight: Number.POSITIVE_INFINITY
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
    readonly property real _horizontalChrome: Theme.spacing.lg * 2
    readonly property real _verticalChrome: Theme.spacing.lg * 2 + Theme.spacing.md + headerHeight
    readonly property real resolvedViewportWidth: Math.min(preferredViewportWidth > 0
                                                           ? preferredViewportWidth :
                                                             contentImplicitWidth, Math.max(0,
                                                                                            maximumViewportWidth))
    readonly property real resolvedViewportHeight: Math.min(preferredViewportHeight > 0
                                                            ? preferredViewportHeight :
                                                              contentImplicitHeight, Math.max(0,
                                                                                              maximumViewportHeight))
    readonly property real actualViewportWidth: Math.min(resolvedViewportWidth, Math.max(0, width
                                                                                         - _horizontalChrome))
    readonly property real actualViewportHeight: Math.min(resolvedViewportHeight, Math.max(0,
                                                                                           height - _verticalChrome))
    readonly property bool horizontalOverflow: contentImplicitWidth > resolvedViewportWidth
    readonly property bool verticalOverflow: contentImplicitHeight > resolvedViewportHeight
    readonly property bool scrolling: horizontalOverflow || verticalOverflow
    readonly property int headerHeight: Theme.size.controlHeightMd
    readonly property Item backControl: backButton
    readonly property Item titleControl: titleLabel
    readonly property real headerImplicitWidth: backButton.width + headerRow.spacing
                                                + titleLabel.implicitWidth

    property bool _componentReady: false

    Item {
        anchors.fill: parent

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
                Accessible.name: qsTr("Back")
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
                ToolTip.text: qsTr("Back")
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
            width: frame.actualViewportWidth
            height: frame.actualViewportHeight
            contentWidth: contentHost.width
            contentHeight: contentHost.height
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: frame.horizontalOverflow && frame.verticalOverflow
                                ? Flickable.HorizontalAndVerticalFlick : frame.horizontalOverflow
                                  ? Flickable.HorizontalFlick : Flickable.VerticalFlick
            interactive: frame.scrolling
            clip: contentWidth > width || contentHeight > height

            Item {
                id: contentHost

                objectName: "subviewContentHost"
                width: Math.max(frame.contentImplicitWidth, frame.resolvedViewportWidth)
                height: Math.max(frame.contentImplicitHeight, frame.resolvedViewportHeight)
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
            policy: frame.verticalOverflow ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
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

    implicitWidth: Math.max(Theme.size.islandSubviewMinimumWidth, headerImplicitWidth
                            + _horizontalChrome, resolvedViewportWidth + _horizontalChrome)
    implicitHeight: resolvedViewportHeight + _verticalChrome
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
        const viewportWidth = actualViewportWidth;
        const viewportHeight = actualViewportHeight;
        if (viewportWidth > 0) {
            if (topLeft.x < contentViewport.contentX) {
                contentViewport.contentX = Math.max(0, topLeft.x);
            } else if (right > contentViewport.contentX + viewportWidth) {
                contentViewport.contentX = Math.max(0, Math.min(contentViewport.contentWidth
                                                                - viewportWidth, right
                                                                - viewportWidth));
            }
        }
        if (viewportHeight > 0) {
            if (topLeft.y < contentViewport.contentY) {
                contentViewport.contentY = Math.max(0, topLeft.y);
            } else if (bottom > contentViewport.contentY + viewportHeight) {
                contentViewport.contentY = Math.max(0, Math.min(contentViewport.contentHeight
                                                                - viewportHeight, bottom
                                                                - viewportHeight));
            }
        }
    }

    Component.onCompleted: {
        _componentReady = true;
        if (active) {
            _prepareInitialFocus();
        }
    }

    onActiveChanged: {
        if (_componentReady && active) {
            _prepareInitialFocus();
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

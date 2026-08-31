import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property string iconMeaning: ""
    property string title: ""
    property string description: ""
    readonly property bool controlCenterPageFocusTarget: true

    Layout.fillWidth: true
    Layout.bottomMargin: Theme.spacing.lg
    implicitWidth: heroSurface.implicitWidth
    implicitHeight: heroSurface.implicitHeight
    activeFocusOnTab: false
    Accessible.role: Accessible.Pane
    Accessible.name: title
    Accessible.description: description
    Accessible.focusable: true
    Accessible.focused: activeFocus
    Keys.priority: Keys.BeforeItem
    Keys.onTabPressed: focusNextControl()
    Keys.onBacktabPressed: focusPreviousControl()

    function focusNextControl() {
        const next = root.nextItemInFocusChain(true);
        if (next === null || next === root) {
            return false;
        }
        next.forceActiveFocus(Qt.TabFocusReason);
        return next.activeFocus;
    }

    function focusPreviousControl() {
        const previous = root.nextItemInFocusChain(false);
        if (previous === null || previous === root) {
            return false;
        }
        previous.forceActiveFocus(Qt.BacktabFocusReason);
        return previous.activeFocus;
    }

    IslandPanel {
        id: heroSurface
        objectName: "controlCenterPageHeaderSurface"

        anchors.fill: parent
        implicitWidth: heroLayout.implicitWidth + Theme.spacing.xl * 2
        implicitHeight: heroLayout.implicitHeight + Theme.spacing.xl * 2
        radius: Theme.radius.lg
        color: Theme.color.controlFill
        clip: true
        border.color: "transparent"

        ColumnLayout {
            id: heroLayout

            anchors.fill: parent
            anchors.margins: Theme.spacing.xl
            spacing: 0

            Rectangle {
                id: iconWell
                objectName: "controlCenterPageHeaderIconWell"

                Layout.preferredWidth: Theme.size.controlCenterHeroIconWellSize
                Layout.preferredHeight: Theme.size.controlCenterHeroIconWellSize
                Layout.alignment: Qt.AlignHCenter
                radius: width / 2
                color: Theme.color.surfaceActive

                IslandIcon {
                    objectName: "controlCenterPageHeaderIcon"

                    anchors.centerIn: parent
                    meaning: root.iconMeaning
                    semanticState: "active"
                    tint: Theme.snapshot.surfaceActiveAccent
                    size: "lg"
                    Accessible.ignored: true
                }
            }

            IslandText {
                objectName: "controlCenterPageHeaderTitle"

                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing.md
                text: root.title
                size: "pageTitle"
                font.weight: Theme.type.weightSemibold
                color: Theme.snapshot.controlFillForeground
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }

            IslandText {
                objectName: "controlCenterPageHeaderDescription"

                Layout.fillWidth: true
                Layout.maximumWidth: Theme.size.controlCenterHeroDescriptionMaximumWidth
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.spacing.sm
                visible: root.description !== ""
                text: root.description
                size: "body"
                tone: "secondary"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }
        }
    }

    IslandFocusRing {
        objectName: "controlCenterPageHeaderFocusRing"
        anchors.fill: heroSurface
        anchors.margins: Theme.size.focusRingGap
        controlRadius: Math.max(0, Theme.radius.lg - Theme.size.focusRingGap)
        visible: root.activeFocus
    }
}

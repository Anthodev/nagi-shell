pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FocusScope {
    id: view

    required property var service
    required property real ownerEpoch
    property bool active: true
    property bool reducedMotion: false
    property real maximumViewportWidth: Number.POSITIVE_INFINITY
    property real maximumViewportHeight: Number.POSITIVE_INFINITY

    readonly property int actionCellWidth: Theme.spacing.xxl * 3
    readonly property int actionCellHeight: Theme.spacing.xxl * 2
    readonly property int actionGap: Theme.spacing.sm
    readonly property bool narrowArrangement: maximumViewportWidth < 3 * actionCellWidth + 2
                                              * actionGap
    readonly property int actionColumns: narrowArrangement ? 2 : 3
    readonly property int actionRows: Math.ceil(actions.length / actionColumns)
    readonly property real sessionViewportWidth: actionColumns * actionCellWidth + (actionColumns
                                                                                    - 1) * actionGap
    readonly property real actionGridHeight: actionRows * actionCellHeight + Math.max(0, actionRows
                                                                                      - 1) * actionGap
    readonly property int statusLaneExtent: 28
    readonly property real sessionViewportHeight: actionGridHeight + Theme.spacing.md
                                                  + statusLaneExtent
    readonly property bool actionPending: service !== null && service.pending
    readonly property var actions: [
        {
            "action": "lock",
            "description": qsTr("Lock this KDE session"),
            "label": qsTr("Lock"),
            "meaning": "lock",
            "danger": false
        },
        {
            "action": "suspend",
            "description": qsTr("Suspend this computer"),
            "label": qsTr("Suspend"),
            "meaning": "suspend",
            "danger": false
        },
        {
            "action": "restartShell",
            "description": qsTr("Reload Nagi Shell without restarting this computer"),
            "label": qsTr("Restart shell"),
            "meaning": "restartShell",
            "danger": false
        },
        {
            "action": "logout",
            "description": qsTr("Open KDE confirmation to end the current session"),
            "label": qsTr("Log out"),
            "meaning": "logout",
            "danger": true
        },
        {
            "action": "reboot",
            "description": qsTr("Open KDE confirmation to restart this computer"),
            "label": qsTr("Restart"),
            "meaning": "restart",
            "danger": true
        },
        {
            "action": "powerOff",
            "description": qsTr("Open KDE confirmation to power off this computer"),
            "label": qsTr("Power off"),
            "meaning": "powerOff",
            "danger": true
        }
    ]
    implicitWidth: frame.implicitWidth
    implicitHeight: frame.implicitHeight
    visible: active

    signal actionDispatched(int requestId, real ownerEpoch)
    signal cancelled(real ownerEpoch)

    function failureText(failure) {
        if (failure === "busy") {
            return qsTr("Another session action is still pending.");
        }
        if (failure === "denied") {
            return qsTr("Permission denied. Check the KDE session policy and try again.");
        }
        if (failure === "unavailable") {
            return qsTr("This action is unavailable in the current KDE session.");
        }
        if (failure === "timeout") {
            return qsTr("The KDE session service did not respond. Try again.");
        }
        if (failure === "backend") {
            return qsTr("The session action failed. Try again or use KDE's session controls.");
        }
        return "";
    }

    function focusInitialControl() {
        focusAction(0, Qt.ShortcutFocusReason);
    }

    function focusAction(index, reason) {
        const bounded = Math.max(0, Math.min(index, actions.length - 1));
        const target = actionRepeater.itemAt(bounded);
        if (target !== null) {
            target.forceActiveFocus(reason);
        }
    }

    function pendingLabel(action) {
        if (action === "lock") {
            return qsTr("Locking…");
        }
        if (action === "suspend") {
            return qsTr("Suspending…");
        }
        if (action === "logout") {
            return qsTr("Opening logout confirmation…");
        }
        if (action === "restartShell") {
            return qsTr("Restarting shell…");
        }
        if (action === "reboot") {
            return qsTr("Opening restart confirmation…");
        }
        if (action === "powerOff") {
            return qsTr("Opening power-off confirmation…");
        }
        return qsTr("Working…");
    }

    function requestAction(action) {
        if (service === null || actionPending) {
            return false;
        }
        service.clearFailure();
        const requestId = service.requestAction(action);
        if (requestId === 0) {
            return false;
        }
        actionDispatched(requestId, ownerEpoch);
        return true;
    }

    SubviewFrame {
        id: frame

        anchors.fill: parent
        active: view.active
        title: qsTr("Session")
        preferredViewportWidth: view.sessionViewportWidth
        preferredViewportHeight: view.sessionViewportHeight
        maximumViewportWidth: view.maximumViewportWidth
        maximumViewportHeight: view.maximumViewportHeight
        initialFocusItem: actionRepeater.itemAt(0)
        onBackRequested: {
            if (!view.actionPending) {
                view.cancelled(view.ownerEpoch);
            }
        }
        onEscapePressed: {
            if (!view.actionPending) {
                view.cancelled(view.ownerEpoch);
            }
        }

        Item {
            implicitWidth: view.sessionViewportWidth
            implicitHeight: view.sessionViewportHeight
            width: implicitWidth
            height: implicitHeight
            ColumnLayout {
                id: sessionContent

                anchors.fill: parent
                spacing: Theme.spacing.md

                GridLayout {
                    id: actionGrid

                    columns: view.actionColumns
                    columnSpacing: view.actionGap
                    rowSpacing: view.actionGap
                    Layout.alignment: Qt.AlignHCenter

                    Repeater {
                        id: actionRepeater

                        model: view.actions

                        delegate: AbstractButton {
                            id: actionButton

                            required property int index
                            required property var modelData
                            objectName: "sessionActionButton"
                            implicitWidth: view.actionCellWidth
                            implicitHeight: view.actionCellHeight
                            focusPolicy: Qt.StrongFocus
                            hoverEnabled: true
                            enabled: view.service !== null && !view.actionPending && (
                                         modelData.action === "restartShell"
                                         ? view.service.shellRestartReady === true :
                                           view.service.backendReady === true)
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData.label
                            Accessible.description: modelData.description
                            onClicked: view.requestAction(modelData.action)

                            Keys.onLeftPressed: event => {
                                const column = index % view.actionColumns;
                                view.focusAction(column === 0 ? index + view.actionColumns - 1 :
                                                                index - 1, Qt.BacktabFocusReason);
                                event.accepted = true;
                            }
                            Keys.onRightPressed: event => {
                                const column = index % view.actionColumns;
                                view.focusAction(column === view.actionColumns - 1 ? index
                                                                                     - view.actionColumns
                                                                                     + 1 : index + 1,
                                                 Qt.TabFocusReason);
                                event.accepted = true;
                            }
                            Keys.onUpPressed: event => {
                                view.focusAction(index >= view.actionColumns ? index
                                                                               - view.actionColumns :
                                                                               index + view.actions.length
                                                                               - view.actionColumns,
                                                 Qt.BacktabFocusReason);
                                event.accepted = true;
                            }
                            Keys.onDownPressed: event => {
                                view.focusAction(index + view.actionColumns < view.actions.length
                                                 ? index + view.actionColumns : index
                                                   % view.actionColumns, Qt.TabFocusReason);
                                event.accepted = true;
                            }

                            background: Rectangle {
                                radius: Theme.radius.md
                                color: actionButton.modelData.action === "powerOff"
                                       ? actionButton.pressed ? Theme.color.dangerFillPressed :
                                                                actionButton.hovered
                                                                ? Theme.color.dangerFillHover :
                                                                  Theme.color.dangerFill :
                                                                  actionButton.pressed
                                                                  ? Theme.color.surfaceActive :
                                                                    actionButton.hovered
                                                                    ? Theme.color.surfaceHover :
                                                                      "transparent"
                            }

                            contentItem: Item {
                                Column {
                                    anchors.centerIn: parent
                                    spacing: Theme.spacing.sm

                                    IslandIcon {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        meaning: actionButton.modelData.meaning
                                        size: "lg"
                                        semanticState: actionButton.modelData.danger ? "error" :
                                                                                       "normal"
                                    }

                                    IslandText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: actionButton.modelData.label
                                        textFormat: Text.PlainText
                                        color: actionButton.modelData.danger ? Theme.color.danger :
                                                                               Theme.color.textPrimary
                                        size: "label"
                                        font.weight: Theme.type.weightMedium
                                    }
                                }
                            }

                            IslandFocusRing {
                                visible: actionButton.visualFocus
                            }
                        }
                    }
                }

                Item {
                    id: statusLane

                    Layout.fillWidth: true
                    Layout.preferredHeight: view.statusLaneExtent

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        spacing: Theme.spacing.xs

                        IslandText {
                            readonly property string failureMessage: view.service === null ? "" :
                                                                                             view.failureText(
                                                                                                 view.service.failure)

                            width: parent.width
                            text: view.actionPending ? view.pendingLabel(
                                                           view.service.pendingAction) :
                                                       failureMessage
                            visible: text !== ""
                            textFormat: Text.PlainText
                            color: view.actionPending ? Theme.color.textSecondary :
                                                        Theme.color.danger
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            Accessible.role: Accessible.StaticText
                            Accessible.name: text
                        }

                        IslandText {
                            width: parent.width
                            text: qsTr("Session controls unavailable")
                            visible: view.service === null || (!view.service.backendReady &&
                                                               !view.service.shellRestartReady)
                            textFormat: Text.PlainText
                            tone: "secondary"
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            Accessible.role: Accessible.StaticText
                            Accessible.name: text
                        }
                    }
                }
            }
        }
    }

    Binding {
        target: frame.backControl
        property: "enabled"
        value: !view.actionPending
    }
}

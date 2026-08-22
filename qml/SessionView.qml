pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

FocusScope {
    id: view

    required property var service
    required property real ownerEpoch

    readonly property bool actionPending: service !== null && service.pending

    signal actionDispatched(int requestId, real ownerEpoch)
    signal cancelled(real ownerEpoch)

    function failureText(failure) {
        if (failure === "busy") {
            return "Another session action is still pending.";
        }
        if (failure === "denied") {
            return "Permission denied. Check the KDE session policy and try again.";
        }
        if (failure === "unavailable") {
            return "This action is unavailable in the current KDE session.";
        }
        if (failure === "timeout") {
            return "The KDE session service did not respond. Try again.";
        }
        if (failure === "backend") {
            return "The session action failed. Try again or use KDE's session controls.";
        }
        return "";
    }

    function focusInitialControl() {
        lockButton.forceActiveFocus(Qt.ShortcutFocusReason);
    }

    function pendingLabel(action) {
        if (action === "lock") {
            return "Locking…";
        }
        if (action === "suspend") {
            return "Suspending…";
        }
        if (action === "logout") {
            return "Opening logout confirmation…";
        }
        if (action === "reboot") {
            return "Opening restart confirmation…";
        }
        if (action === "powerOff") {
            return "Opening power-off confirmation…";
        }
        return "Working…";
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

    Keys.priority: Keys.BeforeItem
    Keys.onEscapePressed: event => {
        if (!view.actionPending) {
            view.cancelled(view.ownerEpoch);
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing.xl
        spacing: Theme.spacing.lg

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.md

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.xs

                IslandText {
                    text: "Session"
                    size: "title"
                    font.weight: Theme.type.weightSemibold
                }

                IslandText {
                    text: "Choose a session action. KDE confirms logout, restart, and power off."
                    tone: "secondary"
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }

            IslandButton {
                id: cancelButton

                label: "Cancel"
                enabled: !view.actionPending
                Accessible.description: "Return without performing a session action"
                onClicked: view.cancelled(view.ownerEpoch)
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 2
            columnSpacing: Theme.spacing.md
            rowSpacing: Theme.spacing.md

            IslandButton {
                id: lockButton

                label: "Lock"
                enabled: view.service !== null && view.service.backendReady && !view.actionPending
                Layout.fillWidth: true
                Layout.fillHeight: true
                Accessible.description: "Lock this KDE session"
                onClicked: view.requestAction("lock")
            }

            IslandButton {
                label: "Suspend"
                enabled: view.service !== null && view.service.backendReady && !view.actionPending
                Layout.fillWidth: true
                Layout.fillHeight: true
                Accessible.description: "Suspend this computer"
                onClicked: view.requestAction("suspend")
            }

            IslandButton {
                label: "Log out"
                variant: "danger"
                enabled: view.service !== null && view.service.backendReady && !view.actionPending
                Layout.fillWidth: true
                Layout.fillHeight: true
                Accessible.description: "Open KDE confirmation to end the current session"
                onClicked: view.requestAction("logout")
            }

            IslandButton {
                label: "Restart"
                variant: "danger"
                enabled: view.service !== null && view.service.backendReady && !view.actionPending
                Layout.fillWidth: true
                Layout.fillHeight: true
                Accessible.description: "Open KDE confirmation to restart this computer"
                onClicked: view.requestAction("reboot")
            }

            IslandButton {
                label: "Power off"
                variant: "danger"
                enabled: view.service !== null && view.service.backendReady && !view.actionPending
                Layout.columnSpan: 2
                Layout.fillWidth: true
                Layout.fillHeight: true
                Accessible.description: "Open KDE confirmation to power off this computer"
                onClicked: view.requestAction("powerOff")
            }
        }

        IslandText {
            readonly property string failureMessage: view.service === null ? "" : view.failureText(
                                                                                 view.service.failure)

            text: view.actionPending ? view.pendingLabel(view.service.pendingAction) :
                                       failureMessage
            visible: text !== ""
            color: view.actionPending ? Theme.color.textSecondary : Theme.color.danger
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        IslandText {
            text: "Session controls are unavailable. Restart Nagi Shell and try again."
            visible: view.service === null || !view.service.backendReady
            tone: "secondary"
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }
    }
}

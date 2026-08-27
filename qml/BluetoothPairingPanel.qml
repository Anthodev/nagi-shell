pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

IslandPanel {
    id: root

    required property string deviceName
    required property string prompt
    required property string displayValue
    required property int entered
    property bool reducedMotion: false
    property bool operationPending: false

    signal responseRequested(bool accepted, string response)
    signal cancelRequested

    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + Theme.spacing.lg * 2
    color: Theme.color.controlFill
    Accessible.role: Accessible.Pane
    Accessible.name: "Pairing with " + deviceName

    readonly property bool inputPrompt: prompt === "enter-pin" || prompt === "enter-passkey"
    readonly property bool decisionPrompt: prompt === "confirm-passkey" || prompt
                                           === "authorize-pairing"
    readonly property bool displayPrompt: prompt === "display-pin" || prompt === "display-passkey"

    function clearPrivateState() {
        privateInput.clear();
    }

    function focusInput() {
        if (inputPrompt) {
            privateInput.forceInputFocus();
        }
    }

    function submitInput() {
        let accepted = false;
        privateInput.consume(value => {
            root.responseRequested(true, value);
            accepted = true;
        });
        return accepted;
    }

    onPromptChanged: {
        clearPrivateState();
        Qt.callLater(focusInput);
    }
    Component.onDestruction: clearPrivateState()

    ColumnLayout {
        id: content

        anchors.fill: parent
        anchors.margins: Theme.spacing.lg
        spacing: Theme.spacing.md

        IslandText {
            Layout.fillWidth: true
            text: "Pairing with " + root.deviceName
            textFormat: Text.PlainText
            size: "title"
            wrapMode: Text.Wrap
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }

        IslandText {
            Layout.fillWidth: true
            visible: root.prompt === "none"
            text: "Waiting for the device…"
            size: "body"
            color: Theme.color.textSecondary
            Accessible.name: text
        }

        IslandText {
            Layout.fillWidth: true
            visible: root.decisionPrompt
            text: root.prompt === "confirm-passkey"
                  ? "Confirm that this passkey matches the other device." :
                    "Allow this explicit pairing request?"
            size: "body"
            color: Theme.color.textSecondary
            wrapMode: Text.Wrap
            Accessible.name: text
        }

        IslandText {
            Layout.fillWidth: true
            visible: root.displayPrompt || root.prompt === "confirm-passkey"
            text: root.displayValue
            textFormat: Text.PlainText
            size: "display"
            horizontalAlignment: Text.AlignHCenter
            Accessible.name: (root.prompt === "display-pin" ? "PIN " : "Passkey ") + text
        }

        IslandText {
            Layout.fillWidth: true
            visible: root.prompt === "display-passkey"
            text: "Entered digits: " + root.entered
            size: "caption"
            color: Theme.color.textSecondary
            horizontalAlignment: Text.AlignHCenter
            Accessible.name: text
        }

        WifiSecretField {
            id: privateInput

            Layout.fillWidth: true
            visible: root.inputPrompt
            label: root.prompt === "enter-pin" ? "PIN" : "Passkey"
            accessibleName: "Bluetooth " + label.toLowerCase()
            accessibleDescription: "Enter the value shown or requested by the other device"
            inputObjectName: "bluetoothPairingInput"
            minimumLength: 1
            maximumLength: root.prompt === "enter-passkey" ? 6 : 16
            clipboardEnabled: false
            additionalInputMethodHints: root.prompt === "enter-passkey" ? Qt.ImhDigitsOnly :
                                                                          Qt.ImhNone
            operationPending: root.operationPending
            reducedMotion: root.reducedMotion
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.sm

            IslandButton {
                visible: root.inputPrompt
                label: "Submit"
                reducedMotion: root.reducedMotion
                enabled: !root.operationPending && privateInput.acceptable
                onClicked: root.submitInput()
            }

            IslandButton {
                visible: root.decisionPrompt
                label: "Allow"
                reducedMotion: root.reducedMotion
                enabled: !root.operationPending
                onClicked: root.responseRequested(true, "")
            }

            IslandButton {
                visible: root.decisionPrompt
                label: "Reject"
                variant: "danger"
                reducedMotion: root.reducedMotion
                enabled: !root.operationPending
                onClicked: root.responseRequested(false, "")
            }

            IslandButton {
                label: "Cancel"
                variant: "danger"
                reducedMotion: root.reducedMotion
                enabled: !root.operationPending
                onClicked: {
                    root.clearPrivateState();
                    root.cancelRequested();
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }
}

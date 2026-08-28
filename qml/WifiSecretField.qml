pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    property bool reducedMotion: false
    property bool operationPending: false
    property bool secretVisible: false
    property string inputObjectName: "wifiPasswordInput"
    property string label: "Password"
    property string accessibleName: "Wi-Fi password"
    property string accessibleDescription: "Enter the password for this connection"
    property int minimumLength: 8
    property int maximumLength: 64
    property int additionalInputMethodHints: Qt.ImhNone
    property bool clipboardEnabled: true
    readonly property bool acceptable: input.text.length >= minimumLength && input.text.length
                                       <= maximumLength
    readonly property bool empty: input.text.length === 0

    spacing: Theme.spacing.sm

    function clear() {
        input.clear();
        input.deselect();
        root.secretVisible = false;
    }

    function consume(callback) {
        if (!acceptable || typeof callback !== "function") {
            return false;
        }
        const submitted = input.text;
        clear();
        callback(submitted);
        return true;
    }

    function forceInputFocus() {
        input.forceActiveFocus(Qt.TabFocusReason);
    }

    IslandText {
        Layout.fillWidth: true
        text: root.label
        size: "caption"
        color: Theme.color.textSecondary
        Accessible.role: Accessible.StaticText
        Accessible.name: text
    }

    IslandPanel {
        id: field

        objectName: "wifiPasswordField"
        Layout.fillWidth: true
        Layout.preferredHeight: Theme.size.controlHeightLg
        radius: Theme.radius.md
        color: Theme.color.controlFill
        border.width: Theme.size.hairlineWidth
        border.color: input.activeFocus ? Theme.snapshot.focusRing : Theme.color.surfaceBorder
        opacity: root.operationPending ? Theme.opacity.disabled : 1
        Accessible.role: Accessible.EditableText
        Accessible.name: root.accessibleName
        Accessible.description: root.accessibleDescription
        Accessible.passwordEdit: true
        Accessible.selectableText: false
        Accessible.focusable: true
        Accessible.focused: input.activeFocus

        TextInput {
            id: input

            objectName: root.inputObjectName
            anchors.fill: parent
            leftPadding: Theme.spacing.md
            rightPadding: Theme.spacing.md
            enabled: !root.operationPending
            readOnly: root.operationPending
            color: Theme.color.textPrimary
            selectionColor: Theme.snapshot.accent
            selectedTextColor: Theme.snapshot.accentForeground
            font.pixelSize: Theme.type.sizeForItem(this, "body")
            font.family: Theme.type.familyForItem(this)
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            activeFocusOnTab: true
            echoMode: root.secretVisible ? TextInput.Normal : TextInput.NoEcho
            passwordMaskDelay: 0
            maximumLength: root.maximumLength
            selectByMouse: root.secretVisible && root.clipboardEnabled
            persistentSelection: false
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                              | root.additionalInputMethodHints | (root.secretVisible ? Qt.ImhNone :
                                                                                        Qt.ImhHiddenText)
            Accessible.ignored: true

            onSelectedTextChanged: {
                if (!root.secretVisible && selectedText !== "") {
                    deselect();
                }
            }

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: event => {
                const control = (event.modifiers & Qt.ControlModifier) !== 0;
                const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
                if ((!root.secretVisible || !root.clipboardEnabled) && ((control && (event.key
                                                                                     === Qt.Key_C
                                                                                     || event.key
                                                                                     === Qt.Key_X
                                                                                     || event.key
                                                                                     === Qt.Key_Insert))
                                                                        || (shift && event.key
                                                                            === Qt.Key_Delete))) {
                    input.deselect();
                    event.accepted = true;
                }
            }
        }
    }

    SettingToggleRow {
        Layout.fillWidth: true
        label: "Show " + root.label.toLowerCase()
        description: "Reveal only while this form remains open."
        value: root.secretVisible
        writable: !root.operationPending
        onValueRequested: value => root.secretVisible = value
    }
}

import QtQuick
import QtQuick.Controls

ControlCenterSettingRow {
    id: root

    required property string value
    property bool allowAlpha: false
    property bool writable: true
    property string validationText: ""

    signal valueRequested(string value)

    function valid(candidate) {
        const expression = allowAlpha ? /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/ : /^#[0-9a-fA-F]{6}$/;
        return expression.test(candidate);
    }
    function submit(candidate) {
        if (!writable || !valid(candidate)) {
            return false;
        }
        valueRequested(candidate.toUpperCase());
        return true;
    }

    errorText: validationText !== "" ? validationText : input.acceptableInput ? "" : allowAlpha
                                                                                ? qsTr("Use #RRGGBB or #AARRGGBB.") :
                                                                                  qsTr("Use #RRGGBB.")

    TextField {
        id: input

        width: Theme.spacing.xxl * 4
        height: Theme.size.controlHeightMd
        text: root.value
        enabled: root.writable
        selectByMouse: true
        maximumLength: root.allowAlpha ? 9 : 7
        color: Theme.color.textPrimary
        selectionColor: Theme.snapshot.accent
        selectedTextColor: Theme.snapshot.accentForeground
        font.family: Theme.type.familyForItem(this)
        font.pixelSize: Theme.type.sizeForItem(this, "body")
        Accessible.name: root.label
        Accessible.description: root.description
        Accessible.role: Accessible.EditableText
        validator: RegularExpressionValidator {
            regularExpression: root.allowAlpha ? /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/ :
                                                 /^#[0-9a-fA-F]{6}$/
        }
        onEditingFinished: root.submit(text)

        background: IslandPanel {
            color: Theme.color.controlFill
            border.color: input.activeFocus ? Theme.snapshot.focusRing : root.errorText !== ""
                                              ? Theme.color.danger : Theme.color.surfaceBorder
        }
    }
}

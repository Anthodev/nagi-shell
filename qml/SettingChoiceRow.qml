pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

ControlCenterSettingRow {
    id: root

    required property string value
    required property var choices
    property bool writable: true
    property bool reducedMotion: false

    signal valueRequested(string value)
    function request(candidate) {
        if (!writable) {
            return false;
        }
        for (let index = 0; index < choices.length; index += 1) {
            const entry = choices[index];
            const choiceValue = typeof entry === "string" ? entry : entry.value;
            if (choiceValue === candidate) {
                valueRequested(candidate);
                return true;
            }
        }
        return false;
    }

    RowLayout {
        spacing: Theme.spacing.xs

        Repeater {
            model: root.choices

            delegate: IslandButton {
                id: choiceButton

                required property var modelData
                readonly property string choiceValue: typeof modelData === "string" ? modelData :
                                                                                      modelData.value
                readonly property string choiceLabel: typeof modelData === "string" ? modelData :
                                                                                      modelData.label

                reducedMotion: root.reducedMotion
                label: choiceLabel
                variant: root.value === choiceValue ? "accent" : "standard"
                enabled: root.writable && root.value !== choiceValue
                Accessible.role: Accessible.RadioButton
                Accessible.checked: root.value === choiceValue
                Accessible.description: root.description
                onClicked: root.request(choiceValue)
            }
        }
    }
}

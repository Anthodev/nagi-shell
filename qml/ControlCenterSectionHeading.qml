import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property string text: ""
    property bool separated: true
    readonly property int topSeparation: separated ? Theme.spacing.lg : 0

    Layout.fillWidth: true
    Layout.topMargin: topSeparation
    implicitWidth: heading.implicitWidth
    implicitHeight: heading.implicitHeight

    IslandText {
        id: heading

        anchors.left: parent.left
        anchors.right: parent.right
        text: root.text
        size: "caption"
        tone: "secondary"
        font.weight: Theme.type.weightSemibold
        font.capitalization: Font.AllUppercase
        wrapMode: Text.Wrap
        Accessible.role: Accessible.Heading
        Accessible.name: root.text
    }
}

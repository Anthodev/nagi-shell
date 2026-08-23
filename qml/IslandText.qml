import QtQuick

// Text primitive: labels pick a semantic tone and scale instead of raw
// colors or pixel sizes. Callers may still bind `color` directly when they
// need a token-driven color that is not one of the standard tones (for
// example filled-button content).
Text {
    id: label

    property string tone: "primary"
    property string size: "body"

    font.family: Theme.type.family
    font.pixelSize: size === "caption" ? Theme.type.caption : size === "title" ? Theme.type.title :
                                                                                 Theme.type.body
    color: tone === "secondary" ? Theme.color.textSecondary : tone === "muted"
                                  ? Theme.color.textMuted : Theme.color.textPrimary
}

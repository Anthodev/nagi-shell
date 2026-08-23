import QtQuick
import Quickshell.Io
import QtQuick.Effects
import Quickshell.Widgets

// Semantic icon primitive. Callers provide meaning + state, never an asset path;
// the sole exception is application-owned launcher/notification/tray artwork,
// which is passed to IconResolver and is never tinted. Nagi-owned SVGs are
// synchronously finalized from bounded files; other icon sources remain async.
Item {
    id: icon

    property string meaning: ""
    property string semanticState: "normal"
    property string size: "md"
    property string applicationSource: ""
    property string applicationName: ""

    readonly property var resolved: IconResolver.resolve(meaning, semanticState, applicationSource,
                                                         applicationName)
    readonly property string accessibleName: resolved.accessibleName
    readonly property string resolvedKind: resolved.kind
    readonly property string resolvedSource: resolved.source
    readonly property color tint: resolved.tint
    readonly property bool tinted: resolved.tintable || _loadFailed
    readonly property bool showingFallback: _loadFailed || resolved.kind === "placeholder"
    readonly property bool attention: resolved.attention
    readonly property int loadStatus: image.status
    readonly property string displayedSource: image.source
    readonly property int iconSize: IconResolver.sizeFor(size)
    readonly property string rawSource: _loadFailed ? IconResolver.placeholderSource :
                                                      resolved.source
    readonly property bool usesSvgMask: tinted && (_loadFailed || resolvedKind === "nagi"
                                                   || resolvedKind === "placeholder")
    readonly property string renderedSource: usesSvgMask ? tintedSvgSource(_svgTemplate, tint) :
                                                           rawSource
    readonly property bool usesQuickshellIconProvider: !usesSvgMask && rawSource.startsWith(
                                                           "image://icon/")
    readonly property bool loadsAsynchronously: image.asynchronous
    property bool _loadFailed: false
    property string _svgTemplate: ""
    property bool _componentReady: false
    property bool _syncing: false

    implicitWidth: iconSize
    implicitHeight: iconSize
    opacity: resolved.disabled ? Theme.opacity.disabled : 1

    Accessible.role: Accessible.Graphic
    Accessible.name: accessibleName

    onResolvedChanged: {
        _loadFailed = false;
        _svgTemplate = "";
        if (_componentReady) {
            syncSvgTemplate();
        }
    }
    onRawSourceChanged: {
        if (_componentReady) {
            syncSvgTemplate();
        }
    }

    function tintedSvgSource(template, color) {
        if (template === "") {
            return "";
        }
        const tintedTemplate = template.replace(/currentColor/g, color.toString());
        return "data:image/svg+xml;utf8," + encodeURIComponent(tintedTemplate);
    }
    function syncSvgTemplate() {
        if (!_componentReady || _syncing) {
            return;
        }

        _syncing = true;
        let resync = false;
        try {
            if (!usesSvgMask) {
                svgMask.path = "";
                _svgTemplate = "";
            } else {
                const source = rawSource;
                svgMask.path = decodeURIComponent(source.slice(7));
                if (rawSource !== source) {
                    resync = true;
                } else {
                    const template = svgMask.text();
                    if (template.length > 0 && template.length <= 4096 && template.indexOf("<svg")
                            !== -1 && template.indexOf("currentColor") !== -1) {
                        _svgTemplate = template;
                    } else {
                        IconResolver.reportLoadFailure(meaning, resolvedKind);
                        _loadFailed = true;
                        resync = rawSource !== source;
                    }
                }
            }
        } finally {
            _syncing = false;
        }

        if (resync && _componentReady) {
            syncSvgTemplate();
        }
    }

    Component.onCompleted: {
        _componentReady = true;
        syncSvgTemplate();
    }
    Component.onDestruction: _componentReady = false

    // Qt MultiEffect colorization multiplies by source luminance, so a black
    // currentColor SVG remains black. Recolor owned SVG text before rasterizing
    // instead; the 4 KiB bound keeps this local mask path deterministic.
    FileView {
        id: svgMask

        path: ""
        preload: true
        blockLoading: true
        printErrors: false
        onLoaded: icon.syncSvgTemplate()
        onLoadFailed: function (error) {
            if (icon._componentReady && !icon._loadFailed) {
                IconResolver.reportLoadFailure(icon.meaning, icon.resolvedKind);
                icon._loadFailed = true;
            }
        }
    }

    IconImage {
        id: image

        anchors.fill: parent
        source: icon.renderedSource
        implicitSize: icon.iconSize
        // Quickshell's pixmap icon provider calls QIcon::fromTheme; keep every
        // image://icon request on the GUI thread regardless of semantic kind.
        // Local SVG and application file sources remain asynchronous.
        asynchronous: !icon.usesQuickshellIconProvider
        mipmap: icon.iconSize < 24
        layer.enabled: icon.tinted && !icon.usesSvgMask
        layer.effect: MultiEffect {
            // Lift theme-icon pixels before colorization so a dark icon theme
            // cannot suppress the semantic tint.
            brightness: 1
            colorization: 1
            colorizationColor: icon._loadFailed ? Theme.color.textPrimary : icon.tint
            autoPaddingEnabled: false
        }

        onStatusChanged: {
            if (status === Image.Error && !icon._loadFailed) {
                IconResolver.reportLoadFailure(icon.meaning, icon.resolved.kind);
                icon._loadFailed = true;
            }
        }
    }

    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: 5
        height: 5
        radius: width / 2
        color: IconResolver.tintFor("attention")
        visible: icon.resolved.attention
    }
}

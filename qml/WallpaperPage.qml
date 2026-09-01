pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

Flickable {
    id: root

    required property var settingsModel
    required property var wallpaper
    property bool reducedMotion: false
    property string currentDirectoryId: ""
    property string selectedLibraryId: ""
    property string filterText: ""
    property bool applyWarningVisible: false
    property string failureText: ""

    clip: true
    contentWidth: width
    contentHeight: content.height
    flickableDirection: Flickable.VerticalFlick
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {
        policy: root.contentHeight > root.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
    }

    readonly property bool twoColumnWorkspace: width >= 580
    readonly property var roots: settingsModel.snapshot.wallpaper.roots
    readonly property bool previewReady: wallpaper.preview !== null && wallpaper.preview.status
                                         === "ready"

    readonly property bool operationPending: wallpaper.applyStatus === "pending" || (
                                                 wallpaper.preview !== null
                                                 && wallpaper.preview.status === "loading")

    function urlPath(value) {
        const text = String(value);
        if (!text.startsWith("file:///") || text.length > 8192 || text.indexOf("%00") !== -1) {
            return "";
        }
        try {
            const path = decodeURIComponent(text.slice(7));
            return path.startsWith("/") && path.length <= 1024 ? path : "";
        } catch (error) {
            return "";
        }
    }

    function addRoot(value) {
        const path = urlPath(value);
        if (path === "" || roots.length >= 8 || roots.indexOf(path) !== -1) {
            return false;
        }
        const next = roots.slice();
        next.push(path);
        if (!settingsModel.updatePage("wallpaper", {
                                          "roots": next
                                      }, false)) {
            failureText = qsTr("The approved folder could not be saved.");
            return false;
        }
        currentDirectoryId = "";
        failureText = "";
        wallpaper.refreshLibrary(next);
        return true;
    }

    function removeRoot(path) {
        const next = roots.filter(candidate => candidate !== path);
        if (next.length === roots.length || !settingsModel.updatePage("wallpaper", {
                                                                          "roots": next
                                                                      }, false)) {
            failureText = qsTr("The approved folder could not be removed.");
            return false;
        }
        currentDirectoryId = "";
        selectedLibraryId = "";
        wallpaper.cancelPreview();
        wallpaper.refreshLibrary(next);
        return true;
    }

    function ensureDirectory() {
        if (wallpaper.directories.length === 0) {
            currentDirectoryId = "";
            return;
        }
        for (let index = 0; index < wallpaper.directories.length; index += 1) {
            if (wallpaper.directories[index].id === currentDirectoryId) {
                return;
            }
        }
        currentDirectoryId = wallpaper.directories[0].id;
    }

    function currentDirectory() {
        for (let index = 0; index < wallpaper.directories.length; index += 1) {
            if (wallpaper.directories[index].id === currentDirectoryId) {
                return wallpaper.directories[index];
            }
        }
        return null;
    }

    function childDirectories() {
        return wallpaper.directories.filter(directory => directory.parentId === currentDirectoryId);
    }

    function filteredImages() {
        const query = filterText.trim().toLocaleLowerCase();
        return wallpaper.images.filter(image => image.directoryId === currentDirectoryId && (query
                                                                                             === "" || image.name.toLocaleLowerCase(
                                                                                                 ).indexOf(
                                                                                                 query)
                                                                                             !== -1));
    }

    function selectImage(image) {
        selectedLibraryId = image.id;
        applyWarningVisible = false;
        failureText = "";
        return wallpaper.previewImage(image.id);
    }

    function requestApply() {
        if (!previewReady || operationPending) {
            return false;
        }
        if (wallpaper.unsupported && !applyWarningVisible) {
            applyWarningVisible = true;
            return false;
        }
        applyWarningVisible = false;
        failureText = "";
        return wallpaper.applyPreview();
    }

    function currentSummary() {
        if (wallpaper.status === "Ready") {
            return qsTr("One static image is active on every display.");
        }
        if (wallpaper.status === "Multiple") {
            return qsTr("Multiple wallpapers are active across displays.");
        }
        if (wallpaper.status === "UnsupportedPlugin") {
            return qsTr("A slideshow or unsupported Plasma wallpaper is active.");
        }
        if (wallpaper.status === "Unavailable") {
            return qsTr("Plasma wallpaper state is unavailable.");
        }
        return qsTr("The current static wallpaper cannot be used by Nagi.");
    }
    function screenStatusLabel(value) {
        if (value === "Ready") {
            return qsTr("Static");
        }
        if (value === "UnsupportedPlugin") {
            return qsTr("Unsupported");
        }
        if (value === "UnsupportedSource") {
            return qsTr("Unsupported source");
        }
        if (value === "Missing") {
            return qsTr("Missing");
        }
        if (value === "Unreadable") {
            return qsTr("Unreadable");
        }
        if (value === "Unavailable") {
            return qsTr("Unavailable");
        }
        return qsTr("Unknown status");
    }

    function applyStatusLabel(value) {
        return value === "success" ? qsTr("Succeeded") : value === "failed" ? qsTr("Failed") : qsTr(
                                                                                  "Unknown result");
    }

    function rootLabel(path) {
        const parts = path.split("/").filter(part => part !== "");
        return parts.length === 0 ? path : parts[parts.length - 1];
    }

    function formatBytes(bytes) {
        if (bytes >= 1048576) {
            return qsTr("%1 MiB").arg((bytes / 1048576).toFixed(1));
        }
        return qsTr("%1 KiB").arg(Math.max(1, Math.round(bytes / 1024)));
    }

    Component.onCompleted: {
        wallpaper.setPageOpen(true, roots);
        ensureDirectory();
    }
    Component.onDestruction: wallpaper.setPageOpen(false, [])

    Connections {
        target: root.wallpaper

        function onLibraryGenerationChanged() {
            root.ensureDirectory();
        }

        function onApplyStatusChanged() {
            if (root.wallpaper.applyStatus === "partial") {
                root.failureText = qsTr(
                            "Some displays changed and some did not. Review the results below.");
            } else if (root.wallpaper.applyStatus === "failed" || root.wallpaper.applyStatus
                       === "changed") {
                root.failureText = qsTr("The wallpaper was not confirmed on every display.");
            } else if (root.wallpaper.applyStatus === "success") {
                root.failureText = "";
            }
        }
    }

    Connections {
        target: root.settingsModel

        function onSnapshotChanged() {
            if (root.wallpaper.pageOpen) {
                root.wallpaper.refreshLibrary(root.roots);
            }
        }
    }

    FolderDialog {
        id: rootDialog
        title: qsTr("Approve wallpaper folder")
        options: FolderDialog.ReadOnly | FolderDialog.DontResolveSymlinks
        onAccepted: root.addRoot(selectedFolder)
    }

    FileDialog {
        id: browseDialog
        title: qsTr("Preview local image")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("Static images (*.jpg *.jpeg *.png *.webp *.bmp)")]
        options: FileDialog.ReadOnly | FileDialog.DontResolveSymlinks
        onAccepted: {
            root.selectedLibraryId = "";
            root.applyWarningVisible = false;
            if (!root.wallpaper.previewExternal(selectedFile)) {
                root.failureText = qsTr("The selected image could not be validated.");
            }
        }
    }
    Connections {
        target: root.Window.window
        ignoreUnknownSignals: true

        function onActiveFocusItemChanged() {
            const item = target === null ? null : target.activeFocusItem;
            if (item === null) {
                return;
            }
            let ancestor = item;
            while (ancestor !== null && ancestor !== content) {
                ancestor = ancestor.parent;
            }
            if (ancestor !== content) {
                return;
            }
            const origin = item.mapToItem(content, 0, 0);
            const top = origin.y;
            const bottom = top + item.height;
            if (top < root.contentY) {
                root.contentY = Math.max(0, top);
            } else if (bottom > root.contentY + root.height) {
                root.contentY = Math.min(Math.max(0, root.contentHeight - root.height), bottom
                                         - root.height);
            }
        }
    }

    ColumnLayout {
        id: content

        width: Math.max(0, root.width - (root.contentHeight > root.height ? Theme.spacing.md : 0))
        height: Math.max(root.height, implicitHeight)
        spacing: Theme.spacing.md

        ControlCenterPageHeader {
            objectName: "wallpaperPageHeader"
            Layout.fillWidth: true
            iconMeaning: "controlCenterWallpaper"
            title: qsTr("Wallpaper")
            description: qsTr("Browse, preview, and apply a static image for every display.")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.sm

            IslandText {
                Layout.fillWidth: true
                text: root.currentSummary()
                size: "caption"
                color: Theme.color.textSecondary
                wrapMode: Text.Wrap
            }

            IslandButton {
                objectName: "wallpaperBrowseButton"
                label: qsTr("Browse image")
                reducedMotion: root.reducedMotion
                onClicked: browseDialog.open()
            }

            IslandButton {
                objectName: "wallpaperAddRootButton"
                label: qsTr("Add folder")
                reducedMotion: root.reducedMotion
                enabled: root.settingsModel.writable && root.roots.length < 8
                onClicked: rootDialog.open()
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacing.sm
            visible: root.wallpaper.screens.length > 0

            Repeater {
                model: root.wallpaper.screens

                delegate: Rectangle {
                    id: screenChip
                    required property var modelData

                    width: screenStatus.implicitWidth + Theme.spacing.md * 2
                    height: screenStatus.implicitHeight + Theme.spacing.sm * 2
                    radius: Theme.radius.sm
                    color: screenChip.modelData.supported ? Theme.color.surfaceActive :
                                                            Theme.color.controlFill
                    border.width: Theme.size.hairlineWidth
                    border.color: screenChip.modelData.supported ? Theme.snapshot.accent :
                                                                   Theme.color.surfaceBorder

                    IslandText {
                        id: screenStatus
                        anchors.centerIn: parent
                        text: qsTr("%1 · %2").arg(screenChip.modelData.label).arg(
                                  root.screenStatusLabel(screenChip.modelData.status))
                        size: "caption"
                        color: Theme.color.textSecondary
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.sm

            IslandText {
                Layout.fillWidth: true
                text: root.roots.length === 0 ? qsTr(
                                                    "Approve a folder to build the local library. Suggested: Pictures/Wallpapers or /usr/share/wallpapers.") :
                                                root.roots.length + (root.roots.length === 1
                                                                     ? " approved folder" :
                                                                       " approved folders")
                size: "caption"
                tone: "muted"
                wrapMode: Text.Wrap
            }

            IslandText {
                visible: root.wallpaper.libraryScanning
                text: qsTr("Indexing %1 entries…").arg(root.wallpaper.libraryVisited)
                size: "caption"
                color: Theme.snapshot.warning
            }

            IslandText {
                visible: root.wallpaper.libraryTruncated
                text: qsTr("Bound reached")
                size: "caption"
                color: Theme.snapshot.warning
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacing.xs
            visible: root.roots.length > 0

            Repeater {
                model: root.roots

                delegate: IslandButton {
                    required property string modelData

                    label: root.rootLabel(modelData)
                    reducedMotion: root.reducedMotion
                    enabled: root.settingsModel.writable
                    Accessible.description: qsTr("Remove approved folder. Files remain untouched.")
                    onClicked: root.removeRoot(modelData)
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: root.twoColumnWorkspace ? 2 : 1
            columnSpacing: Theme.spacing.md
            rowSpacing: Theme.spacing.md

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 320
                spacing: Theme.spacing.sm

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.sm

                    IslandButton {
                        objectName: "wallpaperDirectoryBack"
                        label: qsTr("Up")
                        reducedMotion: root.reducedMotion
                        enabled: {
                            const directory = root.currentDirectory();
                            return directory !== null && directory.parentId !== "";
                        }
                        onClicked: {
                            const directory = root.currentDirectory();
                            if (directory !== null && directory.parentId !== "") {
                                root.currentDirectoryId = directory.parentId;
                            }
                        }
                    }

                    IslandText {
                        Layout.fillWidth: true
                        text: {
                            const directory = root.currentDirectory();
                            return directory === null ? qsTr("Local library") :
                                                        directory.breadcrumb;
                        }
                        size: "caption"
                        color: Theme.color.textSecondary
                        elide: Text.ElideMiddle
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Rectangle {
                        Layout.preferredWidth: 180
                        Layout.preferredHeight: Theme.size.controlHeightMd
                        radius: Theme.radius.md
                        color: Theme.color.controlFill
                        border.width: Theme.size.hairlineWidth
                        border.color: filterInput.activeFocus ? Theme.snapshot.focusRing :
                                                                Theme.color.surfaceBorder

                        TextInput {
                            id: filterInput
                            objectName: "wallpaperFilterInput"
                            anchors.fill: parent
                            leftPadding: Theme.spacing.md
                            rightPadding: Theme.spacing.md
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.color.textPrimary
                            font.family: Theme.type.familyForItem(this)
                            font.pixelSize: Theme.type.sizeForItem(this, "body")
                            activeFocusOnTab: true
                            clip: true
                            maximumLength: 128
                            Accessible.role: Accessible.EditableText
                            Accessible.name: qsTr("Filter images")
                            Accessible.focused: activeFocus
                            onTextChanged: root.filterText = text
                        }

                        IslandText {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacing.md
                            verticalAlignment: Text.AlignVCenter
                            text: qsTr("Filter images")
                            size: "caption"
                            tone: "muted"
                            visible: filterInput.text === "" && !filterInput.activeFocus
                            Accessible.ignored: true
                        }
                    }
                }

                ListView {
                    id: directoryList
                    Layout.fillWidth: true
                    Layout.preferredHeight: contentHeight > 0 ? Math.min(contentHeight, 88) : 0
                    model: root.childDirectories()
                    orientation: ListView.Horizontal
                    spacing: Theme.spacing.sm
                    clip: true
                    visible: count > 0
                    Accessible.role: Accessible.List
                    Accessible.name: qsTr("Folders")

                    delegate: IslandButton {
                        required property var modelData
                        label: modelData.name
                        reducedMotion: root.reducedMotion
                        Accessible.role: Accessible.ListItem
                        onClicked: root.currentDirectoryId = modelData.id
                    }
                }

                GridView {
                    id: imageGrid
                    objectName: "wallpaperImageGrid"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: root.filteredImages()
                    cellWidth: Math.max(152, Math.floor(width / Math.max(1, Math.floor(width
                                                                                       / 180))))
                    cellHeight: 132
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    keyNavigationEnabled: true
                    Accessible.role: Accessible.List
                    Accessible.name: qsTr("Local wallpaper images")

                    ScrollBar.vertical: ScrollBar {}

                    delegate: FocusScope {
                        id: imageTile
                        required property var modelData
                        width: imageGrid.cellWidth - Theme.spacing.sm
                        height: imageGrid.cellHeight - Theme.spacing.sm
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Preview %1").arg(modelData.name)
                        Accessible.description: qsTr("%1 by %2, %3").arg(modelData.width).arg(
                                                    modelData.height).arg(root.formatBytes(
                                                                              modelData.byteSize))
                        Accessible.focused: activeFocus

                        Component.onCompleted: root.wallpaper.requestThumbnail(modelData.id)
                        Keys.onReturnPressed: event => {
                            root.selectImage(modelData);
                            event.accepted = true;
                        }
                        Keys.onEnterPressed: event => {
                            root.selectImage(modelData);
                            event.accepted = true;
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radius.lg
                            color: Theme.color.controlFill
                            border.width: root.selectedLibraryId === imageTile.modelData.id
                                          || imageTile.activeFocus ? 2 : Theme.size.hairlineWidth
                            border.color: root.selectedLibraryId === imageTile.modelData.id
                                          ? Theme.snapshot.accent : imageTile.activeFocus
                                            ? Theme.snapshot.focusRing : Theme.color.surfaceBorder

                            Image {
                                anchors.fill: parent
                                anchors.margins: Theme.spacing.xs
                                source: {
                                    const revision = root.wallpaper.thumbnailRevision;
                                    return revision >= 0 ? root.wallpaper.thumbnailFor(
                                                               imageTile.modelData.id) : "";
                                }
                                asynchronous: true
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(320, 180)
                                clip: true
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: tileLabel.implicitHeight + Theme.spacing.sm * 2
                                color: Theme.color.surfaceOpaque
                                opacity: 0.92
                                radius: Theme.radius.sm

                                IslandText {
                                    id: tileLabel
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.margins: Theme.spacing.sm
                                    text: imageTile.modelData.name
                                    size: "caption"
                                    color: Theme.color.textPrimary
                                    elide: Text.ElideMiddle
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    imageTile.forceActiveFocus(Qt.MouseFocusReason);
                                    root.selectImage(imageTile.modelData);
                                }
                            }
                        }
                    }

                    IslandText {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, 360)
                        visible: imageGrid.count === 0 && !root.wallpaper.libraryScanning
                        text: root.roots.length === 0 ? qsTr("No approved folders.") :
                                                        root.filterText === "" ? qsTr(
                                                                                     "No static images in this folder.") :
                                                                                 qsTr("No images match this filter.")
                        size: "body"
                        tone: "muted"
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            IslandPanel {
                objectName: "wallpaperPreviewPanel"
                implicitHeight: previewLayout.implicitHeight + Theme.spacing.md * 2
                Layout.fillWidth: true
                Layout.fillHeight: root.twoColumnWorkspace
                Layout.preferredHeight: root.twoColumnWorkspace ? -1 : implicitHeight
                Layout.minimumWidth: 240
                color: Theme.color.controlFill

                ColumnLayout {
                    id: previewLayout
                    anchors.fill: parent
                    anchors.margins: Theme.spacing.md
                    spacing: Theme.spacing.sm

                    IslandText {
                        Layout.fillWidth: true
                        text: qsTr("Preview")
                        size: "body"
                        font.weight: Theme.type.weightSemibold
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 140
                        radius: Theme.radius.lg
                        color: Theme.color.surfaceOpaque
                        border.width: Theme.size.hairlineWidth
                        border.color: Theme.color.surfaceBorder

                        Image {
                            anchors.fill: parent
                            anchors.margins: Theme.spacing.xs
                            source: root.previewReady ? root.wallpaper.preview.thumbnail : ""
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            sourceSize: Qt.size(320, 180)
                        }

                        IslandText {
                            anchors.centerIn: parent
                            width: parent.width - Theme.spacing.xl * 2
                            visible: !root.previewReady
                            text: root.wallpaper.preview !== null && root.wallpaper.preview.status
                                  === "loading" ? qsTr("Analyzing image…") : qsTr(
                                                      "Select or browse a static image.")
                            size: "body"
                            tone: "muted"
                            wrapMode: Text.Wrap
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    ColumnLayout {
                        objectName: "wallpaperPreviewMetadata"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        visible: root.previewReady
                        spacing: Theme.spacing.xs

                        Item {
                            id: previewNameFrame

                            readonly property real boundedNameHeight: Math.min(
                                                                          previewName.implicitHeight,
                                                                          Theme.size.controlHeightLg
                                                                          * 2)

                            objectName: "wallpaperPreviewNameFrame"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredHeight: boundedNameHeight
                            Layout.minimumHeight: boundedNameHeight
                            Layout.maximumHeight: Theme.size.controlHeightLg * 2

                            Flickable {
                                id: previewNameViewport

                                objectName: "wallpaperPreviewNameViewport"
                                anchors.fill: parent
                                contentWidth: width
                                contentHeight: previewName.height
                                flickableDirection: Flickable.VerticalFlick
                                boundsBehavior: Flickable.StopAtBounds
                                interactive: contentHeight > height + 0.5
                                clip: true
                                focusPolicy: interactive ? Qt.StrongFocus : Qt.NoFocus
                                activeFocusOnTab: interactive
                                Accessible.role: interactive ? Accessible.Pane :
                                                               Accessible.StaticText
                                Accessible.name: previewName.text
                                Accessible.description: interactive ? qsTr(
                                                                          "Scrollable filename. Use Up, Down, Page Up, Page Down, Home, or End.") :
                                                                      ""
                                Accessible.focused: activeFocus
                                Keys.priority: Keys.BeforeItem
                                Keys.onPressed: event => event.accepted = handleScrollKey(event.key)

                                function handleScrollKey(key) {
                                    if (!interactive) {
                                        return false;
                                    }
                                    if (key === Qt.Key_Up) {
                                        scrollBy(-Theme.spacing.lg);
                                    } else if (key === Qt.Key_Down) {
                                        scrollBy(Theme.spacing.lg);
                                    } else if (key === Qt.Key_PageUp) {
                                        scrollBy(-pageStep());
                                    } else if (key === Qt.Key_PageDown) {
                                        scrollBy(pageStep());
                                    } else if (key === Qt.Key_Home) {
                                        contentY = 0;
                                    } else if (key === Qt.Key_End) {
                                        contentY = maximumContentY();
                                    } else {
                                        return false;
                                    }
                                    return true;
                                }

                                function maximumContentY() {
                                    return Math.max(0, contentHeight - height);
                                }

                                function pageStep() {
                                    return Math.max(Theme.spacing.lg, height - Theme.spacing.sm);
                                }

                                function scrollBy(delta) {
                                    contentY = Math.max(0, Math.min(maximumContentY(), contentY
                                                                    + delta));
                                }

                                ScrollBar.vertical: ScrollBar {
                                    policy: ScrollBar.AsNeeded
                                }

                                IslandText {
                                    id: previewName

                                    objectName: "wallpaperPreviewName"
                                    width: Math.max(0, previewNameViewport.width - Theme.spacing.sm)
                                    text: root.previewReady ? root.wallpaper.preview.name : ""
                                    size: "caption"
                                    color: Theme.color.textSecondary
                                    wrapMode: Text.WrapAnywhere
                                    Accessible.ignored: true
                                    onTextChanged: previewNameViewport.contentY = 0
                                }
                            }

                            IslandFocusRing {
                                visible: previewNameViewport.activeFocus
                                controlRadius: Theme.radius.sm
                            }
                        }

                        IslandText {
                            objectName: "wallpaperPreviewDetails"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: root.previewReady ? qsTr("%1×%2 · %3").arg(
                                                          root.wallpaper.preview.width).arg(
                                                          root.wallpaper.preview.height).arg(
                                                          root.formatBytes(
                                                              root.wallpaper.preview.byteSize)) : ""
                            size: "caption"
                            color: Theme.color.textSecondary
                            wrapMode: Text.Wrap
                            Accessible.name: text
                        }
                    }

                    IslandText {
                        Layout.fillWidth: true
                        visible: root.previewReady && root.wallpaper.preview.outsideLibrary
                        text: qsTr(
                                  "Previewed outside approved folders. Its directory will not be added or copied.")
                        size: "caption"
                        tone: "muted"
                        wrapMode: Text.Wrap
                    }

                    IslandText {
                        Layout.fillWidth: true
                        visible: root.applyWarningVisible
                        text: qsTr(
                                  "Apply will replace unsupported or slideshow wallpapers with this static image on every active display.")
                        size: "caption"
                        color: Theme.snapshot.warning
                        wrapMode: Text.Wrap
                    }

                    GridLayout {
                        id: previewActions

                        objectName: "wallpaperPreviewActions"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        columns: stackActions ? 1 : 2
                        columnSpacing: Theme.spacing.sm
                        rowSpacing: Theme.spacing.sm

                        readonly property real inlineImplicitWidth:
                        applyButton.implicitContentWidth + clearButton.implicitContentWidth
                        + Theme.spacing.md * 4 + columnSpacing
                        readonly property bool stackActions: width + 0.5 < inlineImplicitWidth

                        IslandButton {
                            id: applyButton

                            objectName: "wallpaperApplyButton"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            leftPadding: previewActions.stackActions ? Theme.spacing.sm :
                                                                       Theme.spacing.md
                            rightPadding: leftPadding
                            label: root.operationPending ? qsTr("Applying…") :
                                                           root.applyWarningVisible ? qsTr(
                                                                                          "Confirm Apply") :
                                                                                      qsTr("Apply everywhere")
                            variant: "accent"
                            reducedMotion: root.reducedMotion
                            enabled: root.previewReady && !root.operationPending
                            Accessible.description: qsTr(
                                                        "Apply the selected image to every active display")
                            onClicked: root.requestApply()
                        }

                        IslandButton {
                            id: clearButton

                            objectName: "wallpaperClearButton"
                            Layout.fillWidth: previewActions.stackActions
                            Layout.minimumWidth: 0
                            leftPadding: previewActions.stackActions ? Theme.spacing.sm :
                                                                       Theme.spacing.md
                            rightPadding: leftPadding
                            label: qsTr("Clear")
                            reducedMotion: root.reducedMotion
                            enabled: root.wallpaper.preview !== null && !root.operationPending
                            onClicked: {
                                root.selectedLibraryId = "";
                                root.applyWarningVisible = false;
                                root.wallpaper.cancelPreview();
                            }
                        }
                    }

                    Repeater {
                        model: root.wallpaper.applyResults

                        delegate: IslandText {
                            required property var modelData
                            Layout.fillWidth: true
                            text: qsTr("%1 · %2").arg(modelData.label).arg(root.applyStatusLabel(
                                                                               modelData.status))
                            size: "caption"
                            color: modelData.status === "success" ? Theme.snapshot.success :
                                                                    Theme.snapshot.danger
                        }
                    }

                    IslandText {
                        Layout.fillWidth: true
                        visible: root.failureText !== ""
                        text: root.failureText
                        size: "caption"
                        color: Theme.snapshot.danger
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}

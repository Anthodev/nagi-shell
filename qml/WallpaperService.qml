pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

// One normalized JSON-lines boundary for current wallpaper observation, the local
// library, preview analysis, and explicit all-display apply. Source paths and
// digests never enter public properties or diagnostics.
Scope {
    id: root

    required property string helperPath

    readonly property int generation: state.currentGeneration
    readonly property bool available: state.currentAvailable
    readonly property string status: state.currentStatus
    readonly property string accent: state.currentAccent
    readonly property bool multiple: state.currentMultiple
    readonly property bool unsupported: state.currentUnsupported
    readonly property var screens: state.currentScreens
    readonly property int libraryGeneration: state.libraryGeneration
    readonly property string libraryStatus: state.libraryStatus
    readonly property bool libraryScanning: state.libraryScanning
    readonly property bool libraryTruncated: state.libraryTruncated
    readonly property int libraryVisited: state.libraryVisited
    readonly property int libraryElapsedMs: state.libraryElapsedMs
    readonly property var directories: state.directories
    readonly property var images: state.images
    readonly property int thumbnailRevision: state.thumbnailRevision
    readonly property var preview: state.preview
    readonly property int previewGeneration: state.previewGeneration
    readonly property string applyStatus: state.applyStatus
    readonly property bool applySuccess: state.applySuccess
    readonly property bool applyPartial: state.applyPartial
    readonly property var applyResults: state.applyResults
    readonly property bool helperRunning: helper.running
    readonly property bool pageOpen: state.pageOpen
    readonly property int activeTimerCount: operationWatchdog.running ? 1 : 0

    function setPageOpen(open, roots) {
        if (typeof open !== "boolean" || !Array.isArray(roots) || roots.length > 8) {
            return false;
        }
        for (let index = 0; index < roots.length; index += 1) {
            if (typeof roots[index] !== "string" || !roots[index].startsWith("/")
                    || roots[index].length > 1024) {
                return false;
            }
        }
        state.pageOpen = open;
        state.approvedRoots = roots.slice();
        if (!open) {
            state.clearPageState();
        }
        return send({
                        "op": "interest",
                        "active": open,
                        "roots": open ? roots : []
                    });
    }

    function refreshLibrary(roots) {
        return state.pageOpen && setPageOpen(true, roots);
    }

    function requestThumbnail(identity) {
        if (!state.pageOpen || typeof identity !== "string" || !/^i[0-9a-f]{24}$/.test(identity)
                || state.thumbnailRequested[identity] === true || state.thumbnails[identity]
                !== undefined) {
            return false;
        }
        state.thumbnailRequested[identity] = true;
        return send({
                        "op": "thumbnail",
                        "id": identity
                    });
    }

    function thumbnailFor(identity) {
        const value = state.thumbnails[identity];
        return typeof value === "string" ? value : "";
    }

    function previewImage(identity) {
        if (!state.pageOpen || typeof identity !== "string" || !/^i[0-9a-f]{24}$/.test(identity)) {
            return false;
        }
        return send({
                        "op": "preview",
                        "id": identity
                    });
    }

    function previewExternal(selectedFile) {
        if (!state.pageOpen) {
            return false;
        }
        const value = String(selectedFile);
        if (!value.startsWith("file:///") || value.length > 8192 || value.indexOf("%00") !== -1) {
            return false;
        }
        let path;
        try {
            path = decodeURIComponent(value.slice(7));
        } catch (error) {
            return false;
        }
        if (!path.startsWith("/") || path.length > 4096) {
            return false;
        }
        return send({
                        "op": "preview-path",
                        "path": path
                    });
    }

    function applyPreview() {
        return state.pageOpen && state.preview !== null && state.preview.status === "ready" && send(
                    {
                        "op": "apply",
                        "id": state.preview.id
                    });
    }

    function cancelPreview() {
        state.preview = null;
        return send({
                        "op": "cancel-preview"
                    });
    }

    function send(command) {
        if (!helper.running || command === null || typeof command !== "object") {
            return false;
        }
        const line = JSON.stringify(command);
        if (line.length > state.maximumCommandLength) {
            return false;
        }
        helper.write(line + "\n");
        return true;
    }

    QtObject {
        id: state

        readonly property int maximumLineLength: 1048576
        readonly property int maximumCommandLength: 16384
        readonly property int maximumDiagnostics: 4
        property int currentGeneration: 0
        property bool currentAvailable: false
        property string currentStatus: "Unavailable"
        property string currentAccent: ""
        property bool currentMultiple: false
        property bool currentUnsupported: false
        property var currentScreens: Object.freeze([])
        property int libraryGeneration: 0
        property string libraryStatus: "idle"
        property bool libraryScanning: false
        property bool libraryTruncated: false
        property int libraryVisited: 0
        property int libraryElapsedMs: 0
        property var directories: Object.freeze([])
        property var images: Object.freeze([])
        property var thumbnails: ({})
        property var thumbnailRequested: ({})
        property int thumbnailRevision: 0
        property var preview: null
        property int previewGeneration: 0
        property int applyGeneration: 0
        property string applyStatus: "idle"
        property bool applySuccess: false
        property bool applyPartial: false
        property var applyResults: Object.freeze([])
        property bool pageOpen: false
        property var approvedRoots: []
        property int diagnosticCount: 0
        property int restartCount: 0
        property bool restartAllowed: true

        function acceptLine(line) {
            if (typeof line !== "string" || line.length === 0 || line.length > maximumLineLength) {
                warnBounded("invalid response length");
                return;
            }
            let candidate;
            try {
                candidate = JSON.parse(line);
            } catch (error) {
                warnBounded("malformed response");
                return;
            }
            if (candidate === null || typeof candidate !== "object" || Array.isArray(candidate)
                    || typeof candidate.type !== "string") {
                warnBounded("invalid response schema");
                return;
            }
            if (candidate.type === "current") {
                acceptCurrent(candidate);
            } else if (candidate.type === "library") {
                acceptLibrary(candidate);
            } else if (candidate.type === "thumbnail") {
                acceptThumbnail(candidate);
            } else if (candidate.type === "preview") {
                acceptPreview(candidate);
            } else if (candidate.type === "apply") {
                acceptApply(candidate);
            } else {
                warnBounded("unknown response type");
            }
        }

        function acceptCurrent(candidate) {
            if (!validGeneration(candidate.generation, currentGeneration)
                    || typeof candidate.available !== "boolean" || !validCurrentStatus(
                        candidate.status) || typeof candidate.multiple !== "boolean"
                    || typeof candidate.unsupported !== "boolean" || typeof candidate.accent
                    !== "string" || !Array.isArray(candidate.screens) || candidate.screens.length
                    < 1 || candidate.screens.length > 16) {
                warnBounded("invalid current snapshot");
                return;
            }
            if (candidate.available ? candidate.status !== "Ready" || !/^#[0-9A-F]{6}$/.test(
                                          candidate.accent) : candidate.accent !== "") {
                warnBounded("inconsistent current snapshot");
                return;
            }
            const normalizedScreens = [];
            for (let index = 0; index < candidate.screens.length; index += 1) {
                const screen = candidate.screens[index];
                if (screen === null || typeof screen !== "object" || typeof screen.label
                        !== "string" || screen.label.length < 1 || screen.label.length > 32 || !validScreenStatus(
                            screen.status) || typeof screen.supported !== "boolean") {
                    warnBounded("invalid display summary");
                    return;
                }
                normalizedScreens.push(Object.freeze({
                                                         "label": screen.label,
                                                         "status": screen.status,
                                                         "supported": screen.supported
                                                     }));
            }
            currentAvailable = candidate.available;
            currentStatus = candidate.status;
            currentAccent = candidate.accent;
            currentMultiple = candidate.multiple;
            currentUnsupported = candidate.unsupported;
            currentScreens = Object.freeze(normalizedScreens);
            Theme.wallpaperPalette = candidate.available ? Object.freeze({
                                                                             "accent": candidate.accent
                                                                         }) : null;
            currentGeneration = candidate.generation;
        }

        function acceptLibrary(candidate) {
            if (!pageOpen || !validGeneration(candidate.generation, libraryGeneration) ||
                    !validLibraryStatus(candidate.status) || typeof candidate.scanning
                    !== "boolean" || typeof candidate.truncated !== "boolean" || !Number.isInteger(
                        candidate.visited) || candidate.visited < 0 || candidate.visited > 4096 ||
                    !Number.isInteger(candidate.elapsedMs) || candidate.elapsedMs < 0
                    || candidate.elapsedMs > 30000 || !Array.isArray(candidate.directories)
                    || candidate.directories.length > 512 || !Array.isArray(candidate.images)
                    || candidate.images.length > 512) {
                warnBounded("invalid library snapshot");
                return;
            }
            const normalizedDirectories = [];
            const directoryIds = {};
            for (let index = 0; index < candidate.directories.length; index += 1) {
                const directory = normalizeDirectory(candidate.directories[index]);
                if (directory === null || directoryIds[directory.id] === true) {
                    warnBounded("invalid directory projection");
                    return;
                }
                directoryIds[directory.id] = true;
                normalizedDirectories.push(Object.freeze(directory));
            }
            const normalizedImages = [];
            const imageIds = {};
            for (let index = 0; index < candidate.images.length; index += 1) {
                const image = normalizeImage(candidate.images[index]);
                if (image === null || imageIds[image.id] === true || directoryIds[image.directoryId]
                        !== true) {
                    warnBounded("invalid image projection");
                    return;
                }
                imageIds[image.id] = true;
                normalizedImages.push(Object.freeze(image));
            }
            libraryStatus = candidate.status;
            libraryScanning = candidate.scanning;
            libraryTruncated = candidate.truncated;
            libraryVisited = candidate.visited;
            libraryElapsedMs = candidate.elapsedMs;
            directories = Object.freeze(normalizedDirectories);
            images = Object.freeze(normalizedImages);
            libraryGeneration = candidate.generation;
            if (!candidate.scanning) {
                operationWatchdog.stop();
            }
        }

        function acceptThumbnail(candidate) {
            if (!pageOpen || typeof candidate.id !== "string" || !/^i[0-9a-f]{24}$/.test(
                        candidate.id) || (candidate.status !== "ready" && candidate.status
                                          !== "failed" && candidate.status !== "timeout")
                    || typeof candidate.data !== "string" || candidate.data.length > 524288 || (
                        candidate.status === "ready" && !candidate.data.startsWith(
                            "data:image/png;base64,")) || (candidate.status !== "ready"
                                                           && candidate.data !== "")) {
                warnBounded("invalid thumbnail response");
                return;
            }
            delete thumbnailRequested[candidate.id];
            if (candidate.status === "ready") {
                thumbnails[candidate.id] = candidate.data;
                thumbnailRevision += 1;
            }
        }

        function acceptPreview(candidate) {
            if (!pageOpen || !validGeneration(candidate.generation, previewGeneration) ||
                    !validPreviewStatus(candidate.status)) {
                warnBounded("invalid preview response");
                return;
            }
            if (candidate.status === "loading") {
                preview = Object.freeze({
                                            "status": "loading"
                                        });
                previewGeneration = candidate.generation;
                operationWatchdog.restart();
                return;
            }
            if (candidate.status !== "ready") {
                preview = Object.freeze({
                                            "status": candidate.status
                                        });
                previewGeneration = candidate.generation;
                operationWatchdog.stop();
                return;
            }
            if (typeof candidate.id !== "string" || !/^c[0-9a-f]{24}$/.test(candidate.id)
                    || typeof candidate.name !== "string" || candidate.name.length < 1
                    || candidate.name.length > 255 || typeof candidate.thumbnail !== "string"
                    || candidate.thumbnail.length > 524288 || !candidate.thumbnail.startsWith(
                        "data:image/png;base64,") || typeof candidate.accent !== "string" || (
                        candidate.accent !== "" && !/^#[0-9A-F]{6}$/.test(candidate.accent)) ||
                    !validDimension(candidate.width) || !validDimension(candidate.height) ||
                    !Number.isInteger(candidate.byteSize) || candidate.byteSize < 1
                    || candidate.byteSize > 33554432 || typeof candidate.outsideLibrary
                    !== "boolean") {
                warnBounded("invalid ready preview");
                return;
            }
            preview = Object.freeze({
                                        "status": "ready",
                                        "id": candidate.id,
                                        "name": candidate.name,
                                        "thumbnail": candidate.thumbnail,
                                        "accent": candidate.accent,
                                        "width": candidate.width,
                                        "height": candidate.height,
                                        "byteSize": candidate.byteSize,
                                        "outsideLibrary": candidate.outsideLibrary
                                    });
            previewGeneration = candidate.generation;
            operationWatchdog.stop();
        }

        function acceptApply(candidate) {
            if (!pageOpen || !validGeneration(candidate.generation, applyGeneration) ||
                    !validApplyStatus(candidate.status)) {
                warnBounded("invalid apply response");
                return;
            }
            if (candidate.status === "pending") {
                state.applySuccess = false;
                state.applyPartial = false;
                state.applyResults = Object.freeze([]);
                state.applyGeneration = candidate.generation;
                state.applyStatus = "pending";
                operationWatchdog.restart();
                return;
            }
            if (typeof candidate.success !== "boolean" || typeof candidate.partial !== "boolean"
                    || typeof candidate.rollbackAttempted !== "boolean" || !Array.isArray(
                        candidate.results) || candidate.results.length > 16) {
                warnBounded("invalid apply result");
                return;
            }
            const normalized = [];
            for (let index = 0; index < candidate.results.length; index += 1) {
                const result = candidate.results[index];
                if (result === null || typeof result !== "object" || typeof result.label
                        !== "string" || result.label.length < 1 || result.label.length > 32 || (
                            result.status !== "success" && result.status !== "failed")) {
                    warnBounded("invalid display apply result");
                    return;
                }
                normalized.push(Object.freeze({
                                                  "label": result.label,
                                                  "status": result.status
                                              }));
            }
            state.applySuccess = candidate.success;
            state.applyPartial = candidate.partial;
            state.applyResults = Object.freeze(normalized);
            state.applyGeneration = candidate.generation;
            state.applyStatus = candidate.status;
            operationWatchdog.stop();
        }

        function normalizeDirectory(candidate) {
            if (candidate === null || typeof candidate !== "object" || typeof candidate.id
                    !== "string" || !/^d[0-9a-f]{24}$/.test(candidate.id)
                    || typeof candidate.parentId !== "string" || (candidate.parentId !== "" && !
                                                                  /^d[0-9a-f]{24}$/.test(
                                                                      candidate.parentId))
                    || typeof candidate.rootId !== "string" || !/^d[0-9a-f]{24}$/.test(
                        candidate.rootId) || typeof candidate.name !== "string"
                    || candidate.name.length < 1 || candidate.name.length > 255
                    || typeof candidate.breadcrumb !== "string" || candidate.breadcrumb.length < 1
                    || candidate.breadcrumb.length > 2048) {
                return null;
            }
            return {
                "id": candidate.id,
                "parentId": candidate.parentId,
                "rootId": candidate.rootId,
                "name": candidate.name,
                "breadcrumb": candidate.breadcrumb
            };
        }

        function normalizeImage(candidate) {
            if (candidate === null || typeof candidate !== "object" || typeof candidate.id
                    !== "string" || !/^i[0-9a-f]{24}$/.test(candidate.id)
                    || typeof candidate.directoryId !== "string" || !/^d[0-9a-f]{24}$/.test(
                        candidate.directoryId) || typeof candidate.name !== "string"
                    || candidate.name.length < 1 || candidate.name.length > 255 || !Number.isInteger(
                        candidate.byteSize) || candidate.byteSize < 1 || candidate.byteSize
                    > 33554432 || !Number.isInteger(candidate.modifiedMs) || candidate.modifiedMs
                    < 0 || !validDimension(candidate.width) || !validDimension(candidate.height)) {
                return null;
            }
            return {
                "id": candidate.id,
                "directoryId": candidate.directoryId,
                "name": candidate.name,
                "byteSize": candidate.byteSize,
                "modifiedMs": candidate.modifiedMs,
                "width": candidate.width,
                "height": candidate.height
            };
        }

        function validGeneration(value, previous) {
            return Number.isInteger(value) && value > previous && value <= 2147483647;
        }

        function validDimension(value) {
            return Number.isInteger(value) && value > 0 && value <= 131072;
        }

        function validCurrentStatus(value) {
            return value === "Ready" || value === "Multiple" || value === "UnsupportedPlugin"
                    || value === "UnsupportedSource" || value === "Missing" || value
                    === "Unreadable" || value === "Unavailable";
        }

        function validScreenStatus(value) {
            return value === "Ready" || value === "UnsupportedPlugin" || value
                    === "UnsupportedSource" || value === "Missing" || value === "Unreadable"
                    || value === "Unavailable";
        }

        function validLibraryStatus(value) {
            return value === "idle" || value === "indexing" || value === "empty" || value
                    === "ready" || value === "truncated" || value === "cancelled" || value
                    === "invalid-roots";
        }

        function validPreviewStatus(value) {
            return value === "loading" || value === "ready" || value === "failed" || value
                    === "invalid" || value === "timeout";
        }

        function validApplyStatus(value) {
            return value === "pending" || value === "success" || value === "partial" || value
                    === "failed" || value === "invalid" || value === "changed";
        }

        function clearPageState() {
            state.libraryGeneration = 0;
            state.libraryStatus = "idle";
            state.libraryScanning = false;
            state.libraryTruncated = false;
            state.libraryVisited = 0;
            state.libraryElapsedMs = 0;
            state.directories = Object.freeze([]);
            state.images = Object.freeze([]);
            state.thumbnails = ({});
            state.thumbnailRequested = ({});
            state.thumbnailRevision += 1;
            state.preview = null;
            state.previewGeneration = 0;
            state.applyGeneration = 0;
            state.applyStatus = "idle";
            state.applySuccess = false;
            state.applyPartial = false;
            state.applyResults = Object.freeze([]);
            operationWatchdog.stop();
        }

        function publishUnavailable() {
            currentAvailable = false;
            currentStatus = "Unavailable";
            currentAccent = "";
            currentMultiple = false;
            currentUnsupported = false;
            currentScreens = Object.freeze([]);
            currentGeneration = 0;
            Theme.wallpaperPalette = null;
        }

        function warnBounded(message) {
            if (diagnosticCount >= maximumDiagnostics) {
                return;
            }
            diagnosticCount += 1;
            console.warn("Wallpaper service: " + message);
        }

        function restartHelper() {
            if (restartCount >= 2 || root.helperPath === "") {
                return;
            }
            restartCount += 1;
            restartAllowed = false;
            restartDelay.restart();
        }
    }

    Process {
        id: helper

        command: [root.helperPath]
        stdinEnabled: true
        running: root.helperPath !== "" && state.restartAllowed

        stdout: SplitParser {
            onRead: data => state.acceptLine(data)
        }

        stderr: SplitParser {
            onRead: data => state.warnBounded("helper diagnostic suppressed")
        }

        onStarted: {
            state.restartCount = 0;
            if (state.pageOpen) {
                root.send({
                              "op": "interest",
                              "active": true,
                              "roots": state.approvedRoots
                          });
            }
        }

        onExited: {
            state.publishUnavailable();
            if (state.pageOpen) {
                state.clearPageState();
            }
            state.warnBounded("helper exited");
            state.restartHelper();
        }
    }

    Timer {
        id: operationWatchdog
        interval: 4000
        repeat: false
        onTriggered: {
            state.warnBounded("page operation timed out");
            state.restartHelper();
        }
    }

    Timer {
        id: restartDelay
        interval: 120
        repeat: false
        onTriggered: state.restartAllowed = true
    }

    Component.onDestruction: {
        if (helper.running) {
            helper.write("{\"op\":\"shutdown\"}\n");
        }
        helper.running = false;
        Theme.wallpaperPalette = null;
    }
}

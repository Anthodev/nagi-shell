import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    property string configuredHelperPath: ""
    property bool libraryRequested: false
    property bool thumbnailObserved: false
    property bool recoveryMode: false

    function startWhenThemeReady() {
        if (configuredHelperPath === "" && Theme.snapshot.source === "configured") {
            configuredHelperPath = Quickshell.env("NAGI_WALLPAPER_HELPER") ?? "";
        }
    }

    function fail(message) {
        console.error("FAIL: " + message);
        Qt.exit(1);
        throw new Error(message);
    }

    function require(condition, message) {
        if (!condition) {
            fail(message);
        }
    }

    Component.onCompleted: Qt.callLater(test.startWhenThemeReady)

    Connections {
        target: Theme

        function onSnapshotChanged() {
            test.startWhenThemeReady();
        }
    }

    WallpaperService {
        id: service

        helperPath: test.configuredHelperPath

        onGenerationChanged: {
            if (test.recoveryMode) {
                if (generation === 1) {
                    test.require(available && helperRunning,
                                 "helper crash restarts observation without crashing the shell");
                    Qt.callLater(test.finish);
                }
                return;
            }
            if (generation === 1) {
                test.require(available && status === "Ready" && accent === "#D94A38"
                             && screens.length === 1,
                             "common Ready state is normalized without exposing its source path");
                test.require(Theme.wallpaperPalette !== null
                             && Theme.wallpaperPalette.accent === "#D94A38"
                             && Theme.snapshot.source === "wallpaper",
                             "confirmed current state alone publishes the wallpaper accent");
            } else if (generation === 2) {
                test.require(!available && status === "UnsupportedPlugin" && unsupported,
                             "unsupported plugin state remains explicit");
                test.require(Theme.wallpaperPalette === null && Theme.snapshot.source === "configured",
                             "unsupported state restores the configured fallback");
            } else if (generation === 3) {
                test.require(available && status === "Ready" && accent === "#1E6FD9",
                             "later confirmed current state replaces the palette atomically");
                test.require(setPageOpen(true, []), "page interest starts explicitly");
            } else {
                test.fail("unexpected current generation");
            }
        }

        onLibraryGenerationChanged: {
            if (libraryGeneration === 1 && libraryStatus === "ready") {
                test.require(directories.length === 1 && images.length === 1
                             && images[0].name === "fixture.png",
                             "bounded library and metadata projection is normalized");
                test.libraryRequested = true;
                test.require(requestThumbnail(images[0].id),
                             "thumbnail decoding is requested lazily for a visible image");
                test.require(previewImage(images[0].id),
                             "selection dispatches only the opaque image identity");
            }
        }

        onThumbnailRevisionChanged: {
            if (libraryRequested && thumbnailFor("i000000000000000000000000").startsWith(
                        "data:image/png;base64,")) {
                test.thumbnailObserved = true;
            }
        }

        onPreviewGenerationChanged: {
            if (preview !== null && preview.status === "ready") {
                test.require(preview.name === "fixture.png" && preview.accent === "#AA55CC",
                             "preview exposes bounded metadata and candidate state");
                test.require(Theme.snapshot.wallpaperAccent === "#1E6FD9"
                             && Theme.snapshot.source === "wallpaper",
                             "preview analysis never recolors production Theme");
                test.require(applyPreview(), "Apply dispatches the current opaque preview candidate");
            }
        }

        onApplyStatusChanged: {
            if (applyStatus === "partial") {
                test.require(!applySuccess && applyPartial && applyResults.length === 2
                             && applyResults[0].status === "success"
                             && applyResults[1].status === "failed",
                             "partial readback can never masquerade as global success");
                test.require(test.thumbnailObserved, "lazy thumbnail response reached the view model");
                Qt.callLater(function () {
                    test.require(service.setPageOpen(false, []),
                                 "closing page unloads helper interest");
                    test.recoveryMode = true;
                    test.require(service.send({
                                                  "op": "crash"
                                              }),
                                 "controlled codec-process crash is dispatched");
                });
            }
        }
    }

    function runInterestSoak() {
        for (let cycle = 0; cycle < 50; cycle += 1) {
            require(service.setPageOpen(true, []), "wallpaper soak opens page interest");
            require(service.setPageOpen(false, []), "wallpaper soak closes page interest");
            require(!service.pageOpen && service.images.length === 0 && service.preview === null
                    && service.applyStatus === "idle" && service.activeTimerCount === 0,
                    "wallpaper soak cancels page-owned work exactly");
        }
    }

    function finish() {
        runInterestSoak();
        require(test.recoveryMode && service.helperRunning && !service.pageOpen
                && service.images.length === 0 && service.preview === null
                && service.applyStatus === "idle" && service.activeTimerCount === 0,
                "closed page and recovered helper retain no page-owned work");
        console.log("wallpaper QML tests passed");
        Qt.exit(0);
    }

    Timer {
        interval: 10000
        running: true
        onTriggered: test.fail("wallpaper QML test timed out")
    }
}

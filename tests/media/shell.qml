import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick
import "qml"

ShellRoot {
    id: test

    property var calls: []
    property string artPath: Quickshell.cacheDir + "/media-test-art-" + Quickshell.processId + ".bmp"
    property string artUrl: "file://" + artPath

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    // Transport-call records live here so fake player method closures reach
    // the original array even though QML copies plain objects across var
    // properties.
    function recordCall(player, action, argument) {
        test.calls.push({
                            "dbusName": player.dbusName,
                            "action": action,
                            "argument": argument
                        });
    }

    function makePlayer(overrides) {
        const properties = {};
        for (const key in overrides) {
            properties[key] = overrides[key];
        }

        return playerFactory.createObject(test, properties);
    }

    // Each adapter observes its own injectable model; production uses
    // Mpris.players instead.
    function makeAdapter(overrides) {
        const model = modelFactory.createObject(test);
        const properties = {
            "playersModel": model
        };
        for (const key in overrides) {
            properties[key] = overrides[key];
        }

        return {
            "adapter": mediaFactory.createObject(test, properties),
            "model": model
        };
    }

    function apply(bundle, mutation) {
        mutation();
        bundle.adapter.processPendingChanges();
    }

    function setPlayers(bundle, players) {
        bundle.model.values = players.slice();
        bundle.adapter.processPendingChanges();
    }

    function destroyBundle(bundle) {
        bundle.adapter.destroy();
        bundle.model.destroy();
    }

    // Bounded wait for asynchronous decoder state.
    function waitFor(predicate, continuation, message) {
        settleTimer.predicate = predicate;
        settleTimer.continuation = continuation;
        settleTimer.message = message;
        settleTimer.attemptsLeft = 200;
        settleTimer.restart();
    }

    function bmpCharacter(value) {
        return String.fromCharCode(value);
    }

    // A valid 1x1 24-bit BMP built only from bytes <= 0x7f so it survives a
    // UTF-8 text write unchanged.
    function bmpImage() {
        const header = [0x42, 0x4d, 58, 0, 0, 0, 0, 0, 0, 0, 54, 0, 0, 0, 40, 0, 0,
            0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 24, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0x13,
            0x0b, 0, 0, 0x13, 0x0b, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        const pixels = [0x41, 0x42, 0x43, 0];
        let text = "";
        for (let i = 0; i < header.length; ++i) {
            text += bmpCharacter(header[i]);
        }

        for (let j = 0; j < pixels.length; ++j) {
            text += bmpCharacter(pixels[j]);
        }

        return text;
    }

    Component {
        id: playerFactory

        QtObject {
            signal trackChanged
            signal postTrackChanged
            property string dbusName: ""
            property string identity: ""
            property string desktopEntry: ""
            property int uniqueId: 0
            property string trackTitle: ""
            property string trackArtist: ""
            property string trackAlbum: ""
            property string trackArtUrl: ""
            property int playbackState: MprisPlaybackState.Stopped
            property real position: 0
            property bool positionSupported: false
            property real length: 0
            property bool lengthSupported: false
            property bool canControl: true
            property bool canGoPrevious: false
            property bool canGoNext: false
            property bool canTogglePlaying: false
            property bool canSeek: false

            function previous() {
                test.recordCall(this, "previous", null);
            }

            function next() {
                test.recordCall(this, "next", null);
            }

            function togglePlaying() {
                test.recordCall(this, "togglePlaying", null);
            }

            function seek(offset) {
                test.recordCall(this, "seek", offset);
            }
        }
    }

    Component {
        id: modelFactory

        QtObject {
            property var values: []
        }
    }

    Component {
        id: mediaFactory

        MediaAdapter {}
    }

    Timer {
        id: settleTimer

        interval: 20
        repeat: false
        property var predicate: null
        property var continuation: null
        property string message: ""
        property int attemptsLeft: 0

        onTriggered: {
            if (predicate !== null && predicate()) {
                const continuation = settleTimer.continuation;
                settleTimer.predicate = null;
                settleTimer.continuation = null;
                continuation();
                return;
            }

            if (settleTimer.attemptsLeft > 0) {
                settleTimer.attemptsLeft -= 1;
                settleTimer.restart();
                return;
            }

            test.require(false, "condition did not settle: " + settleTimer.message);
        }
    }

    FileView {
        id: artFile

        path: test.artPath
        blockWrites: true
        printErrors: false
    }

    function runUnavailableStage() {
        console.warn("media: unavailable stage");
        const bundle = makeAdapter({});
        require(!bundle.adapter.available && bundle.adapter.selectedGeneration === 0,
                "an empty session exposes no selected player");
        require(bundle.adapter.trackKey === "" && !bundle.adapter.positionTimerRunning,
                "unavailable media carries no track key and no position timer");
        require(bundle.adapter.position === null && bundle.adapter.duration === null,
                "unsupported timing stays null");
        require(bundle.adapter.artworkStatus === "empty" && bundle.adapter.artworkRequest === "",
                "compact unavailable media performs no artwork work");
        require(bundle.adapter.trackedPlayerCount === 0 && bundle.adapter.failure === "none"
                && bundle.adapter.pendingAction === "none",
                "unavailable media tracks nothing and reports no failure");
        require(bundle.adapter.previous() === "rejected" && bundle.adapter.failure === "unavailable",
                "transport dispatch without a player is locally rejected");
        bundle.adapter.dispatchDeadlineReached();
        require(bundle.adapter.failure === "none",
                "the bounded failure clears at its deadline");
        destroyBundle(bundle);
        runSelectionStages();
    }

    function runSelectionStages() {
        console.warn("media: selection stages");
        const bundle = makeAdapter({});
        const alpha = makePlayer({
                                     "dbusName": "org.mpris.alpha",
                                     "identity": "Alpha",
                                     "desktopEntry": "alpha",
                                     "uniqueId": 11,
                                     "trackTitle": "  Song\tOne \u0007 ",
                                     "playbackState": MprisPlaybackState.Paused
                                 });
        setPlayers(bundle, [alpha]);
        require(bundle.adapter.available && bundle.adapter.selectedGeneration === 1,
                "a paused player with metadata is selected");
        require(bundle.adapter.trackKey === "1:11" && bundle.adapter.playerName === "Alpha",
                "track key combines generation and unique id");
        require(bundle.adapter.title === "Song One" && bundle.adapter.artist === ""
                && bundle.adapter.album === "",
                "control characters are removed and whitespace collapses");
        require(bundle.adapter.playbackState === "paused" && bundle.adapter.playerDesktopEntry === "alpha",
                "paused state and desktop entry normalize");

        alpha.trackTitle = "";
        for (let i = 0; i < 300; ++i) {
            alpha.trackTitle += "x";
        }

        apply(bundle, () => {
                  alpha.trackArtist = "\u0002\u001f\u0007";
              });
        require(bundle.adapter.title.length === 256,
                "metadata fields are bounded");
        require(bundle.adapter.artist === "",
                "control-character-only fields normalize to empty");
        alpha.trackTitle = "Song One";
        apply(bundle, () => {});

        const beta = makePlayer({
                                    "dbusName": "org.mpris.beta",
                                    "identity": "Beta",
                                    "uniqueId": 22,
                                    "trackTitle": "Second",
                                    "playbackState": MprisPlaybackState.Paused
                                });
        setPlayers(bundle, [alpha, beta]);
        require(bundle.adapter.selectedGeneration === 1,
                "the selected meaningful paused player is retained over equal candidates");

        apply(bundle, () => {
                  beta.playbackState = MprisPlaybackState.Playing;
              });
        require(bundle.adapter.selectedGeneration === 2 && bundle.adapter.playerName === "Beta"
                && bundle.adapter.playbackState === "playing",
                "the most recent Playing transition wins");

        apply(bundle, () => {
                  beta.playbackState = MprisPlaybackState.Paused;
              });
        require(bundle.adapter.selectedGeneration === 2,
                "the selected paused player is retained after pausing");

        apply(bundle, () => {
                  beta.playbackState = MprisPlaybackState.Stopped;
              });
        require(bundle.adapter.selectedGeneration === 1 && bundle.adapter.playerName === "Alpha",
                "a stopped player falls back to the meaningful paused candidate");
        destroyBundle(bundle);

        const stoppedOnlyBundle = makeAdapter({});
        const stoppedOnly = makePlayer({
                                           "dbusName": "org.mpris.stopped",
                                           "identity": "StoppedOnly",
                                           "uniqueId": 33,
                                           "trackTitle": "Idle Track",
                                           "playbackState": MprisPlaybackState.Stopped
                                       });
        setPlayers(stoppedOnlyBundle, [stoppedOnly]);
        require(!stoppedOnlyBundle.adapter.available,
                "stopped-only players do not keep media visible");
        destroyBundle(stoppedOnlyBundle);

        runTieAndRestartStages();
    }

    function runTieAndRestartStages() {
        console.warn("media: tie and restart stages");
        const bundle = makeAdapter({});
        const zeta = makePlayer({
                                    "dbusName": "org.mpris.zeta",
                                    "identity": "Zeta",
                                    "uniqueId": 44,
                                    "trackTitle": "Zeta Song",
                                    "playbackState": MprisPlaybackState.Playing
                                });
        const yankee = makePlayer({
                                      "dbusName": "org.mpris.yankee",
                                      "identity": "Yankee",
                                      "uniqueId": 55,
                                      "trackTitle": "Yankee Song",
                                      "playbackState": MprisPlaybackState.Playing
                                  });
        setPlayers(bundle, [zeta, yankee]);
        require(bundle.adapter.playerName === "Yankee",
                "simultaneous startup ties resolve lexically by dbus name");
        const yankeeGeneration = bundle.adapter.selectedGeneration;

        setPlayers(bundle, [zeta]);
        apply(bundle, () => {});
        require(bundle.adapter.playerName === "Zeta",
                "removal reselects the remaining playing player");
        const zetaGeneration = bundle.adapter.selectedGeneration;

        const restartedYankee = makePlayer({
                                               "dbusName": "org.mpris.yankee",
                                               "identity": "Yankee",
                                               "uniqueId": 56,
                                               "trackTitle": "Yankee Song",
                                               "playbackState": MprisPlaybackState.Paused
                                           });
        setPlayers(bundle, [zeta, restartedYankee]);
        require(bundle.adapter.playerName === "Zeta"
                && bundle.adapter.trackedPlayerCount === 2,
                "a restarted service does not win selection from stale recency");
        require(restartedYankee.uniqueId === 56,
                "the replacement instance keeps its own identity");

        const watcher = bundle.adapter.selectedGeneration;
        require(watcher === zetaGeneration,
                "zeta keeps its original generation across the restart");
        destroyBundle(bundle);

        const replayBundle = makeAdapter({});
        const oldPlayer = makePlayer({
                                         "dbusName": "org.mpris.replayed",
                                         "identity": "Replayed",
                                         "uniqueId": 66,
                                         "trackTitle": "One",
                                         "playbackState": MprisPlaybackState.Paused
                                     });
        setPlayers(replayBundle, [oldPlayer]);
        const firstGeneration = replayBundle.adapter.selectedGeneration;
        setPlayers(replayBundle, []);
        setPlayers(replayBundle, [oldPlayer]);
        require(replayBundle.adapter.selectedGeneration > firstGeneration,
                "a reconnected dbus name becomes a new player generation");
        destroyBundle(replayBundle);
        runArtworkStage();
    }

    function runArtworkStage() {
        console.warn("media: artwork stage");
        artFile.setText(test.bmpImage());
        const bundle = makeAdapter({
                                       "detailsVisible": true
                                   });
        const player = makePlayer({
                                      "dbusName": "org.mpris.art",
                                      "identity": "Art",
                                      "uniqueId": 77,
                                      "trackTitle": "Art Song",
                                      "playbackState": MprisPlaybackState.Paused
                                  });
        setPlayers(bundle, [player]);
        require(bundle.adapter.artworkStatus === "empty" && bundle.adapter.artworkRequest === "",
                "no artwork is requested before the player provides a source");

        waitFor(() => {
                    return true;
                }, () => {
                    runLateArtworkStage(bundle, player);
                }, "artwork stage bootstrap");
    }

    function runLateArtworkStage(bundle, player) {
        player.trackArtUrl = test.artUrl;
        apply(bundle, () => {});
        require(bundle.adapter.artworkSource === test.artUrl,
                "a bounded file url is accepted for the current track");
        require(bundle.adapter.artworkRequest === test.artUrl,
                "visible expanded media requests the validated artwork");
        waitFor(() => {
                    return bundle.adapter.artworkStatus !== "loading";
                }, () => {
                    require(bundle.adapter.artworkStatus === "ready",
                            "bounded local artwork decodes asynchronously to ready status");

                    player.uniqueId += 1;
                    player.trackArtUrl = "";
                    apply(bundle, () => {});
                    require(bundle.adapter.artworkSource === ""
                            && bundle.adapter.artworkStatus === "empty"
                            && bundle.adapter.artworkRequest === "",
                            "cleared late artwork leaves no request behind");

                    runRejectedSchemesStage(bundle, player);
                }, "local artwork decode settles");
    }

    function runRejectedSchemesStage(bundle, player) {
        const rejected = ["http://example.com/cover.png", "data:image/png;base64,AAAA",
            "ftp://example.com/cover.png", "javascript://example.com/x",
            "https://user:pass@example.com/cover.png", "https:///cover.png",
            "https://ex ample.com/cover.png", "file://evil.example/cover.png",
            "file:/relative/cover.png", "https://example.com/" + "x".repeat(2100),
            "https://example.com/cover.png\u0007"];
        for (let i = 0; i < rejected.length; ++i) {
            player.trackArtUrl = rejected[i];
            apply(bundle, () => {});
            require(bundle.adapter.artworkSource === "" && bundle.adapter.artworkRequest === "",
                    "rejected scheme or shape " + i + " never reaches the loader");
            require(bundle.adapter.artworkStatus === "empty",
                    "rejected artwork keeps the neutral empty status");
        }

        const accepted = ["HTTPS://Example.com/cover.png?q=1#frag",
            "https://example.com/cover.png", "file:///absolute/cover.png",
            "file://localhost/absolute/cover.png"];
        for (let j = 0; j < accepted.length; ++j) {
            player.trackArtUrl = accepted[j];
            apply(bundle, () => {});
            require(bundle.adapter.artworkSource === accepted[j],
                    "accepted artwork shape " + j + " is published verbatim");
        }

        player.trackArtUrl = "";
        apply(bundle, () => {});

        const missingBundle = makeAdapter({
                                              "detailsVisible": true
                                          });
        const missingPlayer = makePlayer({
                                             "dbusName": "org.mpris.missing-art",
                                             "identity": "MissingArt",
                                             "uniqueId": 88,
                                             "trackTitle": "Missing Art",
                                             "playbackState": MprisPlaybackState.Paused,
                                             "trackArtUrl": "file:///nonexistent/cover.png"
                                         });
        setPlayers(missingBundle, [missingPlayer]);
        waitFor(() => {
                    return missingBundle.adapter.artworkStatus !== "loading";
                }, () => {
                    require(missingBundle.adapter.artworkStatus === "failed",
                            "undecodable artwork fails into the neutral failed status");
                    destroyBundle(missingBundle);
                    destroyBundle(bundle);
                    runControlsStage();
                }, "missing artwork decode settles");
    }

    function runControlsStage() {
        console.warn("media: controls stage");
        const bundle = makeAdapter({});
        const player = makePlayer({
                                      "dbusName": "org.mpris.controls",
                                      "identity": "Controls",
                                      "uniqueId": 99,
                                      "trackTitle": "Control Song",
                                      "playbackState": MprisPlaybackState.Paused
                                  });
        setPlayers(bundle, [player]);

        require(bundle.adapter.next() === "rejected" && bundle.adapter.failure === "unsupported"
                && bundle.adapter.pendingAction === "none" && test.calls.length === 0,
                "unsupported controls are locally rejected without calls");
        bundle.adapter.dispatchDeadlineReached();
        require(bundle.adapter.failure === "none",
                "rejection failure clears at the bounded deadline");

        apply(bundle, () => {
                  player.canGoNext = true;
              });
        require(bundle.adapter.canNext,
                "capability changes republish");
        require(bundle.adapter.next() === "dispatched" && test.calls.length === 1
                && test.calls[0].dbusName === "org.mpris.controls"
                && test.calls[0].action === "next",
                "capable next dispatches exactly once to the live player");
        require(bundle.adapter.pendingAction === "next",
                "dispatch marks bounded pending transport state");
        test.calls = [];

        apply(bundle, () => {
                  player.trackTitle = "Confirmed";
              });
        require(bundle.adapter.pendingAction === "none" && bundle.adapter.failure === "none",
                "a backend-confirmed change clears pending state silently");
        require(bundle.adapter.title === "Confirmed",
                "confirmed metadata publishes");

        apply(bundle, () => {
                  player.canGoPrevious = true;
              });
        require(bundle.adapter.previous() === "dispatched"
                && bundle.adapter.pendingAction === "previous",
                "capable previous dispatches and marks pending state");

        apply(bundle, () => {
                  player.postTrackChanged();
              });
        require(bundle.adapter.pendingAction === "none" && bundle.adapter.failure === "none",
                "the postTrackChanged ordering hint clears pending state");

        apply(bundle, () => {
                  player.canTogglePlaying = true;
              });
        require(bundle.adapter.togglePlayback() === "dispatched"
                && bundle.adapter.pendingAction === "toggle",
                "toggle playback dispatches when capable");
        bundle.adapter.dispatchDeadlineReached();
        require(bundle.adapter.pendingAction === "none" && bundle.adapter.failure === "none",
                "pending clears at the deadline without inventing failure");

        require(bundle.adapter.seekBy(15) === "rejected"
                && bundle.adapter.failure === "unsupported",
                "seek is rejected while unsupported");
        bundle.adapter.dispatchDeadlineReached();

        apply(bundle, () => {
                  player.canSeek = true;
                  player.lengthSupported = true;
                  player.length = 200.5;
                  player.positionSupported = true;
                  player.position = 10;
                  player.playbackState = MprisPlaybackState.Playing;
              });
        require(bundle.adapter.duration === 200.5 && bundle.adapter.position === 10,
                "supported duration and position publish in seconds");
        require(bundle.adapter.seekBy(-30) === "dispatched" && test.calls.length >= 1,
                "relative seek dispatches when supported");
        const seekRecord = test.calls[test.calls.length - 1];
        require(seekRecord.action === "seek" && seekRecord.argument === -30,
                "seek forwards the exact offset");
        require(bundle.adapter.seekBy(Number.NaN) === "rejected",
                "non-finite seek offsets are rejected");
        test.calls = [];

        apply(bundle, () => {
                  player.canControl = false;
              });
        require(!bundle.adapter.canPrevious && !bundle.adapter.canTogglePlayback
                && !bundle.adapter.canNext && !bundle.adapter.canSeek,
                "capabilities are ANDed with canControl");
        require(bundle.adapter.previous() === "rejected"
                && bundle.adapter.failure === "unsupported" && test.calls.length === 0,
                "canControl=false rejects every transport action");
        bundle.adapter.dispatchDeadlineReached();

        runPositionStage(bundle, player);
    }

    function runPositionStage(bundle, player) {
        console.warn("media: position stage");
        bundle.adapter.detailsVisible = true;
        apply(bundle, () => {});
        require(bundle.adapter.positionTimerRunning,
                "the shared position timer runs only while visible and playing");

        apply(bundle, () => {
                  player.position = 11.25;
              });
        bundle.adapter.positionTickReached();
        require(bundle.adapter.position === 11.25,
                "position ticks read the refreshed backend position");

        apply(bundle, () => {
                  player.position = 500;
              });
        bundle.adapter.positionTickReached();
        require(bundle.adapter.position === 200.5,
                "position clamps to the published duration");
        apply(bundle, () => {
                  player.position = -5;
              });
        bundle.adapter.positionTickReached();
        require(bundle.adapter.position === 0,
                "negative positions clamp to zero");

        apply(bundle, () => {
                  player.positionSupported = false;
              });
        require(bundle.adapter.position === null && !bundle.adapter.positionTimerRunning,
                "unsupported position stops the timer and publishes null");

        apply(bundle, () => {
                  player.positionSupported = true;
                  player.lengthSupported = false;
              });
        require(bundle.adapter.duration === null && bundle.adapter.position === null
                && !bundle.adapter.positionTimerRunning,
                "duration requires length support and gates position too");

        apply(bundle, () => {
                  player.lengthSupported = true;
                  player.position = 10;
              });
        require(bundle.adapter.positionTimerRunning,
                "restoring support restarts the shared timer");

        bundle.adapter.detailsVisible = false;
        apply(bundle, () => {});
        require(!bundle.adapter.positionTimerRunning
                && bundle.adapter.artworkRequest === "",
                "hiding expanded media stops recurring work");

        bundle.adapter.detailsVisible = true;
        apply(bundle, () => {
                  player.playbackState = MprisPlaybackState.Paused;
              });
        require(!bundle.adapter.positionTimerRunning,
                "pausing stops the shared timer");
        require(bundle.adapter.position === 10,
                "pausing retains the last confirmed position");

        runCleanupStage(bundle, player);
    }

    function runCleanupStage(bundle, player) {
        console.warn("media: cleanup stage");
        apply(bundle, () => {
                  player.canControl = true;
                  player.canGoPrevious = true;
                  player.playbackState = MprisPlaybackState.Playing;
              });
        require(bundle.adapter.previous() === "dispatched",
                "cleanup scenario starts from dispatched pending state");

        setPlayers(bundle, []);
        require(!bundle.adapter.available && bundle.adapter.trackKey === ""
                && bundle.adapter.trackedPlayerCount === 0,
                "session loss clears availability, track key, and tracked players");
        require(bundle.adapter.pendingAction === "none" && bundle.adapter.failure === "none",
                "session loss clears pending actions and failures");
        require(!bundle.adapter.positionTimerRunning && bundle.adapter.artworkRequest === ""
                && bundle.adapter.artworkStatus === "empty",
                "session loss stops timers and artwork work");
        require(bundle.adapter.duration === null && bundle.adapter.position === null,
                "session loss clears timing values");

        destroyBundle(bundle);
        for (let i = 0; i < 3; ++i) {
            const disposable = makeAdapter({});
            setPlayers(disposable, [player]);
            destroyBundle(disposable);
        }

        console.warn("media tests passed");
        Qt.exit(0);
    }

    Component.onCompleted: Qt.callLater(test.runUnavailableStage)
}

pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// MPRIS media state behind the media island states (ADR-0004 boundary).
//
// Platform adapter owning deterministic player selection, metadata
// normalization, artwork policy, optional position timing, and guarded
// transport dispatch. Presentation consumes only the typed state below; raw
// D-Bus names, metadata maps, deprecated fields, and unvalidated artwork
// URLs never leave this file, and no metadata, URL, D-Bus name, or payload
// value is ever logged.
Scope {
    id: root

    // Verification seam following the injected-dependency pattern.
    // Production leaves it unset and observes Mpris.players directly.
    property var playersModel: null
    // Disabling the integration disconnects every player watcher and avoids
    // touching the process-wide MPRIS model.
    property bool enabled: true
    // Presentation policy remains normalized here so every region consumes
    // the same selected player.
    property string playerPolicy: "automatic"
    property string preferredApplication: ""

    // Set by presentation while the expanded media view is visible. Artwork
    // decoding and the shared 1 Hz position refresh run only while true;
    // compact Idle performs neither.
    property bool detailsVisible: false

    // ---- bounded policy constants -----------------------------------------

    readonly property int maximumTextCharacters: 256
    readonly property int maximumIdentityCharacters: 128
    readonly property int maximumArtworkUrlCharacters: 2048
    // Bounded requested decode width; height scales proportionally. Views
    // must request the identical sourceSize so the standard Qt image cache
    // serves them the decoded result instead of decoding a second time.
    readonly property int artworkMaximumWidth: 512
    readonly property int dispatchTimeoutMs: 2000
    readonly property int positionIntervalMs: 1000

    // ---- normalized state --------------------------------------------------

    // True while a meaningful player is selected. Stopped-only players and
    // an absent session bus both leave this false.
    readonly property bool available: root.enabled && engine.state.available
    // Monotonic connection generation of the selected player instance.
    readonly property int selectedGeneration: engine.state.generation
    // Transient track identity "<generation>:<uniqueId>"; changes whenever
    // the selected generation or track changes. Empty when unavailable.
    readonly property string trackKey: engine.state.trackKey
    readonly property string playerName: engine.state.playerName
    readonly property string playerDesktopEntry: engine.state.playerDesktopEntry
    readonly property string title: engine.state.title
    readonly property string artist: engine.state.artist
    readonly property string album: engine.state.album
    // "playing", "paused", or "stopped".
    readonly property string playbackState: engine.state.playbackState
    // Nullable seconds. Position exists only when both position and length
    // are supported, finite, and the length is positive.
    readonly property var position: engine.state.position
    readonly property var duration: engine.state.duration
    // Transport capabilities, already ANDed with canControl.
    readonly property bool canPrevious: engine.state.canPrevious
    readonly property bool canTogglePlayback: engine.state.canTogglePlayback
    readonly property bool canNext: engine.state.canNext
    readonly property bool canSeek: engine.state.canSeek
    // Validated, bounded artwork source for the selected track, or "".
    readonly property string artworkSource: engine.state.artworkUrl
    // "empty" while nothing is gated for load, then "loading", "ready", or
    // "failed" for the selected track's decode. Views must show a neutral
    // placeholder unless this is "ready" for the current trackKey so late or
    // superseded artwork can never appear.
    readonly property string artworkStatus: engine.artworkStatusFor()
    // Verification visibility: what the loader requests right now.
    readonly property string artworkRequest: artworkLoader.source.toString()
    readonly property bool positionTimerRunning: positionTimer.running
    readonly property int trackedPlayerCount: engine.records.length
    readonly property var availableApplications: engine.availableApplications
    // "none" while idle, otherwise the action awaiting confirmation.
    readonly property string pendingAction: engine.pendingAction
    // Bounded failure kinds: "none", "unavailable", "stale", "unsupported".
    readonly property string failure: engine.failure

    // Results are exactly "dispatched" or "rejected". MPRIS calls return no
    // success value, so optimistic success is never reported; backend
    // confirmed properties stay authoritative.
    function previous() {
        return engine.dispatchAction("previous");
    }

    function togglePlayback() {
        return engine.dispatchAction("toggle");
    }

    function next() {
        return engine.dispatchAction("next");
    }

    function seekBy(offsetSeconds) {
        return engine.dispatchAction("seek", offsetSeconds);
    }

    // Deadline and tick seams. The internal timers invoke these; exposing
    // them lets verification fire exact deadlines deterministically. Each is
    // idempotent and guarded.
    function dispatchDeadlineReached() {
        engine.dispatchDeadlineReached();
    }

    function positionTickReached() {
        engine.refreshPosition();
    }

    // Flushes a coalesced rebuild scheduled by player notifications. The
    // runtime flushes through the event loop; tests call this directly.
    function processPendingChanges() {
        engine.flushScheduled();
    }

    Component.onCompleted: engine.rebuild()
    onPlayersModelChanged: engine.scheduleRebuild()
    onEnabledChanged: engine.scheduleRebuild()
    onPlayerPolicyChanged: engine.selectAndPublish()
    onPreferredApplicationChanged: engine.selectAndPublish()

    Timer {
        id: dispatchTimer

        interval: root.dispatchTimeoutMs
        onTriggered: root.dispatchDeadlineReached()
    }

    Timer {
        id: positionTimer

        interval: root.positionIntervalMs
        repeat: true
        running: root.detailsVisible && root.available && root.playbackState === "playing" && root.position
                 !== null && root.duration !== null
        onTriggered: root.positionTickReached()
    }

    // Offscreen decoder for the selected track's artwork. It never renders;
    // views consume the standard-cache result of the same URL and size.
    Image {
        id: artworkLoader

        visible: false
        asynchronous: true
        sourceSize.width: root.artworkMaximumWidth
        source: root.detailsVisible && root.available && root.artworkSource !== ""
                ? root.artworkSource : ""
    }

    Connections {
        target: engine.currentModel
        ignoreUnknownSignals: true

        function onValuesChanged() {
            engine.scheduleRebuild();
        }

        function onObjectInsertedPost() {
            engine.scheduleRebuild();
        }

        function onObjectRemovedPost() {
            engine.scheduleRebuild();
        }
    }

    Component {
        id: playerWatcher

        Connections {
            function onTrackChanged() {
                engine.handlePlayerSignal(target);
            }

            function onPostTrackChanged() {
                engine.handlePlayerSignal(target);
            }

            function onPlaybackStateChanged() {
                engine.handlePlayerSignal(target);
            }

            function onTrackTitleChanged() {
                engine.handlePlayerSignal(target);
            }

            function onTrackArtistChanged() {
                engine.handlePlayerSignal(target);
            }

            function onTrackAlbumChanged() {
                engine.handlePlayerSignal(target);
            }

            function onTrackArtUrlChanged() {
                engine.handlePlayerSignal(target);
            }

            function onUniqueIdChanged() {
                engine.handlePlayerSignal(target);
            }

            function onCanGoPreviousChanged() {
                engine.handlePlayerSignal(target);
            }

            function onCanGoNextChanged() {
                engine.handlePlayerSignal(target);
            }

            function onCanTogglePlayingChanged() {
                engine.handlePlayerSignal(target);
            }

            function onCanSeekChanged() {
                engine.handlePlayerSignal(target);
            }

            function onCanControlChanged() {
                engine.handlePlayerSignal(target);
            }

            function onPositionSupportedChanged() {
                engine.handlePlayerSignal(target);
            }

            function onLengthSupportedChanged() {
                engine.handlePlayerSignal(target);
            }

            function onLengthChanged() {
                engine.handlePlayerSignal(target);
            }

            function onPositionChanged() {
                engine.handlePlayerSignal(target);
            }
        }
    }

    QtObject {
        id: engine

        property var state: {
            "available": false,
            "generation": 0,
            "trackKey": "",
            "playerName": "",
            "playerDesktopEntry": "",
            "title": "",
            "artist": "",
            "album": "",
            "playbackState": "stopped",
            "position": null,
            "duration": null,
            "canPrevious": false,
            "canTogglePlayback": false,
            "canNext": false,
            "canSeek": false,
            "artworkUrl": ""
        }
        // One record per connected player instance. Identity-keyed by object
        // so a restarted service with the same dbusName is always a new
        // generation with cleared recency.
        property var records: []
        property var selectedRecord: null
        property var availableApplications: []
        property string pendingAction: "none"
        property string failure: "none"
        property int logicalClock: 0
        property int generationCounter: 0
        property bool scheduled: false
        property var warnedKeys: ({})
        readonly property var currentModel: !root.enabled ? null : root.playersModel !== null
                                                            ? root.playersModel : Mpris.players

        function artworkStatusFor() {
            if (!state.available || state.artworkUrl === "") {
                return "empty";
            }

            if (artworkLoader.status === Image.Ready) {
                return "ready";
            }

            if (artworkLoader.status === Image.Error) {
                return "failed";
            }

            return "loading";
        }

        function warnOnce(key, message) {
            if (warnedKeys[key] === true) {
                return;
            }

            warnedKeys[key] = true;
            console.warn(message);
        }

        function truthy(value) {
            return value === true;
        }

        function safeRead(object, name, fallback) {
            try {
                const value = object[name];
                return value === undefined ? fallback : value;
            } catch (error) {
                return fallback;
            }
        }

        // Plain-text normalization: control characters become spaces,
        // whitespace collapses, and the result is bounded.
        function normalizeText(value, limit) {
            if (typeof value !== "string") {
                return "";
            }

            const cleaned = value.replace(/[\u0000-\u001f\u007f-\u009f]/g, " ").replace(/\s+/g,
                                                                                        " ").trim();
            return cleaned.length > limit ? cleaned.slice(0, limit) : cleaned;
        }

        // Accepts only bounded credential-free file: and https: URLs. Every
        // other scheme, userinfo, whitespace authority, or control character
        // is rejected without logging the value.
        function validateArtworkUrl(value) {
            if (typeof value !== "string" || value.length === 0 || value.length
                    > root.maximumArtworkUrlCharacters) {
                return "";
            }

            if (/[\u0000-\u001f\u007f-\u009f]/.test(value)) {
                return "";
            }

            const httpsMatch = /^https:\/\/([^/?#]*)((?:[/?#]).*)?$/i.exec(value);
            if (httpsMatch !== null) {
                const authority = httpsMatch[1];
                if (authority.length === 0 || authority.indexOf("@") !== -1 || /\s/.test(
                            authority)) {
                    return "";
                }

                return value;
            }

            const fileMatch = /^file:\/\/([^/?#]*)(\/[^\s]*)$/i.exec(value);
            if (fileMatch !== null) {
                const authority = fileMatch[1];
                if (authority !== "" && authority.toLowerCase() !== "localhost") {
                    return "";
                }

                return value;
            }

            return "";
        }

        function isPlaying(record) {
            return safeRead(record.player, "playbackState", MprisPlaybackState.Stopped)
                    === MprisPlaybackState.Playing;
        }

        function isPaused(record) {
            return safeRead(record.player, "playbackState", MprisPlaybackState.Stopped)
                    === MprisPlaybackState.Paused;
        }

        function hasMeaningfulMetadata(record) {
            const limit = root.maximumTextCharacters;
            return normalizeText(safeRead(record.player, "trackTitle", ""), limit) !== ""
                    || normalizeText(safeRead(record.player, "trackArtist", ""), limit) !== ""
                    || normalizeText(safeRead(record.player, "trackAlbum", ""), limit) !== "";
        }

        function findRecord(player) {
            for (let i = 0; i < records.length; ++i) {
                if (records[i].player === player) {
                    return records[i];
                }
            }

            return null;
        }

        function adopt(player) {
            generationCounter += 1;
            const record = {
                "player": player,
                "dbusName": normalizeText(safeRead(player, "dbusName", ""),
                                          root.maximumIdentityCharacters),
                "sequence": generationCounter,
                "playingStamp": 0,
                "activeStamp": 0,
                "wasPlaying": false,
                "watcher": null
            };
            // Keep the watcher outside the MprisPlayer. Quickshell destroys the
            // player before ObjectModel emits its post-removal update; parenting
            // here leaves a valid watcher for disposeRecord() to release.
            record.watcher = playerWatcher.createObject(engine, {
                                                            "target": player
                                                        });
            return record;
        }

        function disposeRecord(record) {
            if (record.watcher !== null) {
                record.watcher.destroy();
                record.watcher = null;
            }
        }

        function clearTransient() {
            pendingAction = "none";
            failure = "none";
            dispatchTimer.stop();
        }

        function armDeadline() {
            if (pendingAction !== "none" || failure !== "none") {
                dispatchTimer.restart();
            } else {
                dispatchTimer.stop();
            }
        }

        function emptySnapshot() {
            return {
                "available": false,
                "generation": 0,
                "trackKey": "",
                "playerName": "",
                "playerDesktopEntry": "",
                "title": "",
                "artist": "",
                "album": "",
                "playbackState": "stopped",
                "position": null,
                "duration": null,
                "canPrevious": false,
                "canTogglePlayback": false,
                "canNext": false,
                "canSeek": false,
                "artworkUrl": ""
            };
        }

        function scheduleRebuild() {
            if (scheduled) {
                return;
            }

            scheduled = true;
            Qt.callLater(engine.rebuild);
        }

        function flushScheduled() {
            if (scheduled) {
                rebuild();
            }
        }

        function handlePlayerSignal(player) {
            const record = findRecord(player);
            if (record === null) {
                return;
            }

            if (selectedRecord !== null && record.player === selectedRecord.player && pendingAction
                    !== "none") {
                pendingAction = "none";
                armDeadline();
            }

            scheduleRebuild();
        }

        function hardReset() {
            for (let i = 0; i < records.length; ++i) {
                disposeRecord(records[i]);
            }

            records = [];
            selectedRecord = null;
            availableApplications = [];
            clearTransient();
            state = emptySnapshot();
        }

        // Full resynchronization: drop disconnected generations, adopt
        // newcomers, stamp Playing transitions, then reselect and publish.
        function rebuild() {
            scheduled = false;
            let values = safeRead(currentModel, "values", null);
            // ObjectModel.values is a QML list object rather than a JS
            // array; accept anything indexable with a numeric length.
            if (values === null || typeof values !== "object" || typeof values.length
                    !== "number") {

                values = [];
            }

            const survivors = [];
            for (let i = 0; i < records.length; ++i) {
                let found = false;
                for (let j = 0; j < values.length; ++j) {
                    if (values[j] === records[i].player) {
                        found = true;
                        break;
                    }
                }

                if (found) {
                    survivors.push(records[i]);
                } else {
                    disposeRecord(records[i]);
                }
            }

            const next = survivors.slice();
            for (let j = 0; j < values.length; ++j) {
                let known = false;
                for (let i = 0; i < next.length; ++i) {
                    if (next[i].player === values[j]) {
                        known = true;
                        break;
                    }
                }

                if (!known) {
                    next.push(adopt(values[j]));
                }
            }
            records = next;
            publishApplications();

            // Transitions observed in one pass share one recency stamp so
            // simultaneous startup ties resolve lexically by dbusName.
            const entries = [];
            for (let k = 0; k < records.length; ++k) {
                const playing = isPlaying(records[k]);
                if (playing && !records[k].wasPlaying) {
                    entries.push(records[k]);
                }

                records[k].wasPlaying = playing;
            }

            if (entries.length > 0) {
                logicalClock += 1;
                for (let m = 0; m < entries.length; ++m) {
                    entries[m].playingStamp = logicalClock;
                    entries[m].activeStamp = logicalClock;
                }
            }

            selectAndPublish();
        }

        function eligible(record) {
            return isPlaying(record) || (isPaused(record) && hasMeaningfulMetadata(record));
        }

        function preferred(record) {
            return eligible(record) && normalizeText(safeRead(record.player, "desktopEntry", ""),
                                                     root.maximumIdentityCharacters)
                    === root.preferredApplication;
        }

        function newestPlaying(predicate) {
            let chosen = null;
            for (let index = 0; index < records.length; ++index) {
                const record = records[index];
                if (predicate(record) && isPlaying(record) && (chosen === null
                                                               || record.playingStamp
                                                               > chosen.playingStamp || (
                                                                   record.playingStamp
                                                                   === chosen.playingStamp
                                                                   && record.dbusName
                                                                   < chosen.dbusName))) {
                    chosen = record;
                }
            }
            return chosen;
        }

        function newestPaused(predicate) {
            let chosen = null;
            for (let index = 0; index < records.length; ++index) {
                const record = records[index];
                if (predicate(record) && isPaused(record) && hasMeaningfulMetadata(record) && (
                            chosen === null || record.activeStamp > chosen.activeStamp || (
                                record.activeStamp === chosen.activeStamp && record.dbusName
                                < chosen.dbusName))) {
                    chosen = record;
                }
            }
            return chosen;
        }

        function automaticSelection() {
            let chosen = newestPlaying(record => true);
            if (chosen === null && selectedRecord !== null && findRecord(selectedRecord.player)
                    !== null && isPaused(selectedRecord) && hasMeaningfulMetadata(selectedRecord)) {
                chosen = selectedRecord;
            }
            return chosen === null ? newestPaused(record => true) : chosen;
        }

        // A relevant preferred application wins. When it is absent, stopped,
        // or metadata-empty while paused, the established automatic policy
        // remains the immediate fallback.
        function selectAndPublish() {
            let chosen = null;
            if (root.playerPolicy === "preferred" && root.preferredApplication !== "") {
                chosen = newestPlaying(preferred);
                if (chosen === null && selectedRecord !== null && preferred(selectedRecord) && isPaused(
                            selectedRecord)) {
                    chosen = selectedRecord;
                }
                if (chosen === null) {
                    chosen = newestPaused(preferred);
                }
            }
            if (chosen === null) {
                chosen = automaticSelection();
            }
            if (selectedRecord !== chosen) {
                selectedRecord = chosen;
                clearTransient();
            }
            publish();
        }

        function publishApplications() {
            const byKey = {};
            for (let index = 0; index < records.length; ++index) {
                const player = records[index].player;
                const key = normalizeText(safeRead(player, "desktopEntry", ""),
                                          root.maximumIdentityCharacters);
                if (key === "" || byKey[key] !== undefined) {
                    continue;
                }
                const identity = normalizeText(safeRead(player, "identity", ""),
                                               root.maximumIdentityCharacters);
                byKey[key] = {
                    "label": identity !== "" ? identity : key,
                    "value": key
                };
            }
            const values = Object.keys(byKey).map(key => byKey[key]);
            values.sort((left, right) => left.label === right.label ? left.value.localeCompare(
                                                                          right.value) :
                                                                      left.label.localeCompare(
                                                                          right.label));
            availableApplications = Object.freeze(values.slice(0, 16));
        }

        // One atomic state replacement per publish, always derived from the
        // live selected player so late or reordered provider fields can never
        // resurrect superseded values.
        function publish() {
            const record = selectedRecord;
            if (record === null) {
                state = emptySnapshot();
                return;
            }

            const player = record.player;
            try {
                const durationValue = readDuration(player);
                state = {
                    "available": true,
                    "generation": record.sequence,
                    "trackKey": record.sequence + ":" + safeRead(player, "uniqueId", 0),
                    "playerName": normalizeText(safeRead(player, "identity", ""),
                                                root.maximumIdentityCharacters),
                    "playerDesktopEntry": normalizeText(safeRead(player, "desktopEntry", ""),
                                                        root.maximumIdentityCharacters),
                    "title": normalizeText(safeRead(player, "trackTitle", ""),
                                           root.maximumTextCharacters),
                    "artist": normalizeText(safeRead(player, "trackArtist", ""),
                                            root.maximumTextCharacters),
                    "album": normalizeText(safeRead(player, "trackAlbum", ""),
                                           root.maximumTextCharacters),
                    "playbackState": isPlaying(record) ? "playing" : isPaused(record) ? "paused" :
                                                                                        "stopped",
                    "position": readPosition(player, durationValue),
                    "duration": durationValue,
                    "canPrevious": truthy(safeRead(player, "canControl", false)) && truthy(safeRead(
                                                                                               player, "canGoPrevious",
                                                                                               false)),
                    "canTogglePlayback": truthy(safeRead(player, "canControl", false)) && truthy(
                                             safeRead(player, "canTogglePlaying", false)),
                    "canNext": truthy(safeRead(player, "canControl", false)) && truthy(safeRead(
                                                                                           player, "canGoNext",
                                                                                           false)),
                    "canSeek": truthy(safeRead(player, "canControl", false)) && truthy(safeRead(
                                                                                           player, "canSeek",
                                                                                           false)),
                    "artworkUrl": validateArtworkUrl(safeRead(player, "trackArtUrl", ""))
                };
            } catch (error) {
                warnOnce("publish-error",
                         "media player vanished during publication; resetting media state");
                hardReset();
            }
        }

        function readDuration(player) {
            if (!truthy(safeRead(player, "lengthSupported", false))) {
                return null;
            }

            const length = safeRead(player, "length", Number.NaN);
            if (typeof length !== "number" || !Number.isFinite(length) || length <= 0) {
                return null;
            }

            return length;
        }

        function readPosition(player, durationValue) {
            if (durationValue === null || !truthy(safeRead(player, "positionSupported", false))) {
                return null;
            }

            const position = safeRead(player, "position", Number.NaN);
            if (typeof position !== "number" || !Number.isFinite(position)) {
                return null;
            }

            return Math.min(Math.max(position, 0), durationValue);
        }

        function rejectLocally(kind) {
            pendingAction = "none";
            failure = kind;
            armDeadline();
            return "rejected";
        }

        function dispatchAction(action, argument) {
            const record = selectedRecord;
            if (record === null) {
                return rejectLocally("unavailable");
            }

            if (findRecord(record.player) === null) {
                selectedRecord = null;
                publish();
                return rejectLocally("stale");
            }

            const player = record.player;
            try {
                let capable = false;
                if (action === "previous") {
                    capable = truthy(safeRead(player, "canControl", false)) && truthy(safeRead(
                                                                                          player, "canGoPrevious",
                                                                                          false));
                } else if (action === "toggle") {
                    capable = truthy(safeRead(player, "canControl", false)) && truthy(safeRead(
                                                                                          player, "canTogglePlaying",
                                                                                          false));
                } else if (action === "next") {
                    capable = truthy(safeRead(player, "canControl", false)) && truthy(safeRead(
                                                                                          player, "canGoNext",
                                                                                          false));
                } else if (action === "seek") {
                    capable = truthy(safeRead(player, "canControl", false)) && truthy(safeRead(
                                                                                          player, "canSeek",
                                                                                          false))
                            && typeof argument === "number" && Number.isFinite(argument);
                }

                if (!capable) {
                    return rejectLocally("unsupported");
                }

                if (action === "previous") {
                    player.previous();
                } else if (action === "toggle") {
                    player.togglePlaying();
                } else if (action === "next") {
                    player.next();
                } else {
                    player.seek(argument);
                }
            } catch (error) {
                return rejectLocally("stale");
            }

            failure = "none";
            pendingAction = action;
            armDeadline();
            return "dispatched";
        }

        function dispatchDeadlineReached() {
            pendingAction = "none";
            failure = "none";
            dispatchTimer.stop();
        }

        // Shared 1 Hz position refresh. Emits the documented positionChanged
        // hint so the player re-reads its backend position, then republishes.
        function refreshPosition() {
            const record = selectedRecord;
            if (record === null) {
                return;
            }

            const player = record.player;
            if (!truthy(safeRead(player, "positionSupported", false))) {
                return;
            }

            try {
                player.positionChanged();
            } catch (error) {
                warnOnce("position-refresh",
                         "media player rejected the position refresh; skipping");
            }

            publish();
        }
    }
}

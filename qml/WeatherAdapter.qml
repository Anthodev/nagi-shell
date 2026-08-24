pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

// MET Norway Locationforecast 2.0 compact weather state (ADR-0003 boundary).
//
// Platform adapter owning the request, validation, bounded cache, one-shot
// scheduling, backoff, and symbol normalization behind the optional Idle
// weather state. Presentation consumes only the typed state below; provider
// codes, URLs, coordinates, payloads, and cache contents never leave this
// file, and no request-related value is ever logged.
//
// Privacy model: weather is opt-in through explicit local coordinates.
// Missing or invalid coordinates perform no request and keep no cache.
// Requests carry two-decimal truncated coordinates and the public identifying
// User-Agent only; the optional label never leaves the machine.
Scope {
    id: root

    // Project version reported in the provider User-Agent. Bump with releases.
    property string version: "0.1.0"
    property bool enabled: false

    // Opt-in location. Invalid or missing values keep weather unavailable
    // without any request. Altitude is optional whole metres; the label is
    // local-only and is never sent, persisted, or logged.
    property real latitude: Number.NaN
    property real longitude: Number.NaN
    property var altitude: null
    property string label: ""

    // Verification seams following the coordinator's injected-clock pattern.
    // Production leaves them unset and uses the wall clock, Math.random, the
    // built-in XMLHttpRequest transport, and the per-shell cache directory.
    property var wallNow: null
    property var randomSource: null
    property var transport: null
    property int requestTimeoutMs: 10000
    property string cacheDirectory: ""
    property string cacheFileName: "weather.json"

    // ---- normalized state -------------------------------------------------

    // True while a valid current timestep is exposed, including the bounded
    // stale window before the six-hour cutoff.
    readonly property bool available: root.enabled && engine.available
    // True while available content comes from an expired cache record.
    readonly property bool stale: engine.stale
    readonly property real temperatureC: engine.snapshot === null ? Number.NaN :
                                                                    engine.snapshot.temperatureC
    readonly property string condition: engine.snapshot === null ? "unknown" :
                                                                   engine.snapshot.condition

    readonly property string dayPhase: engine.snapshot === null ? "day" : engine.snapshot.dayPhase
    readonly property date forecastTime: engine.snapshot === null ? new Date(Number.NaN) : new Date(
                                                                        engine.snapshot.forecastEpoch)
    readonly property date fetchedAt: Number.isFinite(engine.fetchedAt) ? new Date(
                                                                              engine.fetchedAt) :
                                                                          new Date(Number.NaN)
    // Bounded failure kinds: "none", "unconfigured", "transient", "throttled",
    // "permanent", "stale". It reports the most recent failure and never
    // carries provider payloads.
    readonly property string failure: engine.failure

    // Scheduling visibility for verification: epoch milliseconds of the next
    // allowed network request (0 when none is scheduled) and the number of
    // requests started since instantiation.
    readonly property real nextRequestAt: engine.nextRequestAt
    readonly property int requestCount: engine.requestCount
    readonly property bool locationConfigured: engine.locationKey !== ""
    readonly property int maximumResponseCharacters: 1048576
    readonly property int cacheSchemaVersion: 1

    // Emitted after every completed cache write, including clears. Verification
    // uses it to sequence cross-instance cache scenarios deterministically.
    signal cacheSaved

    // Deadline handlers. The internal one-shot timers invoke these; exposing
    // them lets verification fire exact deadlines deterministically. Each is
    // idempotent and guarded.
    function refreshDeadlineReached() {
        engine.runRefresh();
    }

    function localDeadlineReached() {
        engine.runLocalDeadline();
    }

    function requestTimeoutReached() {
        engine.requestTimeoutReached();
    }

    Component.onCompleted: applyLocation()
    onLatitudeChanged: engine.scheduleLocationSync()
    onLongitudeChanged: engine.scheduleLocationSync()
    onAltitudeChanged: engine.scheduleLocationSync()
    onVersionChanged: engine.scheduleLocationSync()
    onEnabledChanged: engine.scheduleLocationSync()

    FileView {
        id: cacheFileView

        path: root.cacheDirectory === "" ? Quickshell.cacheDir + "/" + root.cacheFileName : root.cacheDirectory
                                           + "/" + root.cacheFileName
        atomicWrites: true
        blockLoading: true
        printErrors: false
        onSaved: root.cacheSaved()
    }

    Timer {
        id: refreshTimer

        repeat: false
        onTriggered: root.refreshDeadlineReached()
    }

    Timer {
        id: localTimer

        repeat: false
        onTriggered: root.localDeadlineReached()
    }

    Timer {
        id: timeoutTimer

        repeat: false
        onTriggered: root.requestTimeoutReached()
    }

    QtObject {
        id: engine

        // Backoff tiers in milliseconds for network errors, timeouts, invalid
        // responses, and 5xx responses; 429 uses throttleTiers.
        readonly property var backoffTiers: [600000, 1800000, 3600000, 10800000, 21600000]
        readonly property var throttleTiers: [3600000, 10800000, 21600000]
        readonly property real backoffJitterFraction: 0.2
        readonly property int refreshJitterMs: 300000
        readonly property int startupJitterMs: 30000
        readonly property int expiresFallbackMs: 3600000
        readonly property int minimumRefreshGapMs: 600000
        readonly property int staleCutoffMs: 21600000
        readonly property int maximumTimestepAgeMs: 5400000
        readonly property real minimumTemperatureC: -90
        readonly property real maximumTemperatureC: 60

        property string locationKey: ""
        property string activeVersion: ""
        property string coarseLatitude: ""
        property string coarseLongitude: ""
        property var coarseAltitude: null

        property var cache: null
        property real expiresEpoch: Number.NaN
        property var snapshot: null
        property real fetchedAt: Number.NaN

        property bool available: false
        property bool stale: false
        property string failure: "unconfigured"

        property int backoffIndex: 0
        property int throttleTier: 0
        property var permanentKey: null
        property real nextRequestAt: 0

        property bool inFlight: false
        property int requestCount: 0
        property int requestSerial: 0
        property var activeRequest: null
        property var warnedKeys: ({})
        property bool locationSyncScheduled: false

        function currentTime() {
            const value = root.wallNow === null ? Date.now() : root.wallNow();
            return typeof value === "number" && Number.isFinite(value) ? value : 0;
        }

        function random01() {
            const value = root.randomSource === null ? Math.random() : root.randomSource();
            if (typeof value !== "number" || !Number.isFinite(value)) {
                return 0;
            }

            return Math.min(Math.max(value, 0), 1);
        }

        // Positive jitter in [0, span) milliseconds.
        function jitter(span) {
            return Math.floor(random01() * span);
        }

        function warnOnce(key, message) {
            if (warnedKeys[key] === true) {
                return;
            }

            warnedKeys[key] = true;
            console.warn(message);
        }

        // Truncation toward zero at two decimals with a tolerance for binary
        // rounding dust around exact hundredths, so 48.85 stays 48.85 while
        // 48.8566 still truncates to 48.85.
        function truncateCoordinate(value) {
            const scaled = value * 100;
            const rounded = Math.round(scaled);
            const corrected = Math.abs(scaled - rounded) < 0.000001 ? rounded : scaled;
            const truncated = corrected < 0 ? Math.ceil(corrected) : Math.floor(corrected);
            return truncated === 0 ? 0 : truncated / 100;
        }

        function validatedLocation() {
            if (!root.enabled || typeof root.latitude !== "number" || !Number.isFinite(root.latitude)
                    || typeof root.longitude !== "number" || !Number.isFinite(root.longitude)
                    || root.latitude < -90 || root.latitude > 90 || root.longitude < -180
                    || root.longitude > 180) {
                return null;
            }

            let altitudeValue = null;
            if (root.altitude !== null && root.altitude !== undefined) {
                if (typeof root.altitude !== "number" || !Number.isFinite(root.altitude) || !Number.isInteger(
                            root.altitude)) {
                    return null;
                }

                altitudeValue = root.altitude;
            }

            const latitude = truncateCoordinate(root.latitude);
            const longitude = truncateCoordinate(root.longitude);
            return {
                "key": "v1|" + latitude.toFixed(2) + "|" + longitude.toFixed(2) + (altitudeValue
                                                                                   === null ? "" :
                                                                                              "|" + altitudeValue),
                "latitude": latitude.toFixed(2),
                "longitude": longitude.toFixed(2),
                "altitude": altitudeValue === null ? null : String(altitudeValue)
            };
        }

        function scheduleLocationSync() {
            if (locationSyncScheduled) {
                return;
            }

            locationSyncScheduled = true;
            Qt.callLater(function () {
                locationSyncScheduled = false;
                root.applyLocation();
            });
        }

        // Single entry point for configuration changes. Any location or version
        // change cancels in-flight work, drops previous verdicts, and restarts
        // from the cache; clearing the location additionally removes the
        // previous location's cached content.
        function applyLocation() {
            const location = validatedLocation();
            const key = location === null ? "" : location.key;
            const version = typeof root.version === "string" && root.version.length > 0
                  ? root.version : "unknown";
            if (key === locationKey && version === activeVersion) {
                return;
            }

            abortActiveRequest();
            stopTimers();
            cache = null;
            expiresEpoch = Number.NaN;
            nextRequestAt = 0;
            backoffIndex = 0;
            throttleTier = 0;
            permanentKey = null;
            snapshot = null;
            fetchedAt = Number.NaN;
            available = false;
            stale = false;
            locationKey = key;
            activeVersion = version;

            if (key === "") {
                coarseLatitude = "";
                coarseLongitude = "";
                coarseAltitude = null;
                failure = "unconfigured";
                clearCacheFile();
                return;
            }

            coarseLatitude = location.latitude;
            coarseLongitude = location.longitude;
            coarseAltitude = location.altitude;

            const now = currentTime();
            const record = loadCacheRecord(key);
            failure = "none";
            if (record !== null) {
                cache = record;
                const parsedExpires = Date.parse(record.expires);
                expiresEpoch = Number.isFinite(parsedExpires) ? parsedExpires : Number.NaN;
                adoptRecord(now);
                armRefresh(expiresEpoch > now ? expiresEpoch + jitter(refreshJitterMs) : now
                                                + jitter(startupJitterMs));
            } else {
                armRefresh(now + jitter(startupJitterMs));
            }
        }

        function loadCacheRecord(key) {
            const raw = cacheFileView.text();
            if (typeof raw !== "string" || raw.length === 0) {
                return null;
            }

            let record = null;
            try {
                record = JSON.parse(raw);
            } catch (error) {
                record = null;
            }

            const valid = record !== null && typeof record === "object" && record.schemaVersion
                  === root.cacheSchemaVersion && record.locationKey === key && typeof record.body
                  === "string" && record.body.length > 0 && record.body.length
                  <= root.maximumResponseCharacters && typeof record.expires === "string"
                  && typeof record.lastModified === "string" && Number.isFinite(record.retrievedAt)
                  && Number.isFinite(record.validatedAt) && Number.isFinite(Date.parse(
                                                                                record.expires));
            if (!valid) {
                clearCacheFile();
                return null;
            }

            return record;
        }

        // Re-derives visible state from the adopted cache body without any
        // request, exactly as ADR-0003 requires on startup.
        function adoptRecord(now) {
            const selection = selectTimestep(cache.body, now);
            if (selection.ok) {
                commitSnapshot(selection.snapshot, cache.retrievedAt);
            } else {
                clearWeather("stale");
            }

            armLocalDeadline();
        }

        function runLocalDeadline() {
            if (cache === null) {
                return;
            }

            const now = currentTime();
            if (now - cache.validatedAt >= staleCutoffMs) {
                cache = null;
                expiresEpoch = Number.NaN;
                clearWeather("stale");
                clearCacheFile();
                stopLocalTimer();
                return;
            }

            const selection = selectTimestep(cache.body, now);
            if (selection.ok) {
                snapshot = selection.snapshot;
                available = true;
                stale = Number.isFinite(expiresEpoch) && expiresEpoch <= now;
                if (failure === "stale") {
                    failure = "none";
                }
            } else {
                clearWeather("stale");
            }

            armLocalDeadline();
        }

        // Selects the latest timeseries entry not later than now, no more than
        // 90 minutes old, whose same entry carries both required fields.
        function selectTimestep(bodyText, now) {
            let parsed = null;
            try {
                parsed = JSON.parse(bodyText);
            } catch (error) {
                parsed = null;
            }

            const timeseries = parsed !== null && typeof parsed === "object" && parsed.properties
                  !== null && typeof parsed.properties === "object" && parsed.properties.timeseries
                  !== null && typeof parsed.properties.timeseries === "object"
                  && parsed.properties.timeseries.length > 0 ? parsed.properties.timeseries : null;
            if (timeseries === null) {
                return {
                    "ok": false
                };
            }

            let best = null;
            let bestTime = -Infinity;
            for (let index = 0; index < timeseries.length; index += 1) {
                const entry = timeseries[index];
                if (entry === null || typeof entry !== "object" || typeof entry.time !== "string") {
                    continue;
                }

                const time = Date.parse(entry.time);
                if (!Number.isFinite(time) || time > now || now - time > maximumTimestepAgeMs) {
                    continue;
                }

                const details = entry.data !== null && typeof entry.data === "object"
                      && entry.data.instant !== null && typeof entry.data.instant === "object"
                      && entry.data.instant.details !== null && typeof entry.data.instant.details
                      === "object" ? entry.data.instant.details : null;
                const summary = entry.data !== null && typeof entry.data === "object"
                      && entry.data.next_1_hours !== null && typeof entry.data.next_1_hours
                      === "object" && entry.data.next_1_hours.summary !== null
                      && typeof entry.data.next_1_hours.summary === "object"
                      ? entry.data.next_1_hours.summary : null;
                const temperature = details === null ? null : details.air_temperature;
                const symbolCode = summary === null ? null : summary.symbol_code;
                if (typeof temperature !== "number" || !Number.isFinite(temperature) || temperature
                        < minimumTemperatureC || temperature > maximumTemperatureC
                        || typeof symbolCode !== "string" || symbolCode.length === 0) {
                    continue;
                }

                if (time > bestTime) {
                    bestTime = time;
                    const normalized = normalizeSymbol(symbolCode);
                    best = {
                        "temperatureC": temperature,
                        "condition": normalized.condition,
                        "dayPhase": normalized.dayPhase,
                        "forecastEpoch": time
                    };
                }
            }

            return best === null ? {
                                       "ok": false
                                   } : {
                "ok": true,
                "snapshot": best
            };
        }

        // Collapses MET Norway symbol codes into the stable compact condition
        // enum and separates the day phase suffix. Thunder is tested before the
        // precipitation families because thunder variants span all of them.
        // Unknown codes map to "unknown" with one bounded diagnostic that
        // carries no raw provider output.
        function normalizeSymbol(code) {
            let phase = "day";
            let base = code;
            const suffixes = [["polartwilight", "polartwilight"], ["night", "night"], ["day",
                                                                                       "day"]];


            for (let index = 0; index < suffixes.length; index += 1) {
                const suffix = "_" + suffixes[index][0];
                if (base.length > suffix.length && base.lastIndexOf(suffix) === base.length
                        - suffix.length) {
                    phase = suffixes[index][1];
                    base = base.slice(0, base.length - suffix.length);
                    break;
                }
            }

            let condition = "unknown";
            if (base === "clearsky") {
                condition = "clear";
            } else if (base === "fair") {
                condition = "mostlyClear";
            } else if (base === "partlycloudy") {
                condition = "partlyCloudy";
            } else if (base === "cloudy") {
                condition = "cloudy";
            } else if (base === "fog") {
                condition = "fog";
            } else if (base.indexOf("thunder") !== -1) {
                condition = "thunderstorm";
            } else if (base.indexOf("sleet") !== -1) {
                condition = "sleet";
            } else if (base.indexOf("snow") !== -1) {
                condition = "snow";
            } else if (base.indexOf("rain") !== -1) {
                condition = "rain";
            } else {
                warnOnce("unknown-symbol",
                         "weather: unrecognized provider condition; using the unknown condition");
            }

            return {
                "condition": condition,
                "dayPhase": phase
            };
        }

        function commitSnapshot(snapshotValue, fetchedEpoch) {
            snapshot = snapshotValue;
            fetchedAt = fetchedEpoch;
            available = true;
            stale = Number.isFinite(expiresEpoch) && expiresEpoch <= currentTime();
            failure = "none";
        }

        function clearWeather(kind) {
            snapshot = null;
            fetchedAt = Number.NaN;
            available = false;
            stale = false;
            failure = kind;
        }

        function runRefresh() {
            if (locationKey === "" || permanentKey !== null || inFlight) {
                return;
            }

            const now = currentTime();
            if (nextRequestAt > now) {
                return;
            }

            let url = "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat="
                + coarseLatitude + "&lon=" + coarseLongitude;
            if (coarseAltitude !== null) {
                url += "&altitude=" + coarseAltitude;
            }

            const headers = {
                "User-Agent": root.userAgentValue
            };
            if (cache !== null && cache.lastModified !== "") {
                headers["If-Modified-Since"] = cache.lastModified;
            }

            startRequest(url, headers);
        }

        function startRequest(url, headers) {
            requestSerial += 1;
            const serial = requestSerial;
            inFlight = true;
            requestCount += 1;
            timeoutTimer.interval = Math.max(1, root.requestTimeoutMs);
            timeoutTimer.restart();
            const request = {
                "url": url,
                "headers": headers,
                "timeoutMs": Math.max(1, root.requestTimeoutMs),
                "onCompleted": function (outcome) {
                    if (serial !== requestSerial || !inFlight) {
                        return;
                    }

                    finishRequest(outcome);
                }
            };
            activeRequest = root.transport === null ? builtinRequest(request) :
                                                      root.transport.create(request);
        }

        // Built-in asynchronous XMLHttpRequest transport. Qt exposes no request
        // timeout, so the one-shot timeout timer aborts the request.
        function builtinRequest(request) {
            const xhr = new XMLHttpRequest();
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE) {
                    return;
                }

                if (xhr.status === 0) {
                    request.onCompleted({
                                            "networkError": true
                                        });
                    return;
                }

                request.onCompleted({
                                        "status": xhr.status,
                                        "headers": root.parseHeaderBlock(xhr.getAllResponseHeaders(
                                                                             )),
                                        "bodyText": xhr.responseText
                                    });
            };
            xhr.open("GET", request.url, true);
            for (const name in request.headers) {
                xhr.setRequestHeader(name, request.headers[name]);
            }

            xhr.send();
            return {
                "abort": function () {
                    xhr.abort();
                }
            };
        }

        function finishRequest(outcome) {
            inFlight = false;
            timeoutTimer.stop();
            handleOutcome(outcome);
        }

        function requestTimeoutReached() {
            if (!inFlight) {
                return;
            }

            abortActiveRequest();
            finishRequest({
                              "networkError": true
                          });
        }

        function handleOutcome(outcome) {
            const now = currentTime();
            if (outcome === null || typeof outcome !== "object" || outcome.networkError === true
                    || typeof outcome.status !== "number") {
                scheduleBackoff();
                return;
            }

            const status = Math.floor(outcome.status);
            if (status === 200 || status === 203) {
                adoptSuccessResponse(status, outcome, now);
            } else if (status === 304) {
                adoptNotModified(outcome, now);
            } else if (status === 429) {
                scheduleThrottle(outcome.headers, now);
            } else if (status >= 500 && status <= 599) {
                scheduleBackoff();
            } else if (status >= 400 && status <= 499) {
                markPermanent();
            } else {
                // Unexpected 1xx/2xx/3xx codes are malformed responses.
                scheduleBackoff();
            }
        }

        function adoptSuccessResponse(status, outcome, now) {
            const body = typeof outcome.bodyText === "string" ? outcome.bodyText : "";
            const headers = outcome.headers !== null && typeof outcome.headers === "object" ? outcome.headers :
                                                                                              {};
            if (body.length === 0 || body.length > root.maximumResponseCharacters) {
                scheduleBackoff();
                return;
            }

            const selection = selectTimestep(body, now);
            if (!selection.ok) {
                scheduleBackoff();
                return;
            }

            const expiresRaw = typeof headers["expires"] === "string" ? headers["expires"] : "";
            const lastModifiedRaw = typeof headers["last-modified"] === "string"
                  ? headers["last-modified"] : "";
            const parsedExpires = Date.parse(expiresRaw);
            cache = {
                "schemaVersion": root.cacheSchemaVersion,
                "locationKey": locationKey,
                "body": body,
                "expires": expiresRaw,
                "lastModified": lastModifiedRaw,
                "retrievedAt": now,
                "validatedAt": now
            };
            expiresEpoch = Number.isFinite(parsedExpires) ? parsedExpires : Number.NaN;
            backoffIndex = 0;
            throttleTier = 0;
            commitSnapshot(selection.snapshot, now);
            writeCache(cache);
            armRefresh(successRefreshAt(now, expiresEpoch));
            armLocalDeadline();
            if (status === 203) {
                warnOnce("deprecated",
                         "weather: provider reports deprecating data; honoring cache headers");
            }
        }

        // A 304 keeps the cached body, re-selects the current timestep locally,
        // refreshes validation metadata from the new headers, and schedules the
        // next request without downloading a replacement body.
        function adoptNotModified(outcome, now) {
            if (cache === null || cache.lastModified === "") {
                scheduleBackoff();
                return;
            }

            const headers = outcome.headers !== null && typeof outcome.headers === "object" ? outcome.headers :
                                                                                              {};
            const expiresRaw = typeof headers["expires"] === "string" ? headers["expires"] : "";
            let refreshedExpires = cache.expires;
            if (expiresRaw !== "") {
                const parsedExpires = Date.parse(expiresRaw);
                if (Number.isFinite(parsedExpires)) {
                    refreshedExpires = expiresRaw;
                    expiresEpoch = parsedExpires;
                }
            }

            const lastModifiedRaw = typeof headers["last-modified"] === "string"
                  ? headers["last-modified"] : "";
            // Records are replaced wholesale instead of mutated in place.
            cache = {
                "schemaVersion": cache.schemaVersion,
                "locationKey": cache.locationKey,
                "body": cache.body,
                "expires": refreshedExpires,
                "lastModified": lastModifiedRaw === "" ? cache.lastModified : lastModifiedRaw,
                "retrievedAt": cache.retrievedAt,
                "validatedAt": now
            };
            backoffIndex = 0;
            throttleTier = 0;
            const selection = selectTimestep(cache.body, now);
            if (selection.ok) {
                commitSnapshot(selection.snapshot, cache.retrievedAt);
            } else {
                clearWeather("stale");
            }

            writeCache(cache);
            armRefresh(successRefreshAt(now, expiresEpoch));
            armLocalDeadline();
        }

        // Next request after a successful validation: the response expiry plus
        // positive jitter, with the 60-minute fallback when headers are missing
        // or invalid, never sooner than ten minutes after completion.
        function successRefreshAt(now, expiresEpochValue) {
            const base = Number.isFinite(expiresEpochValue) ? Math.max(expiresEpochValue, now
                                                                       + minimumRefreshGapMs) : now
                                                              + expiresFallbackMs;
            return base + jitter(refreshJitterMs);
        }

        function scheduleBackoff() {
            const now = currentTime();
            const index = Math.min(backoffIndex, backoffTiers.length - 1);
            backoffIndex = Math.min(index + 1, backoffTiers.length - 1);
            const delay = backoffTiers[index] + jitter(Math.floor(backoffTiers[index]
                                                                  * backoffJitterFraction));
            failure = "transient";
            armRefresh(now + delay);
        }

        function scheduleThrottle(headers, now) {
            const raw = headers !== null && typeof headers === "object" && typeof headers["retry-after"]
                  === "string" ? headers["retry-after"] : "";
            let retryAfter = 0;
            if (/^[0-9]+$/.test(raw)) {
                retryAfter = parseInt(raw, 10) * 1000;
            } else {
                const parsed = Date.parse(raw);
                if (Number.isFinite(parsed)) {
                    retryAfter = Math.max(0, parsed - now);
                }
            }

            const tierDelay = throttleTiers[Math.min(throttleTier, throttleTiers.length - 1)];
            throttleTier = Math.min(throttleTier + 1, throttleTiers.length - 1);
            const base = Math.max(retryAfter, tierDelay);
            const delay = base + jitter(Math.floor(base * backoffJitterFraction));
            failure = "throttled";
            armRefresh(now + delay);
        }

        function markPermanent() {
            permanentKey = locationKey + "|" + activeVersion;
            stopTimers();
            nextRequestAt = 0;
            clearWeather("permanent");
        }

        function armRefresh(atEpoch) {
            const now = currentTime();
            nextRequestAt = Math.max(atEpoch, now);
            refreshTimer.interval = Math.max(1, Math.floor(nextRequestAt - now));
            refreshTimer.restart();
        }

        // One local deadline covers the next cached timeseries boundary and the
        // six-hour stale cutoff; both recompute state without network activity.
        function armLocalDeadline() {
            if (cache === null) {
                stopLocalTimer();
                return;
            }

            const now = currentTime();
            let deadline = cache.validatedAt + staleCutoffMs;
            // The expiry instant flips the exposed stale flag; past expiries
            // are skipped so the deadline never re-arms in a tight loop.
            if (Number.isFinite(expiresEpoch) && expiresEpoch > now) {
                deadline = Math.min(deadline, expiresEpoch);
            }

            let parsed = null;
            try {
                parsed = JSON.parse(cache.body);
            } catch (error) {
                parsed = null;
            }

            const timeseries = parsed !== null && typeof parsed === "object" && parsed.properties
                  !== null && typeof parsed.properties === "object" && parsed.properties.timeseries
                  !== null && typeof parsed.properties.timeseries === "object"
                  ? parsed.properties.timeseries : null;
            if (timeseries !== null) {
                for (let index = 0; index < timeseries.length; index += 1) {
                    const entry = timeseries[index];
                    if (entry === null || typeof entry !== "object" || typeof entry.time
                            !== "string") {
                        continue;
                    }

                    const time = Date.parse(entry.time);
                    if (Number.isFinite(time) && time > now) {
                        deadline = Math.min(deadline, time + 1);
                        break;
                    }
                }
            }

            localTimer.interval = Math.max(1, Math.floor(deadline - now));
            localTimer.restart();
        }

        function stopLocalTimer() {
            localTimer.stop();
        }

        function stopTimers() {
            refreshTimer.stop();
            stopLocalTimer();
            timeoutTimer.stop();
        }

        function abortActiveRequest() {
            requestSerial += 1;
            const active = activeRequest;
            activeRequest = null;
            if (active !== null && active !== undefined && active.abort !== undefined && active.abort
                    !== null) {
                active.abort();
            }
        }

        // The cache holds one location's bounded record: schema version, the
        // complete compact body, the exact header strings, and the timestamps.
        // Quickshell exposes no file-deletion API, so removal overwrites the
        // file with empty content; an empty or foreign record never validates.
        function writeCache(record) {
            const serialized = JSON.stringify(record);
            if (serialized.length >= root.maximumResponseCharacters) {
                warnOnce("cache-size",
                         "weather: cache record exceeds the size bound; skipping persistence");
                return;
            }

            cacheFileView.setText(serialized);
        }

        function clearCacheFile() {
            if (cacheFileView.loaded) {
                cacheFileView.setText("");
            }
        }
    }

    readonly property string userAgentValue: "NagiShell/" + version
                                             + " github.com/Anthodev/nagi-shell"

    function applyLocation() {
        engine.applyLocation();
    }

    function parseHeaderBlock(raw) {
        const headers = {};
        if (typeof raw !== "string" || raw.length === 0) {
            return headers;
        }

        const lines = raw.split("\n");
        for (let index = 0; index < lines.length; index += 1) {
            const line = lines[index];
            const carriage = line.charCodeAt(line.length - 1) === 13;
            const cleaned = carriage ? line.slice(0, line.length - 1) : line;
            const separator = cleaned.indexOf(":");
            if (separator <= 0) {
                continue;
            }

            headers[cleaned.slice(0, separator).toLowerCase()] = cleaned.slice(separator + 1).trim(
                        );

        }

        return headers;
    }
}

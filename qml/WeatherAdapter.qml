pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

// MET Norway Locationforecast 2.0 compact weather state (ADRs 0003 and 0016).
//
// This process-wide adapter owns the only forecast request, validation,
// bounded cache, schedule, backoff, unit conversion, and immutable model.
// Presentation consumes normalized values only. Provider codes, URLs,
// coordinates, payloads, and cache contents never leave this file or logs.
Scope {
    id: root

    property string version: "0.1.0"
    property bool enabled: false
    property real latitude: Number.NaN
    property real longitude: Number.NaN
    property string label: ""
    property string temperatureUnit: "auto"
    property string windUnit: "auto"
    property string refreshPreset: "1h"

    // Verification seams following the coordinator's injected-clock pattern.
    property var wallNow: null
    property var randomSource: null
    property var transport: null
    property int requestTimeoutMs: 10000
    property string cacheDirectory: ""
    property string cacheFileName: "weather.json"

    // Current compatibility properties remain shallow for compact Idle.
    readonly property bool available: root.enabled && engine.model !== null
    readonly property bool stale: engine.stale
    readonly property real temperatureC: engine.model === null ? Number.NaN :
                                                                 engine.model.current.temperatureC

    readonly property string condition: engine.model === null ? "unknown" :
                                                                engine.model.current.condition
    readonly property string dayPhase: engine.model === null ? "day" : engine.model.current.dayPhase
    readonly property date forecastTime: engine.model === null ? new Date(Number.NaN) : new Date(
                                                                     engine.model.current.forecastEpoch)
    readonly property date fetchedAt: Number.isFinite(engine.fetchedAt) ? new Date(
                                                                              engine.fetchedAt) :
                                                                          new Date(Number.NaN)
    readonly property string failure: engine.failure

    // One frozen generation contains local location, normalized current
    // conditions, up to the exact requested 12 hourly and five daily entries,
    // converted presentation values, and no provider-specific fields.
    readonly property var model: engine.model
    readonly property int modelGeneration: engine.modelGeneration
    readonly property var current: engine.model === null ? null : engine.model.current
    readonly property var hourly: engine.model === null ? emptyModel : engine.model.hourly
    readonly property var daily: engine.model === null ? emptyModel : engine.model.daily
    readonly property real lastUpdatedAgeMs: Number.isFinite(engine.fetchedAt) ? Math.max(0,
                                                                                          engine.currentTime(
                                                                                              ) - engine.fetchedAt) :
                                                                                 Number.NaN
    readonly property bool refreshInFlight: engine.inFlight
    readonly property bool manualRefreshAvailable: {
        const revision = engine.manualAvailabilityRevision;
        return revision >= 0 && engine.canManualRefresh();
    }
    readonly property real nextManualRefreshAt: engine.nextManualRefreshAt()
    readonly property real nextRequestAt: engine.nextRequestAt
    readonly property int requestCount: engine.requestCount
    readonly property bool locationConfigured: engine.locationKey !== ""
    readonly property int maximumResponseCharacters: 1048576
    readonly property int cacheSchemaVersion: 2
    readonly property var emptyModel: Object.freeze([])

    signal cacheSaved

    function refreshDeadlineReached() {
        engine.runRefresh();
    }

    function localDeadlineReached() {
        engine.runLocalDeadline();
    }

    function requestTimeoutReached() {
        engine.requestTimeoutReached();
    }

    function manualRefresh() {
        return engine.manualRefresh();
    }

    function manualRefreshDeadlineReached() {
        engine.armManualAvailability();
    }

    Component.onCompleted: applyLocation()
    onLatitudeChanged: engine.scheduleLocationSync()
    onLongitudeChanged: engine.scheduleLocationSync()
    onLabelChanged: engine.scheduleLocationSync()
    onVersionChanged: engine.scheduleLocationSync()
    onEnabledChanged: engine.scheduleLocationSync()
    onTemperatureUnitChanged: engine.rebuildModel()
    onWindUnitChanged: engine.rebuildModel()
    onRefreshPresetChanged: engine.rearmSuccessfulSchedule()

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
        id: manualRefreshTimer

        repeat: false
        onTriggered: root.manualRefreshDeadlineReached()
    }

    Timer {
        id: timeoutTimer

        repeat: false
        onTriggered: root.requestTimeoutReached()
    }

    QtObject {
        id: engine

        readonly property var backoffTiers: [600000, 1800000, 3600000, 10800000, 21600000]
        readonly property var throttleTiers: [3600000, 10800000, 21600000]
        readonly property real backoffJitterFraction: 0.2
        readonly property int refreshJitterMs: 300000
        readonly property int startupJitterMs: 30000
        readonly property int expiresFallbackMs: 3600000
        readonly property int minimumRefreshGapMs: 600000
        readonly property int manualRefreshCooldownMs: 60000
        readonly property int staleCutoffMs: 21600000
        readonly property int maximumTimestepAgeMs: 5400000
        readonly property int maximumTimeseriesEntries: 512
        readonly property int maximumObjectCount: 4096
        readonly property int maximumObjectDepth: 12
        readonly property int maximumStringLength: 256
        readonly property real minimumTemperatureC: -90
        readonly property real maximumTemperatureC: 60
        readonly property real minimumWindMs: 0
        readonly property real maximumWindMs: 150
        readonly property real minimumHumidity: 0
        readonly property real maximumHumidity: 100

        property string locationKey: ""
        property string activeVersion: ""
        property string requestLatitude: ""
        property string requestLongitude: ""

        property var cache: null
        property real expiresEpoch: Number.NaN
        property var normalized: null
        property var model: null
        property int modelGeneration: 0
        property real fetchedAt: Number.NaN
        property bool stale: false
        property string failure: "unconfigured"

        property int backoffIndex: 0
        property int throttleTier: 0
        property var permanentKey: null
        property real nextRequestAt: 0
        property real providerNotBeforeAt: 0
        property real lastManualRefreshAt: 0
        property int manualAvailabilityRevision: 0

        property bool inFlight: false
        property int requestCount: 0
        property int requestSerial: 0
        property var activeRequest: null
        property var warnedKeys: ({})
        property bool locationSyncScheduled: false

        onLocationKeyChanged: armManualAvailability()
        onPermanentKeyChanged: armManualAvailability()
        onProviderNotBeforeAtChanged: armManualAvailability()
        onLastManualRefreshAtChanged: armManualAvailability()
        onInFlightChanged: armManualAvailability()

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

        // MET Norway permits at most four decimals. Truncating toward zero
        // avoids disclosing more precision through rounding.
        function truncateCoordinate(value) {
            const scaled = value * 10000;
            const rounded = Math.round(scaled);
            const corrected = Math.abs(scaled - rounded) < 0.000001 ? rounded : scaled;
            const truncated = corrected < 0 ? Math.ceil(corrected) : Math.floor(corrected);
            return truncated === 0 ? 0 : truncated / 10000;
        }

        function labelFingerprint(value) {
            let hash = 2166136261;
            for (let index = 0; index < value.length; index += 1) {
                hash ^= value.charCodeAt(index);
                hash = Math.imul(hash, 16777619);
            }
            return (hash >>> 0).toString(16);
        }

        function utf8Length(value) {
            try {
                return encodeURIComponent(value).replace(/%[0-9A-F]{2}/gi, "x").length;
            } catch (error) {
                return Infinity;
            }
        }

        function validatedLocation() {
            if (!root.enabled || typeof root.latitude !== "number" || !Number.isFinite(root.latitude)
                    || typeof root.longitude !== "number" || !Number.isFinite(root.longitude)
                    || root.latitude < -90 || root.latitude > 90 || root.longitude < -180
                    || root.longitude > 180 || typeof root.label !== "string" || root.label.length
                    === 0 || utf8Length(root.label) > 128 || /[\x00-\x1F\x7F]/.test(root.label)) {
                return null;
            }

            const latitude = truncateCoordinate(root.latitude).toFixed(4);
            const longitude = truncateCoordinate(root.longitude).toFixed(4);
            return {
                "key": "v2|" + latitude + "|" + longitude + "|" + labelFingerprint(root.label),
                "latitude": latitude,
                "longitude": longitude
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
                rebuildModel();
                return;
            }

            abortActiveRequest();
            stopTimers();
            cache = null;
            expiresEpoch = Number.NaN;
            nextRequestAt = 0;
            providerNotBeforeAt = 0;
            lastManualRefreshAt = 0;
            backoffIndex = 0;
            throttleTier = 0;
            permanentKey = null;
            normalized = null;
            model = null;
            fetchedAt = Number.NaN;
            stale = false;
            locationKey = key;
            activeVersion = version;

            if (key === "") {
                requestLatitude = "";
                requestLongitude = "";
                failure = "unconfigured";
                clearCacheFile();
                modelGeneration += 1;
                return;
            }

            requestLatitude = location.latitude;
            requestLongitude = location.longitude;

            const now = currentTime();
            const record = loadCacheRecord(key);
            failure = "none";
            if (record !== null) {
                cache = record;
                const parsedExpires = Date.parse(record.expires);
                expiresEpoch = Number.isFinite(parsedExpires) ? parsedExpires : Number.NaN;
                providerNotBeforeAt = Number.isFinite(expiresEpoch) ? Math.max(expiresEpoch,
                                                                               record.validatedAt
                                                                               + minimumRefreshGapMs) :
                                                                      record.validatedAt
                                                                      + expiresFallbackMs;
                adoptRecord(now);
                armRefresh(successRefreshAt(record.validatedAt, expiresEpoch));
            } else {
                providerNotBeforeAt = now;
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

        function adoptRecord(now) {
            const parsed = normalizeForecast(cache.body, now);
            if (parsed === null) {
                clearWeather("stale");
            } else {
                commitNormalized(parsed, cache.retrievedAt);
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

            const parsed = normalizeForecast(cache.body, now);
            if (parsed === null) {
                clearWeather("stale");
            } else {
                normalized = parsed;
                stale = Number.isFinite(expiresEpoch) && expiresEpoch <= now;
                rebuildModel();
                if (failure === "stale") {
                    failure = "none";
                }
            }
            armLocalDeadline();
        }

        function boundedGraph(value) {
            let objectCount = 0;
            const stack = [
                      {
                          "value": value,
                          "depth": 0
                      }
                  ];
            while (stack.length > 0) {
                const frame = stack.pop();
                if (frame.depth > maximumObjectDepth) {
                    return false;
                }
                if (typeof frame.value === "string") {
                    if (frame.value.length > maximumStringLength) {
                        return false;
                    }
                    continue;
                }
                if (frame.value === null || typeof frame.value !== "object") {
                    continue;
                }
                objectCount += 1;
                if (objectCount > maximumObjectCount) {
                    return false;
                }
                const keys = Object.keys(frame.value);
                if (keys.length > maximumTimeseriesEntries) {
                    return false;
                }
                for (let index = 0; index < keys.length; index += 1) {
                    if (keys[index].length > 64) {
                        return false;
                    }
                    stack.push({
                                   "value": frame.value[keys[index]],
                                   "depth": frame.depth + 1
                               });
                }
            }
            return true;
        }

        function finiteRange(value, minimum, maximum) {
            return typeof value === "number" && Number.isFinite(value) && value >= minimum && value
                    <= maximum;
        }

        function normalizeEntry(entry) {
            if (entry === null || typeof entry !== "object" || typeof entry.time !== "string"
                    || entry.time.length > 40) {
                return null;
            }
            const epoch = Date.parse(entry.time);
            const data = entry.data;
            const details = data !== null && typeof data === "object" && data.instant !== null
                  && typeof data.instant === "object" && data.instant.details !== null
                  && typeof data.instant.details === "object" ? data.instant.details : null;
            if (!Number.isFinite(epoch) || details === null || !finiteRange(details.air_temperature,
                                                                            minimumTemperatureC,
                                                                            maximumTemperatureC) ||
                    !finiteRange(details.relative_humidity, minimumHumidity, maximumHumidity) ||
                    !finiteRange(details.wind_speed, minimumWindMs, maximumWindMs)) {
                return null;
            }

            const nextHour = data.next_1_hours;
            const summary = nextHour !== null && typeof nextHour === "object" && nextHour.summary !== null
                  && typeof nextHour.summary === "object" ? nextHour.summary : null;
            const code = summary === null ? "" : summary.symbol_code;
            if (code !== "" && (typeof code !== "string" || !/^[a-z0-9_]{1,64}$/.test(code))) {
                return null;
            }
            const symbol = code === "" ? {
                                             "condition": "unknown",
                                             "dayPhase": "day"
                                         } : normalizeSymbol(code);
            return {
                "forecastEpoch": epoch,
                "temperatureC": details.air_temperature,
                "humidity": details.relative_humidity,
                "windMs": details.wind_speed,
                "condition": symbol.condition,
                "dayPhase": symbol.dayPhase,
                "hasSymbol": code !== ""
            };
        }

        function feelsLikeC(temperatureC, humidity, windMs) {
            if (temperatureC > 26 && humidity > 40) {
                const fahrenheit = temperatureC * 9 / 5 + 32;
                const heatIndexF = -42.379 + 2.04901523 * fahrenheit + 10.14333127 * humidity
                      - 0.22475541 * fahrenheit * humidity - 0.00683783 * fahrenheit * fahrenheit
                      - 0.05481717 * humidity * humidity + 0.00122874 * fahrenheit * fahrenheit
                      * humidity + 0.00085282 * fahrenheit * humidity * humidity - 0.00000199
                      * fahrenheit * fahrenheit * humidity * humidity;
                return Math.max(temperatureC, Math.min(80, (heatIndexF - 32) * 5 / 9));
            }
            if (temperatureC < 10 && windMs > 1.33) {
                const windKmhPower = Math.pow(windMs * 3.6, 0.16);
                return Math.max(-120, 13.12 + 0.6215 * temperatureC - 11.37 * windKmhPower + 0.3965
                                * temperatureC * windKmhPower);
            }
            return temperatureC;
        }

        function dailyEntries(entries, now) {
            const groups = {};
            const order = [];
            for (let index = 0; index < entries.length; index += 1) {
                const entry = entries[index];
                if (entry.forecastEpoch < now - maximumTimestepAgeMs) {
                    continue;
                }
                const date = new Date(entry.forecastEpoch);
                const key = date.getFullYear() + "-" + date.getMonth() + "-" + date.getDate();
                if (groups[key] === undefined) {
                    if (order.length >= 5) {
                        continue;
                    }
                    groups[key] = [];
                    order.push({
                                   "key": key,
                                   "epoch": new Date(date.getFullYear(), date.getMonth(),
                                                     date.getDate()).getTime()
                               });
                }
                groups[key].push(entry);
            }

            const result = [];
            for (let index = 0; index < order.length; index += 1) {
                const values = groups[order[index].key];
                let minimum = Infinity;
                let maximum = -Infinity;
                let representative = values[0];
                let representativeDistance = Infinity;
                for (let valueIndex = 0; valueIndex < values.length; valueIndex += 1) {
                    const value = values[valueIndex];
                    minimum = Math.min(minimum, value.temperatureC);
                    maximum = Math.max(maximum, value.temperatureC);
                    const hourDistance = Math.abs(new Date(value.forecastEpoch).getHours() - 12);
                    if (value.hasSymbol && hourDistance < representativeDistance) {
                        representative = value;
                        representativeDistance = hourDistance;
                    }
                }
                result.push({
                                "dateEpoch": order[index].epoch,
                                "minimumTemperatureC": minimum,
                                "maximumTemperatureC": maximum,
                                "condition": representative.condition,
                                "dayPhase": representative.dayPhase
                            });
            }
            return result;
        }

        function normalizeForecast(bodyText, now) {
            let parsed = null;
            try {
                parsed = JSON.parse(bodyText);
            } catch (error) {
                return null;
            }
            if (!boundedGraph(parsed) || parsed === null || typeof parsed !== "object" || parsed.properties
                    === null || typeof parsed.properties !== "object" || parsed.properties.meta
                    === null || typeof parsed.properties.meta !== "object"
                    || parsed.properties.meta.units === null || typeof parsed.properties.meta.units
                    !== "object" || parsed.properties.meta.units.air_temperature !== "celsius"
                    || parsed.properties.meta.units.relative_humidity !== "%"
                    || parsed.properties.meta.units.wind_speed !== "m/s" || !Array.isArray(
                        parsed.properties.timeseries) || parsed.properties.timeseries.length === 0
                    || parsed.properties.timeseries.length > maximumTimeseriesEntries) {
                return null;
            }

            const entries = [];
            for (let index = 0; index < parsed.properties.timeseries.length; index += 1) {
                const entry = normalizeEntry(parsed.properties.timeseries[index]);
                if (entry === null || (entries.length > 0 && entry.forecastEpoch
                                       <= entries[entries.length - 1].forecastEpoch)) {
                    return null;
                }
                entries.push(entry);
            }

            let currentEntry = null;
            for (let index = 0; index < entries.length; index += 1) {
                if (entries[index].forecastEpoch <= now && now - entries[index].forecastEpoch
                        <= maximumTimestepAgeMs && entries[index].hasSymbol) {
                    currentEntry = entries[index];
                }
            }
            if (currentEntry === null) {
                return null;
            }

            const currentValue = Object.assign({}, currentEntry, {
                                                   "feelsLikeC": feelsLikeC(
                                                                     currentEntry.temperatureC,
                                                                     currentEntry.humidity,
                                                                     currentEntry.windMs),
                                                   "feelsLikeCalculated": true
                                               });
            const hourly = [];
            const horizon = now + 12 * 60 * 60 * 1000;
            for (let index = 0; index < entries.length && hourly.length < 12; index += 1) {
                if (entries[index].forecastEpoch > now && entries[index].forecastEpoch <= horizon) {
                    hourly.push(entries[index]);
                }
            }
            return {
                "current": currentValue,
                "hourly": hourly,
                "daily": dailyEntries(entries, now)
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

        function resolvedTemperatureUnit() {
            if (root.temperatureUnit === "celsius" || root.temperatureUnit === "fahrenheit") {
                return root.temperatureUnit;
            }
            return Qt.locale().measurementSystem === Locale.ImperialUSSystem ? "fahrenheit" :
                                                                               "celsius";
        }

        function resolvedWindUnit() {
            if (root.windUnit === "kmh" || root.windUnit === "mph" || root.windUnit === "ms") {
                return root.windUnit;
            }
            return Qt.locale().measurementSystem === Locale.ImperialUSSystem ? "mph" : "kmh";
        }

        function convertTemperature(value, unit) {
            return unit === "fahrenheit" ? value * 9 / 5 + 32 : value;
        }

        function convertWind(value, unit) {
            return unit === "mph" ? value * 2.2369362921 : unit === "kmh" ? value * 3.6 : value;
        }

        function presentationEntry(entry, temperatureUnitValue, windUnitValue) {
            const result = {
                "forecastEpoch": entry.forecastEpoch,
                "temperatureC": entry.temperatureC,
                "temperature": convertTemperature(entry.temperatureC, temperatureUnitValue),
                "temperatureUnit": temperatureUnitValue,
                "humidity": entry.humidity,
                "windMs": entry.windMs,
                "wind": convertWind(entry.windMs, windUnitValue),
                "windUnit": windUnitValue,
                "condition": entry.condition,
                "dayPhase": entry.dayPhase
            };
            if (entry.feelsLikeC !== undefined) {
                result.feelsLikeC = entry.feelsLikeC;
                result.feelsLike = convertTemperature(entry.feelsLikeC, temperatureUnitValue);
                result.feelsLikeCalculated = true;
            }
            return Object.freeze(result);
        }

        function rebuildModel() {
            if (normalized === null) {
                return;
            }
            const temperatureUnitValue = resolvedTemperatureUnit();
            const windUnitValue = resolvedWindUnit();
            const hourlyValues = [];
            for (let index = 0; index < normalized.hourly.length; index += 1) {
                hourlyValues.push(presentationEntry(normalized.hourly[index], temperatureUnitValue,
                                                    windUnitValue));
            }
            const dailyValues = [];
            for (let index = 0; index < normalized.daily.length; index += 1) {
                const entry = normalized.daily[index];
                dailyValues.push(Object.freeze({
                                                   "dateEpoch": entry.dateEpoch,
                                                   "minimumTemperature": convertTemperature(
                                                                             entry.minimumTemperatureC,
                                                                             temperatureUnitValue),
                                                   "maximumTemperature": convertTemperature(
                                                                             entry.maximumTemperatureC,
                                                                             temperatureUnitValue),
                                                   "temperatureUnit": temperatureUnitValue,
                                                   "condition": entry.condition,
                                                   "dayPhase": entry.dayPhase
                                               }));
            }
            modelGeneration += 1;
            model = Object.freeze({
                                      "generation": modelGeneration,
                                      "location": root.label,
                                      "current": presentationEntry(normalized.current,
                                                                   temperatureUnitValue,
                                                                   windUnitValue),
                                      "hourly": Object.freeze(hourlyValues),
                                      "daily": Object.freeze(dailyValues),
                                      "stale": stale,
                                      "fetchedAtEpoch": fetchedAt
                                  });
        }

        function commitNormalized(value, fetchedEpoch) {
            normalized = value;
            fetchedAt = fetchedEpoch;
            stale = Number.isFinite(expiresEpoch) && expiresEpoch <= currentTime();
            failure = "none";
            rebuildModel();
        }

        function clearWeather(kind) {
            normalized = null;
            model = null;
            modelGeneration += 1;
            fetchedAt = Number.NaN;
            stale = false;
            failure = kind;
        }

        function runRefresh() {
            if (locationKey === "" || permanentKey !== null || inFlight) {
                return;
            }
            const now = currentTime();
            if (nextRequestAt > now || providerNotBeforeAt > now) {
                return;
            }
            const url = "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat="
                  + requestLatitude + "&lon=" + requestLongitude;
            const headers = {
                // Qt's network stack transparently negotiates gzip/deflate.
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
            const handle = root.transport === null ? builtinRequest(request) : root.transport.create(
                                                         request);


            if (serial === requestSerial && inFlight) {
                activeRequest = handle;
            }
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
            activeRequest = null;
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
            const parsed = normalizeForecast(body, now);
            if (parsed === null) {
                scheduleBackoff();
                return;
            }

            const expiresHeader = typeof headers["expires"] === "string" ? headers["expires"] : "";
            const parsedExpires = Date.parse(expiresHeader);
            expiresEpoch = Number.isFinite(parsedExpires) ? parsedExpires : now + expiresFallbackMs;
            const lastModified = typeof headers["last-modified"] === "string"
                  ? headers["last-modified"] : "";
            cache = {
                "schemaVersion": root.cacheSchemaVersion,
                "locationKey": locationKey,
                "body": body,
                "expires": new Date(expiresEpoch).toUTCString(),
                "lastModified": lastModified,
                "retrievedAt": now,
                "validatedAt": now
            };
            backoffIndex = 0;
            throttleTier = 0;
            providerNotBeforeAt = Math.max(expiresEpoch, now + minimumRefreshGapMs);
            commitNormalized(parsed, now);
            writeCache(cache);
            armRefresh(successRefreshAt(now, expiresEpoch));
            armLocalDeadline();
            if (status === 203) {
                warnOnce("deprecated",
                         "weather: provider reports deprecating data; honoring cache headers");
            }
        }

        function adoptNotModified(outcome, now) {
            if (cache === null || cache.lastModified === "") {
                scheduleBackoff();
                return;
            }
            const headers = outcome.headers !== null && typeof outcome.headers === "object" ? outcome.headers :
                                                                                              {};
            const expiresHeader = typeof headers["expires"] === "string" ? headers["expires"] : "";
            const parsedExpires = Date.parse(expiresHeader);
            expiresEpoch = Number.isFinite(parsedExpires) ? parsedExpires : now + expiresFallbackMs;
            const lastModified = typeof headers["last-modified"] === "string"
                  ? headers["last-modified"] : "";
            cache = {
                "schemaVersion": cache.schemaVersion,
                "locationKey": cache.locationKey,
                "body": cache.body,
                "expires": new Date(expiresEpoch).toUTCString(),
                "lastModified": lastModified === "" ? cache.lastModified : lastModified,
                "retrievedAt": cache.retrievedAt,
                "validatedAt": now
            };
            const parsed = normalizeForecast(cache.body, now);
            if (parsed === null) {
                scheduleBackoff();
                return;
            }
            backoffIndex = 0;
            throttleTier = 0;
            providerNotBeforeAt = Math.max(expiresEpoch, now + minimumRefreshGapMs);
            commitNormalized(parsed, cache.retrievedAt);
            writeCache(cache);
            armRefresh(successRefreshAt(now, expiresEpoch));
            armLocalDeadline();
        }

        function refreshPresetMs() {
            if (root.refreshPreset === "15m")
                return 900000;
            if (root.refreshPreset === "30m")
                return 1800000;
            if (root.refreshPreset === "3h")
                return 10800000;
            return 3600000;
        }

        function successRefreshAt(now, expiresEpochValue) {
            const providerAt = Number.isFinite(expiresEpochValue) ? Math.max(expiresEpochValue, now
                                                                             + minimumRefreshGapMs) :
                                                                    now + expiresFallbackMs;
            providerNotBeforeAt = providerAt;
            return Math.max(providerAt, now + refreshPresetMs()) + jitter(refreshJitterMs);
        }

        function rearmSuccessfulSchedule() {
            if (cache !== null && permanentKey === null && !inFlight) {
                armRefresh(successRefreshAt(cache.validatedAt, expiresEpoch));
            }
        }

        function nextManualRefreshAt() {
            return Math.max(providerNotBeforeAt, lastManualRefreshAt + manualRefreshCooldownMs);
        }

        function canManualRefresh() {
            return locationKey !== "" && permanentKey === null && !inFlight && currentTime()
                    >= nextManualRefreshAt();
        }

        function armManualAvailability() {
            manualRefreshTimer.stop();
            manualAvailabilityRevision += 1;
            if (locationKey === "" || permanentKey !== null || inFlight) {
                return;
            }
            const now = currentTime();
            const deadline = nextManualRefreshAt();
            if (deadline > now) {
                manualRefreshTimer.interval = Math.max(1, Math.floor(deadline - now));
                manualRefreshTimer.restart();
            }
        }

        function manualRefresh() {
            if (!canManualRefresh()) {
                return false;
            }
            lastManualRefreshAt = currentTime();
            armRefresh(lastManualRefreshAt);
            runRefresh();
            return true;
        }

        function scheduleBackoff() {
            const now = currentTime();
            const index = Math.min(backoffIndex, backoffTiers.length - 1);
            backoffIndex = Math.min(index + 1, backoffTiers.length - 1);
            const delay = backoffTiers[index] + jitter(Math.floor(backoffTiers[index]
                                                                  * backoffJitterFraction));
            failure = "transient";
            providerNotBeforeAt = now + delay;
            armRefresh(providerNotBeforeAt);
        }

        function scheduleThrottle(headers, now) {
            const raw = headers !== null && typeof headers === "object" && typeof headers["retry-after"]
                  === "string" ? headers["retry-after"] : "";
            let retryAfter = 0;
            if (/^[0-9]+$/.test(raw)) {
                retryAfter = Math.min(parseInt(raw, 10) * 1000, staleCutoffMs);
            } else {
                const parsed = Date.parse(raw);
                if (Number.isFinite(parsed)) {
                    retryAfter = Math.max(0, Math.min(parsed - now, staleCutoffMs));
                }
            }
            const tierDelay = throttleTiers[Math.min(throttleTier, throttleTiers.length - 1)];
            throttleTier = Math.min(throttleTier + 1, throttleTiers.length - 1);
            const base = Math.max(retryAfter, tierDelay);
            const delay = base + jitter(Math.floor(base * backoffJitterFraction));
            failure = "throttled";
            providerNotBeforeAt = now + delay;
            armRefresh(providerNotBeforeAt);
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
            manualRefreshTimer.stop();
        }

        function abortActiveRequest() {
            requestSerial += 1;
            const active = activeRequest;
            activeRequest = null;
            inFlight = false;
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
                                             + " https://github.com/Anthodev/nagi-shell"

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

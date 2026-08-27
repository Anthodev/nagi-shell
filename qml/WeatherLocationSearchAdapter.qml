pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

// Explicit, bounded city/postal lookup. It owns no location history and starts
// network work only from search(). Results are normalized before publication;
// queries, URLs, coordinates, and raw provider content never enter logs.
Scope {
    id: root

    property bool allowed: false
    property string version: "0.1.0"
    property var wallNow: null
    property var transport: null
    property int requestTimeoutMs: 10000
    property string nominatimEndpoint: "https://nominatim.openstreetmap.org"

    readonly property bool inFlight: engine.inFlight
    readonly property var results: engine.results
    readonly property string failure: engine.failure
    readonly property string attribution: engine.attribution
    readonly property int requestCount: engine.requestCount
    readonly property int maximumResults: 5
    readonly property int maximumResponseCharacters: 262144
    readonly property var emptyResults: Object.freeze([])

    function search(query) {
        return engine.search(query);
    }

    function clear() {
        engine.clear();
    }

    function requestTimeoutReached() {
        engine.requestTimeoutReached();
    }

    onAllowedChanged: {
        if (!allowed) {
            clear();
        }
    }

    Timer {
        id: timeoutTimer
        repeat: false
        onTriggered: root.requestTimeoutReached()
    }

    QtObject {
        id: engine

        property bool inFlight: false
        property var results: root.emptyResults
        property string failure: "none"
        property string attribution: "Location data by GeoNames via Open-Meteo · CC BY 4.0"
        property int requestCount: 0
        property int serial: 0
        property var activeRequest: null
        property string activeProvider: ""
        property string activeEncodedQuery: ""
        property real lastNominatimAt: -1000

        function currentTime() {
            const value = root.wallNow === null ? Date.now() : root.wallNow();
            return typeof value === "number" && Number.isFinite(value) ? value : 0;
        }

        function utf8Length(value) {
            try {
                return encodeURIComponent(value).replace(/%[0-9A-F]{2}/gi, "x").length;
            } catch (error) {
                return Infinity;
            }
        }

        function validQuery(query) {
            if (typeof query !== "string") {
                return "";
            }
            const value = query.trim();
            if (value.length < 2 || utf8Length(value) > 128 || /[\x00-\x1F\x7F]/.test(value)) {
                return "";
            }
            return value;
        }

        function search(query) {
            if (!root.allowed || inFlight) {
                return false;
            }
            const value = validQuery(query);
            if (value === "") {
                failure = "invalid-query";
                results = root.emptyResults;
                return false;
            }
            results = root.emptyResults;
            failure = "none";
            attribution = "Location data by GeoNames via Open-Meteo · CC BY 4.0";
            activeEncodedQuery = encodeURIComponent(value);
            start("openmeteo", "https://geocoding-api.open-meteo.com/v1/search?name="
                  + activeEncodedQuery + "&count=5&format=json&language=en");
            return true;
        }

        function start(provider, url) {
            serial += 1;
            const requestSerial = serial;
            activeProvider = provider;
            inFlight = true;
            requestCount += 1;
            timeoutTimer.interval = Math.max(1, root.requestTimeoutMs);
            timeoutTimer.restart();
            const request = {
                "url": url,
                "headers": {
                    "User-Agent": "NagiShell/" + root.version
                                  + " https://github.com/Anthodev/nagi-shell"
                },
                "onCompleted": function (outcome) {
                    if (requestSerial !== serial || !inFlight) {
                        return;
                    }
                    finish(outcome);
                }
            };
            const handle = root.transport === null ? builtinRequest(request) : root.transport.create(
                                                         request);


            if (requestSerial === serial && inFlight) {
                activeRequest = handle;
            }
        }

        function builtinRequest(request) {
            const xhr = new XMLHttpRequest();
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE) {
                    return;
                }
                request.onCompleted(xhr.status === 0 ? {
                                                           "networkError": true
                                                       } : {
                                        "status": xhr.status,
                                        "bodyText": xhr.responseText
                                    });
            };
            xhr.open("GET", request.url, true);
            xhr.setRequestHeader("User-Agent", request.headers["User-Agent"]);
            xhr.send();
            return {
                "abort": function () {
                    xhr.abort();
                }
            };
        }

        function finish(outcome) {
            inFlight = false;
            activeRequest = null;
            timeoutTimer.stop();
            if (outcome === null || typeof outcome !== "object" || outcome.networkError === true
                    || typeof outcome.status !== "number") {
                fallbackOrFail();
                return;
            }
            const status = Math.floor(outcome.status);
            if (status === 200) {
                const normalized = activeProvider === "openmeteo" ? normalizeOpenMeteo(
                                                                        outcome.bodyText) :
                                                                    normalizeNominatim(
                                                                        outcome.bodyText);
                if (normalized === null) {
                    fallbackOrFail();
                    return;
                }
                results = Object.freeze(normalized);
                failure = normalized.length === 0 ? "no-results" : "none";
                activeEncodedQuery = "";
                return;
            }
            if (status === 429) {
                failure = "throttled";
                results = root.emptyResults;
                activeEncodedQuery = "";
                return;
            }
            if (status >= 500) {
                fallbackOrFail();
                return;
            }
            failure = "provider";
            results = root.emptyResults;
            activeEncodedQuery = "";
        }

        function fallbackOrFail() {
            if (activeProvider !== "openmeteo") {
                failure = "unavailable";
                results = root.emptyResults;
                activeEncodedQuery = "";
                return;
            }
            const now = currentTime();
            if (now - lastNominatimAt < 1000) {
                failure = "rate-limited";
                activeEncodedQuery = "";
                return;
            }
            if (activeEncodedQuery === "") {
                failure = "unavailable";
                return;
            }
            const endpoint = normalizedNominatimEndpoint();
            if (endpoint === "") {
                failure = "unavailable";
                activeEncodedQuery = "";
                return;
            }
            lastNominatimAt = now;
            attribution = "Location data © OpenStreetMap contributors · ODbL";
            start("nominatim", endpoint + "/search?format=jsonv2&limit=5&addressdetails=1&q="
                  + activeEncodedQuery);
        }

        function normalizedNominatimEndpoint() {
            const value = root.nominatimEndpoint.replace(/\/+$/, "");
            return /^https:\/\/[A-Za-z0-9.-]+(?::[0-9]{1,5})?(?:\/[A-Za-z0-9._~-]*)*$/.test(value)
                    ? value : "";
        }

        function boundedString(value, maximum, allowEmpty) {
            return typeof value === "string" && utf8Length(value) <= maximum && (allowEmpty
                                                                                 || value.length
                                                                                 > 0) && !
                    /[\x00-\x1F\x7F]/.test(value);
        }

        function location(labelParts, latitude, longitude) {
            if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90 || !Number.isFinite(
                        longitude) || longitude < -180 || longitude > 180) {
                return null;
            }
            const parts = [];
            for (let index = 0; index < labelParts.length; index += 1) {
                const part = labelParts[index];
                if (boundedString(part, 128, true) && part !== "" && parts.indexOf(part) === -1) {
                    parts.push(part);
                }
            }
            const label = parts.join(", ");
            if (!boundedString(label, 128, false)) {
                return null;
            }
            return Object.freeze({
                                     "label": label,
                                     "latitude": latitude,
                                     "longitude": longitude
                                 });
        }

        function normalizeOpenMeteo(bodyText) {
            if (typeof bodyText !== "string" || bodyText.length === 0 || bodyText.length
                    > root.maximumResponseCharacters) {
                return null;
            }
            let parsed = null;
            try {
                parsed = JSON.parse(bodyText);
            } catch (error) {
                return null;
            }
            if (parsed === null || typeof parsed !== "object" || (parsed.results !== undefined &&
                                                                  !Array.isArray(parsed.results))) {
                return null;
            }
            const source = parsed.results ?? [];
            if (source.length > 100) {
                return null;
            }
            const values = [];
            for (let index = 0; index < source.length && values.length < root.maximumResults; index
                 += 1) {
                const item = source[index];
                if (item === null || typeof item !== "object" || !boundedString(item.name, 128,
                                                                                false)) {
                    return null;
                }
                const value = location([item.name, item.admin1 ?? "", item.country ?? ""], item.latitude,
                                       item.longitude);
                if (value === null) {
                    return null;
                }
                values.push(value);
            }
            return values;
        }

        function normalizeNominatim(bodyText) {
            if (typeof bodyText !== "string" || bodyText.length === 0 || bodyText.length
                    > root.maximumResponseCharacters) {
                return null;
            }
            let parsed = null;
            try {
                parsed = JSON.parse(bodyText);
            } catch (error) {
                return null;
            }
            if (!Array.isArray(parsed) || parsed.length > 50) {
                return null;
            }
            const values = [];
            for (let index = 0; index < parsed.length && values.length < root.maximumResults; index
                 += 1) {
                const item = parsed[index];
                if (item === null || typeof item !== "object" || !boundedString(item.display_name,
                                                                                512, false)) {
                    return null;
                }
                const parts = item.display_name.split(",").slice(0, 3).map(function (part) {
                    return part.trim();
                });
                const value = location(parts, Number(item.lat), Number(item.lon));
                if (value === null) {
                    return null;
                }
                values.push(value);
            }
            return values;
        }

        function requestTimeoutReached() {
            if (!inFlight) {
                return;
            }
            abort();
            failure = "timeout";
        }

        function abort() {
            serial += 1;
            const request = activeRequest;
            activeRequest = null;
            inFlight = false;
            timeoutTimer.stop();
            if (request !== null && request !== undefined && typeof request.abort === "function") {
                request.abort();
            }
        }

        function clear() {
            abort();
            results = root.emptyResults;
            failure = "none";
            activeProvider = "";
            activeEncodedQuery = "";
        }
    }
}

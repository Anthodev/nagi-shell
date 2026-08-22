import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    property real nowMs: 1755800400000
    property int runId: Quickshell.processId
    property int fileCounter: 0
    property var rngQueue: []
    property var sharedFirst: null
    property var sharedSecond: null
    property var sharedThird: null
    property var sharedFourth: null
    property var sharedFirstCap: null
    property var sharedSecondCap: null
    property var sharedThirdCap: null
    property var sharedFourthCap: null

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function nextRandom() {
        return rngQueue.length > 0 ? rngQueue.shift() : 0;
    }

    // QML copies plain JavaScript objects when they cross into a var property,
    // so the harness keeps each capture record here and hands the adapter only
    // the transport whose closures reach the original record.
    function newCapture(responder) {
        const record = {
            "requests": [],
            "responder": responder
        };
        const transport = {
            "create": function (request) {
                record.requests.push(request);
                const outcome = record.responder === null ? null : record.responder(
                        record.requests.length, request);
                if (outcome !== null && typeof outcome === "object") {
                    request.onCompleted(outcome);
                }

                return {
                    "abort": function () {}
                };
            }
        };
        return {
            "record": record,
            "transport": transport
        };
    }

    function metEntry(offsetMs, temperature, symbolCode) {
        return {
            "time": new Date(test.nowMs + offsetMs).toISOString(),
            "data": {
                "instant": {
                    "details": {
                        "air_temperature": temperature
                    }
                },
                "next_1_hours": {
                    "summary": {
                        "symbol_code": symbolCode
                    }
                }
            }
        };
    }

    function metBody(entries) {
        return JSON.stringify({
                                  "properties": {
                                      "timeseries": entries
                                  }
                              });
    }

    function ok(status, bodyText, expiresDeltaMs, lastModified) {
        return {
            "status": status,
            "headers": {
                "expires": new Date(test.nowMs + expiresDeltaMs).toUTCString(),
                "last-modified": lastModified
            },
            "bodyText": bodyText
        };
    }

    function makeWeather(overrides) {
        const properties = {
            "wallNow": function () {
                return test.nowMs;
            },
            "randomSource": function () {
                return test.nextRandom();
            },
            "cacheDirectory": Quickshell.shellDir,
            "cacheFileName": "weather-" + test.runId + "-" + (test.fileCounter++) + ".json"
        };
        for (const key in overrides) {
            properties[key] = overrides[key];
        }

        return weatherFactory.createObject(test, properties);
    }

    function conditionFor(symbolCode) {
        const capture = newCapture(function () {
            return ok(200, metBody([metEntry(-600000, 12.5, symbolCode)]), 1800000, "Symbol LM");
        });
        const weather = makeWeather({
                                        "latitude": 48.8566,
                                        "longitude": 2.3522,
                                        "transport": capture.transport
                                    });
        weather.refreshDeadlineReached();
        require(weather.available, "condition probe for " + symbolCode + " exposes state");
        const result = {
            "condition": weather.condition,
            "dayPhase": weather.dayPhase
        };
        weather.destroy();
        return result;
    }

    function run() {
        rngQueue = [];

        // Unconfigured and invalid locations never request and stay unavailable.
        const unconfiguredCap = newCapture(null);
        const unconfigured = makeWeather({
                                             "transport": unconfiguredCap.transport
                                         });
        unconfigured.refreshDeadlineReached();
        require(!unconfigured.locationConfigured && !unconfigured.available
                && unconfigured.failure === "unconfigured",
                "unconfigured weather stays unavailable without requests");
        require(unconfiguredCap.record.requests.length === 0,
                "unconfigured weather sends no request");

        const invalidLatitudeCap = newCapture(null);
        const invalidLatitude = makeWeather({
                                                "latitude": 95.0,
                                                "longitude": 10.0,
                                                "transport": invalidLatitudeCap.transport
                                            });
        invalidLatitude.refreshDeadlineReached();
        require(invalidLatitude.failure === "unconfigured"
                && invalidLatitudeCap.record.requests.length === 0,
                "out-of-range latitude performs no request");

        const fractionalAltitudeCap = newCapture(null);
        const fractionalAltitude = makeWeather({
                                                   "latitude": 10.0,
                                                   "longitude": 10.0,
                                                   "altitude": 12.5,
                                                   "transport": fractionalAltitudeCap.transport
                                               });
        fractionalAltitude.refreshDeadlineReached();
        require(fractionalAltitude.failure === "unconfigured"
                && fractionalAltitudeCap.record.requests.length === 0,
                "fractional altitude performs no request");

        // Requests carry truncated coarse coordinates, the identifying public
        // User-Agent, no credential, and never the local label.
        const shapedCap = newCapture(null);
        const shaped = makeWeather({
                                       "latitude": 48.8566,
                                       "longitude": 2.3522,
                                       "altitude": 35,
                                       "label": "Home label",
                                       "transport": shapedCap.transport
                                   });
        shaped.refreshDeadlineReached();
        require(shapedCap.record.requests.length === 1,
                "configured weather sends exactly its scheduled request");
        const shapedRequest = shapedCap.record.requests[0];
        require(shapedRequest.url
                === "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=48.85&lon=2.35&altitude=35",
                "request URL uses two-decimal truncated coordinates");
        require(shapedRequest.headers["User-Agent"]
                === "NagiShell/0.1.0 github.com/Anthodev/nagi-shell",
                "requests identify Nagi Shell with the public User-Agent");
        require(shapedRequest.url.indexOf("Home") === -1,
                "the local label never leaves the machine");
        require(Object.keys(shapedRequest.headers).length === 1,
                "requests carry no credential or extra header");

        const negativeShapedCap = newCapture(null);
        const negativeShaped = makeWeather({
                                               "latitude": -33.8688,
                                               "longitude": -74.0066,
                                               "transport": negativeShapedCap.transport
                                           });
        negativeShaped.refreshDeadlineReached();
        require(negativeShapedCap.record.requests[0].url.indexOf("?lat=-33.86&lon=-74.00")
                !== -1 && negativeShapedCap.record.requests[0].url.indexOf("altitude") === -1,
                "negative coordinates truncate toward zero and unknown altitude is omitted");

        const zeroishShapedCap = newCapture(null);
        const zeroishShaped = makeWeather({
                                              "latitude": 0.001,
                                              "longitude": -0.001,
                                              "transport": zeroishShapedCap.transport
                                          });
        zeroishShaped.refreshDeadlineReached();
        require(zeroishShapedCap.record.requests[0].url.indexOf("?lat=0.00&lon=0.00") !== -1,
                "near-zero coordinates normalize without a negative-zero sign");

        // A valid response exposes temperature and normalized condition from
        // one current timestep and honors the expiry schedule with jitter.
        const validCap = newCapture(null);
        const valid = makeWeather({
                                      "latitude": 48.8566,
                                      "longitude": 2.3522,
                                      "transport": validCap.transport
                                  });
        const completionTime = test.nowMs;
        valid.refreshDeadlineReached();
        validCap.record.requests[0].onCompleted(ok(
                                                     200,
                                                     metBody([metEntry(-1800000, 21.5,
                                                                       "partlycloudy_day"),
                                                         metEntry(-600000, 18.4, "clearsky_night")]),
                                                     1800000, "LM-1"));
        require(valid.available && !valid.stale && valid.failure === "none",
                "a valid response is available and fresh");
        require(valid.temperatureC === 18.4 && valid.condition === "clear"
                && valid.dayPhase === "night",
                "state comes from the latest satisfying single timestep");
        require(valid.forecastTime.getTime() === completionTime - 600000,
                "forecast time matches the selected entry");
        require(valid.fetchedAt.getTime() === completionTime,
                "fetched time marks the retrieval");
        require(valid.nextRequestAt === Math.max(completionTime + 1800000,
                                                 completionTime + 600000),
                "zero jitter schedules the next request exactly at expiry");

        // Symbol normalization matrix: intensity and shower variants collapse;
        // day-phase suffixes separate; thunder wins over precipitation families.
        const matrix = [["clearsky", "clear", "day"], ["fair", "mostlyClear", "day"],
            ["partlycloudy_day", "partlyCloudy", "day"],
            ["partlycloudy_night", "partlyCloudy", "night"], ["cloudy", "cloudy", "day"],
            ["fog_polartwilight", "fog", "polartwilight"],
            ["heavyrainshowersandthunder_day", "thunderstorm", "day"],
            ["lightsleetshowers_night", "sleet", "night"], ["heavysnow", "snow", "day"],
            ["rainshowers_day", "rain", "day"], ["lightrain", "rain", "day"],
            ["sleet", "sleet", "day"]];
        for (let index = 0; index < matrix.length; index += 1) {
            const normalized = conditionFor(matrix[index][0]);
            require(normalized.condition === matrix[index][1] && normalized.dayPhase
                    === matrix[index][2],
                    "symbol " + matrix[index][0] + " normalizes to " + matrix[index][1] + "/"
                    + matrix[index][2]);
        }

        require(conditionFor("mysterycode").condition === "unknown",
                "unknown provider codes map to the bounded unknown condition");

        // Only one request may be in flight, and none before the deadline.
        const gatedCap = newCapture(null);
        const gated = makeWeather({
                                      "latitude": 48.8566,
                                      "longitude": 2.3522,
                                      "transport": gatedCap.transport
                                  });
        gated.refreshDeadlineReached();
        gated.refreshDeadlineReached();
        require(gatedCap.record.requests.length === 1,
                "no second request starts while one is in flight");
        gatedCap.record.requests[0].onCompleted(ok(200,
                                                   metBody([metEntry(-600000, 9.9, "fog")]),
                                                   3600000, "LM-2"));
        gated.refreshDeadlineReached();
        require(gatedCap.record.requests.length === 1,
                "no request occurs before Expires");

        test.nowMs += 3600000;
        gated.refreshDeadlineReached();
        require(gatedCap.record.requests.length === 2,
                "expiry opens the conditional refresh window");
        require(gatedCap.record.requests[1].headers["If-Modified-Since"] === "LM-2",
                "the conditional request replays the exact cached Last-Modified value");
        const notModifiedAt = test.nowMs;
        gatedCap.record.requests[1].onCompleted({
                                                    "status": 304,
                                                    "headers": {
                                                        "expires": new Date(
                                                            test.nowMs + 7200000).toUTCString()
                                                    },
                                                    "bodyText": ""
                                                });
        require(gated.available && gated.temperatureC === 9.9 && !gated.stale,
                "a 304 keeps the cached body and reselects state locally");
        require(gated.nextRequestAt === Math.max(notModifiedAt + 7200000,
                                                 notModifiedAt + 600000),
                "a 304 refreshes validation metadata from the new headers");

        // Timeouts and network errors take the transient backoff tiers.
        const timingOutCap = newCapture(null);
        const timingOut = makeWeather({
                                          "latitude": 48.8566,
                                          "longitude": 2.3522,
                                          "transport": timingOutCap.transport
                                      });
        timingOut.refreshDeadlineReached();
        require(timingOutCap.record.requests.length === 1,
                "timeout scenario sends its request");
        timingOut.requestTimeoutReached();
        require(timingOut.failure === "transient" && !timingOut.available,
                "an aborted request is a transient failure without state");
        require(timingOut.nextRequestAt === test.nowMs + 600000,
                "first transient failure retries after ten minutes plus jitter");
        const expectedTiers = [1800000, 3600000, 10800000, 21600000, 21600000];
        for (let tier = 1; tier < 6; tier += 1) {
            test.nowMs = timingOut.nextRequestAt;
            timingOut.refreshDeadlineReached();
            timingOutCap.record.requests[tier].onCompleted({
                                                               "networkError": true
                                                           });
            require(timingOut.nextRequestAt === test.nowMs + expectedTiers[tier - 1],
                    "transient failure tier " + tier + " follows the bounded backoff ladder");
        }

        // A 5xx response takes the same bounded transient ladder.
        test.nowMs = timingOut.nextRequestAt;
        timingOut.refreshDeadlineReached();
        timingOutCap.record.requests[6].onCompleted(ok(500, "server error", 60000, ""));
        require(timingOut.nextRequestAt === test.nowMs + 21600000,
                "a 5xx response follows the capped transient tier");

        // A 203 deprecation response still yields valid normalized state.
        const deprecatedCap = newCapture(null);
        const deprecated = makeWeather({
                                           "latitude": 48.8566,
                                           "longitude": 2.3522,
                                           "transport": deprecatedCap.transport
                                       });
        deprecated.refreshDeadlineReached();
        deprecatedCap.record.requests[0].onCompleted(ok(203,
                                                        metBody([metEntry(-600000, 6.6,
                                                                          "fog")]),
                                                        1800000, "LM-203"));
        require(deprecated.available && deprecated.temperatureC === 6.6
                && deprecated.failure === "none",
                "a 203 deprecation response still exposes valid state");

        // Throttling waits at least as long as Retry-After and escalates tiers.
        const throttledCap = newCapture(null);
        const throttled = makeWeather({
                                          "latitude": 48.8566,
                                          "longitude": 2.3522,
                                          "transport": throttledCap.transport
                                      });
        throttled.refreshDeadlineReached();
        throttledCap.record.requests[0].onCompleted({
                                                        "status": 429,
                                                        "headers": {
                                                            "retry-after": "120"
                                                        },
                                                        "bodyText": ""
                                                    });
        require(throttled.failure === "throttled"
                && throttled.nextRequestAt === test.nowMs + 3600000,
                "throttling waits for the greater of Retry-After and sixty minutes");
        test.nowMs = throttled.nextRequestAt;
        throttled.refreshDeadlineReached();
        throttledCap.record.requests[1].onCompleted({
                                                        "status": 429,
                                                        "bodyText": ""
                                                    });
        require(throttled.nextRequestAt === test.nowMs + 10800000,
                "repeated throttling escalates to the three-hour tier");
        test.nowMs = throttled.nextRequestAt;
        throttled.refreshDeadlineReached();
        throttledCap.record.requests[2].onCompleted({
                                                        "status": 429,
                                                        "headers": {
                                                            "retry-after": new Date(
                                                                test.nowMs + 90000).toUTCString()
                                                        },
                                                        "bodyText": ""
                                                    });
        require(throttled.nextRequestAt === test.nowMs + 21600000,
                "HTTP-date Retry-After parses and repeated throttling caps at six hours");

        // Other 4xx responses are permanent until location or version changes.
        const permanentCap = newCapture(null);
        const permanent = makeWeather({
                                          "latitude": 48.8566,
                                          "longitude": 2.3522,
                                          "transport": permanentCap.transport
                                      });
        permanent.refreshDeadlineReached();
        permanentCap.record.requests[0].onCompleted(ok(404, "gone", 60000, ""));
        require(permanent.failure === "permanent" && !permanent.available,
                "permanent rejection exposes unavailable weather");
        test.nowMs += 86400000;
        permanent.refreshDeadlineReached();
        require(permanentCap.record.requests.length === 1,
                "permanent failures stop automatic retries");
        permanent.version = "0.2.0";
        permanent.applyLocation();
        permanent.refreshDeadlineReached();
        require(permanentCap.record.requests.length === 2,
                "changing the application version restarts a permanently rejected location");

        // Malformed and oversized responses retry transiently and preserve the
        // last valid content during the stale window.
        const resilientCap = newCapture(null);
        const resilient = makeWeather({
                                          "latitude": 48.8566,
                                          "longitude": 2.3522,
                                          "transport": resilientCap.transport
                                      });
        resilient.refreshDeadlineReached();
        resilientCap.record.requests[0].onCompleted(ok(200,
                                                       metBody([metEntry(-600000, 7.5, "fog")]),
                                                       600000, "LM-3"));
        require(resilient.temperatureC === 7.5, "preservation scenario reaches a valid state");
        test.nowMs += 600000;
        resilient.localDeadlineReached();
        resilient.refreshDeadlineReached();
        resilientCap.record.requests[1].onCompleted(ok(200, "{not json", 600000, "LM-4"));
        require(resilient.failure === "transient" && resilient.available
                && resilient.temperatureC === 7.5 && resilient.stale,
                "malformed bodies keep the last valid content through the stale window");
        const oversized = "x".repeat(resilient.maximumResponseCharacters + 1);
        test.nowMs = resilient.nextRequestAt;
        resilient.refreshDeadlineReached();
        resilientCap.record.requests[2].onCompleted(ok(200, oversized, 600000, "LM-5"));
        require(resilient.available && resilient.temperatureC === 7.5,
                "oversized bodies never replace exposed state");

        const missingFieldsCap = newCapture(null);
        const missingFields = makeWeather({
                                              "latitude": 48.8566,
                                              "longitude": 2.3522,
                                              "transport": missingFieldsCap.transport
                                          });
        missingFields.refreshDeadlineReached();
        missingFieldsCap.record.requests[0].onCompleted(ok(200,
                                                           metBody([metEntry(-60000, 150,
                                                                             "fog")]),
                                                           600000, ""));
        require(missingFields.failure === "transient" && !missingFields.available,
                "responses failing field validation expose nothing");

        // Cached content ages locally: the expiry instant flips stale, the
        // timeseries boundary advances selection, and six hours clear everything.
        const agingCap = newCapture(null);
        const aging = makeWeather({
                                      "latitude": 48.8566,
                                      "longitude": 2.3522,
                                      "transport": agingCap.transport
                                  });
        aging.refreshDeadlineReached();
        const agingValidatedAt = test.nowMs;
        agingCap.record.requests[0].onCompleted(ok(
                                                   200,
                                                   metBody([metEntry(-4800000, 3.3, "snow"),
                                                       metEntry(300000, 4.4, "rain")]),
                                                   1800000, "LM-6"));
        require(aging.temperatureC === 3.3 && aging.condition === "snow",
                "aging scenario starts on the current entry");
        test.nowMs += 300001;
        aging.localDeadlineReached();
        require(aging.temperatureC === 4.4 && aging.condition === "rain" && !aging.stale,
                "the timeseries boundary advances the selected entry without a request");
        require(agingCap.record.requests.length === 1,
                "local advancement performs no network activity");
        test.nowMs += 1499999;
        aging.localDeadlineReached();
        require(aging.available && aging.stale,
                "passing Expires exposes stale but available content");
        test.nowMs = agingValidatedAt + 21600001;
        aging.localDeadlineReached();
        require(!aging.available && aging.failure === "stale",
                "six hours without validation clears the weather");
        aging.refreshDeadlineReached();
        require(agingCap.record.requests.length === 2
                && agingCap.record.requests[1].headers["If-Modified-Since"] === undefined,
                "after the cutoff recovery requests are unconditional again");

        // A cache whose entries all age out clears at the next local deadline.
        const exhaustedCap = newCapture(null);
        const exhausted = makeWeather({
                                          "latitude": 48.8566,
                                          "longitude": 2.3522,
                                          "transport": exhaustedCap.transport
                                      });
        exhausted.refreshDeadlineReached();
        exhaustedCap.record.requests[0].onCompleted(ok(200,
                                                       metBody([metEntry(-5400000, 1.1,
                                                                         "fog")]),
                                                       3600000, "LM-7"));
        test.nowMs += 60001;
        exhausted.localDeadlineReached();
        require(!exhausted.available && exhausted.failure === "stale",
                "losing the last valid timestep clears the weather immediately");

        // Startup jitter stays inside its positive bound.
        rngQueue = [0.9999];
        const jitterBase = test.nowMs;
        const jittered = makeWeather({
                                         "latitude": 48.8566,
                                         "longitude": 2.3522,
                                         "transport": newCapture(null).transport
                                     });
        require(jittered.nextRequestAt === jitterBase + Math.floor(0.9999 * 30000),
                "startup refresh waits a positive sub-thirty-second jitter");

        // The clock stays independent of every weather failure above.
        require(/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(clock.text),
                "the compact clock renders 24-hour minute text");
        require(clock.precision === SystemClock.Minutes && !isNaN(clock.date.getTime()),
                "the compact clock updates only at minute precision");
        require(clock.dateText.length > 0 && /^Week [1-9][0-9]?$/.test(clock.weekText),
                "expanded clock derives date and ISO week from the same minute source");

        // Cache lifecycle across instances: adoption without requests, keyed
        // replacement, and removal of a previous location's record.
        sharedFirstCap = newCapture(null);
        sharedFirst = makeWeather({
                                      "latitude": 48.8566,
                                      "longitude": 2.3522,
                                      "cacheFileName": "weather-shared-" + runId + ".json",
                                      "transport": sharedFirstCap.transport
                                  });
        sharedFirst.refreshDeadlineReached();
        sharedFirstCap.record.requests[0].onCompleted(ok(
                                                          200,
                                                          metBody([metEntry(-600000, 19.5,
                                                                            "partlycloudy_day")]),
                                                          3600000, "LM-SHARED"));
        afterSaved(sharedFirst, runCacheReplacementStage);
    }

    // The shared-cache scenarios continue across cache-saved signals so every
    // stage observes fully persisted state.
    function afterSaved(weatherAdapter, continuation) {
        const handler = function () {
            weatherAdapter.cacheSaved.disconnect(handler);
            continuation();
        };

        weatherAdapter.cacheSaved.connect(handler);
    }

    function runCacheReplacementStage() {
        require(sharedFirst.temperatureC === 19.5 && sharedFirst.available,
                "the first shared instance holds its response state");

        sharedSecondCap = newCapture(null);
        sharedSecond = makeWeather({
                                       "latitude": 48.8566,
                                       "longitude": 2.3522,
                                       "cacheFileName": "weather-shared-" + runId + ".json",
                                       "transport": sharedSecondCap.transport
                                   });
        sharedSecond.refreshDeadlineReached();
        require(sharedSecond.available && sharedSecond.temperatureC === 19.5,
                "a matching startup adopts the cached forecast without a request");
        require(sharedSecondCap.record.requests.length === 0 && !sharedSecond.stale,
                "adopted caches serve while their stored expiry is in the future");

        sharedThirdCap = newCapture(null);
        sharedThird = makeWeather({
                                      "latitude": 41.3874,
                                      "longitude": 2.1686,
                                      "cacheFileName": "weather-shared-" + runId + ".json",
                                      "transport": sharedThirdCap.transport
                                  });
        afterSaved(sharedThird, runCacheClearedStage);
    }

    function runCacheClearedStage() {
        sharedFourthCap = newCapture(null);
        sharedFourth = makeWeather({
                                       "latitude": 48.8566,
                                       "longitude": 2.3522,
                                       "cacheFileName": "weather-shared-" + runId + ".json",
                                       "transport": sharedFourthCap.transport
                                   });
        sharedFourth.refreshDeadlineReached();
        require(sharedFourthCap.record.requests.length === 1,
                "a replaced location removes the previous location's cache record");
        require(sharedFourthCap.record.requests[0].headers["If-Modified-Since"] === undefined,
                "removed records cannot produce conditional requests");

        console.log("weather state tests passed");
        Qt.exit(0);
    }

    Component {
        id: weatherFactory

        WeatherAdapter {}
    }

    CompactClock {
        id: clock
    }

    Component.onCompleted: Qt.callLater(test.run)
}


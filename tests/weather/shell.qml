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

    function metEntry(offsetMs, temperature, symbolCode, humidity, windMs) {
        const data = {
            "instant": {
                "details": {
                    "air_temperature": temperature,
                    "relative_humidity": humidity === undefined ? 55 : humidity,
                    "wind_speed": windMs === undefined ? 3 : windMs
                }
            }
        };
        if (symbolCode !== null) {
            data.next_1_hours = {
                "summary": {
                    "symbol_code": symbolCode
                }
            };
        }
        return {
            "time": new Date(test.nowMs + offsetMs).toISOString(),
            "data": data
        };
    }

    function metBody(entries) {
        return JSON.stringify({
                                  "properties": {
                                      "meta": {
                                          "units": {
                                              "air_temperature": "celsius",
                                              "relative_humidity": "%",
                                              "wind_speed": "m/s"
                                          }
                                      },
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
            "enabled": true,
            "label": "Test location",
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

    function makeLookup(overrides) {
        const properties = {
            "allowed": true,
            "wallNow": function () {
                return test.nowMs;
            }
        };
        for (const key in overrides) {
            properties[key] = overrides[key];
        }
        return lookupFactory.createObject(test, properties);
    }

    function runLocationLookupTests() {
        const disabledCap = newCapture(null);
        const disabledLookup = makeLookup({
                                                   "allowed": false,
                                                   "transport": disabledCap.transport
                                               });
        require(!disabledLookup.search("Paris") && disabledCap.record.requests.length === 0,
                "disabled location lookup performs zero requests");

        const cityCap = newCapture(function () {
            return {
                "status": 200,
                "bodyText": JSON.stringify({
                                                "results": [{
                                                        "name": "Paris",
                                                        "admin1": "Île-de-France",
                                                        "country": "France",
                                                        "latitude": 48.85341,
                                                        "longitude": 2.3488
                                                    }]
                                            })
            };
        });
        const cityLookup = makeLookup({
                                               "transport": cityCap.transport
                                           });
        require(cityLookup.search("Paris, France") && cityLookup.results.length === 1
                && cityLookup.results[0].label === "Paris, Île-de-France, France",
                "explicit city lookup publishes one bounded normalized result");
        require(cityCap.record.requests[0].url.indexOf("Paris%2C%20France") !== -1
                && cityLookup.results[0].latitude === 48.85341,
                "city query is submitted only on explicit search and coordinates stay normalized");

        const postalCap = newCapture(function () {
            return {
                "status": 200,
                "bodyText": JSON.stringify({
                                                "results": [{
                                                        "name": "Berlin",
                                                        "country": "Germany",
                                                        "latitude": 52.52,
                                                        "longitude": 13.41
                                                    }]
                                            })
            };
        });
        const postalLookup = makeLookup({
                                                 "transport": postalCap.transport
                                             });
        require(postalLookup.search("10115")
                && postalCap.record.requests[0].url.indexOf("name=10115") !== -1,
                "postal input uses the same explicit bounded lookup contract");

        const fallbackCap = newCapture(function (index) {
            return index === 1 ? {
                                     "networkError": true
                                 } : {
                "status": 200,
                "bodyText": JSON.stringify([{
                                                "display_name": "Paris, Île-de-France, France",
                                                "lat": "48.8534",
                                                "lon": "2.3488"
                                            }])
            };
        });
        const fallbackLookup = makeLookup({
                                                   "transport": fallbackCap.transport
                                               });
        require(fallbackLookup.search("Paris") && fallbackCap.record.requests.length === 2
                && fallbackCap.record.requests[1].url.indexOf("/search?format=jsonv2") !== -1
                && fallbackLookup.results.length === 1
                && fallbackLookup.attribution.indexOf("OpenStreetMap") !== -1,
                "Open-Meteo failure uses the bounded attributed Nominatim fallback");
        fallbackLookup.clear();
        require(fallbackLookup.results.length === 0 && fallbackLookup.failure === "none",
                "clearing lookup retains no result or query history");

        const boundedQueryCap = newCapture(null);
        const boundedQuery = makeLookup({
                                                 "transport": boundedQueryCap.transport
                                             });
        require(!boundedQuery.search("é".repeat(65))
                && boundedQueryCap.record.requests.length === 0
                && boundedQuery.failure === "invalid-query",
                "location queries are bounded by UTF-8 bytes before transport");

        const invalidEndpointCap = newCapture(function () {
            return {
                "networkError": true
            };
        });
        const invalidEndpoint = makeLookup({
                                                    "nominatimEndpoint": "http://unsafe.example",
                                                    "transport": invalidEndpointCap.transport
                                                });
        require(invalidEndpoint.search("Paris") && invalidEndpointCap.record.requests.length === 1
                && invalidEndpoint.failure === "unavailable",
                "fallback rejects a non-HTTPS endpoint before dispatch");

        const cancellation = {
            "aborted": false
        };
        const pendingLookup = makeLookup({
                                                  "transport": {
                                                      "create": function () {
                                                          return {
                                                              "abort": function () {
                                                                  cancellation.aborted = true;
                                                              }
                                                          };
                                                      }
                                                  }
                                              });
        require(pendingLookup.search("Helsinki") && pendingLookup.inFlight,
                "lookup exposes one pending request");
        pendingLookup.allowed = false;
        require(!pendingLookup.inFlight && cancellation.aborted && pendingLookup.results.length === 0,
                "closing the lookup gate cancels work and clears normalized results");
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
        runLocationLookupTests();

        const disabledCap = newCapture(null);
        const disabled = makeWeather({
                                         "enabled": false,
                                         "latitude": 48.8566,
                                         "longitude": 2.3522,
                                         "transport": disabledCap.transport
                                     });
        disabled.refreshDeadlineReached();
        require(!disabled.locationConfigured && !disabled.available
                && disabled.failure === "unconfigured"
                && disabledCap.record.requests.length === 0,
                "disabled weather performs no cache adoption or request");

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


        // Requests carry four-decimal coordinates and the identifying public
        // User-Agent only; Qt supplies transparent compression support.
        const shapedCap = newCapture(null);
        const shaped = makeWeather({
                                       "latitude": 48.85667,
                                       "longitude": 2.35229,
                                       "label": "Home label",
                                       "transport": shapedCap.transport
                                   });
        shaped.refreshDeadlineReached();
        require(shapedCap.record.requests.length === 1,
                "configured weather sends exactly its scheduled request");
        const shapedRequest = shapedCap.record.requests[0];
        require(shapedRequest.url
                === "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=48.8566&lon=2.3522",
                "request URL uses four-decimal truncated coordinates");
        require(shapedRequest.headers["User-Agent"]
                === "NagiShell/0.1.0 https://github.com/Anthodev/nagi-shell",
                "requests identify Nagi Shell with the public User-Agent");
        require(Object.keys(shapedRequest.headers).length === 1,
                "requests add no credential or provider-unsupported custom header");
        require(shapedRequest.url.indexOf("Home") === -1,
                "the local label never leaves the machine");

        const negativeShapedCap = newCapture(null);
        const negativeShaped = makeWeather({
                                               "latitude": -33.86889,
                                               "longitude": -74.00669,
                                               "transport": negativeShapedCap.transport
                                           });
        negativeShaped.refreshDeadlineReached();
        require(negativeShapedCap.record.requests[0].url.indexOf(
                    "?lat=-33.8688&lon=-74.0066") !== -1,
                "negative coordinates truncate toward zero");

        const zeroishShapedCap = newCapture(null);
        const zeroishShaped = makeWeather({
                                              "latitude": 0.00001,
                                              "longitude": -0.00001,
                                              "transport": zeroishShapedCap.transport
                                          });
        zeroishShaped.refreshDeadlineReached();
        require(zeroishShapedCap.record.requests[0].url.indexOf(
                    "?lat=0.0000&lon=0.0000") !== -1,
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
        require(valid.nextRequestAt === completionTime + 3600000,
                "refresh preference defers a shorter provider expiry");
        valid.label = "Replacement location";
        valid.applyLocation();
        require(!valid.available && valid.failure === "none",
                "changing the confirmed label atomically invalidates prior-location state");
        valid.refreshDeadlineReached();
        require(validCap.record.requests.length === 2
                && validCap.record.requests[1].headers["If-Modified-Since"] === undefined,
                "a changed location never reuses the old label's conditional cache");

        // Extended state publishes one deeply frozen, provider-independent
        // generation with bounded 12-hour and five-day projections.
        const forecastEntries = [metEntry(-600000, 30, "clearsky_day", 70, 1)];
        for (let hour = 1; hour <= 144; hour += 1) {
            forecastEntries.push(metEntry(hour * 3600000, 10 + hour / 10,
                                          hour % 2 === 0 ? "partlycloudy_day" : "rain",
                                          40 + hour % 50, 2 + hour % 8));
        }
        const modelCap = newCapture(function () {
            return ok(200, metBody(forecastEntries), 900000, "LM-MODEL");
        });
        const extended = makeWeather({
                                         "latitude": 48.8566,
                                         "longitude": 2.3522,
                                         "temperatureUnit": "celsius",
                                         "windUnit": "ms",
                                         "transport": modelCap.transport
                                     });
        extended.refreshDeadlineReached();
        require(extended.model !== null && extended.current.location === undefined
                && extended.model.location === "Test location",
                "normalized model keeps only the local bounded location label");
        require(extended.hourly.length === 12 && extended.daily.length === 5,
                "forecast model caps returned hourly and daily projections at 12 and 5");
        require(Object.isFrozen(extended.model) && Object.isFrozen(extended.current)
                && Object.isFrozen(extended.hourly) && Object.isFrozen(extended.daily),
                "one immutable model generation publishes atomically");
        require(extended.current.feelsLikeCalculated
                && extended.current.feelsLike > extended.current.temperature,
                "hot humid conditions expose a calculated heat-index feels-like value");
        const celsiusGeneration = extended.modelGeneration;
        extended.temperatureUnit = "fahrenheit";
        extended.windUnit = "mph";
        require(extended.modelGeneration > celsiusGeneration
                && Math.round(extended.current.temperature) === 86
                && extended.current.temperatureUnit === "fahrenheit"
                && extended.current.windUnit === "mph",
                "independent temperature and wind overrides rebuild converted presentation");

        const windChillCap = newCapture(function () {
            return ok(200, metBody([metEntry(-600000, 0, "snow", 70, 10)]), 3600000,
                      "LM-CHILL");
        });
        const windChill = makeWeather({
                                        "latitude": 48.8566,
                                        "longitude": 2.3522,
                                        "temperatureUnit": "celsius",
                                        "transport": windChillCap.transport
                                    });
        windChill.refreshDeadlineReached();
        require(windChill.current.feelsLikeCalculated && windChill.current.feelsLike < 0,
                "cold windy conditions expose a calculated wind-chill value");

        const badUnitsCap = newCapture(function () {
            const payload = JSON.parse(metBody([metEntry(-600000, 12, "clear")]));
            payload.properties.meta.units.wind_speed = "knots";
            return ok(200, JSON.stringify(payload), 3600000, "LM-BAD-UNITS");
        });
        const badUnits = makeWeather({
                                         "latitude": 48.8566,
                                         "longitude": 2.3522,
                                         "transport": badUnitsCap.transport
                                     });
        badUnits.refreshDeadlineReached();
        require(!badUnits.available && badUnits.failure === "transient",
                "unexpected provider units reject the complete generation");

        const manualCap = newCapture(null);
        const manual = makeWeather({
                                      "latitude": 48.8566,
                                      "longitude": 2.3522,
                                      "refreshPreset": "3h",
                                      "transport": manualCap.transport
                                  });
        manual.refreshDeadlineReached();
        manualCap.record.requests[0].onCompleted(ok(200,
                                                    metBody([metEntry(-600000, 12, "clear")]),
                                                    900000, "LM-MANUAL"));
        require(manual.nextRequestAt === test.nowMs + 10800000
                && !manual.manualRefreshAvailable && !manual.manualRefresh(),
                "provider expiry and cooldown block premature manual refresh");
        test.nowMs += 900000;
        manual.manualRefreshDeadlineReached();
        require(manual.manualRefreshAvailable && manual.manualRefresh()
                && manualCap.record.requests.length === 2,
                "manual refresh bypasses the preference only after provider expiry");

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
        test.nowMs = resilient.nextRequestAt;
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
        require(clock.precision === SystemClock.Minutes && clock.enabled
                && !isNaN(clock.date.getTime()),
                "the shared clock defaults to an active minute-only schedule");
        require(clock.dateText.length > 0,
                "expanded clock derives its date from the shared minute source");
        clock.showSeconds = true;
        require(clock.precision === SystemClock.Seconds
                && /^(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d$/.test(clock.text),
                "seconds enable exactly the shared second-level clock schedule");
        clock.scheduleActive = false;
        require(!clock.enabled && clock.precision === SystemClock.Minutes,
                "a hidden clock pauses updates and does not retain second precision");
        clock.scheduleActive = true;
        clock.showSeconds = false;
        clock.dateFormat = "yyyy-MM-dd";
        require(/^\d{4}-\d{2}-\d{2}$/.test(clock.dateText),
                "the compact clock applies a validated date pattern");
        clock.dateFormat = "dddd, d MMMM";
        clock.format = "12h";
        require(/^(?:1[0-2]|[1-9]):[0-5]\d\s.+$/.test(clock.text),
                "the compact clock renders localized 12-hour text with an AM/PM indicator");
        clock.format = "auto";
        require(clock.text.length > 0, "automatic format follows the active locale");
        clock.format = "24h";

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

    Component {
        id: lookupFactory

        WeatherLocationSearchAdapter {}
    }

    CompactClock {
        id: clock
    }

    Component.onCompleted: Qt.callLater(test.run)
}


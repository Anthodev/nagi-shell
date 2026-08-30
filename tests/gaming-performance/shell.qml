import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    property var messages: []
    property int invalidations: 0

    component FakeBridge: QtObject {
        property bool ready: true
        signal snapshotReceived(var snapshot)
        signal fatalFailure

        function publish(gameClients, performance, event, gameAvailable, powerAvailable) {
            snapshotReceived({
                                 "available": gameAvailable || powerAvailable,
                                 "gameModeAvailable": gameAvailable,
                                 "powerProfilesAvailable": powerAvailable,
                                 "gameClientCount": gameClients,
                                 "performanceProfile": performance,
                                 "sourceCount": gameClients + (performance ? 1 : 0),
                                 "event": event
                             });
        }
    }

    FakeBridge {
        id: fake
    }

    GamingPerformanceBridge {
        id: validator
        helperPath: ""
        enabled: false
    }

    GamingPerformanceService {
        id: service
        helperPath: ""
        bridge: fake
        onFeedbackRequested: function (sourceToken, sourceGeneration, revision) {
            const presentation = service.resolveTransient(sourceToken, sourceGeneration, revision);
            test.messages.push(presentation.primary);
        }
        onFeedbackInvalidated: test.invalidations += 1
    }

    function require(condition, message) {
        if (!condition) {
            throw new Error("gaming-performance-test: " + message);
        }
    }

    function lastMessage() {
        return messages.length === 0 ? "" : messages[messages.length - 1];
    }

    function run() {
        require(validator.normalizeSnapshot({
                                                "type": "state",
                                                "available": true,
                                                "gameModeAvailable": true,
                                                "powerProfilesAvailable": true,
                                                "gameClientCount": 2,
                                                "performanceProfile": true,
                                                "sourceCount": 3,
                                                "event": "registered"
                                            }).sourceCount === 3,
                "valid bounded aggregate is accepted");
        require(validator.normalizeSnapshot({
                                                "type": "state",
                                                "available": true,
                                                "gameModeAvailable": true,
                                                "powerProfilesAvailable": false,
                                                "gameClientCount": 2,
                                                "performanceProfile": false,
                                                "sourceCount": 3,
                                                "event": "registered"
                                            }) === null,
                "inconsistent aggregate is rejected");

        fake.publish(0, false, "snapshot", true, true);
        require(service.available && !service.active && messages.length === 0,
                "inactive initial snapshot remains silent");
        fake.publish(0, false, "sourceUnavailable", false, true);
        require(lastMessage() === "Gaming performance source unavailable" && !service.active
                && service.available,
                "inactive owner loss is still a distinct unavailable transition");
        fake.publish(0, false, "snapshot", true, true);
        fake.publish(1, false, "registered", true, true);
        require(service.sourceCount === 1 && lastMessage() === "Gaming performance active",
                "zero to one emits active");
        const generation = service.generation;
        fake.publish(2, false, "registered", true, true);
        require(lastMessage() === "Gaming performance requested",
                "additional client emits requested");
        fake.publish(2, true, "profile", true, true);
        require(service.sourceCount === 3 && lastMessage() === "Gaming performance requested",
                "performance profile is one additional source");
        const countBeforeDuplicate = messages.length;
        fake.publish(2, true, "profile", true, true);
        require(messages.length === countBeforeDuplicate,
                "unchanged effective profile is coalesced");
        fake.publish(1, true, "unregistered", true, true);
        require(lastMessage() === "Gaming performance request ended",
                "intermediate removal emits ended");
        fake.publish(0, false, "profile", true, true);
        require(lastMessage() === "Gaming performance inactive",
                "final normal removal emits inactive");

        fake.publish(1, false, "registered", true, true);
        const revisionBeforeBurst = service.revision;
        fake.publish(2, false, "registered", true, true);
        fake.publish(1, false, "unregistered", true, true);
        require(service.generation === generation && service.revision === revisionBeforeBurst + 2
                && lastMessage() === "Gaming performance request ended",
                "burst keeps one token generation and latest truthful revision");
        fake.publish(0, false, "sourceUnavailable", false, true);
        require(lastMessage() === "Gaming performance source unavailable" && !service.active,
                "active owner loss has distinct unavailable feedback");

        service.enabled = false;
        require(!service.active && service.generation === 0 && invalidations === 1
                && service.activeTimerCount === 0,
                "disable invalidates feedback and leaves no timer");
        const disabledMessageCount = messages.length;
        fake.publish(4, true, "registered", true, true);
        require(messages.length === disabledMessageCount && !service.active,
                "disabled service ignores backend events");
        service.enabled = true;
        fake.publish(0, true, "snapshot", false, true);
        require(service.active && service.generation !== generation
                && lastMessage() === "Gaming performance active",
                "reenable creates a fresh aggregate generation");

        let previousGeneration = service.generation;
        for (let cycle = 0; cycle < 20; cycle += 1) {
            service.enabled = false;
            const messageCount = messages.length;
            fake.publish(4, true, "registered", true, true);
            require(!service.active && service.generation === 0
                    && service.activeTimerCount === 0 && messages.length === messageCount,
                    "disabled soak cycle retains zero work");
            service.enabled = true;
            fake.publish(1, false, "registered", true, true);
            require(service.active && service.generation !== 0
                    && service.generation !== previousGeneration,
                    "owner replacement soak creates a fresh generation");
            previousGeneration = service.generation;
            const burstCount = messages.length;
            fake.publish(2, false, "registered", true, true);
            fake.publish(2, false, "registered", true, true);
            require(messages.length === burstCount + 1,
                    "burst soak coalesces an unchanged backend snapshot");
            fake.publish(0, false, "sourceUnavailable", false, true);
            require(!service.active && service.activeTimerCount === 0,
                    "owner loss soak settles without inactive timer work");
        }
        service.enabled = true;
        fake.publish(1, false, "registered", true, true);

        const presentation = service.resolveTransient(service.sourceToken, service.generation,
                                                      service.revision);
        const serialized = JSON.stringify(presentation);
        require(serialized.indexOf("pid") < 0 && serialized.indexOf("game") < 0
                && serialized.indexOf("sender") < 0 && serialized.length < 512,
                "presentation is bounded and identity-free");
        console.log("gaming-performance-test: all assertions passed");
        Qt.exit(0);
    }

    Timer {
        interval: 1
        running: true
        onTriggered: test.run()
    }
}

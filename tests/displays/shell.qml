import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    readonly property int expectedOutputs: parseInt(Quickshell.env("NAGI_TEST_OUTPUTS") ?? "2")
    property int step: 0
    property int attempts: 0
    property var disabledScreen: null
    property var replacementToken: null

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function awaitState(condition, message) {
        if (condition) {
            attempts = 0;
            return true;
        }
        attempts += 1;
        if (attempts > 500) {
            require(false, message);
        }
        retry.restart();
        return false;
    }

    function tokenForScreen(screen) {
        for (let index = 0; index < host.registry.length; index += 1) {
            if (host.registry[index].screen === screen) {
                return host.registry[index].token;
            }
        }
        return null;
    }

    function run() {
        if (step === 0) {
            if (!awaitState(host.liveSurfaceCount === expectedOutputs
                            && coordinator.surfaceCount === expectedOutputs,
                            "one live island did not settle on every connected output")) {
                return;
            }
            const rows = host.activeDisplays();
            require(rows.length === expectedOutputs && host.enabledDisplayCount === expectedOutputs,
                    "new installations enable every connected display");
            require(host.rememberedDisplays.length === 0,
                    "unreliable ShellScreen identities never create remembered rows");
            for (let index = 0; index < rows.length; index += 1) {
                require(rows[index].enabled && !rows[index].reliable,
                        "active display row is enabled and session-only");
            }
            require(displaysPage.displayController === host,
                    "Displays page consumes the shared display controller");
            const pointerToken = host.routeSurfaceToken(null);
            require(pointerToken !== null && coordinator.openDashboard(null)
                    && coordinator.surfaceSnapshot(pointerToken).ownerName === "expanded",
                    "global action routes through the native pointer-screen bridge");
            require(coordinator.resetToIdle(pointerToken),
                    "pointer-routed dashboard returns to its initiating surface Idle");
            if (expectedOutputs === 1) {
                require(!host.setEnabled(rows[0].screen, false)
                        && host.liveSurfaceCount === 1,
                        "configuration rejects disabling the final island");
                console.warn("display orchestration single-output tests passed");
                Qt.exit(0);
                return;
            }

            const first = rows[0];
            const second = rows[1];
            require(host.setFallback(second.screen), "active enabled fallback is accepted");
            require(host.routeFallbackToken(null) === tokenForScreen(second.screen),
                    "configured fallback resolves to its live surface");
            require(host.routeSurfaceToken(null) === pointerToken
                    && pointerToken !== host.routeFallbackToken(null),
                    "pointer screen wins over a different configured fallback");
            require(!host.setFallback(null), "disconnected fallback is rejected");

            const firstToken = tokenForScreen(first.screen);
            require(coordinator.openLauncher(firstToken), "Interactive task opens on first island");
            disabledScreen = first.screen;
            require(host.setEnabled(first.screen, false),
                    "disabling an Interactive host transfers it safely");
            step = 1;
            retry.restart();
            return;
        }

        if (step === 1) {
            if (!awaitState(host.liveSurfaceCount === expectedOutputs - 1
                            && coordinator.surfaceCount === expectedOutputs - 1,
                            "disabled island did not destroy independently")) {
                return;
            }
            require(coordinator.interactiveHostToken === host.routeFallbackToken(null),
                    "one Interactive owner survives on the fallback island");
            require(host.setEnabled(disabledScreen, true), "disabled island re-enables");
            step = 2;
            retry.restart();
            return;
        }

        if (step === 2) {
            if (!awaitState(host.liveSurfaceCount === expectedOutputs
                            && tokenForScreen(disabledScreen) !== null,
                            "re-enabled island did not receive a fresh surface")) {
                return;
            }
            replacementToken = tokenForScreen(disabledScreen);
            require(coordinator.surfaceSnapshot(replacementToken).ownerName === "idle",
                    "replacement generation starts with local Idle state");
            const interactive = coordinator.surfaceSnapshot(coordinator.interactiveHostToken);
            require(coordinator.cancelInteractive(interactive.ownerEpoch),
                    "transferred Interactive task completes before global feedback");
            require(coordinator.requestNotification("broadcast", 1, 1, null),
                    "notification enters the global mailbox");
            for (let index = 0; index < host.registry.length; index += 1) {
                require(coordinator.surfaceSnapshot(host.registry[index].token).ownerName
                        === "notification", "notification mirrors to every eligible island");
            }
            require(coordinator.pendingTransientCount === 1,
                    "mirrored notification consumes one global slot");
            require(coordinator.invalidateTransient("broadcast", 1),
                    "mirrored notification invalidates atomically");

            coordinator.syncPolkitModal(true, true, 9);
            const modalRecord = host.registryRecordForToken(coordinator.modalHostToken);
            require(modalRecord !== null && !host.setEnabled(modalRecord.screen, false),
                    "Modal host cannot be voluntarily disabled");
            coordinator.syncPolkitModal(false, false, 0);
            console.warn("display orchestration " + expectedOutputs + "-output tests passed");
            Qt.exit(0);
        }
    }

    IslandStateCoordinator {
        id: coordinator
    }

    IslandSurfaceHost {
        id: host

        coordinator: coordinator
    }

    DisplaysPage {
        id: displaysPage

        visible: false
        displayController: host
    }

    Timer {
        id: retry

        interval: 10
        onTriggered: test.run()
    }

    Timer {
        interval: 1
        running: true
        onTriggered: test.run()
    }
}

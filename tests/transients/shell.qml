import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    property real nowMs: 0
    property var surfaceToken: null

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function requireWorkspaceGeometry(view, label) {
        require(view.implicitWidth >= Theme.size.islandTransientCompactMinimumWidth
                && view.implicitWidth <= Theme.size.islandTransientCompactWidth, label
                + " stays within compact transient width bounds");
        require(Math.abs(view.contentCenterX - view.width / 2) <= 1 && Math.abs(view.workspaceIndicatorCenterX
                                                                                - view.width / 2)
                <= 1, label + " content and position dots stay centered");
    }

    function run() {
        require(notificationView.bodyText === "Bounded plain-text body"
                && notificationView.implicitHeight > Theme.size.islandTransientNotificationHeight,
                "notification morph grows for bounded sender, summary, and body hierarchy");
        require(notificationView.semanticIconLoaded && !notificationView.semanticIconTinted
                && notificationView.appIconName !== "",
                "notification preserves an available application icon without tinting");
        require(volumeView.iconMeaning === "volumeHigh" && volumeView.showProgress
                && volumeView.showValue && volumeView.progressValue === 0.64,
                "confirmed volume projection renders semantic icon, progress, and percentage");
        require(brightnessView.iconMeaning === "brightness" && brightnessView.showProgress
                && brightnessView.showValue && brightnessView.progressValue === 0.8,
                "confirmed brightness projection renders semantic icon, progress, and percentage");
        require(Theme.size.islandTransientCompactMinimumWidth === 288
                && Theme.size.islandTransientCompactWidth === 340,
                "compact transients use the 288 px optical floor and retain the 340 px cap");
        require(Theme.size.islandWorkspaceIndicatorWidth === 28
                && Theme.size.islandWorkspaceIndicatorHeight === 22
                && workspaceView.workspaceBadgeItem.width
                === Theme.size.islandWorkspaceIndicatorWidth
                && workspaceView.workspaceBadgeItem.height
                === Theme.size.islandWorkspaceIndicatorHeight,
                "workspace transients use the shared compact indicator geometry");
        require(volumeView.implicitWidth >= Theme.size.islandTransientCompactMinimumWidth
                && volumeView.implicitWidth <= Theme.size.islandTransientCompactWidth
                && brightnessView.implicitWidth >= Theme.size.islandTransientCompactMinimumWidth
                && brightnessView.implicitWidth <= Theme.size.islandTransientCompactWidth,
                "volume and brightness share the compact transient width bounds");
        require(shortWorkspaceView.workspacePosition === 2 && shortWorkspaceView.workspaceCount
                === 4 && shortWorkspaceView.workspaceDisplayText === "02" &&
                !shortWorkspaceView.workspaceUsesCustomName,
                "generic Desktop 2 renders the normalized two-digit position");
        require(workspaceView.workspacePosition === 3 && workspaceView.workspaceCount === 12
                && workspaceView.workspaceDisplayText === "03" && !workspaceView.semanticIconLoaded
                && !workspaceView.showValue,
                "workspace renders the normalized position plus compact position dots without an icon");
        require(shortWorkspaceView.implicitWidth >= Theme.size.islandTransientCompactMinimumWidth
                && shortWorkspaceView.implicitWidth <= Theme.size.islandTransientCompactWidth,
                "short workspace names stay within compact transient width bounds");
        require(workspaceView.implicitWidth >= Theme.size.islandTransientCompactMinimumWidth
                && workspaceView.implicitWidth <= Theme.size.islandTransientCompactWidth,
                "long workspace names stay within compact transient width bounds");
        require(Math.abs(shortWorkspaceView.contentCenterX - shortWorkspaceView.width / 2) <= 1
                && Math.abs(shortWorkspaceView.workspaceIndicatorCenterX - shortWorkspaceView.width
                            / 2) <= 1, "short workspace content stays centered on the surface");
        require(Math.abs(workspaceView.contentCenterX - workspaceView.width / 2) <= 1 && Math.abs(
                    workspaceView.workspaceIndicatorCenterX - workspaceView.width / 2) <= 1,
                "long workspace content stays centered on the surface");
        require(largeWorkspaceView.workspacePosition === 12 && largeWorkspaceView.workspaceCount
                === 16 && largeWorkspaceView.workspaceDisplayText === "12",
                "two-digit workspace positions remain unprefixed at 10 and above");
        require(customWorkspaceView.workspacePosition === 0 && customWorkspaceView.workspaceCount
                === 0 && customWorkspaceView.workspaceDisplayText === "Focus"
                && customWorkspaceView.workspaceUsesCustomName,
                "invalid position payload preserves only a bounded custom workspace name");
        require(invalidWorkspaceView.workspacePosition === 0 && invalidWorkspaceView.workspaceCount
                === 0 && invalidWorkspaceView.workspaceDisplayText === "07" &&
                !invalidWorkspaceView.workspaceUsesCustomName,
                "invalid position payload never exposes a generic Desktop 7 name");
        requireWorkspaceGeometry(largeWorkspaceView, "position 12 workspace");
        requireWorkspaceGeometry(customWorkspaceView, "custom-name workspace fallback");
        requireWorkspaceGeometry(invalidWorkspaceView, "invalid-payload workspace fallback");
        require(!inactiveNotificationView.semanticIconLoaded &&
                !inactiveNotificationView.entryAnimationRunning,
                "hidden transient performs no icon load or animation work");
        require(missingIconNotificationView.semanticIconLoaded
                && missingIconNotificationView.semanticIconFallback
                && missingIconNotificationView.semanticIconTinted,
                "missing notification application icon uses the established neutral fallback");

        surfaceToken = {};
        require(coordinator.attachSurface(surfaceToken, 1), "transient surface attaches");
        workspace.confirmedWorkspaceChanged("workspace-current", 1, 1);
        require(coordinator.ownerName === "workspace" && coordinator.ownerSourceRevision === 1,
                "confirmed workspace change routes once to the fallback surface");
        const workspaceEpoch = coordinator.ownerEpoch;
        for (let revision = 2; revision <= 20; revision += 1) {
            workspace.confirmedWorkspaceChanged("workspace-current", 1, revision);
        }
        require(coordinator.ownerName === "workspace" && coordinator.ownerEpoch === workspaceEpoch
                && coordinator.ownerSourceRevision === 20 && coordinator.pendingTransientCount === 0,
                "workspace burst coalesces in place without queue growth");

        brightness.confirmedBrightnessChanged("1:display0", 1, 1, null);
        require(coordinator.ownerName === "brightness" && coordinator.restorationDepth === 1,
                "external brightness preempts workspace through fallback routing");
        workspace.confirmedWorkspaceInvalidated("workspace-current", 1);
        require(coordinator.restorationDepth === 0,
                "workspace generation loss removes its suspended feedback");
        const brightnessEpoch = coordinator.ownerEpoch;
        brightness.confirmedBrightnessChanged("1:display0", 1, 2, surfaceToken);
        require(coordinator.ownerEpoch === brightnessEpoch && coordinator.ownerSourceRevision === 2
                && coordinator.pendingTransientCount === 0,
                "local brightness confirmation coalesces without a parallel routing path");
        brightness.confirmedBrightnessInvalidated("1:display0", 1);
        require(coordinator.ownerName === "idle",
                "brightness display removal invalidates visible feedback");

        audio.confirmedOutputChanged("audio-output-1", 1, 1);
        require(coordinator.ownerName === "volume" && coordinator.ownerSourceRevision === 1,
                "confirmed output change enters the volume owner");
        const volumeEpoch = coordinator.ownerEpoch;
        for (let revision = 2; revision <= 20; revision += 1) {
            audio.confirmedOutputChanged("audio-output-1", 1, revision);
        }
        require(coordinator.ownerName === "volume" && coordinator.ownerEpoch === volumeEpoch
                && coordinator.ownerSourceRevision === 20 && coordinator.pendingTransientCount === 0,
                "rapid visible output confirmations coalesce in place without queue growth");

        audio.confirmedInputChanged("audio-input-1", 1, 1);
        require(coordinator.ownerSourceToken === "audio-output-1"
                && coordinator.ownerSourceRevision === 20,
                "default-input confirmation cannot create an output-volume transient");

        notifications.transientRequested("notification-1", 1, 1);
        require(coordinator.ownerName === "notification" && coordinator.restorationDepth === 1,
                "notification priority preempts and suspends confirmed volume");
        audio.confirmedOutputChanged("audio-output-1", 1, 21);
        require(coordinator.restorationDepth === 1 && coordinator.pendingTransientCount === 0,
                "suspended volume source coalesces to one latest revision");
        audio.confirmedOutputInvalidated("audio-output-1", 1);
        require(coordinator.ownerName === "notification" && coordinator.restorationDepth === 0,
                "endpoint removal invalidates the suspended volume without stale restoration");

        notifications.transientRequested("notification-2", 1, 1);
        require(coordinator.pendingTransientCount === 1,
                "independent notification occupies one shared mailbox slot");
        const notificationEpoch = coordinator.ownerEpoch;
        notifications.transientRequested("notification-1", 1, 2);
        require(coordinator.ownerEpoch === notificationEpoch && coordinator.ownerSourceRevision
                === 2 && coordinator.pendingTransientCount === 1,
                "same-notification replacement coalesces without disturbing independent work");
        notifications.transientInvalidated("notification-1", 1);
        require(coordinator.ownerName === "notification" && coordinator.ownerSourceToken
                === "notification-2" && coordinator.pendingTransientCount === 0,
                "notification invalidation restores the next eligible source atomically");
        notifications.transientInvalidated("notification-2", 1);
        require(coordinator.ownerName === "idle", "last notification invalidation restores Idle");

        require(coordinator.setHover(1, true), "expanded baseline enters for pending test");
        for (let revision = 1; revision <= 20; revision += 1) {
            audio.confirmedOutputChanged("audio-output-2", 2, revision);
        }
        require(coordinator.ownerName === "expanded" && coordinator.pendingTransientCount === 1,
                "blocked output burst keeps one replaceable pending transient");
        audio.confirmedOutputInvalidated("audio-output-2", 2);
        require(coordinator.pendingTransientCount === 0,
                "endpoint disappearance drops pending audio before presentation");
        require(coordinator.setHover(1, false) && coordinator.ownerName === "idle",
                "expired pending audio cannot replay after Expanded");

        audio.confirmedOutputChanged("audio-output-3", 3, 1);
        require(coordinator.ownerName === "volume" && coordinator.ownerSourceToken
                === "audio-output-3", "replacement endpoint presents only its fresh generation");
        audio.confirmedOutputInvalidated("audio-output-3", 3);
        require(coordinator.ownerName === "idle",
                "unavailable output cannot leave a stale volume owner");

        console.warn("transient integration tests passed");
        Qt.exit(0);
    }

    QtObject {
        id: workspace

        signal confirmedWorkspaceChanged(string sourceToken, int sourceGeneration, int revision)
        signal confirmedWorkspaceInvalidated(string sourceToken, int sourceGeneration)
    }

    QtObject {
        id: brightness

        signal confirmedBrightnessChanged(string sourceToken, int sourceGeneration, int revision,
                                          var initiatingSurfaceToken)
        signal confirmedBrightnessInvalidated(string sourceToken, int sourceGeneration)
    }

    QtObject {
        id: audio

        signal confirmedOutputChanged(string sourceToken, int sourceGeneration, int revision)
        signal confirmedInputChanged(string sourceToken, int sourceGeneration, int revision)
        signal confirmedOutputInvalidated(string sourceToken, int sourceGeneration)
    }

    QtObject {
        id: notifications

        signal transientRequested(string sourceToken, int sourceGeneration, int revision)
        signal transientInvalidated(string sourceToken, int sourceGeneration)
    }

    IslandStateCoordinator {
        id: coordinator

        monotonicNow: () => test.nowMs
    }

    TransientCoordinatorBridge {
        coordinator: coordinator
        surfaceToken: test.surfaceToken
        workspaceSource: workspace
        brightnessSource: brightness
        audioSource: audio
        notificationSource: notifications
    }

    TransientView {
        id: notificationView

        active: true
        reducedMotion: true
        kind: "notification"
        presentation: ({
                           "appIconName": Quickshell.shellPath("assets/icons/nagi/notification.svg"),
                           "body": "Bounded plain-text body",
                           "detail": "Review requested",
                           "primary": "Messages",
                           "value": ""
                       })
        surfaceGeneration: 1
        ownerEpoch: 1
        ownerRevision: 1
    }

    TransientView {
        id: volumeView

        active: true
        reducedMotion: true
        kind: "volume"
        presentation: ({
                           "detail": "Output volume",
                           "primary": "Built-in Audio",
                           "progress": 0.64,
                           "value": "64%"
                       })
        surfaceGeneration: 1
        ownerEpoch: 1
        ownerRevision: 1
    }

    TransientView {
        id: brightnessView

        active: true
        reducedMotion: true
        kind: "brightness"
        presentation: ({
                           "detail": "PowerDevil confirmed",
                           "primary": "Brightness",
                           "progress": 0.8,
                           "value": "80%"
                       })
        surfaceGeneration: 1
        ownerEpoch: 1
        ownerRevision: 1
    }

    TransientView {
        id: shortWorkspaceView

        active: true
        reducedMotion: true
        kind: "workspace"
        width: implicitWidth
        presentation: ({
                           "detail": "Current desktop",
                           "primary": "Desktop 2",
                           "value": "2 / 4"
                       })
        surfaceGeneration: 1
        ownerEpoch: 1
        ownerRevision: 1
    }

    TransientView {
        id: workspaceView

        active: true
        reducedMotion: true
        kind: "workspace"
        width: implicitWidth
        presentation: ({
                           "detail": "Current desktop",
                           "primary": "Desktop 3 — Product Development",
                           "value": "3 / 12"
                       })
        surfaceGeneration: 1
        ownerEpoch: 1
        ownerRevision: 1
    }

    TransientView {
        id: largeWorkspaceView

        active: true
        reducedMotion: true
        kind: "workspace"
        width: implicitWidth
        presentation: ({
                           "detail": "Current desktop",
                           "primary": "Desktop 12",
                           "value": "12 / 16"
                       })
        surfaceGeneration: 1
        ownerEpoch: 1
        ownerRevision: 1
    }

    TransientView {
        id: customWorkspaceView

        active: true
        reducedMotion: true
        kind: "workspace"
        width: implicitWidth
        presentation: ({
                           "detail": "Current desktop",
                           "primary": "Focus",
                           "value": "invalid"
                       })
        surfaceGeneration: 1
        ownerEpoch: 1
        ownerRevision: 1
    }

    TransientView {
        id: invalidWorkspaceView

        active: true
        reducedMotion: true
        kind: "workspace"
        width: implicitWidth
        presentation: ({
                           "detail": "Current desktop",
                           "primary": "Desktop 7",
                           "value": "invalid"
                       })
        surfaceGeneration: 1
        ownerEpoch: 1
        ownerRevision: 1
    }

    TransientView {
        id: inactiveNotificationView

        active: false
        reducedMotion: false
        kind: "notification"
        presentation: ({
                           "appIconName": Quickshell.shellPath("assets/icons/nagi/notification.svg"),
                           "body": "Hidden",
                           "detail": "Hidden",
                           "primary": "Hidden",
                           "value": ""
                       })
        surfaceGeneration: 1
        ownerEpoch: 1
        ownerRevision: 1
    }

    TransientView {
        id: missingIconNotificationView

        active: true
        reducedMotion: true
        kind: "notification"
        presentation: ({
                           "appIconName": "",
                           "body": "",
                           "detail": "No application icon",
                           "primary": "Notification",
                           "value": ""
                       })
        surfaceGeneration: 1
        ownerEpoch: 1
        ownerRevision: 1
    }

    Component.onCompleted: Qt.callLater(run)
}

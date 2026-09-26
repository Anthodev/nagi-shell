import Quickshell
import QtQuick
import "qml"

ShellRoot {
    id: test

    property real nowMs: 0
    property var surfaceToken: null
    property var secondSurfaceToken: null
    readonly property var workspaceOutputToken: ({})
    readonly property var staleWorkspaceOutputToken: ({})
    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function snapshotFor(token) {
        return coordinator.surfaceSnapshot(token);
    }

    function snapshot() {
        return snapshotFor(surfaceToken);
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
        require(Theme.motion.scale === 1 && Theme.motion.durationMorphMinimum === 120
                && Theme.motion.durationMorphMaximum === 200
                && Theme.motion.durationExpansionMinimum === 100
                && Theme.motion.durationExpansionMaximum === 160
                && Theme.motion.easingMorph === Easing.InOutCubic
                && Math.round(100 * Theme.effectiveMotionScale("reduced", 1)) === 50
                && Math.round(160 * Theme.effectiveMotionScale("reduced", 1)) === 80
                && Math.round(100 * Theme.effectiveMotionScale("minimal", 1)) === 0
                && Math.round(160 * Theme.effectiveMotionScale("minimal", 1)) === 0,
                "general morphs remain 120–200 ms while expansion publishes Full, Reduced, and Minimal endpoints");
        require(notificationView.bodyText === "Bounded plain-text body"
                && notificationView.implicitHeight
                >= Theme.size.islandTransientNotificationHeight,
                "notification morph retains the bounded sender, summary, and body hierarchy");
        require(notificationView.semanticIconLoaded && !notificationView.semanticIconTinted
                && notificationView.appIconName !== "",
                "notification preserves an available application icon without tinting");
        notificationView.ownerRevision = 2;
        notificationView.presentation = {
            "appIconName": Quickshell.shellPath("assets/icons/nagi/notification.svg"),
            "body": "Updated bounded body",
            "detail": "Review requested",
            "primary": "Messages",
            "value": ""
        };
        notificationView.syncBoundPresentation();
        require(notificationView.bodyText === "Updated bounded body"
                && notificationView.incomingOpacity === 1
                && notificationView.outgoingOpacity === 0
                && !notificationView.replacementActive,
                "same-owner transient revisions update in place without fading from zero");
        require(volumeView.iconMeaning === "volumeHigh" && volumeView.showProgress
                && volumeView.showValue && volumeView.progressValue === 0.64,
                "confirmed volume projection renders semantic icon, progress, and percentage");
        require(brightnessView.iconMeaning === "brightness" && brightnessView.showProgress
                && brightnessView.showValue && brightnessView.progressValue === 0.8,
                "confirmed brightness projection renders semantic icon, progress, and percentage");
        require(gamingView.iconMeaning === "gamingPerformance" && !gamingView.showProgress
                && !gamingView.showValue
                && gamingView.Accessible.name
                === "Gaming performance active, System status",
                "gaming feedback uses one generic semantic status projection");
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
        require(!inactiveNotificationView.semanticIconLoaded && !inactiveNotificationView.visible,
                "hidden transient performs no icon load or presentation work");
        require(missingIconNotificationView.semanticIconLoaded
                && missingIconNotificationView.semanticIconFallback
                && missingIconNotificationView.semanticIconTinted,
                "missing notification application icon uses the established neutral fallback");

        surfaceToken = {};
        secondSurfaceToken = {};
        require(coordinator.attachSurface(surfaceToken, 1)
                && coordinator.attachSurface(secondSurfaceToken, 1),
                "two transient surfaces attach");
        workspace.confirmedWorkspaceChanged("workspace-visible-stale", 1, 1,
                                            workspaceOutputToken);
        require(snapshot().ownerName === "workspace" && coordinator.pendingTransientCount === 1,
                "a mapped workspace presentation enters the visible owner");
        workspace.confirmedWorkspaceInvalidated("workspace-visible-stale", 1);
        require(snapshot().ownerName === "idle" && coordinator.pendingTransientCount === 0,
                "source invalidation removes a visible obsolete workspace presentation");
        require(coordinator.setHover(surfaceToken, 1, true),
                "Expanded blocks workspace presentation for stale pending coverage");
        workspace.confirmedWorkspaceChanged("workspace-pending-stale", 1, 1,
                                            workspaceOutputToken);
        require(snapshot().ownerName === "expanded" && coordinator.pendingTransientCount === 1,
                "a blocked workspace presentation remains pending on its mapped surface");
        workspace.confirmedWorkspaceInvalidated("workspace-pending-stale", 1);
        require(snapshot().ownerName === "expanded" && coordinator.pendingTransientCount === 0,
                "source invalidation removes blocked obsolete workspace presentation");
        require(coordinator.setHover(surfaceToken, 1, false) && snapshot().ownerName === "idle",
                "invalidated workspace presentation cannot resume after Expanded");
        workspace.confirmedWorkspaceChanged("workspace-source-a", 1, 1,
                                            workspaceOutputToken);
        require(snapshot().ownerName === "workspace"
                && snapshot().ownerSourceRevision === 1
                && snapshotFor(secondSurfaceToken).ownerName === "idle"
                && coordinator.pendingTransientCount === 1,
                "confirmed workspace change routes to exactly its mapped output surface");
        workspace.confirmedWorkspaceChanged("workspace-source-a", 1, 2,
                                            staleWorkspaceOutputToken);
        require(snapshot().ownerSourceRevision === 1
                && snapshotFor(secondSurfaceToken).ownerName === "idle"
                && coordinator.pendingTransientCount === 1,
                "unknown opaque output tokens fail closed without fallback routing");
        const workspaceEpoch = snapshot().ownerEpoch;
        for (let revision = 2; revision <= 20; revision += 1) {
            workspace.confirmedWorkspaceChanged("workspace-source-a", 1, revision,
                                                workspaceOutputToken);
        }
        require(snapshot().ownerName === "workspace" && snapshot().ownerEpoch === workspaceEpoch
                && snapshot().ownerSourceRevision === 20
                && snapshotFor(secondSurfaceToken).ownerName === "idle"
                && coordinator.pendingTransientCount === 1,
                "workspace burst coalesces only on the mapped surface");
        require(coordinator.detachSurface(secondSurfaceToken, 1),
                "secondary routing surface detaches before shared transient coverage");
        brightness.confirmedBrightnessChanged("1:display0", 1, 1, surfaceToken);
        require(snapshot().ownerName === "brightness" && snapshot().restorationDepth === 1,
                "targeted brightness preempts workspace");
        workspace.confirmedWorkspaceInvalidated("workspace-source-a", 1);
        require(snapshot().restorationDepth === 0 && coordinator.pendingTransientCount === 1,
                "workspace invalidation removes its suspended event globally");
        const brightnessEpoch = snapshot().ownerEpoch;
        brightness.confirmedBrightnessChanged("1:display0", 1, 2, surfaceToken);
        require(snapshot().ownerEpoch === brightnessEpoch
                && snapshot().ownerSourceRevision === 2
                && coordinator.pendingTransientCount === 1,
                "local brightness confirmation coalesces without another slot");
        brightness.confirmedBrightnessInvalidated("1:display0", 1);
        require(snapshot().ownerName === "idle", "brightness invalidation restores Idle");

        audio.confirmedOutputChanged("audio-output-1", 1, 1);
        require(snapshot().ownerName === "volume" && snapshot().ownerSourceRevision === 1,
                "confirmed output change enters one volume event");
        const volumeEpoch = snapshot().ownerEpoch;
        for (let revision = 2; revision <= 20; revision += 1) {
            audio.confirmedOutputChanged("audio-output-1", 1, revision);
        }
        require(snapshot().ownerName === "volume" && snapshot().ownerEpoch === volumeEpoch
                && snapshot().ownerSourceRevision === 20
                && coordinator.pendingTransientCount === 1,
                "rapid output confirmations coalesce in one event record");

        audio.confirmedInputChanged("audio-input-1", 1, 1);
        require(snapshot().ownerSourceToken === "audio-output-1"
                && snapshot().ownerSourceRevision === 20,
                "input confirmation cannot create an output-volume event");

        gaming.feedbackRequested("gaming-performance", 1, 1);
        require(snapshot().ownerName === "gamingPerformance"
                && snapshot().restorationDepth === 1
                && coordinator.pendingTransientCount === 2,
                "gaming feedback preempts volume independently from DND");
        const gamingEpoch = snapshot().ownerEpoch;
        for (let revision = 2; revision <= 20; revision += 1) {
            gaming.feedbackRequested("gaming-performance", 1, revision);
        }
        require(snapshot().ownerEpoch === gamingEpoch && snapshot().ownerSourceRevision === 20
                && coordinator.pendingTransientCount === 2,
                "gaming burst replaces one shared token generation");
        gaming.feedbackInvalidated("gaming-performance", 1);
        require(snapshot().ownerName === "volume" && coordinator.pendingTransientCount === 1,
                "gaming invalidation restores suspended volume");

        notifications.transientRequested("notification-1", 1, 1);
        require(snapshot().ownerName === "notification" && snapshot().restorationDepth === 1
                && coordinator.pendingTransientCount === 2,
                "notification priority preempts volume without per-display duplication");
        audio.confirmedOutputChanged("audio-output-1", 1, 21);
        require(snapshot().restorationDepth === 1
                && coordinator.pendingTransientCount === 2,
                "suspended volume source coalesces in its existing event");
        audio.confirmedOutputInvalidated("audio-output-1", 1);
        require(snapshot().ownerName === "notification" && snapshot().restorationDepth === 0
                && coordinator.pendingTransientCount === 1,
                "endpoint removal invalidates suspended volume globally");

        notifications.transientRequested("notification-2", 1, 1);
        require(coordinator.pendingTransientCount === 2,
                "independent notification occupies one additional global slot");
        const notificationEpoch = snapshot().ownerEpoch;
        notifications.transientRequested("notification-1", 1, 2);
        require(snapshot().ownerEpoch === notificationEpoch
                && snapshot().ownerSourceRevision === 2
                && coordinator.pendingTransientCount === 2,
                "same-notification replacement updates without slot growth");
        notifications.transientInvalidated("notification-1", 1);
        require(snapshot().ownerName === "notification" && snapshot().ownerSourceToken
                === "notification-2" && coordinator.pendingTransientCount === 1,
                "invalidation restores the next eligible notification atomically");
        notifications.transientInvalidated("notification-2", 1);
        require(snapshot().ownerName === "idle" && coordinator.pendingTransientCount === 0,
                "last notification invalidation restores Idle");

        require(coordinator.setHover(surfaceToken, 1, true),
                "expanded baseline enters for pending test");
        for (let revision = 1; revision <= 20; revision += 1) {
            audio.confirmedOutputChanged("audio-output-2", 2, revision);
        }
        require(snapshot().ownerName === "expanded" && coordinator.pendingTransientCount === 1,
                "blocked output burst keeps one replaceable global event");
        audio.confirmedOutputInvalidated("audio-output-2", 2);
        require(coordinator.pendingTransientCount === 0,
                "endpoint disappearance drops blocked audio before presentation");
        require(coordinator.setHover(surfaceToken, 1, false)
                && snapshot().ownerName === "idle",
                "invalidated audio cannot replay after Expanded");

        console.warn("transient integration tests passed");
        Qt.exit(0);
    }

    QtObject {
        id: workspace

        signal confirmedWorkspaceChanged(var sourceToken, int sourceGeneration, int revision,
                                         var outputToken)
        signal confirmedWorkspaceInvalidated(var sourceToken, int sourceGeneration)
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
        id: gaming

        property bool doNotDisturb: true
        signal feedbackRequested(string sourceToken, int sourceGeneration, int revision)
        signal feedbackInvalidated(string sourceToken, int sourceGeneration)
    }

    QtObject {
        id: notifications

        signal transientRequested(string sourceToken, int sourceGeneration, int revision)
        signal transientInvalidated(string sourceToken, int sourceGeneration)
    }

    QtObject {
        id: surfaceRouter

        function surfaceTokenForOutput(outputToken) {
            if (outputToken === test.workspaceOutputToken) {
                return test.surfaceToken;
            }
            return null;
        }
    }

    IslandStateCoordinator {
        id: coordinator

        monotonicNow: () => test.nowMs
    }

    TransientCoordinatorBridge {
        coordinator: coordinator
        surfaceHost: surfaceRouter
        workspaceSource: workspace
        brightnessSource: brightness
        audioSource: audio
        gamingPerformanceSource: gaming
        notificationSource: notifications
    }

    TransientView {
        id: notificationView

        active: true
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
        id: gamingView

        active: true
        kind: "gamingPerformance"
        presentation: ({
                           "detail": "System status",
                           "primary": "Gaming performance active",
                           "progress": -1,
                           "value": ""
                       })
        surfaceGeneration: 1
        ownerEpoch: 1
        ownerRevision: 1
    }

    TransientView {
        id: shortWorkspaceView

        active: true
        kind: "workspace"
        width: implicitWidth
        height: implicitHeight
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
        kind: "workspace"
        width: implicitWidth
        height: implicitHeight
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
        kind: "workspace"
        width: implicitWidth
        height: implicitHeight
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
        kind: "workspace"
        width: implicitWidth
        height: implicitHeight
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
        kind: "workspace"
        width: implicitWidth
        height: implicitHeight
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

    Timer {
        interval: 10
        running: true
        repeat: false
        onTriggered: test.run()
    }
}

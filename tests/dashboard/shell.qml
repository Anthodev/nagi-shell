import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "qml"

ShellRoot {
    id: test

    property var mediaActions: []
    property var audioActions: []
    property int audioOpenRequests: 0
    property var connectivityActions: []
    property var launchActions: []
    property var navigationActions: []
    property var trayActions: []
    property var trayMenuActions: []
    property int quickExternalActionCount: 0
    property int quickMenuOpeningCount: 0
    property var tooltipChecks: []
    property int tooltipCheckIndex: 0
    readonly property var muteSamples: [
        {
            "label": "output unmuted",
            "role": "output",
            "outputMuted": false,
            "inputMuted": false,
            "pendingOutputMute": false,
            "pendingInputMute": false,
            "expectedMeaning": "volumeHigh",
            "expectedState": "normal"
        },
        {
            "label": "output muted",
            "role": "output",
            "outputMuted": true,
            "inputMuted": false,
            "pendingOutputMute": false,
            "pendingInputMute": false,
            "expectedMeaning": "volumeMuted",
            "expectedState": "off"
        },
        {
            "label": "output pending",
            "role": "output",
            "outputMuted": false,
            "inputMuted": false,
            "pendingOutputMute": true,
            "pendingInputMute": false,
            "expectedMeaning": "volumeHigh",
            "expectedState": "pending"
        },
        {
            "label": "input unmuted",
            "role": "input",
            "outputMuted": false,
            "inputMuted": false,
            "pendingOutputMute": false,
            "pendingInputMute": false,
            "expectedMeaning": "microphone",
            "expectedState": "normal"
        },
        {
            "label": "input muted",
            "role": "input",
            "outputMuted": false,
            "inputMuted": true,
            "pendingOutputMute": false,
            "pendingInputMute": false,
            "expectedMeaning": "microphoneMuted",
            "expectedState": "off"
        },
        {
            "label": "input pending",
            "role": "input",
            "outputMuted": false,
            "inputMuted": false,
            "pendingOutputMute": false,
            "pendingInputMute": true,
            "expectedMeaning": "microphone",
            "expectedState": "pending"
        }
    ]

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
        return true;
    }
    function beginTooltipChecks() {
        const statusButtons = [];
        findObjects(quickView, "dashboardStatusItem", statusButtons);
        tooltipChecks = [
                    {
                        "control": findObject(mediaView, "dashboardMediaPrevious"),
                        "text": "Previous track"
                    },
                    {
                        "control": findObject(mediaView, "dashboardMediaToggle"),
                        "text": "Pause"
                    },
                    {
                        "control": findObject(mediaView, "dashboardMediaNext"),
                        "text": "Next track"
                    },
                    {
                        "control": findObject(quickView, "dashboardWifi"),
                        "text": "Wi-Fi · On"
                    },
                    {
                        "control": findObject(quickView, "dashboardBluetooth"),
                        "text": "Bluetooth · Off"
                    },
                    {
                        "control": statusButtons[0],
                        "text": "Mail needs attention"
                    },
                    {
                        "control": statusButtons[2],
                        "text": "Beeper is active"
                    },
                    {
                        "control": findObject(audioView, "dashboardOutputMute"),
                        "text": "Mute output"
                    },
                    {
                        "control": findObject(audioView, "dashboardInputMute"),
                        "text": "Mute input"
                    },
                    {
                        "control": findObject(dashboard, "dashboardTray"),
                        "text": "System tray"
                    },
                    {
                        "control": findObject(dashboard, "dashboardLauncher"),
                        "text": "Launcher"
                    },
                    {
                        "control": findObject(dashboard, "dashboardHistory"),
                        "text": "Notification history"
                    },
                    {
                        "control": findObject(dashboard, "dashboardSettings"),
                        "text": "Nagi Control Center"
                    },
                    {
                        "control": findObject(dashboard, "dashboardSession"),
                        "text": "Session"
                    }
                ];
        tooltipCheckIndex = 0;
        focusNextTooltip();
    }
    function focusNextTooltip() {
        if (tooltipCheckIndex >= tooltipChecks.length) {
            settleTimer.restart();
            return;
        }
        const check = tooltipChecks[tooltipCheckIndex];
        require(check.control !== null && check.control !== undefined
                && check.control.ToolTip.delay === Theme.motion.durationSlow,
                "tooltip control mounts with the shared delay");
        check.control.ToolTip.delay = 0;
        check.control.forceActiveFocus(Qt.TabFocusReason);
        tooltipTimer.restart();
    }
    function verifyFocusedTooltip() {
        const check = tooltipChecks[tooltipCheckIndex];
        require(check.control.activeFocus && check.control.visualFocus
                && check.control.ToolTip.visible && check.control.ToolTip.text === check.text,
                check.control.objectName + " shows its tooltip while keyboard focused: focus="
                + check.control.activeFocus + ", visual=" + check.control.visualFocus
                + ", visible=" + check.control.ToolTip.visible + ", text="
                + check.control.ToolTip.text);
        tooltipCheckIndex += 1;
        focusNextTooltip();
    }

    function requireFocusRing(control, ownerRadius, label, objectName) {
        const ring = objectName === undefined ? findObject(control, "islandFocusRing") : findObject(
                                                    control, objectName);
        require(control !== null && ring !== null && ring.controlRadius === ownerRadius
                && ring.radius === ownerRadius + Theme.size.focusRingGap, label
                + " focus ring follows its owner curve");
        if (control.background !== ring) {
            require(control.background.radius === ownerRadius, label
                    + " focus ring matches its actual background radius");
        }
        return ring;
    }

    function focusNames(start) {
        const names = [];
        let current = start;
        for (let hop = 0; hop < 64 && current !== null; ++hop) {
            const name = current.objectName;
            if (name !== "" && names.indexOf(name) === -1) {
                names.push(name);
            }
            current = current.nextItemInFocusChain(true);
            if (current === start) {
                break;
            }
        }
        return names;
    }

    function containsText(item, text) {
        if (item === null || item === undefined) {
            return false;
        }
        if (typeof item.text === "string" && item.text === text) {
            return true;
        }
        const children = item.children ?? [];
        for (let index = 0; index < children.length; ++index) {
            if (containsText(children[index], text)) {
                return true;
            }
        }
        return false;
    }
    function findObject(item, objectName) {
        if (item === null || item === undefined) {
            return null;
        }
        if (item.objectName === objectName) {
            return item;
        }
        const children = item.children ?? [];
        for (let index = 0; index < children.length; ++index) {
            const found = findObject(children[index], objectName);
            if (found !== null) {
                return found;
            }
        }
        return null;
    }
    function findObjects(item, objectName, matches) {
        if (item === null || item === undefined) {
            return;
        }
        if (item.objectName === objectName) {
            matches.push(item);
        }
        const children = item.children ?? [];
        for (let index = 0; index < children.length; ++index) {
            findObjects(children[index], objectName, matches);
        }
    }

    function semanticIconCount(item, meanings) {
        if (item === null || item === undefined) {
            return 0;
        }
        let count = typeof item.meaning === "string" && meanings.indexOf(item.meaning) >= 0 ? 1 : 0;
        const children = item.children ?? [];
        for (let index = 0; index < children.length; ++index) {
            count += semanticIconCount(children[index], meanings);
        }
        return count;
    }

    function audioFixture(sample) {
        return {
            "available": true,
            "outputAvailable": true,
            "outputDisplayLabel": "Built-in Audio",
            "outputLabel": "Built-in Audio",
            "outputVolume": 0.4,
            "outputMuted": sample.outputMuted,
            "outputOveramplified": false,
            "inputAvailable": true,
            "inputDisplayLabel": "Desk Microphone",
            "inputVolume": 0.3,
            "inputMuted": sample.inputMuted,
            "inputLabel": "Desk Microphone",
            "inputOveramplified": false,
            "pendingOutputVolume": false,
            "pendingInputVolume": false,
            "pendingOutputMute": sample.pendingOutputMute,
            "pendingInputMute": sample.pendingInputMute,
            "pendingOutputSelection": false,
            "pendingInputSelection": false
        };
    }

    function muteSamplesSettled() {
        for (let index = 0; index < muteSampleRepeater.count; index += 1) {
            const sample = muteSampleRepeater.itemAt(index);
            if (sample === null || !sample.sampled) {
                return false;
            }
        }
        return true;
    }

    function runChecks() {
        if (!muteSamplesSettled()) {
            settleTimer.restart();
            return;
        }

        const muteEvidence = [];
        for (let sampleIndex = 0; sampleIndex < muteSampleRepeater.count; sampleIndex += 1) {
            const sample = muteSampleRepeater.itemAt(sampleIndex);
            require(sample.hiddenReady && sample.remountCompleted, sample.modelData.label
                    + " preloads its persistent tint while hidden and survives required remount");
            require(sample.icon !== null && sample.icon.resolvedKind === "nagi"
                    && sample.icon.resolvedSource.indexOf("/assets/icons/nagi/") >= 0
                    && sample.icon.renderedSource.startsWith("data:image/svg+xml"),
                    sample.modelData.label + " uses the CPU-tinted owned-SVG render path");
            require(sample.icon.meaning === sample.modelData.expectedMeaning
                    && sample.icon.semanticState === sample.modelData.expectedState,
                    sample.modelData.label + " resolves the expected semantic meaning and state");
            require(sample.occupiedPixels > 0 && sample.minimumContrast >= 4.5,
                    sample.modelData.label + " has occupied raster pixels at >=4.5:1 contrast");
            muteEvidence.push(sample.modelData.label + "=" + sample.occupiedPixels + "px/"
                              + sample.minimumContrast.toFixed(2) + ":1/"
                              + sample.icon.tint.toString());
        }
        const unmutedInputSample = muteSampleRepeater.itemAt(3);
        const mutedInputSample = muteSampleRepeater.itemAt(4);
        require(unmutedInputSample.icon.resolvedSource !== mutedInputSample.icon.resolvedSource
                && unmutedInputSample.icon.accessibleName === "Microphone"
                && mutedInputSample.icon.accessibleName === "Muted microphone",
                "input mute changes source shape and accessibility label independently of tint");

        require(dashboard.loadedRegionCount === 6, "all implemented dashboard regions mount");
        require(dashboard.implicitWidth === Math.min(dashboard.naturalWidth,
                                                     dashboard.availableWidth)
                && dashboard.implicitHeight === Math.min(dashboard.naturalHeight,
                                                         dashboard.availableHeight),
                "dashboard implicit geometry is content-derived and screen-bounded");
        const mediaRegion = test.findObject(dashboard, "dashboardMediaRegion");
        const clockRegion = test.findObject(dashboard, "dashboardClockRegion");
        const quickRegion = test.findObject(dashboard, "dashboardQuickControlsRegion");
        const primaryRow = test.findObject(dashboard, "dashboardPrimaryRow");
        const audioRegion = test.findObject(dashboard, "dashboardAudioRegion");
        const notificationsRegion = test.findObject(dashboard, "dashboardNotificationsRegion");
        const navigationRegion = test.findObject(dashboard, "dashboardNavigationRegion");
        const outputSection = test.findObject(dashboard, "dashboardOutputSection");
        const inputSection = test.findObject(dashboard, "dashboardInputSection");
        require(mediaRegion !== null && clockRegion !== null && primaryRow !== null && quickRegion
                !== null && audioRegion !== null && notificationsRegion !== null,
                "dashboard exposes every composed main-column region");
        require(mediaRegion.x === quickRegion.x && quickRegion.x === audioRegion.x && audioRegion.x
                === notificationsRegion.x,
                "media, quick controls, audio, and recents share one left edge");
        require(notificationsRegion.y >= audioRegion.y + audioRegion.height + Theme.spacing.lg - 1
                && notificationsRegion.width === audioRegion.width && notificationsRegion.width
                === quickRegion.width,
                "recent notifications span the main column below the audio row");
        require(outputSection !== null && inputSection !== null && outputSection.y
                === inputSection.y && Math.abs(outputSection.width - inputSection.width) < 1,
                "Output and Input are equal top-aligned audio columns");
        require(dashboard.primaryRowMode === "media-and-clock" && clockRegion.x + clockRegion.width
                === primaryRow.width && clockRegion.x - mediaRegion.width >= Theme.spacing.lg - 1,
                "media and clock occupy opposite edges with their natural gap");
        const dashboardTime = test.findObject(dashboard, "dashboardTime");
        const dashboardDate = test.findObject(dashboard, "dashboardDate");
        require(dashboardTime !== null && dashboardDate !== null && Math.abs(dashboardTime.x
                                                                             + dashboardTime.width
                                                                             / 2 - dashboardDate.x
                                                                             - dashboardDate.width
                                                                             / 2) < 0.5,
                "expanded time and localized date share one horizontal center");

        require(mediaView.previous() === "dispatched" && mediaView.togglePlayback()
                === "dispatched" && mediaView.next() === "dispatched" && mediaActions.join(",")
                === "previous,toggle,next",
                "media controls dispatch only through normalized actions");
        mediaAdapter.canNext = false;
        require(mediaView.next() === "rejected" && mediaActions.length === 3 && !test.findObject(
                    mediaView, "dashboardMediaNext").enabled,
                "unsupported media control is disabled and locally rejected");
        require(mediaView.timingVisible, "reliable normalized timing exposes progress");
        mediaAdapter.timingReliable = false;
        require(!mediaView.timingVisible, "unreliable timing removes progress completely");
        mediaAdapter.timingReliable = true;

        mediaView.visible = true;
        require(mediaView.artworkRequest === mediaAdapter.artworkSource,
                "visible media requests only the validated selected artwork");
        mediaView.visible = false;
        require(mediaView.artworkRequest === "", "hidden media drops its artwork request");

        require(quickView.pinCount === 2 && typeof quickView.selectOutput !== "function"
                && test.findObject(quickView, "dashboardOutputCandidate") === null
                && test.findObject(quickView, "trayItemList") === null,
                "quick controls contain neither output selection nor embedded tray content");
        const wifiButton = test.findObject(quickView, "dashboardWifi");
        const bluetoothButton = test.findObject(quickView, "dashboardBluetooth");
        const wifiIcon = test.findObject(quickView, "dashboardWifiIcon");
        const bluetoothIcon = test.findObject(quickView, "dashboardBluetoothIcon");
        require(wifiButton.width === Theme.size.controlHeightLg && wifiButton.height
                === Theme.size.controlHeightLg && bluetoothButton.width
                === Theme.size.controlHeightLg && bluetoothButton.height
                === Theme.size.controlHeightLg && wifiIcon.size === "lg" && bluetoothIcon.size
                === "lg", "connectivity uses fixed large icon-button geometry");
        require(wifiButton.restingColor.toString() !== "transparent"
                && bluetoothButton.restingColor.toString() !== "transparent"
                && wifiButton.restingColor.toString() !== bluetoothButton.restingColor.toString(),
                "confirmed active and off connectivity states have distinct persistent surfaces");
        require(wifiIcon.resolved.kind === "nagi" && wifiIcon.resolved.source.indexOf("wifi.svg")
                >= 0 && bluetoothIcon.resolved.kind === "nagi"
                && bluetoothIcon.resolved.source.indexOf("bluetooth-") >= 0,
                "connectivity buttons resolve the bold Nagi icon sources");
        require(quickView.toggleWifi() && quickView.toggleBluetooth() && connectivityActions.join(
                    ",") === "wifi,bluetooth",
                "connectivity controls dispatch real adapter toggles");
        const bluetoothOffColor = bluetoothButton.restingColor.toString();
        connectivityAdapter.bluetoothFailure = "backend";
        require(quickView.bluetoothFailureVisible && bluetoothButton.restingColor.toString()
                !== bluetoothOffColor,
                "connectivity backend failure has a distinct persistent error surface");
        const bluetoothErrorColor = bluetoothButton.restingColor.toString();
        connectivityAdapter.bluetoothFailure = "none";
        connectivityAdapter.bluetoothPending = true;
        require(!bluetoothButton.enabled && bluetoothButton.restingColor.toString()
                !== bluetoothOffColor && bluetoothButton.restingColor.toString()
                !== bluetoothErrorColor && bluetoothIcon.semanticState === "pending",
                "pending connectivity is disabled with a distinct persistent surface");
        connectivityAdapter.bluetoothPending = false;
        require(quickView.launchPin(0) === 41 && launchActions[0] === "first.desktop"
                && quickExternalActionCount === 1,
                "pinned control dispatches the exact desktop ID and reports external focus transfer");
        applications.pinnedApplications = [applications.eligibleEntries[1]];
        require(quickView.pinCount === 1 && applications.pinIds.length === 2
                && applications.pinIds[0] === "dormant.desktop" && test.findObject(quickView,
                                                                                   "dashboardPinnedApplication")
                !== null, "eligible pins stay visible while dormant persistence slots remain untouched");
        const attentionGroup = test.findObject(quickView, "dashboardStatusItems");
        const attentionButton = test.findObject(quickView, "dashboardStatusItem");
        const statusIcons = [];
        test.findObjects(quickView, "dashboardStatusIcon", statusIcons);
        const statusButtons = [];
        test.findObjects(quickView, "dashboardStatusItem", statusButtons);
        const quickRow = test.findObject(quickView, "dashboardQuickControlRow");
        require(quickView.statusItems.length === 4 && Object.isFrozen(quickView.statusItems)
                && quickView.statusItems.map(item => item.token).join(",") === "11,12,21,22"
                && attentionGroup.visible && attentionButton.Accessible.name === "Mail"
                && statusIcons.length === 4 && statusIcons.every(icon => icon.resolved.kind
                                                                         === "application" &&
                                                                         !icon.resolved.tintable)
                && statusIcons.map(icon => icon.semanticState).join(",")
                === "attention,attention,active,active",
                "attention precedes active items, duplicates/passive items are excluded, and the frozen projection is capped at four untinted icons without fake attention state");
        const dashboardStatusGroup = test.findObject(dashboard, "dashboardStatusItems");
        const fourItemPosition = dashboardStatusGroup.mapToItem(dashboard, 0, 0);
        const clockPosition = clockRegion.mapToItem(dashboard, 0, 0);
        const clockCenterX = clockPosition.x + clockRegion.width / 2;
        require(Math.abs(fourItemPosition.x + dashboardStatusGroup.width / 2 - clockCenterX) <= 1,
                "four projected tray icons center beneath the time/date lane");
        attentionButton.clicked();
        require(trayActions.length === 1 && trayActions[0] === 11
                && quickExternalActionCount === 2,
                "projected tray activation reports one external focus transfer");
        const projectedItems = trayAdapter.items;
        const passiveItem = projectedItems[2];
        require(quickView.openStatusMenu(quickView.statusItems[0], attentionButton)
                === "dispatched" && trayMenuActions.length === 1
                && trayMenuActions[0].token === 11
                && trayMenuActions[0].parentWindow === quickView.menuParentWindow
                && quickExternalActionCount === 2 && quickMenuOpeningCount === 1
                && quickView.openedMenuToken === 11,
                "opening a projected tray menu retains its exact token without external focus transfer");
        trayAdapter.items = [passiveItem];
        require(quickView.statusItems.length === 0,
                "menu action may remove its icon from the current Expanded projection");
        trayAdapter.menuActionTriggered(11);
        require(quickExternalActionCount === 3 && quickView.openedMenuToken === 0,
                "the retained Expanded menu token survives projection changes and resets on selection");
        trayAdapter.items = [projectedItems[1]];
        const quickRowHeight = quickRow.height;

        require(audioView.outputDeviceName === "Built-in Audio" && audioView.inputDeviceName
                === "Desk Microphone" && test.findObject(audioView, "dashboardOutputCandidate")
                === null, "audio consolidates confirmed output and input device names without candidates");
        const outputDeviceButton = test.findObject(audioView, "dashboardOutputDeviceName");
        const inputDeviceButton = test.findObject(audioView, "dashboardInputDeviceName");
        require(outputDeviceButton !== null && inputDeviceButton !== null
                && outputDeviceButton.Accessible.name.indexOf("Built-in Audio") > 0
                && inputDeviceButton.Accessible.name.indexOf("Desk Microphone") > 0,
                "confirmed device names are accessible navigation buttons");
        const outputChannelRow = test.findObject(audioView, "dashboardOutputChannelRow");
        const inputChannelRow = test.findObject(audioView, "dashboardInputChannelRow");
        const outputMuteIcon = test.findObject(audioView, "dashboardOutputMuteIcon");
        const inputMuteIcon = test.findObject(audioView, "dashboardInputMuteIcon");
        require(outputMuteIcon !== null && inputMuteIcon !== null && test.semanticIconCount(
                    outputChannelRow, ["volumeHigh", "volumeMuted"]) === 1 && test.semanticIconCount(
                    inputChannelRow, ["microphone", "microphoneMuted"]) === 1
                && test.semanticIconCount(outputDeviceButton, ["volumeHigh", "volumeMuted"]) === 0
                && test.semanticIconCount(inputDeviceButton, ["microphone", "microphoneMuted"])
                === 0, "each channel row keeps only its mute action icon and device buttons duplicate no channel icon");
        require(audioView.Accessible.name === "Audio" && test.findObject(audioView,
                                                                         "dashboardOutputSection").Accessible.name
                === "Output audio" && test.findObject(audioView,
                                                      "dashboardInputSection").Accessible.name
                === "Input audio" && !test.containsText(audioView, "Audio") && !test.containsText(
                    audioView, "Output") && !test.containsText(audioView, "Input"),
                "audio keeps accessible grouping names without duplicate visible headings");
        outputDeviceButton.clicked();
        inputDeviceButton.clicked();
        require(audioOpenRequests === 2,
                "both confirmed device buttons request the shared Audio subview");
        const outputPercentage = test.findObject(audioView, "dashboardOutputPercentage");
        const inputPercentage = test.findObject(audioView, "dashboardInputPercentage");
        const outputMute = test.findObject(audioView, "dashboardOutputMute");
        const inputMute = test.findObject(audioView, "dashboardInputMute");
        const audioOutputSection = test.findObject(audioView, "dashboardOutputSection");
        const channelOutputVolume = test.findObject(audioView, "dashboardOutputVolume");
        const channelInputVolume = test.findObject(audioView, "dashboardInputVolume");
        const dashboardFocusControls = [[test.findObject(mediaView, "dashboardMediaPrevious"),
                                         Theme.radius.md, "media previous"], [test.findObject(
                                                                                  mediaView,
                                                                                  "dashboardMediaToggle"),
                                                                              Theme.radius.md,
                                                                              "media playback"],
                                        [test.findObject(mediaView, "dashboardMediaNext"),
                                         Theme.radius.md, "media next"], [test.findObject(quickView,
                                                                                          "dashboardWifi"),
                                                                          Theme.radius.lg, "Wi-Fi"],
                                        [test.findObject(quickView, "dashboardBluetooth"),
                                         Theme.radius.lg, "Bluetooth"], [outputDeviceButton,
                                                                         Theme.radius.md,
                                                                         "output device"],
                                        [inputDeviceButton, Theme.radius.md, "input device"],
                                        [outputMute, Theme.radius.md, "output mute"], [inputMute,
                                                                                       Theme.radius.md,
                                                                                       "input mute"]];
        const focusStatusButtons = [];
        findObjects(quickView, "dashboardStatusItem", focusStatusButtons);
        for (let index = 0; index < focusStatusButtons.length; ++index) {
            dashboardFocusControls.push([focusStatusButtons[index], Theme.radius.md, "status item "
                                         + index]);
        }
        for (let index = 0; index < dashboardFocusControls.length; ++index) {
            const entry = dashboardFocusControls[index];
            requireFocusRing(entry[0], entry[1], entry[2]);
        }
        requireFocusRing(channelOutputVolume, Theme.radius.sm, "output volume",
                         "dashboardOutputVolumeFocusRing");
        requireFocusRing(channelInputVolume, Theme.radius.sm, "input volume",
                         "dashboardInputVolumeFocusRing");
        const outputDevicePosition = outputDeviceButton.mapToItem(audioOutputSection, 0, 0);
        const outputMutePosition = outputMute.mapToItem(audioOutputSection, 0, 0);
        const outputVolumePosition = channelOutputVolume.mapToItem(audioOutputSection, 0, 0);
        const outputLabelBaseline = outputDeviceButton.contentItem.mapToItem(outputChannelRow, 0,
                                                                             outputDeviceButton.contentItem.baselineOffset).y;
        const outputPercentageBaseline = outputPercentage.mapToItem(outputChannelRow, 0,
                                                                    outputPercentage.baselineOffset).y;
        const inputLabelBaseline = inputDeviceButton.contentItem.mapToItem(inputChannelRow, 0,
                                                                           inputDeviceButton.contentItem.baselineOffset).y;
        const inputPercentageBaseline = inputPercentage.mapToItem(inputChannelRow, 0,
                                                                  inputPercentage.baselineOffset).y;
        const outputMuteIconPosition = outputMuteIcon.mapToItem(outputChannelRow, 0, 0);
        const inputMuteIconPosition = inputMuteIcon.mapToItem(inputChannelRow, 0, 0);
        require(Math.abs(outputLabelBaseline - outputPercentageBaseline) <= 1 && Math.abs(
                    inputLabelBaseline - inputPercentageBaseline) <= 1 && Math.abs(
                    outputMuteIconPosition.y + outputMuteIcon.height / 2 - outputChannelRow.height
                    / 2) <= 1 && Math.abs(inputMuteIconPosition.y + inputMuteIcon.height / 2
                                          - inputChannelRow.height / 2) <= 1
                && outputPercentage.text === "40%",
                "device labels and confirmed percentages share baselines while mute icons center in each channel row");
        require(Math.abs(outputVolumePosition.y - (outputMutePosition.y + outputMute.height
                                                   + Theme.spacing.xs)) < 1 && Math.abs(
                    channelOutputVolume.width - audioOutputSection.width) < 1,
                "the full-width output slider sits immediately below its channel row");
        require(audioView.requestVolume("output", 0.7, true) && audioActions[audioActions.length
                                                                             - 1] === "output-volume:0.7:true",
                "output volume gesture reaches the confirmed audio adapter");
        audioAdapter.pendingOutputVolume = true;
        require(outputVolume.stateText.indexOf("Pending · confirmed 40%") === 0,
                "pending output remains distinct from the confirmed value");
        audioAdapter.outputAvailable = false;
        require(!audioView.requestVolume("output", 0.2, true),
                "unavailable output blocks writes without optimistic state");
        audioAdapter.outputAvailable = true;
        outputVolume.forceActiveFocus(Qt.MouseFocusReason);
        require(outputVolume.activeFocus && !outputVolume.visualFocus && !test.findObject(
                    outputVolume, "dashboardOutputVolumeFocusRing").visible,
                "pointer-focused volume control suppresses the whole-control focus ring");
        inputDeviceButton.forceActiveFocus(Qt.MouseFocusReason);
        outputVolume.forceActiveFocus(Qt.TabFocusReason);
        require(outputVolume.activeFocus && outputVolume.visualFocus && test.findObject(outputVolume,
                                                                                        "dashboardOutputVolumeFocusRing").visible,
                "keyboard-focused volume control retains its visible focus ring");

        require(recentView.rowCount === 4 && !recentView.empty,
                "recent notifications use the service-owned four-record projection");
        require(recentView.Accessible.name === "Recent notifications" && !test.containsText(
                    recentView, "Recent notifications"),
                "recents keep an accessible region name without a visible redundant heading");
        notificationsModel.setProperty(0, "summary", "Replaced in place");

        require(test.findObject(dashboard, "dashboardCloseButton") === null && !test.containsText(
                    dashboard, clockState.weekText),
                "dashboard reserves neither a Close row nor secondary calendar text");
        const trayButton = test.findObject(dashboard, "dashboardTray");
        const launcherButton = test.findObject(dashboard, "dashboardLauncher");
        const historyButton = test.findObject(dashboard, "dashboardHistory");
        const settingsButton = test.findObject(dashboard, "dashboardSettings");
        const sessionButton = test.findObject(dashboard, "dashboardSession");
        require(trayButton !== null && launcherButton !== null && historyButton !== null
                && settingsButton !== null && sessionButton !== null && navigationRegion !== null,
                "rail exposes all five actions and its containing region");
        const trayPosition = trayButton.mapToItem(dashboard, 0, 0);
        const launcherPosition = launcherButton.mapToItem(dashboard, 0, 0);
        const historyPosition = historyButton.mapToItem(dashboard, 0, 0);
        const settingsPosition = settingsButton.mapToItem(dashboard, 0, 0);
        const sessionPosition = sessionButton.mapToItem(dashboard, 0, 0);
        const navigationPosition = navigationRegion.mapToItem(dashboard, 0, 0);
        require(trayPosition.y < launcherPosition.y && launcherPosition.y < historyPosition.y
                && settingsPosition.y >= historyPosition.y + historyButton.height + Theme.spacing.xl
                && settingsPosition.y < sessionPosition.y
                && Math.abs(sessionPosition.y + sessionButton.height - navigationPosition.y
                            - navigationRegion.height) < 1,
                "rail keeps its top cluster together and Settings immediately above final Session");
        require(trayButton.Accessible.name === "System tray" && launcherButton.Accessible.name
                === "Launcher" && historyButton.Accessible.name === "Notification history"
                && settingsButton.Accessible.name === "Nagi Control Center"
                && settingsButton.Accessible.description === ""
                && sessionButton.Accessible.name === "Session" && trayButton.implicitHeight
                >= Theme.size.controlHeightMd,
                "rail actions expose stable accessible names and adequate hit targets");
        require(IconResolver.resolve("settings", "normal", "", "").source.indexOf(
                    "preferences-system") !== -1,
                "Settings uses the active KDE preferences-system semantic icon");
        trayButton.clicked();
        launcherButton.clicked();
        historyButton.clicked();
        settingsButton.clicked();
        sessionButton.clicked();
        require(navigationActions.join(",") === "tray,launcher,history,settings,session",
                "rail preserves each normalized open-request route");

        dashboard.focusInitialControl();
        require(dashboardWindow.activeFocusItem !== null
                && dashboardWindow.activeFocusItem.objectName !== "dashboardCloseButton",
                "dashboard initial keyboard focus enters real content");
        const names = focusNames(dashboardWindow.activeFocusItem);
        const expected = ["dashboardMediaPrevious", "dashboardMediaToggle", "dashboardWifi",
                          "dashboardBluetooth", "dashboardPinnedApplication",
                          "dashboardOutputVolume", "dashboardOutputMute", "dashboardInputVolume",
                          "dashboardInputMute", "dashboardTray", "dashboardLauncher",
                          "dashboardHistory", "dashboardSettings", "dashboardSession"];
        require(names.indexOf("dashboardTray") < names.indexOf("dashboardLauncher") && names.indexOf(
                    "dashboardLauncher") < names.indexOf("dashboardHistory") && names.indexOf(
                    "dashboardHistory") < names.indexOf("dashboardSettings") && names.indexOf(
                    "dashboardSettings") < names.indexOf("dashboardSession"),
                "rail focus order remains Tray, Launcher, History, Settings, Session");
        for (let index = 0; index < expected.length; ++index) {
            require(names.indexOf(expected[index]) !== -1, "focus traversal reaches "
                    + expected[index]);
        }

        Qt.callLater(function () {
            const oneItemPosition = dashboardStatusGroup.mapToItem(dashboard, 0, 0);
            require(quickView.statusItems.length === 1 && Math.abs(oneItemPosition.x
                                                                   + dashboardStatusGroup.width / 2
                                                                   - clockCenterX) <= 1,
                    "one projected tray icon stays centered beneath the time/date lane");
            require(test.containsText(recentView, "Replaced in place"),
                    "notification replacement updates the live delegate without a view copy");

            const mediaNaturalWidth = dashboard.naturalWidth;
            const mediaNaturalHeight = dashboard.naturalHeight;
            mediaAdapter.available = false;
            dashboard.mediaContent = null;
            Qt.callLater(function () {
                const primaryPosition = primaryRow.mapToItem(dashboard, 0, 0);
                const noMediaClockPosition = clockRegion.mapToItem(dashboard, 0, 0);
                const noMediaClockCenter = noMediaClockPosition.x + clockRegion.width / 2;
                const mainLaneCenter = primaryPosition.x + primaryRow.width / 2;
                const noMediaStatusPosition = dashboardStatusGroup.mapToItem(dashboard, 0, 0);
                const dashboardBluetooth = test.findObject(dashboard, "dashboardBluetooth");
                const dashboardBluetoothPosition = dashboardBluetooth.mapToItem(dashboard, 0, 0);

                require(dashboard.loadedRegionCount === 5 && dashboard.primaryRowMode
                        === "clock-only" && dashboard.primaryRowWidth === clockRegion.implicitWidth
                        && dashboard.primaryRowHeight === clockRegion.implicitHeight
                        && mediaRegion.width === 0 && mediaRegion.height === 0,
                        "clock-only mode removes all media width, height, and inter-region spacing");
                require(Math.abs(noMediaClockCenter - mainLaneCenter) <= 1,
                        "absent media centers the clock in the full main-content lane");
                require(quickView.statusItems.length === 1 && Math.abs(noMediaStatusPosition.x
                                                                       + dashboardStatusGroup.width
                                                                       / 2 - noMediaClockCenter)
                        <= 1 && noMediaStatusPosition.x >= dashboardBluetoothPosition.x
                        + dashboardBluetooth.width + Theme.spacing.sm - 1,
                        "one active tray icon centers under the no-media clock without overlapping leading controls");
                require(dashboard.implicitWidth === Math.min(dashboard.naturalWidth,
                                                             dashboard.availableWidth)
                        && dashboard.implicitHeight === Math.min(dashboard.naturalHeight,
                                                                 dashboard.availableHeight)
                        && notificationsRegion.y >= audioRegion.y + audioRegion.height
                        + Theme.spacing.lg - 1,
                        "clock-only implicit geometry recomputes while lower rows remain unchanged");
                const noMediaNaturalWidth = dashboard.naturalWidth;
                const noMediaNaturalHeight = dashboard.naturalHeight;
                const noMediaStatusCenter = noMediaStatusPosition.x + dashboardStatusGroup.width
                      / 2;

                trayAdapter.items = [passiveItem];
                Qt.callLater(function () {
                    require(quickView.statusItems.length === 0 && !attentionGroup.visible
                            && quickRow.height === quickRowHeight,
                            "a zero-item projection reserves no extra row or height");

                    trayAdapter.items = projectedItems;
                    mediaAdapter.available = true;
                    dashboard.mediaContent = mediaContent;
                    Qt.callLater(function () {
                        const restoredClockPosition = clockRegion.mapToItem(dashboard, 0, 0);
                        const restoredStatusPosition = dashboardStatusGroup.mapToItem(dashboard, 0,
                                                                                      0);
                        const restoredClockCenter = restoredClockPosition.x + clockRegion.width / 2;

                        require(dashboard.loadedRegionCount === 6 && dashboard.primaryRowMode
                                === "media-and-clock" && dashboard.primaryRowWidth
                                === mediaRegion.implicitWidth + Theme.spacing.lg
                                + clockRegion.implicitWidth && dashboard.naturalWidth
                                === mediaNaturalWidth && dashboard.naturalHeight
                                === mediaNaturalHeight,
                                "restoring media recomputes the original natural geometry in one transition");
                        require(quickView.statusItems.length === 4 && Math.abs(
                                    restoredStatusPosition.x + dashboardStatusGroup.width / 2
                                    - restoredClockCenter) <= 1,
                                "four active tray icons return to the fixed right clock lane");

                        notificationsModel.clear();
                        notificationService.serverOwned = false;
                        Qt.callLater(function () {
                            require(test.containsText(recentView, "No notifications") &&
                                    !test.containsText(recentView, "Notifications unavailable") &&
                                    !test.containsText(recentView, "No recent notifications"),
                                    "empty and unavailable recents use the exact requested copy");
                            muteCaptureContent.grabToImage(function (result) {
                                const capturePath = "/tmp/nagi-dashboard-mute-icons.png";
                                require(result.saveToFile(capturePath),
                                        "real Dashboard mute-state capture was saved");
                                console.warn(
                                            "expanded dashboard tests passed; geometry media clock/status "
                                            + clockCenterX + "/" + (fourItemPosition.x
                                                                    + dashboardStatusGroup.width
                                                                    / 2) + ", no-media lane/clock/status "
                                            + mainLaneCenter + "/" + noMediaClockCenter + "/"
                                            + noMediaStatusCenter + ", natural "
                                            + mediaNaturalWidth + "x" + mediaNaturalHeight + " -> "
                                            + noMediaNaturalWidth + "x" + noMediaNaturalHeight
                                            + " -> " + dashboard.naturalWidth + "x"
                                            + dashboard.naturalHeight + "; mute raster evidence: "
                                            + muteEvidence.join(", ") + "; capture: "
                                            + capturePath);
                                Qt.exit(0);
                            });
                        });
                    });
                });
            });
        });
    }

    Component.onCompleted: Qt.callLater(test.beginTooltipChecks)

    QtObject {
        id: mediaAdapter

        property bool available: true
        property string title: "Track"
        property string artist: "Artist"
        property string album: "Album"
        property string playbackState: "playing"
        property real position: 30
        property real duration: 120
        property bool timingReliable: true
        property bool canPrevious: true
        property bool canTogglePlayback: true
        property bool canNext: true
        property string artworkSource: "file:///tmp/nagi-dashboard-artwork.png"
        property string artworkStatus: "ready"
        property int artworkMaximumWidth: 512
        property string pendingAction: "none"

        function previous() {
            test.mediaActions.push("previous");
            return "dispatched";
        }
        function togglePlayback() {
            test.mediaActions.push("toggle");
            return "dispatched";
        }
        function next() {
            test.mediaActions.push("next");
            return "dispatched";
        }
    }

    QtObject {
        id: connectivityAdapter

        property bool wifiAvailable: true
        property bool wifiEnabled: true
        property bool wifiPending: false
        property bool bluetoothAvailable: true
        property bool bluetoothEnabled: false
        property bool bluetoothPending: false
        property string wifiFailure: "none"
        property string bluetoothFailure: "none"

        function toggleWifi() {
            test.connectivityActions.push("wifi");
            return true;
        }
        function toggleBluetooth() {
            test.connectivityActions.push("bluetooth");
            return true;
        }
    }

    QtObject {
        id: audioAdapter

        property bool available: true
        property bool isSynchronized: true
        property bool outputAvailable: true
        property string outputLabel: "Built-in Audio"
        property string outputDisplayLabel: outputLabel
        property real outputVolume: 0.4
        property bool outputMuted: false
        property bool outputOveramplified: false
        property bool inputAvailable: true
        property string inputLabel: "Desk Microphone"
        property string inputDisplayLabel: inputLabel
        property real inputVolume: 0.3
        property bool inputMuted: false
        property bool inputOveramplified: false
        property bool pendingOutputVolume: false
        property bool pendingInputVolume: false
        property bool pendingOutputMute: false
        property bool pendingInputMute: false
        property bool pendingOutputSelection: false
        property bool pendingInputSelection: false
        property var outputCandidates: [
            {
                "endpointKey": "physical-output",
                "label": "Built-in Audio",
                "isDefault": true
            },
            {
                "endpointKey": "virtual-output",
                "label": "EasyEffects Sink",
                "isDefault": false
            }
        ]
        property var inputCandidates: [
            {
                "endpointKey": "physical-input",
                "label": "Desk Microphone",
                "isDefault": true
            }
        ]

        function requestOutputSelection(endpointKey) {
            test.audioActions.push("select:" + endpointKey);
            return true;
        }
        function requestInputSelection(endpointKey) {
            test.audioActions.push("select-input:" + endpointKey);
            return true;
        }
        function requestOutputVolume(value, finalValue) {
            test.audioActions.push("output-volume:" + value + ":" + finalValue);
            return true;
        }
        function requestInputVolume(value, finalValue) {
            test.audioActions.push("input-volume:" + value + ":" + finalValue);
            return true;
        }
        function requestOutputMute(muted) {
            test.audioActions.push("output-mute:" + muted);
            return true;
        }
        function requestInputMute(muted) {
            test.audioActions.push("input-mute:" + muted);
            return true;
        }
    }

    QtObject {
        id: applications

        property var eligibleEntries: [
            {
                "id": "first.desktop",
                "name": "First"
            },
            {
                "id": "second.desktop",
                "name": "Second"
            }
        ]
        property var pinnedApplications: eligibleEntries
        property var pinIds: ["dormant.desktop", "second.desktop"]
        property bool launchPending: false

        function dispatchLaunch(desktopFileId) {
            test.launchActions.push(desktopFileId);
            return 41;
        }
    }

    QtObject {
        id: trayAdapter
        signal menuActionTriggered(int token)

        property var items: [
            {
                "token": 21,
                "label": "Beeper",
                "tooltip": "Beeper is active",
                "iconSource": "file://" + Quickshell.shellPath("assets/icons/nagi/launcher.svg"),
                "status": "active"
            },
            {
                "token": 11,
                "label": "Mail",
                "tooltip": "Mail needs attention",
                "iconSource": "file://" + Quickshell.shellPath("assets/icons/nagi/launcher.svg"),
                "status": "needsAttention",
                "hasMenu": true,
                "onlyMenu": false
            },
            {
                "token": 30,
                "label": "Passive",
                "tooltip": "Passive tray item",
                "iconSource": "",
                "status": "passive"
            },
            {
                "token": 12,
                "label": "Chat",
                "tooltip": "Chat needs attention",
                "iconSource": "file://" + Quickshell.shellPath(
                                  "assets/icons/nagi/notification-bell.svg"),
                "status": "needsAttention"
            },
            {
                "token": 11,
                "label": "Duplicate",
                "tooltip": "Duplicate token",
                "iconSource": "",
                "status": "active"
            },
            {
                "token": 22,
                "label": "Sync",
                "tooltip": "Sync is active",
                "iconSource": "file://" + Quickshell.shellPath("assets/icons/nagi/tray.svg"),
                "status": "active"
            },
            {
                "token": 23,
                "label": "Update",
                "tooltip": "Update is active",
                "iconSource": "file://" + Quickshell.shellPath("assets/icons/nagi/session.svg"),
                "status": "active"
            },
            {
                "token": 24,
                "label": "Hidden overflow",
                "tooltip": "Fifth projected item",
                "iconSource": "",
                "status": "active"
            }
        ]

        function activate(token) {
            test.trayActions.push(token);
            return "dispatched";
        }

        function openMenu(token, parentWindow, relativeX, relativeY) {
            test.trayMenuActions.push({
                                          "token": token,
                                          "parentWindow": parentWindow,
                                          "relativeX": relativeX,
                                          "relativeY": relativeY
                                      });
            return "dispatched";
        }
    }

    ListModel {
        id: notificationsModel

        ListElement {
            appName: "Mail"
            summary: "Newest"
            body: "Body"
            state: "live"
        }
        ListElement {
            appName: "Calendar"
            summary: "Meeting"
            body: "Body"
            state: "live"
        }
        ListElement {
            appName: "Chat"
            summary: "Message"
            body: "Body"
            state: "expired"
        }
        ListElement {
            appName: "Build"
            summary: "Complete"
            body: "Body"
            state: "live"
        }
    }

    QtObject {
        id: notificationService

        readonly property var dashboardModel: notificationsModel
        property bool serverOwned: true
    }

    QtObject {
        id: clockState

        readonly property string text: "12:34"
        readonly property string dateText: "Saturday, 22 August"
        readonly property string weekText: "Saturday"
    }

    Component {
        id: mediaContent
        DashboardMedia {
            media: mediaAdapter
        }
    }
    Component {
        id: clockContent
        DashboardClock {
            clock: clockState
        }
    }
    Component {
        id: quickContent
        DashboardQuickControls {
            centerStatusInMainLane: !mediaAdapter.available
            connectivity: connectivityAdapter
            applicationModel: applications
            tray: trayAdapter
            menuParentWindow: dashboardWindow
        }
    }
    Component {
        id: audioContent
        DashboardAudio {
            audio: audioAdapter
            onDeviceSelectionRequested: test.audioOpenRequests += 1
        }
    }
    Component {
        id: notificationContent
        DashboardNotifications {
            service: notificationService
        }
    }
    QtObject {
        id: navigationCoordinator

        function openTray(surfaceToken) {
            test.navigationActions.push("tray");
            return true;
        }
        function openLauncher(surfaceToken) {
            test.navigationActions.push("launcher");
            return true;
        }
        function openHistory(surfaceToken) {
            test.navigationActions.push("history");
            return true;
        }
        function openSession(surfaceToken) {
            test.navigationActions.push("session");
            return true;
        }
    }

    Component {
        id: navigationContent

        DashboardNavigation {
            coordinator: navigationCoordinator
            onControlCenterRequested: test.navigationActions.push("settings")
        }
    }

    component MuteRasterSample: Item {
        id: sampleRoot

        required property var modelData
        required property int index
        property var icon: null
        property int occupiedPixels: 0
        property real minimumContrast: 0
        property bool sampled: false
        property bool requested: false
        property bool hiddenReady: false
        property bool revealed: false
        property bool remountRequested: false
        property bool remountCompleted: index !== 0
        property string sourceBeforeRemount: ""

        width: 360
        height: 92

        Loader {
            id: audioLoader

            active: true
            visible: sampleRoot.revealed
            sourceComponent: Component {
                DashboardAudio {
                    width: 340
                    audio: test.audioFixture(sampleRoot.modelData)
                }
            }
        }

        Canvas {
            id: rasterSampler

            x: 342
            width: Theme.size.iconSizeMd
            height: Theme.size.iconSizeMd

            function colorHex(red, green, blue) {
                return "#" + red.toString(16).padStart(2, "0") + green.toString(16).padStart(2, "0")
                        + blue.toString(16).padStart(2, "0");
            }

            onImageLoaded: requestPaint()
            onPaint: {
                if (sampleRoot.icon === null || !isImageLoaded(sampleRoot.icon.renderedSource)) {
                    return;
                }
                const context = getContext("2d");
                context.clearRect(0, 0, width, height);
                context.drawImage(sampleRoot.icon.renderedSource, 0, 0, width, height);
                const pixels = context.getImageData(0, 0, width, height).data;
                let occupied = 0;
                let contrast = Number.POSITIVE_INFINITY;
                for (let offset = 0; offset < pixels.length; offset += 4) {
                    if (pixels[offset + 3] < 32) {
                        continue;
                    }
                    occupied += 1;
                    contrast = Math.min(contrast, Theme.contrast(colorHex(pixels[offset],
                                                                          pixels[offset + 1],
                                                                          pixels[offset + 2]),
                                                                 IconResolver.iconSurface));
                }
                sampleRoot.occupiedPixels = occupied;
                sampleRoot.minimumContrast = contrast;
                sampleRoot.sampled = true;
            }
        }

        Timer {
            interval: 25
            running: !sampleRoot.sampled
            repeat: true
            onTriggered: {
                if (sampleRoot.icon === null && audioLoader.item !== null) {
                    sampleRoot.icon = test.findObject(audioLoader.item, sampleRoot.modelData.role
                                                      === "output" ? "dashboardOutputMuteIcon" :
                                                                     "dashboardInputMuteIcon");
                }
                if (sampleRoot.icon === null || sampleRoot.icon.loadStatus !== Image.Ready ||
                        !sampleRoot.icon.renderedSource.startsWith("data:image/svg+xml")
                        || sampleRoot.icon.width !== Theme.size.iconSizeMd
                        || sampleRoot.icon.height !== Theme.size.iconSizeMd) {
                    return;
                }
                if (!sampleRoot.hiddenReady) {
                    sampleRoot.hiddenReady = true;
                }
                if (sampleRoot.index === 0 && !sampleRoot.remountCompleted) {
                    if (!sampleRoot.remountRequested) {
                        sampleRoot.sourceBeforeRemount = sampleRoot.icon.renderedSource;
                        sampleRoot.remountRequested = true;
                        sampleRoot.icon = null;
                        audioLoader.active = false;
                        Qt.callLater(function () {
                            audioLoader.active = true;
                        });
                        return;
                    }
                    test.require(sampleRoot.icon.renderedSource === sampleRoot.sourceBeforeRemount
                                 && sampleRoot.icon.loadStatus === Image.Ready
                                 && sampleRoot.icon.width === Theme.size.iconSizeMd
                                 && sampleRoot.icon.height === Theme.size.iconSizeMd,
                                 "hidden Dashboard mute icon survives a component remount");
                    sampleRoot.remountCompleted = true;
                }
                if (!sampleRoot.requested && sampleRoot.remountCompleted) {
                    sampleRoot.revealed = true;
                    sampleRoot.requested = true;
                    rasterSampler.loadImage(sampleRoot.icon.renderedSource);
                }
            }
        }
    }

    Timer {
        id: tooltipTimer
        interval: 25
        onTriggered: test.verifyFocusedTooltip()
    }

    Timer {
        id: settleTimer
        interval: 25
        onTriggered: test.runChecks()
    }

    Timer {
        interval: 15000
        running: true
        onTriggered: {
            console.error("FAIL: dashboard test timed out");
            Qt.exit(1);
        }
    }

    Window {
        id: muteCaptureWindow

        visible: true
        width: 360
        height: muteSamples.length * 92
        color: IconResolver.iconSurface
        flags: Qt.ToolTip | Qt.FramelessWindowHint

        Column {
            id: muteCaptureContent
            Repeater {
                id: muteSampleRepeater
                model: test.muteSamples

                delegate: MuteRasterSample {}
            }
        }
    }

    Window {
        id: dashboardWindow
        visible: true

        width: dashboard.implicitWidth
        height: dashboard.implicitHeight
        color: "black"

        ExpandedDashboard {
            id: dashboard

            anchors.fill: parent
            mediaContent: mediaContent
            clockContent: clockContent
            quickControlsContent: quickContent
            audioContent: audioContent
            notificationsContent: notificationContent
            navigationContent: navigationContent
        }

        Item {
            x: -2000
            width: 700
            height: 480

            DashboardMedia {
                id: mediaView
                visible: false
                width: 340
                height: 132
                media: mediaAdapter
            }

            DashboardQuickControls {
                id: quickView
                y: 140
                connectivity: connectivityAdapter
                applicationModel: applications
                tray: trayAdapter
                menuParentWindow: dashboardWindow
                onExternalActionDispatched: test.quickExternalActionCount += 1
                onShellMenuOpening: test.quickMenuOpeningCount += 1
            }

            DashboardAudio {
                id: audioView
                y: 250
                width: 340
                height: 92
                audio: audioAdapter
                onDeviceSelectionRequested: test.audioOpenRequests += 1
            }

            DashboardVolumeControl {
                id: outputVolume
                y: 350
                width: 300
                label: "Output"
                available: audioAdapter.outputAvailable
                volume: audioAdapter.outputVolume
                muted: audioAdapter.outputMuted
                overamplified: audioAdapter.outputOveramplified
                pendingVolume: audioAdapter.pendingOutputVolume
            }

            DashboardNotifications {
                id: recentView
                x: 350
                y: 250
                width: 300
                height: 92
                service: notificationService
            }
        }
    }
}

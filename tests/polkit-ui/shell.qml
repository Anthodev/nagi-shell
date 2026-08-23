import Quickshell
import QtQuick
import QtTest
import "qml"

ShellRoot {
    id: test

    property int step: 0
    property int retryAttempts: 0
    property var responseInput: null
    property var responseField: null
    property var firstIdentityButton: null
    property var secondIdentityButton: null
    property var cancelButton: null
    property var authenticateButton: null
    readonly property int maximumRetryAttempts: 200

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function findObject(item, name) {
        if (item === null || item === undefined) {
            return null;
        }
        if (item.objectName === name) {
            return item;
        }
        const candidates = [];
        if (item.children !== undefined) {
            for (let index = 0; index < item.children.length; index += 1) {
                candidates.push(item.children[index]);
            }
        }
        if (item.contentItem !== undefined && item.contentItem !== null) {
            candidates.push(item.contentItem);
        }
        for (let index = 0; index < candidates.length; index += 1) {
            const found = findObject(candidates[index], name);
            if (found !== null) {
                return found;
            }
        }
        return null;
    }

    function awaitState(condition, message) {
        if (condition) {
            retryAttempts = 0;
            return true;
        }
        retryAttempts += 1;
        require(retryAttempts <= maximumRetryAttempts, message);
        retry.restart();
        return false;
    }

    function advance() {
        step += 1;
        Qt.callLater(runStep);
    }

    function traversalContains(start, targets) {
        let cursor = start;
        const remaining = targets.slice();
        for (let hop = 0; hop < 16 && cursor !== null && remaining.length > 0; hop += 1) {
            cursor = cursor.nextItemInFocusChain(true);
            const index = remaining.indexOf(cursor);
            if (index >= 0) {
                remaining.splice(index, 1);
            }
        }
        return remaining.length === 0;
    }

    function runStep() {
        if (step === 0) {
            responseInput = findObject(polkitView, "polkitResponseInput");
            responseField = findObject(polkitView, "polkitResponseField");
            firstIdentityButton = findObject(polkitView, "polkitIdentityButton0");
            secondIdentityButton = findObject(polkitView, "polkitIdentityButton1");
            cancelButton = findObject(polkitView, "subviewBackButton");
            authenticateButton = findObject(polkitView, "polkitAuthenticateButton");
            if (!awaitState(responseInput !== null && responseField !== null
                            && firstIdentityButton !== null && secondIdentityButton !== null
                            && cancelButton !== null && authenticateButton !== null,
                            "Polkit controls were not created")) {
                return;
            }
            require(polkitView.requestMessage.length === 512
                    && polkitView.actionId.length === 256,
                    "untrusted request strings are bounded");
            require(polkitView.iconName === "object-locked-symbolic",
                    "unsafe icon names use the fixed fallback");
            require(polkitView.identityCount === 2 && polkitView.selectedIdentity === identityA,
                    "only the normalized identity projection is consumed");
            require(cancelButton.Accessible.name === "Back",
                    "Polkit cancellation uses the shared iconographic Back affordance");
            require(polkitView.supplementaryMessage.length === 512,
                    "supplementary feedback is bounded");
            require(responseField.radius === Theme.radius.md
                    && firstIdentityButton.background.radius === Theme.radius.md
                    && authenticateButton.background.radius === Theme.radius.md
                    && cancelButton.background.radius === Theme.radius.md,
                    "inner fields and standard controls use the 10 px medium radius");
            require(firstIdentityButton.background.radius * 2
                    < firstIdentityButton.implicitHeight,
                    "standard controls do not regress to a 32 px pill");
            polkitView.focusInitialControl();
        } else if (step === 1) {
            if (!awaitState(firstIdentityButton.activeFocus,
                            "multiple identities did not receive initial focus")) {
                return;
            }
            responseInput.text = "synthetic-before-identity-change";
            require(polkitView.requestIdentity(identityB), "live identity change is accepted");
            require(controller.identityChangeCount === 1 && controller.identityWasExact
                    && controller.identityInputWasCleared,
                    "identity dispatch uses the exact object after clearing input");
            require(responseInput.text === "" && controller.selectedIdentity === identityB,
                    "identity replacement retains no prior response");
            controller.promptGeneration += 1;
        } else if (step === 2) {
            if (!awaitState(responseInput.activeFocus,
                            "new hidden prompt did not focus the response field")) {
                return;
            }
            require(responseInput.echoMode === TextInput.NoEcho && !responseInput.selectByMouse,
                    "hidden prompt uses NoEcho and disables mouse selection");
            require(responseInput.passwordMaskDelay === 0 && responseInput.maximumLength === 4096,
                    "hidden prompt has no reveal delay and has the fixed response bound");
            require((responseInput.inputMethodHints & Qt.ImhHiddenText) !== 0
                    && (responseInput.inputMethodHints & Qt.ImhSensitiveData) !== 0
                    && (responseInput.inputMethodHints & Qt.ImhNoPredictiveText) !== 0
                    && (responseInput.inputMethodHints & Qt.ImhNoAutoUppercase) !== 0,
                    "hidden prompt disables learning, prediction, and capitalization");
            require(responseInput.Accessible.ignored && responseField.Accessible.passwordEdit
                    && !responseField.Accessible.selectableText && responseField.Accessible.focused,
                    "accessibility protects the focused response value");
            responseInput.text = "x".repeat(5000);
            require(responseInput.length === 4096,
                    "response is bounded to 4096 UTF-16 code units");
            responseInput.text = "hidden-selection";
            responseInput.select(0, responseInput.length);
            require(responseInput.selectedText === "",
                    "hidden response cannot retain a selection for copy or drag");
            clipboardSource.text = "clipboard-sentinel";
            clipboardSource.selectAll();
            clipboardSource.copy();
            responseInput.text = "synthetic-secret";
            responseInput.selectAll();
            responseInput.copy();
            clipboardProbe.text = "";
            clipboardProbe.paste();
            require(clipboardProbe.text === "clipboard-sentinel",
                    "hidden response cannot replace clipboard contents");
            responseInput.text = "  synthetic response  ";
            require(polkitView.submitCurrentResponse(), "current prompt submits explicitly");
            require(controller.submitCount === 1 && controller.submitMatched
                    && controller.submitInputWasCleared,
                    "exact unnormalized response is submitted after field clear");
            require(responseInput.text === "" && !responseInput.enabled
                    && !polkitView.submitCurrentResponse(),
                    "submission disables editing, stays one-shot, and retains no response");
            controller.submissionPending = false;
            controller.failureGeneration += 1;
            controller.responseVisible = true;
            controller.responseRequired = true;
            controller.promptGeneration += 1;
        } else if (step === 3) {
            if (!awaitState(responseInput.activeFocus && responseInput.echoMode === TextInput.Normal,
                            "visible retry prompt did not refocus in Normal mode")) {
                return;
            }
            require(responseInput.selectByMouse,
                    "visible response permits normal editing without changing submit semantics");
            require(polkitView.submitCurrentResponse(), "empty response remains a valid explicit submit");
            require(controller.submitCount === 2 && controller.emptySubmitMatched
                    && responseInput.text === "",
                    "empty response is forwarded exactly without normalization");
            controller.submissionPending = false;
            controller.responseRequired = true;
            controller.promptGeneration += 1;
        } else if (step === 4) {
            if (!awaitState(responseInput.activeFocus,
                            "prompt after empty response did not refocus")) {
                return;
            }
            require(traversalContains(firstIdentityButton,
                                      [responseInput, cancelButton, authenticateButton]),
                    "focus chain reaches response, Back, and Authenticate");
            responseInput.text = "synthetic-before-cancel";
            keyDriver.pressEscape();
            require(controller.cancelCount === 1 && controller.cancelInputWasCleared
                    && responseInput.text === "",
                    "Escape clears input before the guarded cancellation dispatch");
            require(!polkitView.requestCancellation() && !responseInput.enabled
                    && !cancelButton.enabled && !authenticateButton.enabled,
                    "repeated cancellation, editing, and actions stay disabled");
            controller.cancellationPending = true;
            controller.terminal = true;
            controller.available = false;
        } else if (step === 5) {
            require(!polkitView.visible && responseInput.text === "",
                    "unavailable terminal controller hides and clears the view");
            controller.available = true;
            controller.terminal = false;
            controller.cancellationPending = false;
            controller.flowGeneration += 1;
            controller.promptGeneration += 1;
            controller.identities = [malformedIdentity];
            controller.selectedIdentity = malformedIdentity;
        } else if (step === 6) {
            require(polkitView.identityCount === 0 && !polkitView.responseFieldVisible
                    && !polkitView.authenticateEnabled,
                    "malformed identity projection never exposes a credential field");
            controller.identities = [identityA];
            controller.selectedIdentity = identityA;
            controller.promptGeneration += 1;
            polkitView.ownerRevision += 1;
        } else if (step === 7) {
            if (!awaitState(responseInput.activeFocus,
                            "current owner revision did not receive prompt focus")) {
                return;
            }
            responseInput.text = "synthetic-before-controller-replacement";
            polkitView.controller = incompleteController;
            require(responseInput.text === "" && !polkitView.visible,
                    "incomplete controller contract clears and hides the credential view");
            polkitView.controller = null;
            require(!polkitView.visible, "missing controller keeps the credential view absent");
            polkitView.controller = controller;
        } else if (step === 8) {
            if (!awaitState(responseInput.activeFocus,
                            "replacement controller did not restore current prompt focus")) {
                return;
            }
            responseInput.text = "synthetic-before-owner-change";
            polkitView.ownerEpoch += 1;
            require(responseInput.text === "",
                    "owner replacement clears local response state");
            console.log("Polkit presentation tests passed");
            Qt.exit(0);
            return;
        }
        advance();
    }

    QtObject {
        id: identityA
        readonly property string id: "unix-user:1000"
        readonly property string string: "unix-user:developer"
        readonly property string displayName: "Developer"
        readonly property bool isGroup: false
    }

    QtObject {
        id: identityB
        readonly property string id: "unix-user:0"
        readonly property string string: "unix-user:root"
        readonly property string displayName: "Administrator"
        readonly property bool isGroup: false
    }

    QtObject {
        id: malformedIdentity
        readonly property string id: "missing-fields"
    }

    QtObject {
        id: incompleteController

        readonly property bool available: true
    }

    QtObject {
        id: controller

        property bool available: true
        property bool terminal: false
        property bool responseRequired: true
        property bool responseVisible: false
        property bool submissionPending: false
        property bool cancellationPending: false
        property int flowGeneration: 1
        property int promptGeneration: 1
        property int failureGeneration: 0
        property string message: "M".repeat(600)
        property string actionId: "A".repeat(300)
        property string inputPrompt: "Password"
        property string supplementaryMessage: "S".repeat(600)
        property bool supplementaryIsError: true
        property string iconName: "file:///unsafe/icon"
        property var identities: [identityA, identityB]
        property var selectedIdentity: identityA

        property int identityChangeCount: 0
        property bool identityWasExact: false
        property bool identityInputWasCleared: false
        property int submitCount: 0
        property bool submitMatched: false
        property bool emptySubmitMatched: false
        property bool submitInputWasCleared: false
        property int cancelCount: 0
        property bool cancelInputWasCleared: false

        function cancel() {
            cancelCount += 1;
            cancelInputWasCleared = test.responseInput.text === "";
            cancellationPending = true;
        }

        function selectIdentity(identity) {
            identityChangeCount += 1;
            identityWasExact = identity === identityB;
            identityInputWasCleared = test.responseInput.text === "";
            selectedIdentity = identity;
        }

        function submitResponse(response, generation) {
            submitCount += 1;
            submitInputWasCleared = test.responseInput.text === "";
            if (submitCount === 1) {
                submitMatched = response === "  synthetic response  "
                        && generation === promptGeneration;
            } else if (submitCount === 2) {
                emptySubmitMatched = response === "" && generation === promptGeneration;
            }
            submissionPending = true;
            responseRequired = false;
        }
    }

    Window {
        id: window

        visible: true
        width: polkitView.implicitWidth
        height: polkitView.implicitHeight
        color: Theme.color.surface

        PolkitView {
            id: polkitView

            anchors.fill: parent
            controller: controller
            ownerEpoch: 1
            ownerRevision: 1
        }

        TextInput {

            id: clipboardSource
            visible: false
        }

        TextInput {
            id: clipboardProbe
            visible: false
        }
    }

    TestCase {
        id: keyDriver

        name: "Polkit keyboard driver"
        when: false

        function pressEscape() {
            keyClick(Qt.Key_Escape);
        }
    }
    Timer {
        id: retry
        interval: 10
        onTriggered: test.runStep()
    }

    Component.onCompleted: Qt.callLater(runStep)
}
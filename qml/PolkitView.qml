pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import QtQuick.Layouts

// Presentation-only authentication view. The injected controller is a normalized
// contract; no Polkit object, cookie, PAM payload, or backend identity enters this
// component. The response lives only in responseInput and short-lived method
// locals. Clearing QML/QString references minimizes retention but cannot promise
// forensic zeroization.
FocusScope {
    id: view

    required property var controller
    required property real ownerEpoch
    required property real ownerRevision
    property bool active: true
    property real maximumViewportWidth: Number.POSITIVE_INFINITY
    property real maximumViewportHeight: Number.POSITIVE_INFINITY

    readonly property bool controllerAvailable: controller !== null && controller !== undefined
                                                && controller.available === true
                                                && typeof controller.selectIdentity === "function"
                                                && typeof controller.submitResponse === "function"
                                                && typeof controller.cancel === "function"
    readonly property bool terminal: controllerAvailable && controller.terminal === true
    readonly property bool responseRequired: controllerAvailable && controller.responseRequired
                                             === true
    readonly property bool responseVisible: controllerAvailable && controller.responseVisible
                                            === true
    readonly property bool controllerSubmissionPending: controllerAvailable
                                                        && controller.submissionPending === true
    readonly property bool controllerCancellationPending: controllerAvailable
                                                          && controller.cancellationPending === true
    readonly property bool operationPending: state.submitDispatched || state.cancelDispatched
                                             || controllerSubmissionPending
                                             || controllerCancellationPending
    readonly property int flowGeneration: boundedGeneration(controllerAvailable
                                                            ? controller.flowGeneration : 0)
    readonly property int promptGeneration: boundedGeneration(controllerAvailable
                                                              ? controller.promptGeneration : 0)
    readonly property int failureGeneration: boundedGeneration(controllerAvailable
                                                               ? controller.failureGeneration : 0)
    readonly property var identities: normalizedIdentities()
    readonly property int identityCount: identities.length
    readonly property var selectedIdentity: normalizedSelectedIdentity()
    readonly property int selectedIdentityIndex: selectedIdentity === null ? -1 : identities.indexOf(
                                                                                 selectedIdentity)
    readonly property string requestMessage: boundedText(controllerAvailable ? controller.message :
                                                                               "", 512, qsTr(
                                                             "Authentication is required."))
    readonly property string actionId: boundedText(controllerAvailable ? controller.actionId : "",
                                                   256, "")
    readonly property string inputPrompt: boundedText(controllerAvailable ? controller.inputPrompt :
                                                                            "", 256, qsTr(
                                                          "Authentication response"))
    readonly property string supplementaryMessage: boundedText(controllerAvailable
                                                               ? controller.supplementaryMessage :
                                                                 "", 512, "")
    readonly property bool supplementaryIsError: controllerAvailable
                                                 && controller.supplementaryIsError === true
    readonly property string iconName: normalizedIconName(controllerAvailable ? controller.iconName :
                                                                                "")
    readonly property bool responseFieldVisible: controllerAvailable && !terminal
                                                 && responseRequired && selectedIdentity !== null
    readonly property bool authenticateEnabled: responseFieldVisible && !operationPending
    readonly property bool cancelEnabled: controllerAvailable && !terminal &&
                                          !state.cancelDispatched && !controllerCancellationPending
    readonly property bool responseFocused: responseInput.activeFocus
    readonly property int responseEchoMode: responseInput.echoMode
    readonly property bool backFocused: frame.backControl.activeFocus
    implicitWidth: frame.implicitWidth
    implicitHeight: frame.implicitHeight

    visible: active && controllerAvailable

    function boundedGeneration(value) {
        return Number.isInteger(value) && value >= 0 && value <= 2147483647 ? value : 0;
    }

    function boundedText(value, maximumLength, fallback) {
        if (typeof value !== "string" || value.length === 0) {
            return fallback;
        }
        return value.slice(0, maximumLength);
    }

    function controllerMethod(name) {
        if (!controllerAvailable || typeof controller[name] !== "function") {
            return null;
        }
        return controller[name];
    }

    function identityIsNormalized(identity) {
        return identity !== null && typeof identity === "object" && !Array.isArray(identity)
                && typeof identity.id === "string" && identity.id.length > 0 && identity.id.length <= 128
                && typeof identity.string === "string" && identity.string.length <= 128
                && typeof identity.displayName === "string" && identity.displayName.length <= 128
                && typeof identity.isGroup === "boolean";
    }

    function normalizedIdentities() {
        if (!controllerAvailable || !Array.isArray(controller.identities)) {
            return [];
        }
        for (let index = 0; index < controller.identities.length; index += 1) {
            if (!identityIsNormalized(controller.identities[index])) {
                return [];
            }
        }
        return controller.identities;
    }

    function normalizedSelectedIdentity() {
        if (!controllerAvailable || identities.indexOf(controller.selectedIdentity) < 0) {
            return null;
        }
        return controller.selectedIdentity;
    }

    function identityLabel(identity) {
        if (!identityIsNormalized(identity)) {
            return qsTr("Unknown identity");
        }
        const base = identity.displayName !== "" ? identity.displayName : identity.string !== ""
                                                   ? identity.string : identity.id;
        return identity.isGroup ? qsTr("%1 (group)").arg(base) : base;
    }

    function normalizedIconName(value) {
        if (typeof value === "string" && value.length > 0 && value.length <= 128 &&
                /^[A-Za-z0-9._+-]+$/.test(value) && Quickshell.hasThemeIcon(value)) {
            return value;
        }
        return "object-locked-symbolic";
    }

    function clearResponse() {
        responseInput.clear();
        responseInput.deselect();
    }

    function clearForLifecycle(resetCancellation) {
        clearResponse();
        state.submitDispatched = false;
        if (resetCancellation) {
            state.cancelDispatched = false;
        }
    }

    function queuePromptFocus() {
        promptFocusTimer.attempts = 0;
        promptFocusTimer.restart();
    }

    Timer {
        id: promptFocusTimer
        property int attempts: 0

        interval: 1
        repeat: false
        onTriggered: {
            if (view.visible && view.responseFieldVisible) {
                responseInput.forceActiveFocus(Qt.ShortcutFocusReason);
                if (!responseInput.activeFocus && attempts < 4) {
                    attempts += 1;
                    restart();
                }
            }
        }
    }

    function synchronizeIdentityIndex() {
        identityList.currentIndex = selectedIdentityIndex >= 0 ? selectedIdentityIndex :
                                                                 identityCount > 0 ? 0 : -1;
        if (identityList.currentIndex >= 0) {
            identityList.positionViewAtIndex(identityList.currentIndex, ListView.Contain);
        }
    }

    function focusInitialControl() {
        synchronizeIdentityIndex();
        if (identityCount > 1 && identityList.currentItem !== null) {
            identityList.currentItem.forceActiveFocus(Qt.ShortcutFocusReason);
            return;
        }
        if (responseFieldVisible) {
            responseInput.forceActiveFocus(Qt.ShortcutFocusReason);
            return;
        }
        if (authenticateEnabled) {
            authenticateButton.forceActiveFocus(Qt.ShortcutFocusReason);
            return;
        }
        if (cancelEnabled) {
            frame.backControl.forceActiveFocus(Qt.ShortcutFocusReason);
        }
    }

    function requestIdentity(identity) {
        const method = controllerMethod("selectIdentity");
        if (method === null || operationPending || terminal || identities.indexOf(identity) < 0
                || identity === selectedIdentity) {
            return false;
        }
        clearResponse();
        state.submitDispatched = false;
        method.call(controller, identity);
        return true;
    }

    function submitCurrentResponse() {
        const method = controllerMethod("submitResponse");
        if (!authenticateEnabled || method === null) {
            return false;
        }

        let response = responseInput.text;
        clearResponse();
        state.submitDispatched = true;
        try {
            method.call(controller, response, promptGeneration);
        } finally {
            response = "";
        }
        return true;
    }

    function requestCancellation() {
        const method = controllerMethod("cancel");
        if (!cancelEnabled || method === null) {
            return false;
        }
        clearResponse();
        state.submitDispatched = false;
        state.cancelDispatched = true;
        method.call(controller);
        return true;
    }

    onControllerChanged: {
        clearForLifecycle(true);
        synchronizeIdentityIndex();
        queuePromptFocus();
    }
    onOwnerEpochChanged: clearForLifecycle(true)
    onOwnerRevisionChanged: {
        clearForLifecycle(true);
        queuePromptFocus();
    }
    onVisibleChanged: {
        if (!visible) {
            clearForLifecycle(true);
        }
    }

    Component.onCompleted: {
        clearForLifecycle(true);
        synchronizeIdentityIndex();
        queuePromptFocus();
    }
    Component.onDestruction: clearResponse()

    Connections {
        target: view.controller
        ignoreUnknownSignals: true

        function onAvailableChanged() {
            view.clearForLifecycle(true);
            if (view.controllerAvailable) {
                view.queuePromptFocus();
            }
        }
        function onCancellationPendingChanged() {
            if (view.controllerCancellationPending) {
                view.clearResponse();
            }
        }
        function onFailureGenerationChanged() {
            view.clearForLifecycle(false);
        }
        function onFlowGenerationChanged() {
            view.clearForLifecycle(true);
            view.synchronizeIdentityIndex();
            view.queuePromptFocus();
        }
        function onIdentitiesChanged() {
            view.clearForLifecycle(false);
            view.synchronizeIdentityIndex();
        }
        function onPromptGenerationChanged() {
            view.clearForLifecycle(false);
            view.queuePromptFocus();
        }
        function onResponseRequiredChanged() {
            if (!view.responseRequired) {
                view.clearResponse();
            } else {
                view.queuePromptFocus();
            }
        }
        function onSelectedIdentityChanged() {
            view.clearForLifecycle(false);
            view.synchronizeIdentityIndex();
        }
        function onSubmissionPendingChanged() {
            if (view.controllerSubmissionPending) {
                view.clearResponse();
            }
        }
        function onTerminalChanged() {
            if (view.terminal) {
                view.clearForLifecycle(true);
            }
        }
    }

    QtObject {
        id: state

        property bool submitDispatched: false
        property bool cancelDispatched: false
    }

    SubviewFrame {
        id: frame

        anchors.fill: parent
        active: view.visible
        title: qsTr("Authentication required")
        maximumViewportWidth: view.maximumViewportWidth
        maximumViewportHeight: view.maximumViewportHeight
        initialFocusItem: view.identityCount > 1 ? identityList.currentItem :
                                                   view.responseFieldVisible ? responseInput :
                                                                               authenticateButton
        onBackRequested: view.requestCancellation()
        onEscapePressed: view.requestCancellation()

        Item {
            width: Theme.spacing.xxl * 13
            height: authContent.implicitHeight

            ColumnLayout {
                id: authContent

                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Theme.spacing.lg

                IslandText {
                    Layout.fillWidth: true
                    text: view.requestMessage
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }

                IslandText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: view.actionId
                    textFormat: Text.PlainText
                    tone: "muted"
                    size: "caption"
                    elide: Text.ElideRight
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: view.identityCount > 0
                    spacing: Theme.spacing.sm

                    IslandText {
                        text: view.identityCount > 1 ? qsTr("Identity") : qsTr("Selected identity")
                        textFormat: Text.PlainText
                        tone: "secondary"
                        size: "caption"
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }

                    ListView {
                        id: identityList

                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.size.controlHeightMd
                        orientation: ListView.Horizontal
                        spacing: Theme.spacing.sm
                        interactive: contentWidth > width
                        clip: interactive
                        boundsBehavior: Flickable.StopAtBounds
                        model: view.identities
                        visible: view.identityCount > 1
                        Accessible.role: Accessible.List
                        Accessible.name: qsTr("Authentication identities")

                        delegate: IslandButton {
                            id: identityButton

                            required property int index
                            required property var modelData

                            objectName: "polkitIdentityButton" + index
                            label: view.identityLabel(modelData)
                            variant: modelData === view.selectedIdentity ? "accent" : "standard"
                            enabled: view.controllerAvailable && !view.terminal &&
                                     !view.operationPending
                            Accessible.description: modelData === view.selectedIdentity ? qsTr(
                                                                                              "Selected authentication identity") :
                                                                                          qsTr("Select this authentication identity")
                            onClicked: view.requestIdentity(modelData)

                            Keys.onLeftPressed: event => {
                                const nextIndex = Math.max(0, index - 1);
                                identityList.currentIndex = nextIndex;
                                identityList.positionViewAtIndex(nextIndex, ListView.Contain);
                                if (identityList.currentItem !== null) {
                                    identityList.currentItem.forceActiveFocus(
                                                Qt.ShortcutFocusReason);
                                }
                                event.accepted = true;
                            }
                            Keys.onRightPressed: event => {
                                const nextIndex = Math.min(view.identityCount - 1, index + 1);
                                identityList.currentIndex = nextIndex;
                                identityList.positionViewAtIndex(nextIndex, ListView.Contain);
                                if (identityList.currentItem !== null) {
                                    identityList.currentItem.forceActiveFocus(
                                                Qt.ShortcutFocusReason);
                                }
                                event.accepted = true;
                            }
                        }
                    }

                    IslandText {
                        Layout.fillWidth: true
                        visible: view.identityCount === 1
                        text: view.selectedIdentity === null ? qsTr(
                                                                   "No supported identity selected") :
                                                               view.identityLabel(
                                                                   view.selectedIdentity)
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.sm

                    IslandText {
                        Layout.fillWidth: true
                        text: view.inputPrompt
                        textFormat: Text.PlainText
                        tone: "secondary"
                        size: "caption"
                        wrapMode: Text.Wrap
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }

                    IslandPanel {
                        objectName: "polkitResponseField"
                        Accessible.role: Accessible.EditableText
                        Accessible.name: qsTr("Authentication response")
                        Accessible.description: qsTr(
                                                    "Enter the response requested for authentication")
                        Accessible.passwordEdit: true
                        Accessible.selectableText: false
                        Accessible.focusable: true
                        Accessible.focused: responseInput.activeFocus
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.size.controlHeightLg
                        visible: view.responseFieldVisible
                        opacity: view.operationPending ? Theme.opacity.disabled : 1
                        radius: Theme.radius.md
                        color: Theme.color.controlFill
                        border.width: Theme.size.hairlineWidth
                        border.color: responseInput.activeFocus ? Theme.snapshot.focusRing :
                                                                  Theme.color.surfaceBorder

                        TextInput {
                            id: responseInput

                            objectName: "polkitResponseInput"
                            anchors.fill: parent
                            leftPadding: Theme.spacing.md
                            rightPadding: Theme.spacing.md
                            color: Theme.color.textPrimary
                            selectionColor: Theme.snapshot.accent
                            selectedTextColor: Theme.snapshot.accentForeground
                            font.pixelSize: Theme.type.body
                            font.family: Theme.type.family
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            activeFocusOnTab: true
                            enabled: !view.operationPending
                            readOnly: view.operationPending
                            echoMode: view.responseVisible ? TextInput.Normal : TextInput.NoEcho
                            passwordMaskDelay: 0
                            maximumLength: 4096
                            selectByMouse: view.responseVisible
                            persistentSelection: false
                            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                                              | Qt.ImhNoAutoUppercase | (view.responseVisible
                                                                         ? Qt.ImhNone :
                                                                           Qt.ImhHiddenText)
                            Accessible.ignored: true

                            onSelectedTextChanged: {
                                if (!view.responseVisible && selectedText !== "") {
                                    deselect();
                                }
                            }

                            Keys.priority: Keys.BeforeItem
                            Keys.onPressed: event => {
                                const control = (event.modifiers & Qt.ControlModifier) !== 0;
                                const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
                                const hiddenExposure = !view.responseVisible && ((control && (
                                                                                      event.key
                                                                                      === Qt.Key_C
                                                                                      || event.key
                                                                                      === Qt.Key_X
                                                                                      || event.key
                                                                                      === Qt.Key_Insert))
                                                                                 || (shift
                                                                                     && event.key
                                                                                     === Qt.Key_Delete));
                                if (hiddenExposure) {
                                    deselect();
                                    event.accepted = true;
                                }
                            }
                            Keys.onReturnPressed: event => {
                                view.submitCurrentResponse();
                                event.accepted = true;
                            }
                            Keys.onEnterPressed: event => {
                                view.submitCurrentResponse();
                                event.accepted = true;
                            }
                        }
                    }

                    IslandText {
                        Layout.fillWidth: true
                        visible: !view.responseFieldVisible && view.controllerAvailable &&
                                 !view.terminal
                        text: view.identityCount === 0 ? qsTr(
                                                             "No supported authentication identity is available.") :
                                                         qsTr("Waiting for an authentication prompt…")
                        textFormat: Text.PlainText
                        tone: "secondary"
                        wrapMode: Text.Wrap
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }
                }

                IslandText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: view.controllerCancellationPending || state.cancelDispatched ? qsTr(
                                                                                             "Cancelling…") :
                                                                                         view.controllerSubmissionPending
                                                                                         || state.submitDispatched
                                                                                         ? qsTr("Authenticating…") :
                                                                                           view.supplementaryMessage
                    textFormat: Text.PlainText
                    color: view.supplementaryIsError ? Theme.color.danger :
                                                       Theme.color.textSecondary
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }

                RowLayout {
                    Layout.fillWidth: true

                    Item {
                        Layout.fillWidth: true
                    }

                    IslandButton {
                        id: authenticateButton

                        objectName: "polkitAuthenticateButton"
                        label: qsTr("Authenticate")
                        variant: "accent"
                        enabled: view.authenticateEnabled
                        Accessible.description: qsTr("Submit the current authentication response")
                        onClicked: view.submitCurrentResponse()
                    }
                }
            }
        }
    }

    Binding {
        target: frame.backControl
        property: "enabled"
        value: view.cancelEnabled
    }
}

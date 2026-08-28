pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root

    required property var wifi
    property bool reducedMotion: false
    property string mode: "list"
    property int selectedToken: 0
    property string selectedLabel: ""
    property int forgetToken: 0
    property string forgetLabel: ""
    property bool rememberConnection: false
    property string hiddenSecurity: "wpa-personal"
    property bool managerInterestActive: false

    readonly property bool backendUnavailable: wifi === null || !wifi.backendReady ||
                                               !wifi.wifiAvailable

    readonly property bool operationPending: wifi !== null && wifi.wifiBusy
    readonly property bool formVisible: mode === "password" || mode === "hidden"

    clip: true
    contentWidth: width
    contentHeight: content.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {
        policy: root.contentHeight > root.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
    }

    function clearPrivateState() {
        secretField.clear();
        hiddenSecretField.clear();
        hiddenSsid.clear();
        selectedToken = 0;
        selectedLabel = "";
        forgetToken = 0;
        forgetLabel = "";
        rememberConnection = false;
        hiddenSecurity = "wpa-personal";
        mode = "list";
    }

    function updateInterest() {
        if (wifi === null) {
            managerInterestActive = false;
            return;
        }
        const wanted = visible && wifi.backendReady;
        if (wanted === managerInterestActive) {
            return;
        }
        if (wifi.setWifiManagerOpen(wanted)) {
            managerInterestActive = wanted;
        } else if (!wanted) {
            managerInterestActive = false;
        }
    }

    function openNetwork(network) {
        if (network === null || network === undefined || operationPending) {
            return false;
        }
        if (network.saved || network.security === "open") {
            return wifi.connectWifi(network.token, "", false);
        }
        selectedToken = network.token;
        selectedLabel = network.ssid;
        rememberConnection = false;
        mode = "password";
        Qt.callLater(secretField.forceInputFocus);
        return true;
    }

    function submitVisibleNetwork() {
        if (mode !== "password" || selectedToken < 1 || operationPending) {
            secretField.clear();
            return false;
        }
        let accepted = false;
        secretField.consume(secret => accepted = wifi.connectWifi(selectedToken, secret,
                                                                  rememberConnection));
        if (accepted) {
            selectedToken = 0;
            selectedLabel = "";
            rememberConnection = false;
            mode = "list";
        }
        return accepted;
    }

    function submitHiddenNetwork() {
        if (mode !== "hidden" || hiddenSsid.text.trim() === "" || operationPending) {
            hiddenSecretField.clear();
            return false;
        }
        const ssid = hiddenSsid.text;
        hiddenSsid.clear();
        let accepted = false;
        if (hiddenSecurity === "open") {
            hiddenSecretField.clear();
            accepted = wifi.connectHiddenWifi(ssid, hiddenSecurity, "", rememberConnection);
        } else {
            hiddenSecretField.consume(secret => accepted = wifi.connectHiddenWifi(ssid,
                                                                                  hiddenSecurity,
                                                                                  secret, rememberConnection));
        }
        if (accepted) {
            mode = "list";
            rememberConnection = false;
        }
        return accepted;
    }

    function requestForget(network) {
        if (network === null || network === undefined || !network.forgettable || operationPending) {
            return false;
        }
        forgetToken = network.token;
        forgetLabel = network.ssid;
        mode = "forget";
        return true;
    }

    function confirmForget() {
        if (mode !== "forget" || forgetToken < 1 || operationPending) {
            return false;
        }
        const token = forgetToken;
        forgetToken = 0;
        forgetLabel = "";
        mode = "list";
        return wifi.forgetWifi(token);
    }

    function operationMessage() {
        if (wifi === null)
            return "";
        if (wifi.wifiOperationFailure === "wrong-secret")
            return qsTr("The password was not accepted. Re-enter it and try again.");
        if (wifi.wifiOperationFailure === "denied")
            return qsTr("NetworkManager denied the requested Wi-Fi change.");
        if (wifi.wifiOperationFailure === "cooldown")
            return qsTr("Wait briefly before requesting another scan.");
        if (wifi.wifiOperationFailure === "timeout")
            return qsTr("The Wi-Fi operation timed out.");
        if (wifi.wifiOperationFailure !== "none")
            return qsTr("The Wi-Fi operation could not be completed.");
        if (wifi.wifiOperationResult === "connected")
            return qsTr("Connection completed.");
        if (wifi.wifiOperationResult === "disconnected")
            return qsTr("Disconnected.");
        if (wifi.wifiOperationResult === "forgotten")
            return qsTr("Personal profile forgotten.");
        return "";
    }

    Component.onCompleted: updateInterest()
    Component.onDestruction: {
        clearPrivateState();
        if (wifi !== null && managerInterestActive) {
            wifi.setWifiManagerOpen(false);
        }
        managerInterestActive = false;
    }
    onVisibleChanged: {
        if (!visible) {
            clearPrivateState();
        }
        updateInterest();
    }

    Connections {
        target: root.wifi
        ignoreUnknownSignals: true

        function onBackendReadyChanged() {
            if (!root.wifi.backendReady) {
                root.clearPrivateState();
                root.managerInterestActive = false;
            }
            root.updateInterest();
        }

        function onWifiOperationGenerationChanged() {
            secretField.clear();
            hiddenSecretField.clear();
        }

        function onWifiOperationFailureChanged() {
            if (root.wifi.wifiOperationFailure === "wrong-secret") {
                secretField.clear();
                hiddenSecretField.clear();
            }
        }
    }

    ColumnLayout {
        id: content

        width: Math.min(root.width - (root.contentHeight > root.height ? Theme.spacing.md : 0),
                        Theme.size.controlCenterContentMaximumWidth)
        spacing: Theme.spacing.md

        IslandText {
            text: qsTr("Wi-Fi")
            size: "title"
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }

        IslandPanel {
            Layout.fillWidth: true
            implicitHeight: unavailableColumn.implicitHeight + Theme.spacing.lg * 2
            color: Theme.color.controlFill
            visible: root.backendUnavailable

            ColumnLayout {
                id: unavailableColumn

                anchors.fill: parent
                anchors.margins: Theme.spacing.lg
                spacing: Theme.spacing.sm

                IslandText {
                    Layout.fillWidth: true
                    text: qsTr("Wi-Fi management unavailable")
                    size: "title"
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }

                IslandText {
                    Layout.fillWidth: true
                    text: qsTr(
                              "NetworkManager or a Wi-Fi device is unavailable. Use KDE System Settings to inspect the system service or hardware state.")
                    textFormat: Text.PlainText
                    size: "body"
                    color: Theme.color.textSecondary
                    wrapMode: Text.Wrap
                    Accessible.name: text
                }
            }
        }

        SettingToggleRow {
            Layout.fillWidth: true
            visible: !root.backendUnavailable
            label: qsTr("Wi-Fi radio")
            description: root.wifi.wifiHardwareEnabled ? qsTr(
                                                             "Backend-confirmed NetworkManager state.") :
                                                         qsTr("The hardware radio is disabled.")
            value: root.wifi.wifiEnabled
            writable: root.wifi.wifiHardwareEnabled && !root.operationPending
            onValueRequested: value => root.wifi.requestWifiEnabled(value)
        }

        RowLayout {
            Layout.fillWidth: true
            visible: !root.backendUnavailable && root.wifi.wifiEnabled && root.mode === "list"
            spacing: Theme.spacing.sm

            IslandButton {
                objectName: "wifiRefreshButton"
                label: root.wifi.wifiScanning ? qsTr("Scanning…") : qsTr("Refresh")
                reducedMotion: root.reducedMotion
                enabled: !root.operationPending
                Accessible.description: qsTr("Request one NetworkManager Wi-Fi scan")
                onClicked: root.wifi.refreshWifi()
            }

            IslandButton {
                objectName: "wifiHiddenButton"
                label: qsTr("Hidden network")
                reducedMotion: root.reducedMotion
                enabled: !root.operationPending
                Accessible.description: qsTr("Connect to an explicit hidden SSID")
                onClicked: {
                    root.clearPrivateState();
                    root.mode = "hidden";
                    Qt.callLater(hiddenSsid.forceActiveFocus);
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }

        IslandText {
            Layout.fillWidth: true
            visible: !root.backendUnavailable && root.mode === "list" && root.operationMessage()
                     !== ""
            text: root.operationMessage()
            textFormat: Text.PlainText
            size: "caption"
            color: root.wifi.wifiOperationFailure === "none" ? Theme.color.textSecondary :
                                                               Theme.color.dangerText
            wrapMode: Text.Wrap
            Accessible.name: text
        }

        IslandText {
            Layout.fillWidth: true
            visible: !root.backendUnavailable && root.wifi.wifiEnabled && root.mode === "list" &&
                     !root.wifi.wifiScanning && root.wifi.wifiNetworks.length === 0
            text: qsTr("No networks are currently available. Refresh to request one bounded scan.")
            size: "body"
            color: Theme.color.textSecondary
            wrapMode: Text.Wrap
            Accessible.name: text
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: !root.backendUnavailable && root.wifi.wifiEnabled && root.mode === "list"
            spacing: Theme.spacing.sm
            Accessible.role: Accessible.List
            Accessible.name: qsTr("Connected and available Wi-Fi networks")

            Repeater {
                model: root.wifi === null ? [] : root.wifi.wifiNetworks

                delegate: WifiNetworkRow {
                    required property var modelData

                    network: modelData
                    busy: root.operationPending
                    reducedMotion: root.reducedMotion
                    onConnectRequested: (token, secretRequired) => root.openNetwork(modelData)
                    onDisconnectRequested: root.wifi.disconnectWifi()
                    onForgetRequested: token => root.requestForget(modelData)
                }
            }
        }

        IslandPanel {
            Layout.fillWidth: true
            implicitHeight: passwordColumn.implicitHeight + Theme.spacing.lg * 2
            color: Theme.color.controlFill
            visible: root.mode === "password"

            ColumnLayout {
                id: passwordColumn

                anchors.fill: parent
                anchors.margins: Theme.spacing.lg
                spacing: Theme.spacing.md

                IslandText {
                    Layout.fillWidth: true
                    text: qsTr("Connect to %1").arg(root.selectedLabel)
                    textFormat: Text.PlainText
                    size: "title"
                    elide: Text.ElideRight
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }

                WifiSecretField {
                    id: secretField

                    Layout.fillWidth: true
                    operationPending: root.operationPending
                }

                SettingToggleRow {
                    Layout.fillWidth: true
                    label: qsTr("Remember")
                    description: qsTr("Delegate user-scoped credential storage to NetworkManager.")
                    value: root.rememberConnection
                    writable: !root.operationPending
                    onValueRequested: value => root.rememberConnection = value
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.sm

                    IslandButton {
                        objectName: "wifiPasswordSubmit"
                        label: qsTr("Connect")
                        variant: "accent"
                        reducedMotion: root.reducedMotion
                        enabled: !root.operationPending && secretField.acceptable
                        onClicked: root.submitVisibleNetwork()
                    }

                    IslandButton {
                        label: qsTr("Cancel")
                        reducedMotion: root.reducedMotion
                        enabled: !root.operationPending
                        onClicked: root.clearPrivateState()
                    }
                }
            }
        }

        IslandPanel {
            Layout.fillWidth: true
            implicitHeight: hiddenColumn.implicitHeight + Theme.spacing.lg * 2
            color: Theme.color.controlFill
            visible: root.mode === "hidden"

            ColumnLayout {
                id: hiddenColumn

                anchors.fill: parent
                anchors.margins: Theme.spacing.lg
                spacing: Theme.spacing.md

                IslandText {
                    text: qsTr("Hidden network")
                    size: "title"
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }

                IslandText {
                    Layout.fillWidth: true
                    text: qsTr(
                              "Open and WPA Personal networks only. Enterprise, EAP, certificates, hotspots, and profile editing remain in KDE.")
                    textFormat: Text.PlainText
                    size: "caption"
                    color: Theme.color.textSecondary
                    wrapMode: Text.Wrap
                    Accessible.name: text
                }

                IslandPanel {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.size.controlHeightLg
                    radius: Theme.radius.md
                    color: Theme.color.controlFill
                    border.width: Theme.size.hairlineWidth
                    border.color: hiddenSsid.activeFocus ? Theme.snapshot.focusRing :
                                                           Theme.color.surfaceBorder
                    Accessible.role: Accessible.EditableText
                    Accessible.name: qsTr("Hidden network name")
                    Accessible.focused: hiddenSsid.activeFocus

                    TextInput {
                        id: hiddenSsid

                        objectName: "wifiHiddenSsid"
                        anchors.fill: parent
                        leftPadding: Theme.spacing.md
                        rightPadding: Theme.spacing.md
                        enabled: !root.operationPending
                        color: Theme.color.textPrimary
                        selectionColor: Theme.snapshot.accent
                        selectedTextColor: Theme.snapshot.accentForeground
                        font.pixelSize: Theme.type.sizeForItem(this, "body")
                        font.family: Theme.type.familyForItem(this)
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        activeFocusOnTab: true
                        maximumLength: 32
                        inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                        Accessible.ignored: true
                    }
                }

                SettingChoiceRow {
                    Layout.fillWidth: true
                    label: qsTr("Security")
                    description: qsTr("Choose Open or WPA Personal.")
                    value: root.hiddenSecurity
                    choices: [
                        {
                            "value": "open",
                            "label": qsTr("Open")
                        },
                        {
                            "value": "wpa-personal",
                            "label": qsTr("WPA Personal")
                        }
                    ]
                    writable: !root.operationPending
                    reducedMotion: root.reducedMotion
                    onValueRequested: value => {
                        root.hiddenSecurity = value;
                        if (value === "open") {
                            hiddenSecretField.clear();
                        }
                    }
                }

                WifiSecretField {
                    id: hiddenSecretField
                    inputObjectName: "wifiHiddenPasswordInput"
                    Layout.fillWidth: true
                    visible: root.hiddenSecurity === "wpa-personal"
                    operationPending: root.operationPending
                }

                SettingToggleRow {
                    Layout.fillWidth: true
                    label: qsTr("Remember")
                    description: qsTr("Delegate user-scoped credential storage to NetworkManager.")
                    value: root.rememberConnection
                    writable: !root.operationPending
                    onValueRequested: value => root.rememberConnection = value
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.sm

                    IslandButton {
                        objectName: "wifiHiddenSubmit"
                        label: qsTr("Connect")
                        variant: "accent"
                        reducedMotion: root.reducedMotion
                        enabled: !root.operationPending && hiddenSsid.text.trim() !== "" && (root.hiddenSecurity
                                                                                             === "open"
                                                                                             || hiddenSecretField.acceptable)
                        onClicked: root.submitHiddenNetwork()
                    }

                    IslandButton {
                        label: qsTr("Cancel")
                        reducedMotion: root.reducedMotion
                        enabled: !root.operationPending
                        onClicked: root.clearPrivateState()
                    }
                }
            }
        }

        IslandPanel {
            Layout.fillWidth: true
            implicitHeight: forgetColumn.implicitHeight + Theme.spacing.lg * 2
            color: Theme.color.dangerFill
            visible: root.mode === "forget"

            ColumnLayout {
                id: forgetColumn

                anchors.fill: parent
                anchors.margins: Theme.spacing.lg
                spacing: Theme.spacing.md

                IslandText {
                    Layout.fillWidth: true
                    text: qsTr("Forget %1?").arg(root.forgetLabel)
                    textFormat: Text.PlainText
                    size: "title"
                    elide: Text.ElideRight
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }

                IslandText {
                    Layout.fillWidth: true
                    text: qsTr(
                              "This removes only the proven user-owned NetworkManager profile and its NetworkManager-managed credential.")
                    textFormat: Text.PlainText
                    size: "body"
                    wrapMode: Text.Wrap
                    Accessible.name: text
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.sm

                    IslandButton {
                        objectName: "wifiForgetConfirm"
                        label: qsTr("Forget")
                        variant: "danger"
                        reducedMotion: root.reducedMotion
                        enabled: !root.operationPending
                        onClicked: root.confirmForget()
                    }

                    IslandButton {
                        label: qsTr("Cancel")
                        reducedMotion: root.reducedMotion
                        enabled: !root.operationPending
                        onClicked: root.clearPrivateState()
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.spacing.md
        }
    }
}

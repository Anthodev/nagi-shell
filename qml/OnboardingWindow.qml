pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Scope {
    id: root

    property string settingsFailure: ""
    signal systemSettingsRequested

    readonly property string stateHome: {
        const xdgHome = Quickshell.env("XDG_STATE_HOME") ?? "";
        return xdgHome !== "" ? xdgHome : (Quickshell.env("HOME") ?? "") + "/.local/state";
    }
    readonly property string stateDirectoryPath: stateHome + "/nagi-shell"
    readonly property string statePath: stateDirectoryPath + "/onboarding.state"
    readonly property string dismissedContent: "dismissed=1\n"
    readonly property int maximumStateBytes: 32

    property bool stateResolved: false
    property bool dismissed: false
    readonly property bool onboardingVisible: onboarding.visible
    readonly property alias onboardingWindow: onboarding
    readonly property alias settingsAction: settingsButton
    readonly property alias backgroundItem: onboardingBackground
    readonly property alias closeAction: closeButton

    signal dismissalPersisted

    property bool dismissalWritePending: false
    property bool directoryCreationPending: false

    property bool _resourceLossPending: false
    function resolveState() {
        const data = stateFile.data();
        const byteLength = data !== null && typeof data.byteLength === "number" ? data.byteLength :
                                                                                  stateFile.text(
                                                                                      ).length;
        dismissed = byteLength <= maximumStateBytes && stateFile.text() === dismissedContent;
        stateResolved = true;
    }

    function dismiss() {
        if (dismissed || dismissalWritePending) {
            onboarding.visible = false;
            return;
        }
        dismissed = true;
        dismissalWritePending = true;
        onboarding.visible = false;
        directoryCreationPending = true;
        stateDirectoryCreator.running = true;
    }

    function noteResourceLoss() {
        _resourceLossPending = true;
    }

    function handleClosed() {
        if (_resourceLossPending) {
            _resourceLossPending = false;
            return;
        }
        if (stateResolved && !dismissed) {
            dismiss();
        }
    }

    FileView {
        id: stateFile

        path: root.statePath
        preload: true
        atomicWrites: true
        blockLoading: true
        printErrors: false
        onLoaded: root.resolveState()
        onLoadFailed: function (error) {
            root.dismissed = false;
            root.stateResolved = true;
        }
        onSaved: {
            root.dismissalWritePending = false;
            root.directoryCreationPending = false;
            root.dismissalPersisted();
        }
        onSaveFailed: function (error) {
            root.dismissalWritePending = false;
            root.directoryCreationPending = false;
        }
    }

    Process {
        id: stateDirectoryCreator

        command: ["mkdir", "-p", "--", root.stateDirectoryPath]
        onExited: function (exitCode) {
            root.directoryCreationPending = false;
            if (exitCode === 0 && root.dismissalWritePending) {
                stateFile.setText(root.dismissedContent);
            } else {
                root.dismissalWritePending = false;
            }
        }
    }

    FloatingWindow {
        id: onboarding

        title: "Welcome to Nagi Shell"
        visible: root.stateResolved && !root.dismissed
        implicitWidth: Theme.size.onboardingWidth
        implicitHeight: onboardingContent.implicitHeight + Theme.spacing.xl * 2
        minimumSize: Qt.size(Theme.size.onboardingMinimumWidth, implicitHeight)
        maximumSize: Qt.size(Theme.size.onboardingMaximumWidth, implicitHeight)
        color: Theme.color.surfaceOpaque

        onVisibleChanged: {
            if (visible) {
                Qt.callLater(closeButton.forceActiveFocus);
            }
        }
        onResourcesLost: root.noteResourceLoss()
        onClosed: root.handleClosed()

        Shortcut {
            sequences: [StandardKey.Cancel]
            enabled: onboarding.visible
            onActivated: root.dismiss()
        }

        Rectangle {
            id: onboardingBackground

            anchors.fill: parent
            color: Theme.color.surfaceOpaque
            radius: Theme.radius.xl
            border.color: Theme.color.surfaceBorder
            border.width: Theme.size.hairlineWidth
        }

        ColumnLayout {
            id: onboardingContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacing.xl
            spacing: Theme.spacing.lg

            IslandText {
                Layout.fillWidth: true
                text: "Welcome to Nagi Shell"
                size: "title"
                font.weight: Theme.type.weightSemibold
                Accessible.role: Accessible.Heading
            }

            IslandText {
                Layout.fillWidth: true
                text: "Nagi stores appearance, media, weather, and clock preferences in a private versioned settings.conf and migrates an older theme.conf automatically."
                tone: "secondary"
                wrapMode: Text.Wrap
            }

            IslandText {
                Layout.fillWidth: true
                text: "Use the System Settings action in the dashboard rail to manage Nagi Shell shortcuts. Open Launcher prefers Meta+Space, but Nagi never replaces KRunner's shortcut when it conflicts."
                tone: "secondary"
                wrapMode: Text.Wrap
            }

            IslandText {
                Layout.fillWidth: true
                visible: root.settingsFailure !== ""
                text: root.settingsFailure
                tone: "danger"
                wrapMode: Text.Wrap
                Accessible.role: Accessible.AlertMessage
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: Theme.spacing.sm

                IslandButton {
                    id: settingsButton

                    objectName: "onboardingSettings"
                    label: "System Settings"
                    implicitHeight: Theme.size.controlHeightLg
                    leftPadding: Theme.spacing.lg
                    rightPadding: Theme.spacing.lg
                    onClicked: root.systemSettingsRequested()
                }

                IslandButton {
                    id: closeButton

                    objectName: "onboardingClose"
                    label: "Get started"
                    Accessible.name: "Close onboarding"
                    implicitHeight: Theme.size.controlHeightLg
                    leftPadding: Theme.spacing.lg
                    rightPadding: Theme.spacing.lg
                    onClicked: root.dismiss()
                }
            }
        }
    }
}

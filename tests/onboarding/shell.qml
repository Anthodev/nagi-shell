import Quickshell
import Quickshell.Io
import QtQuick
import "qml"

ShellRoot {
    id: test

    property var onboarding: null
    property string stage: "initial"
    property int settingsRequests: 0
    property int islandMutationCount: 0

    readonly property string statePath: Quickshell.env("XDG_STATE_HOME") + "/nagi-shell/onboarding.state"

    function fail(message) {
        console.error("FAIL: " + message + " (stage=" + stage + ")");
        Qt.exit(1);
        throw new Error(message);
    }

    function require(condition, message) {
        if (!condition) {
            fail(message);
        }
    }
    function findObject(item, objectName) {
        if (item === null || item === undefined) {
            return null;
        }
        if (item.objectName === objectName) {
            return item;
        }
        const children = item.children ?? [];
        for (let index = 0; index < children.length; index += 1) {
            const match = findObject(children[index], objectName);
            if (match !== null) {
                return match;
            }
        }
        return null;
    }


    function createOnboarding() {
        onboarding = onboardingFactory.createObject(test);
        require(onboarding !== null, "onboarding component is created");
        settleTimer.restart();
    }

    function initialStage() {
        require(onboarding.stateResolved && onboarding.onboardingVisible,
                "missing state shows onboarding on first launch");
        require(onboarding.onboardingWindow.parentWindow === null,
                "onboarding is an independent unparented window");
        require(onboarding.onboardingWindow.title === "Welcome to Nagi Shell"
                && onboarding.onboardingWindow.implicitWidth === Theme.size.onboardingWidth
                && onboarding.backgroundItem.radius === Theme.radius.xl,
                "onboarding uses its semantic window geometry tokens");
        require(onboarding.settingsAction.Accessible.name === "Open Control Center"
                && onboarding.closeAction.Accessible.name === "Close onboarding",
                "onboarding actions expose keyboard-accessible names");
        require(findObject(onboarding.settingsAction, "islandFocusRing") !== null
                && findObject(onboarding.closeAction, "islandFocusRing") !== null,
                "onboarding actions use the shared external focus ring");
        onboarding.noteResourceLoss();
        onboarding.handleClosed();
        require(!onboarding.dismissed && onboarding.onboardingVisible,
                "resource loss never persists an onboarding dismissal");
        onboarding.settingsAction.clicked();
        require(settingsRequests === 1 && islandMutationCount === 0,
                "Settings action routes without mutating island state");
        onboarding.closeAction.clicked();
        require(!onboarding.onboardingVisible && onboarding.dismissed,
                "visible close action dismisses onboarding immediately");
        stage = "persisted";
    }

    function persistedStage() {
        onboarding.destroy();
        onboarding = null;
        stage = "second-launch";
        createOnboarding();
    }

    function secondLaunchStage() {
        require(onboarding.stateResolved && onboarding.dismissed && !onboarding.onboardingVisible,
                "persisted intentional dismissal never reshows onboarding");
        onboarding.destroy();
        onboarding = null;
        stage = "malformed-write";
        stateWriter.setText("not-valid\n");
    }

    function malformedStage() {
        stage = "malformed-state";
        createOnboarding();
    }

    function malformedStateStage() {
        require(onboarding.stateResolved && !onboarding.dismissed && onboarding.onboardingVisible,
                "malformed state is ignored without blocking startup");
        require(islandMutationCount === 0,
                "onboarding lifecycle remains outside island ownership");
        onboarding.destroy();
        onboarding = null;
        stage = "remove-state";
        fixtureCommand.command = ["rm", "-f", statePath];
        fixtureCommand.running = true;
    }

    function unwritableStateStage() {
        require(onboarding.stateResolved && onboarding.onboardingVisible,
                "unavailable state storage does not block first-launch UI");
        onboarding.closeAction.clicked();
        stage = "unwritable-dismissed";
        settleTimer.restart();
    }

    function unwritableDismissedStage() {
        require(onboarding.dismissed && !onboarding.onboardingVisible
                && islandMutationCount === 0,
                "unwritable dismissal state does not block or mutate the island");
        onboarding.destroy();
        console.log("onboarding tests passed");
        Qt.exit(0);
    }

    function runSettledStage() {
        if (onboarding === null || !onboarding.stateResolved) {
            settleTimer.restart();
            return;
        }
        switch (stage) {
        case "initial":
            initialStage();
            break;
        case "second-launch":
            secondLaunchStage();
            break;
        case "malformed-state":
            malformedStateStage();
            break;
        case "unwritable-state":
            unwritableStateStage();
            break;
        case "unwritable-dismissed":
            unwritableDismissedStage();
            break;
        default:
            fail("unexpected settled stage");
        }
    }


    Component {
        id: onboardingFactory

        OnboardingWindow {}
    }

    Connections {
        target: onboarding
        ignoreUnknownSignals: true
        function onControlCenterRequested() {
            test.settingsRequests += 1;
        }


        function onDismissalPersisted() {
            if (test.stage === "persisted") {
                test.persistedStage();
            }
        }
    }

    FileView {
        id: stateWriter

        path: test.statePath
        atomicWrites: true
        blockWrites: true
        printErrors: false
        onSaved: {
            if (test.stage === "malformed-write") {
                test.malformedStage();
            }
        }
        onSaveFailed: function (error) {
            test.fail("state fixture write failed");
        }
    }
    Process {
        id: fixtureCommand

        onExited: function (exitCode) {
            require(exitCode === 0, "state fixture command succeeds");
            if (stage === "remove-state") {
                stage = "make-state-directory";
                command = ["mkdir", statePath];
                running = true;
            } else if (stage === "make-state-directory") {
                stage = "unwritable-state";
                createOnboarding();
            }
        }
    }


    Timer {
        id: settleTimer

        interval: 30
        onTriggered: test.runSettledStage()
    }

    Timer {
        interval: 5000
        running: true
        onTriggered: test.fail("onboarding test timed out")
    }

    Component.onCompleted: createOnboarding()
}

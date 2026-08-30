(function() {
    "use strict";

    var stage = 0;
    var firstDesktop = null;
    var secondDesktop = null;
    var retiredDesktop = null;
    var replacementDesktop = null;
    var currentRename = "Nagi Current Renamed";
    var nonCurrentRename = "Nagi Non-current Renamed";
    var retiredRename = "Nagi Retired Renamed";
    var replacementName = "Nagi Replacement";
    var replacementRename = "Nagi Replacement Renamed";
    var timer = new QTimer();
    timer.singleShot = true;
    timer.interval = 180;

    function setAllScreens(desktop) {
        var screens = workspace.screens;
        for (var index = 0; index < screens.length; ++index) {
            workspace.setCurrentDesktopForScreen(desktop, screens[index]);
        }
    }

    function advance() {
        if (workspace.screens.length < 1) {
            timer.start();
            return;
        }
        if (firstDesktop === null) {
            if (workspace.desktops.length < 2) {
                workspace.createDesktop(workspace.desktops.length, "Nagi Consensus Test");
                timer.start();
                return;
            }
            firstDesktop = workspace.desktops[0];
            secondDesktop = workspace.desktops[1];
        }

        var first = firstDesktop;
        var second = secondDesktop;
        if (stage === 0) {
            setAllScreens(first);
            stage = 1;
            timer.start();
            return;
        }
        if (stage === 1) {
            if (workspace.screens.length > 1) {
                workspace.setCurrentDesktopForScreen(second, workspace.screens[workspace.screens.length - 1]);
            }
            stage = 2;
            timer.start();
            return;
        }
        if (stage === 2) {
            setAllScreens(first);
            stage = 3;
            timer.start();
            return;
        }
        if (stage === 3) {
            setAllScreens(second);
            stage = 4;
            timer.start();
            return;
        }
        if (stage === 4) {
            if (workspace.screens.length > 1) {
                workspace.slotSwitchToNextScreen();
            }
            stage = 5;
            timer.interval = 320;
            timer.start();
            return;
        }
        if (stage === 5) {
            workspace.moveDesktop(second, 0);
            stage = 6;
            timer.start();
            return;
        }
        if (stage === 6) {
            second.name = currentRename;
            stage = 7;
            timer.start();
            return;
        }
        if (stage === 7) {
            first.name = nonCurrentRename;
            stage = 8;
            timer.start();
            return;
        }
        if (stage === 8) {
            retiredDesktop = first;
            workspace.removeDesktop(retiredDesktop);
            retiredDesktop.name = retiredRename;
            stage = 9;
            timer.start();
            return;
        }
        if (stage === 9) {
            workspace.createDesktop(workspace.desktops.length, replacementName);
            replacementDesktop = workspace.desktops[workspace.desktops.length - 1];
            stage = 10;
            timer.start();
            return;
        }
        if (stage === 10) {
            replacementDesktop.name = replacementRename;
            stage = 11;
        }
    }

    timer.timeout.connect(advance);
    advance();
})();

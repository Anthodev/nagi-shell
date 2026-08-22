import Quickshell
import Quickshell.Services.SystemTray
import QtQuick
import "qml"

ShellRoot {
    id: test

    property var calls: []

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function recordCall(item, action, argument) {
        calls.push({
                       "name": item.title,
                       "action": action,
                       "argument": argument
                   });
    }

    function makeItem(overrides) {
        return itemFactory.createObject(test, overrides);
    }

    function setItems(items) {
        trayModel.values = items.slice();
        tray.processPendingChanges();
    }

    function itemByLabel(label) {
        for (let index = 0; index < tray.items.length; ++index) {
            if (tray.items[index].label === label) {
                return tray.items[index];
            }
        }
        return null;
    }

    Component {
        id: itemFactory

        QtObject {
            property string title: ""
            property string icon: ""
            property string tooltipTitle: ""
            property string tooltipDescription: ""
            property int status: Status.Passive
            property int category: Category.ApplicationStatus
            property bool hasMenu: false
            property bool onlyMenu: false
            property bool failActivation: false
            property bool failSecondary: false
            property bool failMenu: false

            function activate() {
                if (failActivation) {
                    throw new Error("controlled activation failure");
                }
                test.recordCall(this, "activate", null);
            }

            function secondaryActivate() {
                if (failSecondary) {
                    throw new Error("controlled secondary failure");
                }
                test.recordCall(this, "secondary", null);
            }

            function display(parentWindow, x, y) {
                if (failMenu) {
                    throw new Error("controlled menu failure");
                }
                test.recordCall(this, "menu", {
                                    "parent": parentWindow,
                                    "x": x,
                                    "y": y
                                });
            }
        }
    }

    QtObject {
        id: trayModel

        property var values: []
    }

    TrayAdapter {
        id: tray

        itemsModel: trayModel
    }

    function runLifecycleStage() {
        console.warn("tray: lifecycle and normalization stage");
        require(!tray.available && tray.itemCount === 0 && tray.trackedItemCount === 0,
                "an empty backend collapses tray presentation");

        const alpha = makeItem({
                                   "title": " Alpha\u0007  Item ",
                                   "icon": "image://icon/alpha",
                                   "tooltipDescription": " First\n service ",
                                   "status": Status.Active,
                                   "hasMenu": true
                               });
        const beta = makeItem({
                                  "title": "Beta",
                                  "icon": "image://icon/beta",
                                  "status": Status.Passive
                              });
        setItems([alpha, beta]);
        require(tray.available && tray.itemCount === 2 && tray.trackedItemCount === 2,
                "ready items appear as one live record each");

        const alphaSnapshot = itemByLabel("Alpha Item");
        require(alphaSnapshot !== null && alphaSnapshot.tooltip === "Alpha Item\nFirst service",
                "external text is normalized and bounded");
        require(alphaSnapshot.iconSource === "image://icon/alpha" && alphaSnapshot.status
                === "active" && alphaSnapshot.hasMenu,
                "icon identity, status, and menu support are normalized");
        const alphaToken = alphaSnapshot.token;

        alpha.tooltipTitle = "Attention";
        alpha.tooltipDescription = "Updated";
        alpha.icon = "image://icon/alpha-updated";
        alpha.status = Status.NeedsAttention;
        alpha.onlyMenu = true;
        tray.processPendingChanges();
        const updated = itemByLabel("Attention");
        require(updated !== null && updated.token === alphaToken,
                "property updates retain the connected generation token");
        require(updated.tooltip === "Attention\nUpdated" && updated.iconSource
                === "image://icon/alpha-updated" && updated.status === "needsAttention"
                && updated.onlyMenu,
                "live tooltip, icon, status, and behavior changes publish together");

        setItems([beta]);
        require(tray.itemCount === 1 && tray.trackedItemCount === 1 && itemByLabel("Attention")
                === null, "departed applications disappear and release their record");
        setItems([alpha, beta]);
        require(itemByLabel("Attention").token !== alphaToken,
                "a returning backend object receives a fresh lifecycle token");

        runActionStage(alpha, beta);
    }

    function runActionStage(alpha, beta) {
        console.warn("tray: activation and menu stage");
        calls = [];
        const alphaSnapshot = itemByLabel("Attention");
        const betaSnapshot = itemByLabel("Beta");

        require(tray.activate(alphaSnapshot.token) === "rejected",
                "menu-only items reject unsupported primary activation");
        require(tray.openMenu(alphaSnapshot.token, test, -99999999999, 99999999999) === "dispatched",
                "supported native menus dispatch through the adapter");
        require(calls.length === 1 && calls[0].action === "menu" && calls[0].argument.x ===
                -2147483648 && calls[0].argument.y === 2147483647,
                "menu dispatch keeps the real parent and clamps qint32 coordinates");

        require(tray.activate(betaSnapshot.token) === "dispatched" && tray.secondaryActivate(
                    betaSnapshot.token) === "dispatched",
                "primary and secondary activation reach the real item methods");
        require(calls.length === 3 && calls[1].action === "activate" && calls[2].action
                === "secondary", "activation order is preserved");
        require(tray.openMenu(betaSnapshot.token, test, 0, 0) === "rejected",
                "items without menus never enter the platform menu path");
        require(tray.activate(-1) === "rejected" && tray.openMenu(betaSnapshot.token, null, 0, 0)
                === "rejected", "stale tokens and missing parent windows reject locally");

        runFailureStage(alpha, beta);
    }

    function runFailureStage(alpha, beta) {
        console.warn("tray: isolated failure stage");
        const failing = makeItem({
                                     "title": "Failing",
                                     "icon": "x".repeat(tray.maximumIconSourceCharacters + 1),
                                     "status": Status.Active,
                                     "hasMenu": true,
                                     "failActivation": true,
                                     "failSecondary": true,
                                     "failMenu": true
                                 });
        setItems([alpha, failing, beta]);
        const snapshot = itemByLabel("Failing");
        require(snapshot !== null && snapshot.iconSource === "" && tray.itemCount === 3,
                "one malformed icon falls back without hiding healthy items");
        require(tray.activate(snapshot.token) === "rejected" && tray.secondaryActivate(
                    snapshot.token) === "rejected" && tray.openMenu(snapshot.token, test, 0, 0)
                === "rejected", "one throwing item cannot escape or block the adapter");
        require(tray.activate(itemByLabel("Beta").token) === "dispatched",
                "healthy items remain actionable after a peer failure");

        setItems([]);
        require(!tray.available && tray.itemCount === 0 && tray.trackedItemCount === 0,
                "backend exit clears every live snapshot and watcher");
        alpha.destroy();
        beta.destroy();
        failing.destroy();
        console.warn("tray adapter tests passed");
        Qt.exit(0);
    }

    Component.onCompleted: Qt.callLater(test.runLifecycleStage)
}

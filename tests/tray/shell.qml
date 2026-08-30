import Quickshell
import Quickshell.Services.SystemTray
import QtQuick
import "qml"

ShellRoot {
    id: test

    property var calls: []
    property real cancelledEpoch: 0
    property int menuActionCount: 0
    property int lastMenuActionToken: 0

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
    function trayCell(index) {
        const list = findObject(trayView, "trayItemList");
        require(list !== null, "tray GridView exists");
        list.forceLayout();
        return list.itemAtIndex(index);
    }

    function trayButton(index) {
        return findObject(trayCell(index), "trayItemButton");
    }
    function requireTrayLayout(count, columns, rows, scrollVisible) {
        require(trayView.itemCount === count && trayView.gridColumns === columns
                && trayView.gridRows === rows, "tray grid geometry was wrong for " + count
                + " items");
        const list = findObject(trayView, "trayItemList");
        require(list !== null, "tray GridView exists for " + count + " items");
        list.forceLayout();
        require(trayView.trayViewportWidth === 480 && trayView.trayViewportHeight === 112
                && trayView.implicitWidth === 512 && trayView.implicitHeight === 188,
                "Tray keeps its 480 by 112 viewport and 512 by 188 outer envelope");
        require(trayView.gridScrollVisible === scrollVisible
                && list.interactive === scrollVisible,
                "tray scrollbar threshold was wrong for " + count + " items");
        if (count > 0) {
            require(Math.abs(list.contentHeight - rows * trayView.gridCellExtent) < 0.5,
                    "tray content height includes every row for " + count + " items");
            let checkedDelegates = 0;
            for (let index = 0; index < count; ++index) {
                const cell = list.itemAtIndex(index);
                if (cell === null) {
                    continue;
                }
                const button = findObject(cell, "trayItemButton");
                const expectedX = trayView.gridOffsetX + index % columns
                                  * trayView.gridCellExtent;
                const expectedY = trayView.gridOffsetY + Math.floor(index / columns)
                                  * trayView.gridCellExtent;
                require(button !== null
                        && Math.abs(list.x + cell.x + button.x - expectedX) < 0.5
                        && Math.abs(list.y + cell.y + button.y - expectedY) < 0.5,
                        "tray delegate position was wrong at index " + index + " for " + count
                        + " items");
                checkedDelegates += 1;
            }
            require(checkedDelegates >= Math.min(count, trayView.maximumVisibleItems),
                    "tray instantiates and positions every visible delegate for " + count
                    + " items");
        } else {
            require(trayView.gridOffsetX > 0 && trayView.gridOffsetY > 0,
                    "empty and sparse tray populations stay centered inside the stable envelope");
        }
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
        onMenuActionTriggered: token => {
            test.menuActionCount += 1;
            test.lastMenuActionToken = token;
        }
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
        const beeper = makeItem({
                                    "title": "Beeper",
                                    "icon": "image://icon/beeper",
                                    "status": Status.Active
                                });
        setItems([beeper, alpha, beta]);
        require(Object.isFrozen(quickControls.statusItems) && quickControls.statusItems.map(item
                                                                                            => item.label).join(
                    ",") === "Attention,Beeper",
                "Dashboard projection prioritizes attention before active adapter snapshots and excludes passive snapshots");
        const projected = quickControls.projectTrayItems([
                                                             {
                                                                 "token": 20,
                                                                 "status": "active"
                                                             },
                                                             {
                                                                 "token": 10,
                                                                 "status": "needsAttention"
                                                             },
                                                             {
                                                                 "token": 30,
                                                                 "status": "passive"
                                                             },
                                                             {
                                                                 "token": 11,
                                                                 "status": "needsAttention"
                                                             },
                                                             {
                                                                 "token": 10,
                                                                 "status": "active"
                                                             },
                                                             {
                                                                 "token": 21,
                                                                 "status": "active"
                                                             },
                                                             {
                                                                 "token": 22,
                                                                 "status": "active"
                                                             }
                                                         ]);
        require(Object.isFrozen(projected) && projected.map(item => item.token).join(",") === "10,11,20,21",
                "Dashboard projection is stable, deduplicated by lifecycle token, and capped at four");
        calls = [];
        require(quickControls.activateStatusItem(itemByLabel("Beeper").token) === "dispatched"
                && calls.length === 1 && calls[0].name === "Beeper" && calls[0].action
                === "activate", "Dashboard projection forwards only the selected activation token");
        setItems([alpha, beta]);
        beeper.destroy();

        setItems([beta]);
        require(tray.itemCount === 1 && tray.trackedItemCount === 1 && itemByLabel("Attention")
                === null, "departed applications disappear and release their record");
        setItems([alpha, beta]);
        require(itemByLabel("Attention").token !== alphaToken,
                "a returning backend object receives a fresh lifecycle token");

        Qt.callLater(function () {
            test.runViewStage(alpha, beta);
        });
    }

    function runViewStage(alpha, beta) {
        console.warn("tray: shared subview frame stage");
        const title = findObject(trayView, "subviewTitle");
        const back = findObject(trayView, "subviewBackButton");
        require(trayView.itemCount === 2 && title !== null && title.text === "System tray",
                "dedicated tray content mounts inside the shared titled frame");
        require(trayView.gridColumns === 2 && trayView.gridRows === 1,
                "tray items render as a compact bounded icon grid");

        setItems([]);
        requireTrayLayout(0, 1, 1, false);
        setItems([alpha]);
        requireTrayLayout(1, 1, 1, false);
        const layoutItems = [alpha, beta];
        for (let index = 2; index < trayView.maximumVisibleItems + 1; ++index) {
            layoutItems.push(makeItem({
                                          "title": "Layout " + index,
                                          "icon": "image://icon/layout-" + index,
                                          "status": Status.Active
                                      }));
        }
        setItems(layoutItems.slice(0, 2));
        requireTrayLayout(2, 2, 1, false);
        setItems(layoutItems.slice(0, 5));
        requireTrayLayout(5, 5, 1, false);
        setItems(layoutItems.slice(0, 6));
        requireTrayLayout(6, 6, 1, false);
        setItems(layoutItems.slice(0, 15));
        requireTrayLayout(15, 11, 2, false);
        setItems(layoutItems.slice(0, 33));
        requireTrayLayout(33, 11, 3, false);
        setItems(layoutItems);
        requireTrayLayout(34, 11, 4, true);
        setItems([alpha, beta]);
        const applicationIcon = findObject(trayCell(0), "trayApplicationIcon");
        require(applicationIcon !== null && applicationIcon.meaning === "trayApplication"
                && applicationIcon.applicationSource === itemByLabel("Attention").iconSource
                && applicationIcon.applicationName === "Attention" && applicationIcon.resolvedKind
                === "application" && !applicationIcon.tinted,
                "tray application identity routes through the untinted semantic icon path");
        const attentionDot = findObject(trayCell(0), "trayAttentionDot");
        require(attentionDot !== null && attentionDot.visible,
                "attention tray items retain their independent status dot");
        for (let index = 2; index < layoutItems.length; ++index) {
            layoutItems[index].destroy();
        }

        trayView.focusInitialControl();
        require(trayWindow.activeFocusItem !== null && trayWindow.activeFocusItem.objectName
                === "trayItemButton", "tray frame enters the first normalized item");
        const focusedTrayButton = trayButton(0);
        const trayFocusRing = findObject(focusedTrayButton, "islandFocusRing");
        require(trayFocusRing !== null && trayFocusRing.visible
                && focusedTrayButton.background.radius === Theme.radius.md
                && trayFocusRing.controlRadius === focusedTrayButton.background.radius
                && trayFocusRing.radius === focusedTrayButton.background.radius
                + Theme.size.focusRingGap,
                "tray item keyboard focus ring follows its medium owner curve");
        require(back !== null && back.Accessible.name === "Back",
                "tray frame exposes the shared iconographic Back action");
        back.clicked();
        require(cancelledEpoch === 42, "tray Back emits the current owner epoch");
        runActionStage(alpha, beta);
    }

    function runActionStage(alpha, beta) {
        console.warn("tray: activation and menu stage");
        calls = [];
        const alphaSnapshot = itemByLabel("Attention");
        const betaSnapshot = itemByLabel("Beta");

        require(tray.activate(alphaSnapshot.token) === "rejected",
                "menu-only items reject unsupported primary activation");
        require(tray.openMenu(alphaSnapshot.token, test, -99999999999, 99999999999)
                === "dispatched" && tray.menuTrackingActive
                && tray.activeMenuToken === alphaSnapshot.token,
                "supported native menu dispatch starts one bounded selection observer");
        require(calls.length === 1 && calls[0].action === "menu" && calls[0].argument.x
                === -2147483648 && calls[0].argument.y === 2147483647,
                "menu dispatch keeps the real parent and clamps qint32 coordinates");
        require(tray.notifyMenuAction(alphaSnapshot.token) && !tray.menuTrackingActive
                && menuActionCount === 1 && lastMenuActionToken === alphaSnapshot.token,
                "selecting a menu entry ends observation and emits one external action");

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
        const fallbackIcon = findObject(trayCell(1), "trayApplicationIcon");
        const fallbackLetter = findObject(trayCell(1), "trayApplicationFallbackLetter");
        require(fallbackIcon !== null && fallbackIcon.showingFallback && !fallbackIcon.visible
                && fallbackLetter !== null && fallbackLetter.visible && fallbackLetter.text === "F",
                "invalid tray artwork uses the centralized fallback lifecycle and app letter");
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
        runSoakStage();
    }

    function runSoakStage() {
        console.warn("tray: 20-cycle lifecycle and hidden-menu soak");
        calls = [];
        const initialMenuActions = menuActionCount;
        require(!tray.available && tray.itemCount === 0 && tray.trackedItemCount === 0
                && !tray.menuTrackingActive && trayView.active,
                "tray soak starts from the exact empty backend state");

        for (let cycle = 0; cycle < 20; ++cycle) {
            const item = makeItem({
                                      "title": "Cycle " + cycle,
                                      "icon": "image://icon/cycle-" + cycle,
                                      "status": Status.Active,
                                      "hasMenu": true
                                  });
            setItems([item]);
            require(tray.available && tray.itemCount === 1 && tray.trackedItemCount === 1
                    && tray.items.length === 1
                    && tray.maximumMenuWatcherEntries === 256,
                    "cycle " + cycle + " owns one bounded record and watcher set");
            const token = tray.items[0].token;
            require(tray.openMenu(token, test, cycle, cycle) === "dispatched"
                    && tray.menuTrackingActive && tray.activeMenuToken === token
                    && calls.length === 1,
                    "cycle " + cycle + " starts one native menu observer");

            const callsBeforeClose = calls.length;
            trayView.active = false;
            tray.cancelMenuTracking();
            require(!tray.menuTrackingActive && tray.activeMenuToken === 0
                    && calls.length === callsBeforeClose && !tray.notifyMenuAction(token),
                    "cycle " + cycle + " hidden close cancels menu work without backend mutation");

            item.failActivation = true;
            require(tray.activate(token) === "rejected" && calls.length === callsBeforeClose,
                    "cycle " + cycle + " activation denial leaves backend state unchanged");
            item.icon = "x".repeat(tray.maximumIconSourceCharacters + 1);
            item.tooltipDescription = "\u0001\u0002";
            tray.processPendingChanges();
            require(tray.items.length === 1 && tray.items[0].iconSource === ""
                    && tray.items[0].tooltip === "Cycle " + cycle,
                    "cycle " + cycle + " malformed artwork and text stay bounded");

            setItems([]);
            item.title = "Stale " + cycle;
            tray.processPendingChanges();
            require(!tray.available && tray.itemCount === 0 && tray.trackedItemCount === 0
                    && !tray.menuTrackingActive,
                    "cycle " + cycle + " owner loss clears records, watchers, and menu state");

            const replacement = makeItem({
                                             "title": "Cycle " + cycle,
                                             "icon": "image://icon/replacement-" + cycle,
                                             "status": Status.Active,
                                             "hasMenu": true,
                                             "failMenu": true
                                         });
            setItems([replacement]);
            const replacementToken = tray.items[0].token;
            require(replacementToken !== token && tray.itemCount === 1
                    && tray.trackedItemCount === 1,
                    "cycle " + cycle + " replacement receives one fresh lifecycle token");
            require(tray.openMenu(replacementToken, test, 0, 0) === "rejected"
                    && !tray.menuTrackingActive && calls.length === callsBeforeClose,
                    "cycle " + cycle + " menu failure creates no watcher or backend record");

            setItems([]);
            item.destroy();
            replacement.destroy();
            trayView.active = true;
            calls = [];
            require(!tray.available && tray.itemCount === 0 && tray.trackedItemCount === 0
                    && !tray.menuTrackingActive && tray.activeMenuToken === 0
                    && menuActionCount === initialMenuActions && trayView.active,
                    "cycle " + cycle + " returns to exact model, watcher, menu, and view counts");
        }

        require(calls.length === 0 && !tray.available && tray.itemCount === 0
                && tray.trackedItemCount === 0 && !tray.menuTrackingActive
                && tray.activeMenuToken === 0 && menuActionCount === initialMenuActions,
                "tray soak finishes at its pre-cycle clean state");
        console.warn("tray adapter tests passed");
        Qt.exit(0);
    }

    QtObject {
        id: connectivity

        property bool wifiAvailable: true
        property bool wifiEnabled: true
        property bool wifiPending: false
        property string wifiFailure: "none"
        property bool bluetoothAvailable: true
        property bool bluetoothEnabled: true
        property bool bluetoothPending: false
        property string bluetoothFailure: "none"
    }

    QtObject {
        id: applications

        property var pinnedApplications: []
        property bool launchPending: false
    }

    Window {
        id: trayWindow

        visible: true
        width: Theme.spacing.xxl * 10
        height: Theme.spacing.xxl * 5

        TrayView {
            id: trayView

            anchors.fill: parent
            active: true
            adapter: tray
            ownerEpoch: 42
            reducedMotion: true
            menuParentWindow: trayWindow
            onCancelled: epoch => test.cancelledEpoch = epoch
        }
        DashboardStatusProjection {
            id: quickControls

            visible: false
            tray: tray
            menuParentWindow: trayWindow
        }
    }

    Component.onCompleted: Qt.callLater(test.runLifecycleStage)
}

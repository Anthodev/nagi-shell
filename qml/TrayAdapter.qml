pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Services.SystemTray
import QtQuick

// Stable SystemTray boundary for presentation. Views receive immutable,
// bounded snapshots and opaque generation tokens; backend item objects and
// platform menu handles stay private to this adapter.
Scope {
    id: root

    // Verification seam. Production observes SystemTray.items directly.
    property var itemsModel: null

    readonly property int maximumTextCharacters: 256
    readonly property int maximumIdentityCharacters: 128
    readonly property int maximumIconSourceCharacters: 4096

    readonly property var items: engine.snapshots
    readonly property int itemCount: items.length
    readonly property bool available: itemCount > 0
    readonly property int trackedItemCount: engine.records.length

    function activate(token) {
        return engine.dispatch(token, "activate", null, 0, 0);
    }

    function secondaryActivate(token) {
        return engine.dispatch(token, "secondary", null, 0, 0);
    }

    function openMenu(token, parentWindow, relativeX, relativeY) {
        return engine.dispatch(token, "menu", parentWindow, relativeX, relativeY);
    }

    // Flushes coalesced lifecycle/property updates for deterministic tests.
    function processPendingChanges() {
        engine.flushScheduled();
    }

    Component.onCompleted: engine.rebuild()
    Component.onDestruction: engine.hardReset()
    onItemsModelChanged: engine.scheduleRebuild()

    Connections {
        target: engine.currentModel
        ignoreUnknownSignals: true

        function onValuesChanged() {
            engine.scheduleRebuild();
        }
    }

    Component {
        id: itemWatcher

        Connections {
            ignoreUnknownSignals: true

            function onIdChanged() {
                engine.scheduleRebuild();
            }

            function onTitleChanged() {
                engine.scheduleRebuild();
            }

            function onIconChanged() {
                engine.scheduleRebuild();
            }

            function onStatusChanged() {
                engine.scheduleRebuild();
            }

            function onCategoryChanged() {
                engine.scheduleRebuild();
            }

            function onTooltipTitleChanged() {
                engine.scheduleRebuild();
            }

            function onTooltipDescriptionChanged() {
                engine.scheduleRebuild();
            }

            function onHasMenuChanged() {
                engine.scheduleRebuild();
            }

            function onOnlyMenuChanged() {
                engine.scheduleRebuild();
            }
        }
    }

    QtObject {
        id: engine

        property var records: []
        property var snapshots: []
        property int nextToken: 1
        property bool scheduled: false
        readonly property var currentModel: root.itemsModel === null ? SystemTray.items :
                                                                       root.itemsModel

        function safeRead(object, name, fallback) {
            if (object === null || object === undefined) {
                return fallback;
            }

            try {
                const value = object[name];
                return value === undefined ? fallback : value;
            } catch (error) {
                return fallback;
            }
        }

        function normalizeText(value, limit) {
            if (typeof value !== "string") {
                return "";
            }

            const cleaned = value.replace(/[\u0000-\u001f\u007f-\u009f]/g, " ").replace(/\s+/g,
                                                                                        " ").trim();
            return cleaned.length > limit ? cleaned.slice(0, limit) : cleaned;
        }

        function normalizeIconSource(value) {
            if (typeof value !== "string" || value.length === 0 || value.length > root.maximumIconSourceCharacters
                    || /[\u0000-\u001f\u007f-\u009f]/.test(value)) {
                return "";
            }
            return value;
        }

        function statusName(value) {
            if (value === Status.NeedsAttention) {
                return "needsAttention";
            }
            if (value === Status.Active) {
                return "active";
            }
            return "passive";
        }

        function allocateToken() {
            const token = nextToken;
            nextToken = nextToken >= 2147483647 ? 1 : nextToken + 1;
            return token;
        }

        function findRecord(item) {
            for (let index = 0; index < records.length; ++index) {
                if (records[index].item === item) {
                    return records[index];
                }
            }
            return null;
        }

        function findToken(token) {
            if (!Number.isInteger(token) || token <= 0) {
                return null;
            }
            for (let index = 0; index < records.length; ++index) {
                if (records[index].token === token) {
                    return records[index];
                }
            }
            return null;
        }

        function adopt(item) {
            const record = {
                "item": item,
                "token": allocateToken(),
                "watcher": null
            };
            record.watcher = itemWatcher.createObject(root, {
                                                          "target": item
                                                      });
            return record;
        }

        function disposeRecord(record) {
            if (record.watcher !== null) {
                try {
                    record.watcher.destroy();
                } catch (error) {
                    // The watcher may already have died with its backend item.
                }
                record.watcher = null;
            }
            record.item = null;
        }

        function snapshot(record) {
            const item = record.item;
            let label = normalizeText(safeRead(item, "tooltipTitle", ""),
                                      root.maximumTextCharacters);
            if (label === "") {
                label = normalizeText(safeRead(item, "title", ""), root.maximumTextCharacters);
            }
            if (label === "") {
                label = normalizeText(safeRead(item, "id", ""), root.maximumIdentityCharacters);
            }
            if (label === "") {
                label = "Tray item";
            }

            const description = normalizeText(safeRead(item, "tooltipDescription", ""),
                                              root.maximumTextCharacters);
            return {
                "token": record.token,
                "label": label,
                "tooltip": description === "" ? label : label + "\n" + description,
                "iconSource": normalizeIconSource(safeRead(item, "icon", "")),
                "status": statusName(safeRead(item, "status", Status.Passive)),
                "hasMenu": safeRead(item, "hasMenu", false) === true,
                "onlyMenu": safeRead(item, "onlyMenu", false) === true
            };
        }

        function modelValues() {
            const values = safeRead(currentModel, "values", null);
            if (values === null || typeof values !== "object" || typeof values.length
                    !== "number") {

                return [];
            }
            return values;
        }

        function scheduleRebuild() {
            if (scheduled) {
                return;
            }
            scheduled = true;
            Qt.callLater(engine.rebuild);
        }

        function flushScheduled() {
            if (scheduled) {
                rebuild();
            }
        }

        function rebuild() {
            scheduled = false;
            const values = modelValues();
            const nextRecords = [];

            for (let valueIndex = 0; valueIndex < values.length; ++valueIndex) {
                const item = values[valueIndex];
                if (item === null || item === undefined) {
                    continue;
                }
                const existing = findRecord(item);
                nextRecords.push(existing === null ? adopt(item) : existing);
            }

            for (let recordIndex = 0; recordIndex < records.length; ++recordIndex) {
                if (nextRecords.indexOf(records[recordIndex]) === -1) {
                    disposeRecord(records[recordIndex]);
                }
            }

            records = nextRecords;
            const nextSnapshots = [];
            for (let index = 0; index < records.length; ++index) {
                nextSnapshots.push(snapshot(records[index]));
            }
            snapshots = nextSnapshots;
        }

        function menuCoordinate(value) {
            return Math.max(-2147483648, Math.min(2147483647, Math.round(value)));
        }

        function dispatch(token, action, parentWindow, relativeX, relativeY) {
            const record = findToken(token);
            if (record === null || record.item === null) {
                return "rejected";
            }

            try {
                if (action === "activate") {
                    if (safeRead(record.item, "onlyMenu", false) === true) {
                        return "rejected";
                    }
                    record.item.activate();
                } else if (action === "secondary") {
                    record.item.secondaryActivate();
                } else if (action === "menu") {
                    if (parentWindow === null || parentWindow === undefined || safeRead(record.item,
                                                                                        "hasMenu",
                                                                                        false)
                            !== true || typeof relativeX !== "number" || !Number.isFinite(
                                relativeX) || typeof relativeY !== "number" || !Number.isFinite(
                                relativeY)) {
                        return "rejected";
                    }
                    record.item.display(parentWindow, menuCoordinate(relativeX), menuCoordinate(
                                            relativeY));
                } else {
                    return "rejected";
                }
            } catch (error) {
                return "rejected";
            }
            return "dispatched";
        }

        function hardReset() {
            scheduled = false;
            for (let index = 0; index < records.length; ++index) {
                disposeRecord(records[index]);
            }
            records = [];
            snapshots = [];
        }
    }
}

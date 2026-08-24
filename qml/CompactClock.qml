import Quickshell
import QtQuick

// Minute precision is the visible granularity of both clock formats, so this
// clock updates only when the minute changes.
SystemClock {
    id: clock
    property string format: "24h"
    property string dateFormat: "dddd, d MMMM"
    property bool showIdleDate: false

    precision: SystemClock.Minutes
    function isoWeek(date) {
        const thursday = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
        const day = thursday.getUTCDay() || 7;
        thursday.setUTCDate(thursday.getUTCDate() + 4 - day);
        const yearStart = new Date(Date.UTC(thursday.getUTCFullYear(), 0, 1));
        return Math.ceil((((thursday - yearStart) / 86400000) + 1) / 7);
    }

    readonly property string text: format === "12h" ? Qt.formatDateTime(clock.date, "h:mm AP") :
                                                      Qt.formatDateTime(clock.date, "HH:mm")
    readonly property string dateText: Qt.formatDateTime(clock.date, dateFormat)
    readonly property string weekText: "Week " + isoWeek(clock.date)
}

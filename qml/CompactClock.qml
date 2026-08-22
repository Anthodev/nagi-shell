import Quickshell
import QtQuick

// Compact 24-hour idle clock state. Minute precision is the visible
// granularity of the idle island, so this clock updates only when the minute
// changes; no higher-frequency timer or animation ever runs.
SystemClock {
    id: clock

    precision: SystemClock.Minutes
    function isoWeek(date) {
        const thursday = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
        const day = thursday.getUTCDay() || 7;
        thursday.setUTCDate(thursday.getUTCDate() + 4 - day);
        const yearStart = new Date(Date.UTC(thursday.getUTCFullYear(), 0, 1));
        return Math.ceil((((thursday - yearStart) / 86400000) + 1) / 7);
    }

    readonly property string text: Qt.formatDateTime(clock.date, "HH:mm")
    readonly property string dateText: Qt.formatDateTime(clock.date, "dddd, d MMMM")
    readonly property string weekText: "Week " + isoWeek(clock.date)
}

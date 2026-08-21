import Quickshell
import QtQuick

// Compact 24-hour idle clock state. Minute precision is the visible
// granularity of the idle island, so this clock updates only when the minute
// changes; no higher-frequency timer or animation ever runs.
SystemClock {
    id: clock

    precision: SystemClock.Minutes

    readonly property string text: Qt.formatDateTime(clock.date, "HH:mm")
}

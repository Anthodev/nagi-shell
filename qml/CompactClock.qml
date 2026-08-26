import Quickshell
import QtQuick

// One process-wide clock owns every visible projection. Minute precision remains
// the default; second precision is enabled only while a surface needs it.
SystemClock {
    id: clock
    property string format: "24h"
    property bool showSeconds: false
    property string dateFormat: "dddd, d MMMM"
    property bool showIdleDate: false
    property bool scheduleActive: true

    enabled: scheduleActive
    precision: showSeconds && scheduleActive ? SystemClock.Seconds : SystemClock.Minutes

    readonly property bool usesTwelveHours: format === "12h" || (format === "auto" && Qt.locale(
                                                                     ).timeFormat(
                                                                     Locale.ShortFormat).toUpperCase(
                                                                     ).indexOf("AP") !== -1)
    readonly property string text: Qt.formatDateTime(clock.date, usesTwelveHours ? showSeconds
                                                                                   ? "h:mm:ss AP" :
                                                                                     "h:mm AP" :
                                                                                     showSeconds
                                                                                     ? "HH:mm:ss" :
                                                                                       "HH:mm")
    readonly property string dateText: Qt.formatDateTime(clock.date, dateFormat)
}

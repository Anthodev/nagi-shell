#pragma once

#include <QJsonObject>
#include <QJsonValue>

#include <array>

struct ShortcutActionSpec {
    const char *id;
    const char *name;
    const char *activation;
    bool launcherDefault;
};

inline constexpr std::array<ShortcutActionSpec, 7> kShortcutActionSpecs {{
    {"open-dashboard", "Open Dashboard", "openDashboard", false},
    {"open-launcher", "Open Launcher", "openLauncher", true},
    {"open-system-tray", "Open System Tray", "openTray", false},
    {"open-notification-history", "Open Notification History", "openHistory", false},
    {"open-audio-controls", "Open Audio Controls", "openAudio", false},
    {"open-session-controls", "Open Session Controls", "openSession", false},
    {"open-system-settings", "Open System Settings", "openSystemSettings", false},
}};

using ShortcutValues = std::array<QJsonValue, kShortcutActionSpecs.size()>;

inline QJsonObject shortcutStateMessage(bool available, const ShortcutValues &activeShortcuts,
                                        bool preferredConflict, const QString &preferredShortcut)
{
    QJsonObject actions;
    for (qsizetype index = 0; index < std::ssize(kShortcutActionSpecs); ++index) {
        const ShortcutActionSpec &spec = kShortcutActionSpecs.at(index);
        actions.insert(
            QString::fromLatin1(spec.activation),
            QJsonObject {
                {QStringLiteral("activeShortcut"),
                 available ? activeShortcuts.at(index) : QJsonValue::Null},
                {QStringLiteral("preferredShortcut"),
                 spec.launcherDefault ? QJsonValue(preferredShortcut) : QJsonValue::Null},
                {QStringLiteral("preferredConflict"),
                 available && spec.launcherDefault && preferredConflict},
            });
    }

    return QJsonObject {
        {QStringLiteral("type"), QStringLiteral("state")},
        {QStringLiteral("available"), available},
        {QStringLiteral("actions"), actions},
    };
}

#pragma once

#include <QByteArray>
#include <QString>

namespace easyeffects_status {

enum class PresetState {
    None,
    LastLoaded,
    Unavailable,
    Invalid,
    Timeout,
};

struct PresetResult {
    PresetState state = PresetState::Unavailable;
    QString name;
};

[[nodiscard]] bool isValidPresetName(const QString &name);
[[nodiscard]] PresetResult parsePresetResponse(const QByteArray &response);
[[nodiscard]] const char *presetStateName(PresetState state);

} // namespace easyeffects_status

#pragma once

#include <QByteArray>
#include <QString>
#include <cstdint>
#include <optional>

namespace nagi::audio {

enum class Operation {
    Track,
    Untrack,
    SetVolume,
    SetMute,
    Shutdown,
};

enum class Role {
    Output,
    Input,
};

struct Command {
    Operation operation = Operation::Shutdown;
    Role role = Role::Output;
    std::uint32_t nodeId = 0;
    std::uint32_t generation = 0;
    std::uint32_t requestId = 0;
    double volume = 0.0;
    bool muted = false;
    bool final = false;
};

constexpr qsizetype MaximumCommandBytes = 4096;

std::optional<Command> parseCommand(const QByteArray &line, QString *error = nullptr);
QString roleName(Role role);
QString operationName(Operation operation);

} // namespace nagi::audio

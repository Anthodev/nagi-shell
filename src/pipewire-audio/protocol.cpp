#include "protocol.h"

#include <cmath>
#include <limits>

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QJsonValue>
#include <QSet>

namespace nagi::audio {
namespace {

void setError(QString *error, const QString &message)
{
    if (error != nullptr) {
        *error = message;
    }
}

std::optional<Role> parseRole(const QJsonValue &value)
{
    if (!value.isString()) {
        return std::nullopt;
    }
    if (value.toString() == QStringLiteral("output")) {
        return Role::Output;
    }
    if (value.toString() == QStringLiteral("input")) {
        return Role::Input;
    }
    return std::nullopt;
}

std::optional<std::uint32_t> parseUnsigned(
    const QJsonValue &value,
    bool allowZero = false)
{
    if (!value.isDouble()) {
        return std::nullopt;
    }
    const double number = value.toDouble();
    if (!std::isfinite(number) || std::floor(number) != number || number < 0
        || (!allowZero && number == 0)
        || number > static_cast<double>(std::numeric_limits<std::int32_t>::max())) {
        return std::nullopt;
    }
    return static_cast<std::uint32_t>(number);
}

bool hasExactKeys(const QJsonObject &object, const QSet<QString> &expected)
{
    if (object.size() != expected.size()) {
        return false;
    }
    for (auto iterator = object.constBegin(); iterator != object.constEnd(); ++iterator) {
        if (!expected.contains(iterator.key())) {
            return false;
        }
    }
    return true;
}

} // namespace

std::optional<Command> parseCommand(const QByteArray &line, QString *error)
{
    if (line.isEmpty() || line.size() > MaximumCommandBytes) {
        setError(error, QStringLiteral("command length is invalid"));
        return std::nullopt;
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(line, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        setError(error, QStringLiteral("command is not a JSON object"));
        return std::nullopt;
    }

    const QJsonObject object = document.object();
    const QJsonValue operationValue = object.value(QStringLiteral("op"));
    if (!operationValue.isString()) {
        setError(error, QStringLiteral("command operation is invalid"));
        return std::nullopt;
    }

    const QString operation = operationValue.toString();
    if (operation == QStringLiteral("shutdown")) {
        if (!hasExactKeys(object, {QStringLiteral("op")})) {
            setError(error, QStringLiteral("shutdown command schema is invalid"));
            return std::nullopt;
        }
        return Command{.operation = Operation::Shutdown};
    }

    const auto role = parseRole(object.value(QStringLiteral("role")));
    const auto generation = parseUnsigned(object.value(QStringLiteral("generation")));
    if (!role || !generation) {
        setError(error, QStringLiteral("command role or generation is invalid"));
        return std::nullopt;
    }

    if (operation == QStringLiteral("untrack")) {
        if (!hasExactKeys(
                object,
                {QStringLiteral("op"), QStringLiteral("role"), QStringLiteral("generation")})) {
            setError(error, QStringLiteral("untrack command schema is invalid"));
            return std::nullopt;
        }
        return Command{
            .operation = Operation::Untrack,
            .role = *role,
            .generation = *generation,
        };
    }

    const auto nodeId = parseUnsigned(object.value(QStringLiteral("nodeId")), true);
    if (!nodeId) {
        setError(error, QStringLiteral("command node ID is invalid"));
        return std::nullopt;
    }

    if (operation == QStringLiteral("track")) {
        if (!hasExactKeys(
                object,
                {QStringLiteral("op"),
                 QStringLiteral("role"),
                 QStringLiteral("nodeId"),
                 QStringLiteral("generation")})) {
            setError(error, QStringLiteral("track command schema is invalid"));
            return std::nullopt;
        }
        return Command{
            .operation = Operation::Track,
            .role = *role,
            .nodeId = *nodeId,
            .generation = *generation,
        };
    }

    const auto requestId = parseUnsigned(object.value(QStringLiteral("requestId")));
    if (!requestId) {
        setError(error, QStringLiteral("request ID is invalid"));
        return std::nullopt;
    }

    if (operation == QStringLiteral("setVolume")) {
        const QJsonValue volumeValue = object.value(QStringLiteral("value"));
        const QJsonValue finalValue = object.value(QStringLiteral("final"));
        if (!hasExactKeys(
                object,
                {QStringLiteral("op"),
                 QStringLiteral("role"),
                 QStringLiteral("nodeId"),
                 QStringLiteral("generation"),
                 QStringLiteral("requestId"),
                 QStringLiteral("value"),
                 QStringLiteral("final")})
            || !volumeValue.isDouble() || !finalValue.isBool()) {
            setError(error, QStringLiteral("volume command schema is invalid"));
            return std::nullopt;
        }
        const double volume = volumeValue.toDouble();
        if (!std::isfinite(volume) || volume < 0.0 || volume > 1.0) {
            setError(error, QStringLiteral("volume command value is invalid"));
            return std::nullopt;
        }
        return Command{
            .operation = Operation::SetVolume,
            .role = *role,
            .nodeId = *nodeId,
            .generation = *generation,
            .requestId = *requestId,
            .volume = volume,
            .final = finalValue.toBool(),
        };
    }

    if (operation == QStringLiteral("setMute")) {
        const QJsonValue mutedValue = object.value(QStringLiteral("muted"));
        if (!hasExactKeys(
                object,
                {QStringLiteral("op"),
                 QStringLiteral("role"),
                 QStringLiteral("nodeId"),
                 QStringLiteral("generation"),
                 QStringLiteral("requestId"),
                 QStringLiteral("muted")})
            || !mutedValue.isBool()) {
            setError(error, QStringLiteral("mute command schema is invalid"));
            return std::nullopt;
        }
        return Command{
            .operation = Operation::SetMute,
            .role = *role,
            .nodeId = *nodeId,
            .generation = *generation,
            .requestId = *requestId,
            .muted = mutedValue.toBool(),
        };
    }

    setError(error, QStringLiteral("command operation is unsupported"));
    return std::nullopt;
}

QString roleName(Role role)
{
    return role == Role::Output ? QStringLiteral("output") : QStringLiteral("input");
}

QString operationName(Operation operation)
{
    switch (operation) {
    case Operation::Track:
        return QStringLiteral("track");
    case Operation::Untrack:
        return QStringLiteral("untrack");
    case Operation::SetVolume:
        return QStringLiteral("volume");
    case Operation::SetMute:
        return QStringLiteral("mute");
    case Operation::Shutdown:
        return QStringLiteral("shutdown");
    }
    return QStringLiteral("unknown");
}

} // namespace nagi::audio

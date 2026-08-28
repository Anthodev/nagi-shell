#include "protocol.h"

#include <QChar>
#include <QList>
#include <QStringDecoder>

namespace easyeffects_status {
namespace {

constexpr qsizetype MaximumNameBytes = 100;
constexpr qsizetype MaximumUnicodeScalars = 128;

bool hasSafePresetCharacters(const QString &name)
{
    const QList<uint> scalars = name.toUcs4();
    if (scalars.isEmpty() || scalars.size() > MaximumUnicodeScalars) {
        return false;
    }
    for (const uint scalar : scalars) {
        if (scalar == ':' || scalar == '/' || scalar == '\\') {
            return false;
        }
        const QChar::Category category = QChar::category(scalar);
        if (category == QChar::Other_Control || category == QChar::Other_Format
            || category == QChar::Other_Surrogate || category == QChar::Other_NotAssigned
            || category == QChar::Separator_Line || category == QChar::Separator_Paragraph) {
            return false;
        }
    }
    return true;
}

} // namespace
bool isValidPresetName(const QString &name)
{
    const QByteArray encoded = name.toUtf8();
    return !encoded.isEmpty() && encoded.size() <= MaximumNameBytes && hasSafePresetCharacters(name);
}


PresetResult parsePresetResponse(const QByteArray &response)
{
    const qsizetype newline = response.indexOf('\n');
    if (newline < 0 || newline != response.size() - 1 || newline > MaximumNameBytes
        || response.indexOf('\r') >= 0) {
        return {.state = PresetState::Invalid, .name = {}};
    }

    const QByteArray nameBytes = response.first(newline);
    if (nameBytes.isEmpty()) {
        return {.state = PresetState::None, .name = {}};
    }

    QStringDecoder decoder(QStringDecoder::Utf8);
    const QString name = decoder.decode(nameBytes);
    if (decoder.hasError() || !isValidPresetName(name)) {
        return {.state = PresetState::Invalid, .name = {}};
    }

    return {.state = PresetState::LastLoaded, .name = name};
}

const char *presetStateName(PresetState state)
{
    switch (state) {
    case PresetState::None:
        return "none";
    case PresetState::LastLoaded:
        return "lastLoaded";
    case PresetState::Unavailable:
        return "unavailable";
    case PresetState::Invalid:
        return "invalid";
    case PresetState::Timeout:
        return "timeout";
    }
    return "invalid";
}

} // namespace easyeffects_status

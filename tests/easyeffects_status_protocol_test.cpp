#include "protocol.h"

#include <QByteArray>

#include <cassert>
#include <iostream>

using easyeffects_status::PresetState;

int main()
{
    const auto output = easyeffects_status::parsePresetResponse("Studio\n");
    assert(output.state == PresetState::LastLoaded);
    assert(output.name == QStringLiteral("Studio"));

    const auto unicode = easyeffects_status::parsePresetResponse("Cinéma 🎧\n");
    assert(unicode.state == PresetState::LastLoaded);
    assert(unicode.name == QStringLiteral("Cinéma 🎧"));

    assert(easyeffects_status::parsePresetResponse("\n").state == PresetState::None);
    assert(easyeffects_status::parsePresetResponse("missing-newline").state == PresetState::Invalid);
    assert(easyeffects_status::parsePresetResponse("one\ntwo\n").state == PresetState::Invalid);
    assert(easyeffects_status::parsePresetResponse("path/name\n").state == PresetState::Invalid);
    assert(easyeffects_status::parsePresetResponse("unsafe:name\n").state == PresetState::Invalid);
    assert(easyeffects_status::parsePresetResponse(QByteArray("bad\xFF\n", 5)).state
           == PresetState::Invalid);
    assert(easyeffects_status::parsePresetResponse(QByteArray(100, 'a') + '\n').state
           == PresetState::LastLoaded);
    assert(easyeffects_status::parsePresetResponse(QByteArray(101, 'a') + '\n').state
           == PresetState::Invalid);

    assert(easyeffects_status::isValidPresetName(QStringLiteral("Studio")));
    assert(easyeffects_status::isValidPresetName(QStringLiteral("Cinéma 🎧")));
    assert(!easyeffects_status::isValidPresetName(QStringLiteral("private/path")));
    assert(!easyeffects_status::isValidPresetName(QString(101, 'a')));

    assert(QByteArray(easyeffects_status::presetStateName(PresetState::LastLoaded)) == "lastLoaded");
    assert(QByteArray(easyeffects_status::presetStateName(PresetState::Timeout)) == "timeout");

    std::cout << "EasyEffects status protocol tests passed\n";
    return 0;
}

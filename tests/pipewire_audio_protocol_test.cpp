#include "protocol.h"

#include <cstdio>
#include <cstdlib>

namespace {

void require(bool condition, const char *message)
{
    if (!condition) {
        std::fprintf(stderr, "FAIL: %s\n", message);
        std::exit(1);
    }
}

} // namespace

int main()
{
    using nagi::audio::Operation;
    using nagi::audio::Role;
    using nagi::audio::parseCommand;
    using nagi::audio::EasyEffectsInternalRole;
    using nagi::audio::classifyEasyEffectsNode;

    const auto track = parseCommand(
        R"({"op":"track","role":"output","nodeId":42,"generation":7})");
    require(
        track && track->operation == Operation::Track && track->role == Role::Output
            && track->nodeId == 42 && track->generation == 7,
        "valid track command parses");

    const auto volume = parseCommand(
        R"({"op":"setVolume","role":"input","nodeId":9,"generation":3,"requestId":11,"value":0.75,"final":true})");
    require(
        volume && volume->operation == Operation::SetVolume && volume->role == Role::Input
            && volume->nodeId == 9 && volume->generation == 3 && volume->requestId == 11
            && volume->volume == 0.75 && volume->final,
        "valid volume command parses");

    const auto mute = parseCommand(
        R"({"op":"setMute","role":"output","nodeId":4,"generation":2,"requestId":8,"muted":false})");
    require(
        mute && mute->operation == Operation::SetMute && !mute->muted,
        "valid mute command parses");

    require(
        !parseCommand(
            R"({"op":"setVolume","role":"output","nodeId":4,"generation":2,"requestId":8,"value":1.01,"final":false})"),
        "amplified volume command is rejected");
    require(
        !parseCommand(
            R"({"op":"setMute","role":"output","nodeId":4,"generation":2,"requestId":8,"muted":true,"extra":1})"),
        "unexpected command fields are rejected");
    require(
        !parseCommand(
            R"({"op":"track","role":"stream","nodeId":4,"generation":2})"),
        "unknown roles are rejected");
    require(
        !parseCommand(
            R"({"op":"track","role":"output","nodeId":4,"generation":0})"),
        "zero generations are rejected");
    require(!parseCommand("not-json"), "malformed JSON is rejected");
    require(
        !parseCommand(QByteArray(nagi::audio::MaximumCommandBytes + 1, 'x')),
        "oversized commands are rejected");

    require(
        classifyEasyEffectsNode(
            "easyeffects_sink",
            "com.github.wwmm.easyeffects",
            "true",
            "Audio/Sink")
            == EasyEffectsInternalRole::Output,
        "exact EasyEffects output properties are classified");
    require(
        classifyEasyEffectsNode(
            "easyeffects_source",
            "com.github.wwmm.easyeffects",
            "true",
            "Audio/Source/Virtual")
            == EasyEffectsInternalRole::Input,
        "exact EasyEffects input properties are classified");
    require(
        classifyEasyEffectsNode(
            "easyeffects_sink",
            "com.github.wwmm.easyeffects",
            "true",
            "EE/Audio/Sink")
            == EasyEffectsInternalRole::None,
        "EasyEffects model classes are not graph media classes");
    require(
        classifyEasyEffectsNode(
            "easyeffects_sink",
            "com.github.wwmm.easyeffects",
            "false",
            "Audio/Sink")
            == EasyEffectsInternalRole::None,
        "node name and application ID alone do not classify a node");
    require(
        classifyEasyEffectsNode(
            "unrelated_virtual_sink",
            "com.github.wwmm.easyeffects",
            "true",
            "Audio/Sink")
            == EasyEffectsInternalRole::None,
        "unrelated virtual devices are retained");

    std::puts("pipewire audio protocol tests passed");
    return 0;
}

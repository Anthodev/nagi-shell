#pragma once

#include <optional>
#include <vector>

namespace nagi::audio {

std::optional<std::vector<float>> proportionalCubicVolumes(
    const std::vector<float> &confirmedVisualVolumes,
    double targetAverage);

} // namespace nagi::audio

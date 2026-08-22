#include "volume.h"

#include <cmath>
#include <limits>
#include <numeric>

namespace nagi::audio {

std::optional<std::vector<float>> proportionalCubicVolumes(
    const std::vector<float> &confirmedVisualVolumes,
    double targetAverage)
{
    if (confirmedVisualVolumes.empty() || confirmedVisualVolumes.size() > 64
        || !std::isfinite(targetAverage) || targetAverage < 0.0 || targetAverage > 1.0) {
        return std::nullopt;
    }
    for (float volume : confirmedVisualVolumes) {
        if (!std::isfinite(volume) || volume < 0.0F) {
            return std::nullopt;
        }
    }

    const double average = std::accumulate(
                               confirmedVisualVolumes.begin(),
                               confirmedVisualVolumes.end(),
                               0.0)
        / static_cast<double>(confirmedVisualVolumes.size());
    std::vector<float> cubicVolumes;
    cubicVolumes.reserve(confirmedVisualVolumes.size());
    for (float current : confirmedVisualVolumes) {
        const double visual = average <= 0.000001 ? targetAverage
                                                 : current * targetAverage / average;
        const double cubic = visual * visual * visual;
        if (!std::isfinite(cubic) || cubic > std::numeric_limits<float>::max()) {
            return std::nullopt;
        }
        cubicVolumes.push_back(static_cast<float>(cubic));
    }
    return cubicVolumes;
}

} // namespace nagi::audio

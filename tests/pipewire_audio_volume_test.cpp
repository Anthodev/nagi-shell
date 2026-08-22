#include "volume.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

namespace {

void require(bool condition, const char *message)
{
    if (!condition) {
        std::fprintf(stderr, "FAIL: %s\n", message);
        std::exit(1);
    }
}

bool near(double left, double right)
{
    return std::abs(left - right) < 0.000001;
}

} // namespace

int main()
{
    const auto unequal = nagi::audio::proportionalCubicVolumes({0.5F, 1.0F}, 0.6);
    require(unequal && unequal->size() == 2, "unequal channels scale");
    const double left = std::cbrt((*unequal)[0]);
    const double right = std::cbrt((*unequal)[1]);
    require(near((left + right) / 2.0, 0.6), "scaled average matches target");
    require(near(right / left, 2.0), "channel proportion is preserved");

    const auto silent = nagi::audio::proportionalCubicVolumes({0.0F, 0.0F}, 0.5);
    require(
        silent && near((*silent)[0], 0.125) && near((*silent)[1], 0.125),
        "silent channels receive the requested average equally");

    require(
        !nagi::audio::proportionalCubicVolumes({}, 0.5),
        "empty channel state is rejected");
    require(
        !nagi::audio::proportionalCubicVolumes({0.5F}, 1.01),
        "amplified Nagi target is rejected");
    require(
        !nagi::audio::proportionalCubicVolumes({-0.1F, 0.5F}, 0.4),
        "invalid confirmed channel state is rejected");
    require(
        !nagi::audio::proportionalCubicVolumes(std::vector<float>(65, 0.5F), 0.4),
        "channel state is bounded");

    std::puts("pipewire audio volume tests passed");
    return 0;
}

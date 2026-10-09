#include "app/summary.hpp"

#include "geometry/shapes/area.hpp"
#include "lowlevel/host.hpp"

#include <format>

namespace app {

std::string summary(int width, int height) {
    const auto area = geometry::shapes::area({.width = width, .height = height});
    if (!area) {
        return std::format("no area: {}", area.error());
    }
    return std::format("area {} on {}, clock {}", *area, lowlevel::host_note(),
                       geometry::shapes::clock_runs() ? "runs" : "is stopped");
}

} // namespace app

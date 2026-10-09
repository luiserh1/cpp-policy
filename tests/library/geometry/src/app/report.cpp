#include "app/report.hpp"

#include "geometry/shapes/area.hpp"

#include <format>

namespace app {

std::string report(int width, int height) {
    const auto area = geometry::shapes::area({.width = width, .height = height});
    if (!area) {
        return std::format("no area: {}", area.error());
    }
    return std::format("area {}", *area);
}

} // namespace app

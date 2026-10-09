#include "geometry/shapes/area.hpp"

#include "geometry/lowlevel/clock.hpp"

namespace geometry::shapes {

std::expected<int, std::string> area(const Rectangle& rectangle) {
    if (rectangle.width < 0 || rectangle.height < 0) {
        return std::unexpected{std::string{"a side is negative"}};
    }
    return rectangle.width * rectangle.height;
}

bool clock_runs() {
    const auto first = lowlevel::ticks();
    return lowlevel::ticks() >= first;
}

} // namespace geometry::shapes

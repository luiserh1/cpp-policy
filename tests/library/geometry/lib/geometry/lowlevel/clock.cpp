#include "geometry/lowlevel/clock.hpp"

#include "geometry/lowlevel/internal/units.hpp"

#include <chrono>

namespace geometry::lowlevel {

std::int64_t ticks() {
    return std::chrono::steady_clock::now().time_since_epoch().count() / internal::ticks_per_step;
}

} // namespace geometry::lowlevel

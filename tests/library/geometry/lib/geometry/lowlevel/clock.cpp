#include "geometry/lowlevel/clock.hpp"

#include <chrono>

namespace geometry::lowlevel {

std::int64_t ticks() {
    return std::chrono::steady_clock::now().time_since_epoch().count();
}

} // namespace geometry::lowlevel

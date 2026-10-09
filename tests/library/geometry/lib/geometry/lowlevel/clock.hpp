#pragma once

#include <cstdint>

namespace geometry::lowlevel {

// Ticks since the program started, from the steady clock.
[[nodiscard]] std::int64_t ticks();

} // namespace geometry::lowlevel

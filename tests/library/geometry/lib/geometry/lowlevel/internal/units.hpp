#pragma once

#include <cstdint>

namespace geometry::lowlevel::internal {

// Internal to the lowlevel module: neither the rest of the library nor a user includes it.
inline constexpr std::int64_t ticks_per_step = 1;

} // namespace geometry::lowlevel::internal

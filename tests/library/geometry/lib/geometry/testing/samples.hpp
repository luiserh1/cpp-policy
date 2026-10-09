#pragma once

#include "geometry/shapes/area.hpp"

namespace geometry::testing {

// A rectangle whose area every test knows: 12.
[[nodiscard]] shapes::Rectangle sample_rectangle();

} // namespace geometry::testing

#pragma once

#include <expected>
#include <string>

namespace geometry::shapes {

struct Rectangle {
    int width{};
    int height{};
};

// The area, or why the rectangle has none.
[[nodiscard]] std::expected<int, std::string> area(const Rectangle& rectangle);

// Whether the clock the library reads moves forward.
[[nodiscard]] bool clock_runs();

} // namespace geometry::shapes

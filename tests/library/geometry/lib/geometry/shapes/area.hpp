#pragma once

#include <expected>
#include <string>
#include <string_view>

namespace geometry::shapes {

struct Rectangle {
    int width{};
    int height{};
};

// The area, or why the rectangle has none.
[[nodiscard]] std::expected<int, std::string> area(const Rectangle& rectangle);

// Whether the clock the library reads moves forward.
[[nodiscard]] bool clock_runs();

// The library's release, as its project() line has it.
[[nodiscard]] std::string_view version();

} // namespace geometry::shapes

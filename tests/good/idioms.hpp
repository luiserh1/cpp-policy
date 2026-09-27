#pragma once

#include <cstdint>
#include <optional>
#include <string_view>

namespace policy_sample {

// The idioms of POLICY.md 2.10: each one is the form clang-tidy accepts.

// A small value type gets a constructor, so it is written Rgb{255, 0, 0}.
struct Rgb {
    constexpr Rgb(std::uint8_t red, std::uint8_t green, std::uint8_t blue)
        : r{red}, g{green}, b{blue} {}

    std::uint8_t r;
    std::uint8_t g;
    std::uint8_t b;
};

// Any other struct is built with designated initializers: Size{.width = 4, .height = 2}.
struct Size {
    int width = 0;
    int height = 0;
};

// A member that refers to an outside object and is never null: a pointer, set from a
// reference in the constructor.
class Grid {
public:
    explicit Grid(const Size& size) : size_{&size} {}

    [[nodiscard]] int index(int x, int y) const { return (y * size_->width) + x; }

private:
    const Size* size_; // never null: set from a reference
};

// A whole string_view as a number, with std::from_chars.
[[nodiscard]] std::optional<int> parse_whole(std::string_view text);

// The pixel at the given index of a fixed palette.
[[nodiscard]] Rgb palette_color(int index);

} // namespace policy_sample

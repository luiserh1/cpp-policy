#include "idioms.hpp"

#include <array>
#include <charconv>
#include <memory>
#include <system_error>

namespace policy_sample {

std::optional<int> parse_whole(std::string_view text) {
    // std::to_address gives the range's ends without pointer arithmetic or data().
    const char* const end = std::to_address(text.end());
    int value = 0;
    const auto [last, error] = std::from_chars(std::to_address(text.begin()), end, value);
    if (text.empty() || error != std::errc{} || last != end) {
        return std::nullopt;
    }
    return value;
}

Rgb palette_color(int index) {
    // A list clang-format writes on several lines ends with a trailing comma.
    static constexpr std::array palette{
        Rgb{0, 0, 0},
        Rgb{255, 255, 255},
        Rgb{255, 0, 0},
    };
    return palette.at(static_cast<std::size_t>(index));
}

} // namespace policy_sample

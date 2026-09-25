#include "numbers.hpp"

#include <limits>
#include <numeric>

namespace policy_sample {

std::expected<int, ParseError> parse_int(std::string_view text) {
    if (text.empty()) {
        return std::unexpected{ParseError::empty};
    }
    int value = 0;
    for (const char c : text) {
        if (c < '0' || c > '9') {
            return std::unexpected{ParseError::invalid_digit};
        }
        const int digit = c - '0';
        if (value > (std::numeric_limits<int>::max() - digit) / 10) {
            return std::unexpected{ParseError::overflow};
        }
        value = (value * 10) + digit;
    }
    return value;
}

std::int64_t sum(std::span<const int> values) {
    return std::accumulate(values.begin(), values.end(), std::int64_t{0});
}

} // namespace policy_sample

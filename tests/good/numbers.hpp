#pragma once

#include <cstdint>
#include <expected>
#include <span>
#include <string_view>

namespace policy_sample {

enum class ParseError : std::uint8_t { empty, invalid_digit, overflow };

// Expected failure -> std::expected, not an exception.
[[nodiscard]] std::expected<int, ParseError> parse_int(std::string_view text);

// Non-owning view of a buffer -> std::span, not pointer + length.
[[nodiscard]] std::int64_t sum(std::span<const int> values);

} // namespace policy_sample

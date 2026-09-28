#pragma once

#include <cstddef>
#include <cstdint>
#include <expected>
#include <string>
#include <string_view>

namespace app {

enum class GreetingError : std::uint8_t { empty_name, name_too_long };

inline constexpr std::size_t max_name_length = 40;

// An expected failure is returned, not thrown (POLICY.md 3).
[[nodiscard]] std::expected<std::string, GreetingError> greeting(std::string_view name);

[[nodiscard]] std::string_view describe(GreetingError error);

} // namespace app

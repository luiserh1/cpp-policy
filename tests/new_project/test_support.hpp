#pragma once
// A helper shared by test programs, in a folder of its own under tests/ (added to the
// generated project by tests/new_project/run.cmake): the gate and tidy-files must both accept
// an optional read after REQUIRE here, as in the test sources (POLICY.md 13.4).

#include <doctest/doctest.h>

#include <cstddef>
#include <optional>

namespace test_support {

inline std::size_t required(const std::optional<std::size_t>& value) {
    REQUIRE(value.has_value());
    return *value;
}

[[nodiscard]] std::size_t required_twice(const std::optional<std::size_t>& value);

} // namespace test_support

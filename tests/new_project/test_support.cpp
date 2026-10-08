// A test helper compiled in a library of its own, which the project declares with
// cpp_policy_test_support() (added by tests/new_project/run.cmake).
#include "test_support.hpp"

#include <doctest/doctest.h>

#include <cstddef>
#include <optional>

namespace test_support {

std::size_t required_twice(const std::optional<std::size_t>& value) {
    REQUIRE(value.has_value());
    return *value * 2;
}

} // namespace test_support

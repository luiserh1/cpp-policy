#include "lowlevel/environment.hpp"

#include <doctest/doctest.h>

#include <string_view>

TEST_CASE("a variable that is set is read") {
    constexpr std::string_view name = "PATH";
    CAPTURE(name);
    CHECK(lowlevel::environment_variable(name).has_value());
}

TEST_CASE("a variable that isn't set is nothing") {
    CHECK_FALSE(lowlevel::environment_variable("NO_SUCH_VARIABLE_4B1D").has_value());
}

#include "lowlevel/environment.hpp"

#include <doctest/doctest.h>

TEST_CASE("a variable that is set is read") {
    CHECK(lowlevel::environment_variable("PATH").has_value());
}

TEST_CASE("a variable that isn't set is nothing") {
    CHECK_FALSE(lowlevel::environment_variable("NO_SUCH_VARIABLE_4B1D").has_value());
}

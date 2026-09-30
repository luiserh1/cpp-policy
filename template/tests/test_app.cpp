#include "app/greeting.hpp"

#include <doctest/doctest.h>

#include <array>
#include <ostream>
#include <string>
#include <string_view>

// Failures show the error's description, not its number (POLICY.md 13): the operator is in
// the enum's namespace, where doctest finds it, and inline so the anonymous namespace inside
// keeps it private to this file.
namespace app {
inline namespace {
std::ostream& operator<<(std::ostream& out, GreetingError error) {
    return out << describe(error);
}
} // namespace
} // namespace app

namespace {

using app::GreetingError;

struct Refused {
    std::string_view what;
    std::string name;
    GreetingError error;
};

} // namespace

TEST_CASE("a name is greeted") {
    const auto text = app::greeting("Ada");
    REQUIRE(text.has_value());
    CHECK(*text == "Hello, Ada!");
}

TEST_CASE("a name at the length limit is greeted") {
    const std::string name(app::max_name_length, 'x');
    const auto text = app::greeting(name);
    REQUIRE(text.has_value());
    CHECK(*text == "Hello, " + name + "!");
}

TEST_CASE("empty and too long names are refused") {
    const std::array rows{
        Refused{.what = "empty", .name = "", .error = GreetingError::empty_name},
        Refused{
            .what = "one character over the limit",
            .name = std::string(app::max_name_length + 1, 'x'),
            .error = GreetingError::name_too_long,
        },
    };
    for (const auto& row : rows) {
        CAPTURE(row.what);
        const auto text = app::greeting(row.name);
        // REQUIRE: error() on a success would be undefined behavior.
        REQUIRE_FALSE(text.has_value());
        CHECK(text.error() == row.error);
    }
}

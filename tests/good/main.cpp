#include "lowlevel/byte_view.hpp"
#include "numbers.hpp"
#include "shapes.hpp"
#include "tally.hpp"

#include <array>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <print>
#include <stop_token>

namespace {

bool check(bool condition, std::string_view what) {
    if (!condition) {
        std::println(stderr, "FAILED: {}", what);
    }
    return condition;
}

bool run_all() {
    using namespace policy_sample;
    bool ok = true;

    ok &= check(parse_int("1234") == 1234, "parse_int valid");
    ok &= check(parse_int("").error() == ParseError::empty, "parse_int empty");
    ok &= check(parse_int("12a").error() == ParseError::invalid_digit, "parse_int digit");
    ok &= check(parse_int("99999999999").error() == ParseError::overflow, "parse_int overflow");

    constexpr std::array values{1, 2, 3, 4};
    ok &= check(sum(values) == 10, "sum");

    constexpr std::array sides{1.0, 2.0};
    const auto shapes = make_squares(sides);
    ok &= check(shapes.size() == 2 && shapes[1]->area() == 4.0, "make_squares");

    constexpr std::array bytes{std::byte{0x01}, std::byte{0x02}, std::byte{0x00}, std::byte{0x00}};
    ok &= check(read_u32_le(bytes) == 0x0201U, "read_u32_le");

    constexpr std::array text{std::byte{'o'}, std::byte{'k'}};
    ok &= check(as_text(text) == "ok", "as_text");

    Tally tally;
    add_concurrently(tally, 8, 5);
    ok &= check(tally.total() == 40, "add_concurrently");

    // A stop_source used the standard way. request_stop() is const in libstdc++ only, so
    // without the exemption in .clang-tidy this line fails misc-const-correctness on Linux.
    std::stop_source stop;
    stop.request_stop();
    ok &= check(stop.get_token().stop_requested(), "stop_source");

    return ok;
}

} // namespace

// Program boundary: the only place where every exception is caught (POLICY.md 3).
// The handlers use std::fputs because std::println could itself throw.
int main() {
    try {
        return run_all() ? EXIT_SUCCESS : EXIT_FAILURE;
    } catch (const std::exception& e) {
        std::fputs("unhandled exception: ", stderr);
        std::fputs(e.what(), stderr);
        std::fputs("\n", stderr);
    } catch (...) { // boundary: program
        std::fputs("unhandled unknown exception\n", stderr);
    }
    return EXIT_FAILURE;
}

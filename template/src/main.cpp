#include "app/greeting.hpp"
#include "lowlevel/environment.hpp"

#include <cstdio>
#include <cstdlib>
#include <exception>
#include <print>

namespace {

int run() {
    const auto name = lowlevel::environment_variable("GREETING_NAME").value_or("world");
    const auto text = app::greeting(name);
    if (!text) {
        std::println(stderr, "error: {}", app::describe(text.error()));
        return EXIT_FAILURE;
    }
    std::println("{}", *text);
    return EXIT_SUCCESS;
}

} // namespace

// Program boundary: the only place where every exception is caught (POLICY.md 3).
// The handlers use std::fputs because std::println could itself throw.
int main() {
    try {
        return run();
    } catch (const std::exception& e) {
        std::fputs("unhandled exception: ", stderr);
        std::fputs(e.what(), stderr);
        std::fputs("\n", stderr);
    } catch (...) { // boundary: program
        std::fputs("unhandled unknown exception\n", stderr);
    }
    return EXIT_FAILURE;
}

#pragma once

#include <cstdio>
#include <cstdlib>
#include <exception>
#include <print>
#include <source_location>
#include <string_view>

namespace test {

// Minimal test helper: records failures and turns them into the exit code.
class Checker {
public:
    void expect(bool condition, std::string_view what,
                std::source_location where = std::source_location::current()) {
        if (!condition) {
            ++failures_;
            std::println(stderr, "{}:{}: FAILED: {}", where.file_name(), where.line(), what);
        }
    }

    [[nodiscard]] int exit_code() const { return failures_ == 0 ? EXIT_SUCCESS : EXIT_FAILURE; }

private:
    int failures_ = 0;
};

// Runs `body` as a test program: failures and escaping exceptions give a failing exit code.
// The handlers use std::fputs because std::println could itself throw.
inline int run_tests(void (*body)(Checker&)) noexcept {
    try {
        Checker check;
        body(check);
        return check.exit_code();
    } catch (const std::exception& e) {
        std::fputs("unhandled exception: ", stderr);
        std::fputs(e.what(), stderr);
        std::fputs("\n", stderr);
    } catch (...) { // boundary: test program
        std::fputs("unhandled unknown exception\n", stderr);
    }
    return EXIT_FAILURE;
}

} // namespace test

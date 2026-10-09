#include "app/summary.hpp"

#include <cstdio>
#include <cstdlib>
#include <exception>
#include <print>

int main() {
    try {
        std::println("{}", app::summary(3, 4));
        return EXIT_SUCCESS;
    } catch (const std::exception& e) {
        std::fputs("unhandled exception: ", stderr);
        std::fputs(e.what(), stderr);
        std::fputs("\n", stderr);
    } catch (...) { // boundary: main
        std::fputs("unhandled unknown exception\n", stderr);
    }
    return EXIT_FAILURE;
}

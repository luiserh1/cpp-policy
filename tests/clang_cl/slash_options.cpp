// clang-cl only: slash-form options (/D, /EHsc) must reach the compiler and clang-tidy.
// CMake passes CPP_POLICY_SLASH_OPTION as /D and /EHsc comes from its default flags; if
// clang-tidy drops them, the #error below or the try block fails the build.
#ifndef CPP_POLICY_SLASH_OPTION
#error "a slash-form option (/DCPP_POLICY_SLASH_OPTION) was dropped"
#endif

#include <cstdlib>
#include <stdexcept>

namespace {

int non_negative(int value) {
    if (value < 0) {
        throw std::invalid_argument("negative");
    }
    return value;
}

} // namespace

// Nothing is thrown at run time: with clang-cl, ASan crashes on any throw (POLICY.md 7.3).
// Compiling the try and the throw is the test.
int main() {
    try {
        return non_negative(1) == 1 ? EXIT_SUCCESS : EXIT_FAILURE;
    } catch (...) {
        return EXIT_FAILURE;
    }
}

// Prints how the dependency was compiled, and the project's own standard library, for
// run.cmake to compare with the preset.
#include <probe.h>
#include <probe_build.h>
#include <probe_library.h>

#include <cstdio>
#include <cstdlib>
#include <string>

namespace {

void print_line(const char* label, const char* text) {
    std::fputs(label, stdout);
    std::fputs(text, stdout);
    std::fputs("\n", stdout);
}

} // namespace

int main() {
    print_line("dependency C: ", probe_c_build());
    print_line("dependency C++: ", probe_cpp_build());
    print_line("project: library=", PROBE_LIBRARY);
    return EXIT_SUCCESS;
}

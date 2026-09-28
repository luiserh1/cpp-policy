#include "probe_build.h"

#include <string>

#include "probe.h"
#include "probe_library.h"

// Uses the standard library, so the check covers a C++ dependency: the library it was compiled
// against and its hardening mode.
extern "C" const char* probe_cpp_build(void) {
    static const std::string build =
        std::string(PROBE_BUILD) + " library=" PROBE_LIBRARY " hardening=" PROBE_HARDENING;
    return build.c_str();
}

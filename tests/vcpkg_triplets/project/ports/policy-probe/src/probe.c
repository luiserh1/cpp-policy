#include "probe_build.h"

#include "probe.h"

size_t probe_sum(const unsigned char* data, size_t size) {
    size_t total = 0;
    for (size_t i = 0; i < size; ++i) {
        total += data[i];
    }
    return total;
}

const char* probe_c_build(void) {
    return PROBE_BUILD;
}

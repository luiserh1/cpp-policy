// Confined: calls a C library through a pointer and a length, and the static analyzer
// reports a leak inside that library on the call's line (POLICY.md 5, third-party code).
#include "lowlevel/c_library.hpp"

#include <sample_c.h>

namespace policy_sample {

int checksum(std::span<const std::uint8_t> bytes) {
    // NOLINTNEXTLINE(clang-analyzer-unix.Malloc): the leak is in the C library, sizes over 64
    return sample_c_sum(bytes.data(), static_cast<int>(bytes.size()));
}

} // namespace policy_sample

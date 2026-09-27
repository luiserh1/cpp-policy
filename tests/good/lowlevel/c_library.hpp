#pragma once

#include <cstdint>
#include <span>

namespace policy_sample {

// Safe interface to a C library (third_party/sample_c.h): a span in, a value out.
[[nodiscard]] int checksum(std::span<const std::uint8_t> bytes);

} // namespace policy_sample

#pragma once

#include <cstddef>
#include <cstdint>
#include <span>

namespace policy_sample {

// Safe interface: callers pass a span; the low-level details stay in the .cpp.
[[nodiscard]] std::uint32_t read_u32_le(std::span<const std::byte, 4> bytes);

} // namespace policy_sample

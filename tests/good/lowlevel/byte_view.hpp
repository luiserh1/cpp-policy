#pragma once

#include <cstddef>
#include <cstdint>
#include <span>
#include <string_view>

namespace policy_sample {

// Safe interface: callers pass spans; the low-level details stay in the .cpp.

// Reads a little-endian 32-bit value. Plain indexing: needs no suppression.
[[nodiscard]] std::uint32_t read_u32_le(std::span<const std::byte, 4> bytes);

// Views raw bytes as text without copying them.
[[nodiscard]] std::string_view as_text(std::span<const std::byte> bytes);

} // namespace policy_sample

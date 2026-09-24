// Confined low-level code: demonstrates a justified, audited suppression.
#include "lowlevel/packed_header.hpp"

namespace policy_sample {

std::uint32_t read_u32_le(std::span<const std::byte, 4> bytes) {
    const std::byte* p = bytes.data();
    std::uint32_t value = 0;
    for (std::uint32_t i = 0; i < 4; ++i) {
        // NOLINTNEXTLINE(cppcoreguidelines-pro-bounds-pointer-arithmetic): fixed-size span, i < 4
        value |= std::to_integer<std::uint32_t>(*(p + i)) << (8U * i);
    }
    return value;
}

} // namespace policy_sample

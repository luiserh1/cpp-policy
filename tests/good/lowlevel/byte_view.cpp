// Confined: viewing bytes as characters needs a reinterpret_cast; the standard has no
// cast-free way to do it without copying.
#include "lowlevel/byte_view.hpp"

namespace policy_sample {

std::uint32_t read_u32_le(std::span<const std::byte, 4> bytes) {
    std::uint32_t value = 0;
    for (std::size_t i = 0; i < bytes.size(); ++i) {
        value |= std::to_integer<std::uint32_t>(bytes[i]) << (8U * i);
    }
    return value;
}

std::string_view as_text(std::span<const std::byte> bytes) {
    // NOLINTNEXTLINE(cppcoreguidelines-pro-type-reinterpret-cast): char may alias any object type
    return {reinterpret_cast<const char*>(bytes.data()), bytes.size()};
}

} // namespace policy_sample

// POLICY 2.3: reinterpret_cast for type punning.
// EXPECT: cppcoreguidelines-pro-type-reinterpret-cast
#include <cstdint>

std::uint32_t bits(const float& f) {
    return *reinterpret_cast<const std::uint32_t*>(&f);
}

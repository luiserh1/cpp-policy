// POLICY 2.3: unions for type punning.
// EXPECT: cppcoreguidelines-pro-type-union-access
#include <cstdint>
union Bits {
    float f;
    std::uint32_t u;
};
std::uint32_t bits(float value) {
    Bits b{};
    b.f = value;
    return b.u;
}

// POLICY 2.3: implicit narrowing conversions.
// EXPECT: cppcoreguidelines-narrowing-conversions
#include <cstdint>

std::int32_t narrow(std::int64_t v) {
    return v;
}

// POLICY 2.2: pointer arithmetic outside a confined area.
// EXPECT: cppcoreguidelines-pro-bounds-pointer-arithmetic
#include <cstddef>

int second(const int* p, std::size_t n) {
    return n > 1 ? *(p + 1) : 0;
}

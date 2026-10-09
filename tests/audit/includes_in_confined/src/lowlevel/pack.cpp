#include <zlib.h>

#include <cstddef>

int pack(const unsigned char* data, std::size_t size) {
    // NOLINTNEXTLINE(cppcoreguidelines-pro-bounds-pointer-arithmetic): the caller gives size >= 1
    return *(data + size - 1);
}

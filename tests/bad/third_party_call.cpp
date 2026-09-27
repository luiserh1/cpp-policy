// POLICY 5: a static-analyzer finding inside an excluded third-party header still reaches
// the project, on the line that calls into the header.
// EXPECT: clang-analyzer-unix.Malloc
#include <span>
#include <sample_c.h>
int sum_bytes(std::span<const unsigned char> bytes) {
    return sample_c_sum(bytes.data(), static_cast<int>(bytes.size()));
}

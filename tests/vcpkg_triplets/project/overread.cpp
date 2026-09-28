// Hands the dependency a 16-byte buffer with a size of 17. When vcpkg built the dependency with
// AddressSanitizer, the program stops with heap-buffer-overflow inside probe_sum; otherwise the
// overread goes unnoticed and the sum is printed.
#include <probe.h>

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

int main() {
    const std::vector<unsigned char> data(16, 1);
    const std::size_t total = probe_sum(data.data(), data.size() + 1);
    std::fputs(("sum " + std::to_string(total) + "\n").c_str(), stdout);
    return EXIT_SUCCESS;
}

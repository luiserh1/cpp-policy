// cpp_policy::peak_memory_bytes() (POLICY.md 13.5) on this system: the peak must rise by
// roughly what the test touches, and never go down.
#include "cpp_policy/peak_memory.hpp"

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <print>
#include <vector>

namespace {

constexpr std::uint64_t touched_bytes = 64ULL * 1024 * 1024;

int run() {
    const auto before = cpp_policy::peak_memory_bytes();
    if (!before) {
        std::println(stderr, "peak_memory: {}", before.error());
        return EXIT_FAILURE;
    }
    // Every page written with a value known only at run time, and read back, so the memory is
    // resident and the optimizer can't remove it.
    std::vector<std::uint8_t> block(touched_bytes, static_cast<std::uint8_t>(*before % 251));
    std::uint64_t sum = 0;
    for (std::size_t i = 0; i < block.size(); i += 4096) {
        sum += block.at(i);
    }
    const auto during = cpp_policy::peak_memory_bytes();
    block.clear();
    block.shrink_to_fit();
    const auto after = cpp_policy::peak_memory_bytes();
    if (!during || !after) {
        std::println(stderr, "peak_memory: couldn't read the peak");
        return EXIT_FAILURE;
    }
    std::println("peak_memory: {} bytes before, {} with 64 MiB touched, {} after freeing it "
                 "(checksum {})",
                 *before, *during, *after, sum);
    if (*during < *before + (touched_bytes / 2)) {
        std::println(stderr, "peak_memory: the peak rose by less than half the touched memory");
        return EXIT_FAILURE;
    }
    if (*after < *during) {
        std::println(stderr, "peak_memory: the peak went down");
        return EXIT_FAILURE;
    }
    return EXIT_SUCCESS;
}

} // namespace

int main() {
    try {
        return run();
    } catch (const std::exception& e) {
        std::fputs("unhandled exception: ", stderr);
        std::fputs(e.what(), stderr);
        std::fputs("\n", stderr);
    } catch (...) { // boundary: test program
        std::fputs("unhandled unknown exception\n", stderr);
    }
    return EXIT_FAILURE;
}

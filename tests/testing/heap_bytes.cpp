// cpp_policy::live_heap_bytes(), peak_heap_bytes() and reset_peak_heap_bytes()
// (POLICY.md 13.5) on this system: exact, so every check here is an equality or a bound that
// can't depend on the machine's load.
#include "cpp_policy/heap_bytes.hpp"

#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <memory>
#include <print>
#include <string>
#include <vector>

namespace {

constexpr std::uint64_t block_bytes = 1024ULL * 1024;

struct alignas(64) Aligned {
    std::uint8_t value{};
};

// The optimizer removes an allocation whose address nobody else sees, and then there is
// nothing to count. Writing the address to a volatile makes it visible.
void show(const void* address) {
    [[maybe_unused]] const void* volatile seen = address;
}

// One megabyte in a vector, plus an array, an over-aligned object and a string: both forms
// of operator new (plain and aligned) must be counted and given back.
[[nodiscard]] std::uint64_t churn(std::uint8_t seed) {
    std::vector<std::uint8_t> block(block_bytes, seed);
    const auto array = std::make_unique<std::array<std::uint32_t, 256>>();
    const auto aligned = std::make_unique<Aligned>();
    const std::string text(200, 'x');
    array->front() = seed;
    show(block.data());
    show(array.get());
    show(aligned.get());
    show(text.data());
    return block.at(block_bytes / 2) + array->front() + aligned->value + text.size();
}

[[nodiscard]] bool check(bool condition, const char* what) {
    if (!condition) {
        std::println(stderr, "heap_bytes: {}", what);
    }
    return condition;
}

int run() {
    const auto seed = static_cast<std::uint8_t>(cpp_policy::live_heap_bytes() % 251);
    std::uint64_t sum = churn(seed); // anything allocated once (stdio buffers) comes first
    const std::uint64_t before = cpp_policy::live_heap_bytes();

    cpp_policy::reset_peak_heap_bytes();
    bool ok = check(cpp_policy::peak_heap_bytes() == before, "a reset peak isn't the live bytes");
    sum += churn(seed);
    const std::uint64_t one = cpp_policy::peak_heap_bytes();
    ok = check(one >= before + block_bytes, "the peak rose by less than the megabyte allocated") &&
         ok;
    ok = check(cpp_policy::live_heap_bytes() == before, "freed blocks are still counted") && ok;

    // The same work again, and forty times more: the peak is the same to the byte.
    cpp_policy::reset_peak_heap_bytes();
    for (int i = 0; i < 40; ++i) {
        sum += churn(seed);
    }
    ok = check(cpp_policy::peak_heap_bytes() == one, "the same work gave a different peak") && ok;

    // What is kept is counted exactly.
    std::vector<std::vector<std::uint8_t>> kept;
    kept.reserve(3);
    for (int i = 0; i < 3; ++i) {
        kept.emplace_back(block_bytes, seed);
        show(kept.back().data());
    }
    ok = check(cpp_policy::live_heap_bytes() >= before + (3 * block_bytes),
               "three kept megabytes aren't in the live bytes") &&
         ok;

    std::println("heap_bytes: {} live, peak {} for one megabyte of work (checksum {})", before, one,
                 sum);
    return ok ? EXIT_SUCCESS : EXIT_FAILURE;
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

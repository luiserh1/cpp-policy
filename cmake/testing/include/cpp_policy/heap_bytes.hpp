#pragma once

#include <cstdint>

namespace cpp_policy {

// An exact count of the program's C++ heap (POLICY.md 13.5): every block from operator new,
// at the size the allocator gave it, until its operator delete. The same work gives the same
// numbers on every run, whatever else the machine is doing, which the operating system's
// peak (peak_memory.hpp) doesn't. It doesn't see memory a C library takes with malloc(), or
// mapped files. Including this header in a benchmark test replaces the program's operator
// new and operator delete; in builds with sanitizers nothing is replaced and all three
// functions report 0. Linked into benchmark tests by cpp_policy_add_tests().

// Bytes allocated and not yet freed.
[[nodiscard]] std::uint64_t live_heap_bytes() noexcept;

// The highest live_heap_bytes() has been since the program started, or since the last
// reset_peak_heap_bytes().
[[nodiscard]] std::uint64_t peak_heap_bytes() noexcept;

// Starts a new peak at the current live bytes: call it before the work to measure.
void reset_peak_heap_bytes() noexcept;

} // namespace cpp_policy

#pragma once

#include <cstdint>
#include <expected>
#include <string>

namespace cpp_policy {

// The most memory this process has held at once so far, in bytes (POLICY.md 13.5): resident
// memory on macOS and Linux, private commit on Windows.
// It never goes down: a memory test drives some load, reads it, drives more load and reads it
// again. Linked into benchmark tests by cpp_policy_add_tests().
[[nodiscard]] std::expected<std::uint64_t, std::string> peak_memory_bytes();

} // namespace cpp_policy

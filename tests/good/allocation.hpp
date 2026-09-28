#pragma once

#include <cstddef>

namespace policy_sample {

// Element count to bytes, throwing std::bad_array_new_length on overflow: what the MSVC STL
// does in every allocation (_Get_size_of_n).
[[nodiscard]] std::size_t bytes_for(std::size_t count, std::size_t size);

// A noexcept caller: allowed, because an allocation failure isn't reported (POLICY.md 2.10).
[[nodiscard]] std::size_t buffer_bytes(std::size_t count) noexcept;

} // namespace policy_sample

#include "allocation.hpp"

#include <limits>
#include <new>

namespace policy_sample {

std::size_t bytes_for(std::size_t count, std::size_t size) {
    if (size != 0 && count > std::numeric_limits<std::size_t>::max() / size) {
        throw std::bad_array_new_length{};
    }
    return count * size;
}

std::size_t buffer_bytes(std::size_t count) noexcept {
    return bytes_for(count, sizeof(double));
}

} // namespace policy_sample

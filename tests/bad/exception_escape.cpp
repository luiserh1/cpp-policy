// POLICY 3: an exception other than an allocation failure escaping a noexcept function.
// EXPECT: bugprone-exception-escape
#include <cstddef>
#include <stdexcept>
std::size_t checked(std::size_t count) noexcept {
    if (count > 64) {
        throw std::length_error{"too many"};
    }
    return count;
}

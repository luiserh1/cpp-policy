// Confined: the environment is read through the C runtime. getenv isn't thread-safe, and the
// Windows C runtime deprecates it in favour of getenv_s (POLICY.md 2.10).
#include "lowlevel/environment.hpp"

#include <cstddef>
#include <cstdlib>

namespace lowlevel {

std::optional<std::string> environment_variable(std::string_view name) {
    const std::string key{name};
#ifdef _WIN32
    std::size_t size = 0;
    if (getenv_s(&size, nullptr, 0, key.c_str()) != 0 || size == 0) {
        return std::nullopt;
    }
    std::string value(size, '\0');
    if (getenv_s(&size, value.data(), value.size(), key.c_str()) != 0) {
        return std::nullopt;
    }
    value.resize(size - 1); // size counts the terminating null
    return value;
#else
    // NOLINTNEXTLINE(concurrency-mt-unsafe): read at startup, before any other thread runs
    const char* const value = std::getenv(key.c_str());
    if (value == nullptr) {
        return std::nullopt;
    }
    return std::string{value};
#endif
}

} // namespace lowlevel

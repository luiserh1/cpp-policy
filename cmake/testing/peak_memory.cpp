// The operating system's own record of the process's peak memory: the peak resident memory
// from getrusage() on macOS and Linux, and on Windows the peak private commit from
// GetProcessMemoryInfo(): the memory the process allocated for itself. Windows' peak working
// set also counts shared pages, and moved by a few hundred KB between identical runs; private
// commit stayed flat to the byte and showed a leak with twice the margin (POLICY.md 13.5). Code
// like this belongs in a confined area (POLICY.md 4); cpp-policy keeps it here so that projects'
// tests don't need their own.
#include "cpp_policy/peak_memory.hpp"

#ifdef _WIN32
// clang-format off: <windows.h> must come before <psapi.h>.
#include <windows.h>
#include <psapi.h>
// clang-format on
#else
#include <sys/resource.h>
#endif

#include <format>

namespace cpp_policy {

std::expected<std::uint64_t, std::string> peak_memory_bytes() {
#ifdef _WIN32
    PROCESS_MEMORY_COUNTERS counters{};
    if (GetProcessMemoryInfo(GetCurrentProcess(), &counters, sizeof(counters)) == 0) {
        return std::unexpected{
            std::format("GetProcessMemoryInfo failed: error {}", GetLastError())};
    }
    return counters.PeakPagefileUsage;
#else
    rusage usage{};
    if (getrusage(RUSAGE_SELF, &usage) != 0) {
        return std::unexpected{std::string{"getrusage failed"}};
    }
#ifdef __APPLE__
    constexpr std::uint64_t unit = 1; // macOS reports bytes
#else
    constexpr std::uint64_t unit = 1024; // Linux reports kilobytes
#endif
    // NOLINTNEXTLINE(cppcoreguidelines-pro-type-union-access): glibc declares it in a union
    return static_cast<std::uint64_t>(usage.ru_maxrss) * unit;
#endif
}

} // namespace cpp_policy

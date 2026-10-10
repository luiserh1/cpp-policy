// Waiting W5 (POLICY.md 12): correct code that clang-tidy reports with Microsoft's standard
// library. The finding, clang-analyzer-optin.core.EnumCastOutOfRange, is inside the
// library's own header (xfilesystem_abi.h), reached from each of these three calls.
#include <cstdint>
#include <filesystem>
#include <system_error>

namespace probe {

// Whether the folder is empty, how large the file is, and when it was last written.
struct Facts {
    bool empty = false;
    std::uintmax_t size = 0;
    std::filesystem::file_time_type written;
};

[[nodiscard]] Facts facts(const std::filesystem::path& folder, const std::filesystem::path& file) {
    std::error_code error;
    Facts result;
    result.empty = std::filesystem::is_empty(folder, error);
    result.size = std::filesystem::file_size(file, error);
    result.written = std::filesystem::last_write_time(file, error);
    return result;
}

} // namespace probe

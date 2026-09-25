// Waiting W2 (POLICY.md 12): time zones in libc++ on macOS. Compiles only once they exist.
#include <chrono>

int main() {
    const std::chrono::zoned_time local{std::chrono::current_zone(),
                                        std::chrono::system_clock::now()};
    return local.get_time_zone() == nullptr ? 1 : 0;
}

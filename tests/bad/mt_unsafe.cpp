// POLICY 2.8: a function that is not thread-safe (it returns a shared static buffer).
// EXPECT: concurrency-mt-unsafe
#include <ctime>

namespace {

int hour(std::time_t now) {
    const std::tm* local = std::localtime(&now);
    return local->tm_hour;
}

} // namespace

int main() {
    return hour(0);
}

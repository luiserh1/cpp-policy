// A deliberate data race: two threads increment the same int without a lock.
// Built only with CPP_POLICY_THREAD_SANITIZER, whose test must report it (POLICY.md 2.8).
#include <thread>

int main() {
    constexpr int increments = 100000;
    int counter = 0;
    {
        const auto work = [&counter] {
            for (int i = 0; i < increments; ++i) {
                ++counter;
            }
        };
        const std::jthread first{work};
        const std::jthread second{work};
    }
    return counter > 0 ? 0 : 1;
}

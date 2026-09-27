#include "tally.hpp"

#include <exception>
#include <functional>
#include <thread>
#include <vector>

namespace policy_sample {

namespace {

// The top of each thread: nothing escapes it (POLICY.md 2.8).
void add_catching(Tally& tally, int amount, std::exception_ptr& error) noexcept {
    try {
        tally.add(amount);
    } catch (...) { // boundary: thread top
        error = std::current_exception();
    }
}

} // namespace

void Tally::add(int amount) {
    const std::scoped_lock lock{mutex_};
    total_ += amount;
}

int Tally::total() const {
    const std::scoped_lock lock{mutex_};
    return total_;
}

void add_concurrently(Tally& tally, std::size_t threads, int amount) {
    // One slot per thread, so no two threads write the same element.
    std::vector<std::exception_ptr> errors(threads);
    {
        std::vector<std::jthread> workers;
        workers.reserve(threads);
        for (std::exception_ptr& error : errors) {
            workers.emplace_back(add_catching, std::ref(tally), amount, std::ref(error));
        }
    } // std::jthread joins when it goes out of scope.
    for (const std::exception_ptr& error : errors) {
        if (error) {
            std::rethrow_exception(error);
        }
    }
}

} // namespace policy_sample

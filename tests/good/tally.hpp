#pragma once

#include <cstddef>
#include <mutex>

namespace policy_sample {

// A total that several threads can add to at once (POLICY.md 2.8): the data is
// guarded by a mutex, held only while the total is touched.
class Tally {
public:
    void add(int amount);
    [[nodiscard]] int total() const;

private:
    mutable std::mutex mutex_;
    int total_ = 0;
};

// Adds `amount` to `tally` from `threads` threads at once. An exception in a
// thread is caught at the top of that thread and rethrown here, after all of
// them have finished.
void add_concurrently(Tally& tally, std::size_t threads, int amount);

} // namespace policy_sample

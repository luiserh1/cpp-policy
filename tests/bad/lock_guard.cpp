// POLICY 2.8: std::lock_guard instead of std::scoped_lock.
// EXPECT: modernize-use-scoped-lock
#include <mutex>

namespace {

std::mutex mutex;
int count = 0;

void add() {
    const std::lock_guard<std::mutex> lock{mutex};
    ++count;
}

} // namespace

int main() {
    add();
    return count;
}

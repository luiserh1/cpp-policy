// Allocates nothing itself, yet LeakSanitizer on macOS reports a leak unless cpp-policy's
// suppression list is applied (POLICY.md 5). The sanitizer runtime's own qsort gets
// thread-local storage on a system worker thread, which is still alive at the leak check.
// Built only with CPP_POLICY_SANITIZERS on macOS.
#include <dispatch/dispatch.h>

#include <array>
#include <cstdlib>

namespace {

int compare(const void* left, const void* right) {
    const int a = *static_cast<const int*>(left);
    const int b = *static_cast<const int*>(right);
    if (a < b) {
        return -1;
    }
    return a > b ? 1 : 0;
}

void sort_three(void* /*context*/) {
    std::array values{3, 1, 2};
    std::qsort(values.data(), values.size(), sizeof(int), compare);
}

} // namespace

int main() {
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_async_f(group, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), nullptr,
                           sort_three);
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    dispatch_release(group);
}

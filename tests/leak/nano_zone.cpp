// Allocates nothing itself, yet LeakSanitizer on macOS reports up to 7,168 leaks unless the
// test presets turn off the nano malloc zone (MallocNanoZone=0, POLICY.md 7). libdispatch keeps
// up to 112 freed work items per worker thread for reuse, on at most 64 threads; with the nano
// zone on, the pointers to that cache sit where LeakSanitizer doesn't look. The count stops
// growing at 112 x 64 however much work is queued, so nothing is lost.
// Built only with CPP_POLICY_SANITIZERS on macOS.
#include <dispatch/dispatch.h>

namespace {

void nothing(void* /*context*/) {}

} // namespace

int main() {
    dispatch_group_t group = dispatch_group_create();
    for (int i = 0; i < 1000; ++i) {
        dispatch_group_async_f(group, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), nullptr,
                               nothing);
    }
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    dispatch_release(group);
}

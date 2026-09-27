// Deliberate leaks: memory that is never freed. Built only with CPP_POLICY_SANITIZERS
// (not on Windows); its test must see LeakSanitizer report them (POLICY.md 7).
#include <memory>

namespace {

// release() gives up ownership; the only pointer to each int is lost at the next
// iteration. Several leaks, not one: LeakSanitizer scans the stack conservatively, and a
// single pointer left in a dead stack slot made it miss the leak on some runs (which runs
// depended on the stack address chosen by ASLR). At most one stale pointer can linger
// here, so the other leaks are always found.
int leak_some() {
    int total = 0;
    for (int i = 0; i < 8; ++i) {
        const int* leaked = std::make_unique<int>(i).release();
        total += *leaked;
    }
    return total;
}

} // namespace

int main() {
    return leak_some();
}

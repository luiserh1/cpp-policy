// A deliberate leak: memory that is never freed. Built only with CPP_POLICY_SANITIZERS
// (not on Windows); its test must see LeakSanitizer report it (POLICY.md 7).
#include <memory>

namespace {

// release() gives up ownership; the only pointer to the int is lost on return.
int leak_one() {
    const int* leaked = std::make_unique<int>(0).release();
    return *leaked;
}

} // namespace

int main() {
    return leak_one();
}

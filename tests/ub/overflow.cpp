// A signed overflow, which UndefinedBehaviorSanitizer must report and stop at: the line after
// it must never print (POLICY.md 7.3).
#include <cstdio>
#include <limits>

int main(int argc, char** /*argv*/) {
    int value = std::numeric_limits<int>::max();
    value += argc;
    std::puts("after the overflow");
    return value == 0 ? 1 : 0;
}

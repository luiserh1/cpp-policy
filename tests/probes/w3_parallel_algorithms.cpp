// Waiting W3 (POLICY.md 12): parallel algorithms in libc++ without -fexperimental-library.
// Compiles only once they are stable.
#include <algorithm>
#include <execution>
#include <vector>

int main() {
    std::vector<int> values(8);
    std::for_each(std::execution::par, values.begin(), values.end(), [](int& value) { ++value; });
    return values.front() == 1 ? 0 : 1;
}

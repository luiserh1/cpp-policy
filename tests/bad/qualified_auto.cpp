// POLICY 2.10: a pointer declared with auto says so (auto*), even with IgnoreAliasing off.
// EXPECT: readability-qualified-auto
#include <vector>

int first(const std::vector<int>& values) {
    const int* raw = values.data();
    const auto copy = raw;
    return *copy;
}

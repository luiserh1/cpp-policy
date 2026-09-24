// POLICY 3: never ignore a returned std::expected.
// EXPECT: bugprone-unused-return-value
#include <expected>

std::expected<int, int> load(int key);

void caller() {
    load(1);
}

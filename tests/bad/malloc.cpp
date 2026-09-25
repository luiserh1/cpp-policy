// POLICY 2.1: malloc / free.
// EXPECT: cppcoreguidelines-no-malloc
#include <cstdlib>
void scratch() {
    void* p = std::malloc(4);
    std::free(p);
}

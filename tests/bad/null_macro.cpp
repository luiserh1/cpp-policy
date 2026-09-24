// POLICY 2.3: NULL / 0 as a pointer.
// EXPECT: modernize-use-nullptr
#include <cstddef>

const int* nothing() {
    return NULL;
}

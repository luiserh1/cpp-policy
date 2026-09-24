// POLICY 2.2: C variadic functions.
// EXPECT: cppcoreguidelines-pro-type-vararg
#include <cstdio>

void say(int n) {
    std::printf("%d\n", n);
}

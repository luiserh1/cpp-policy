// POLICY 2.2 in a header: headers are checked too (HeaderFilterRegex in .clang-tidy).
// EXPECT: cppcoreguidelines-avoid-c-arrays
#include "in_header.hpp"

int use() {
    return first_value();
}

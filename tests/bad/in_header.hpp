#pragma once

// The violation is in this header, not in the .cpp that clang-tidy runs on.
inline int first_value() {
    const int values[3] = {1, 2, 3};
    return values[0];
}

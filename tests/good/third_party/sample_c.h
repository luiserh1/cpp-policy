/* A stand-in for a single-header C library such as stb_image: C code compiled into the
   project, under a directory clang-tidy's ExcludeHeaderFilterRegex excludes. It leaks on one
   path, which the static analyzer finds (POLICY.md 5, third-party code). */
#pragma once

#include <stdlib.h>
#include <string.h>

static inline int sample_c_sum(const unsigned char* data, int size) {
    unsigned char* copy = (unsigned char*)malloc((size_t)size);
    if (copy == NULL) {
        return -1;
    }
    if (size > 64) {
        return -1; /* leaks copy */
    }
    memcpy(copy, data, (size_t)size);
    int sum = 0;
    for (int i = 0; i < size; ++i) {
        sum += copy[i];
    }
    free(copy);
    return sum;
}

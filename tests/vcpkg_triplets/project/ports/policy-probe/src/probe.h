#pragma once
/* cpp-policy self-test: a dependency that reports how vcpkg compiled it. */
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Adds up the size bytes that start at data. */
size_t probe_sum(const unsigned char* data, size_t size);

/* How probe.c was compiled: "compiler=clang-23 sanitizer=address ssp=strong fortify=0". */
const char* probe_c_build(void);

/* How probe.cpp was compiled: the same, plus its standard library and hardening mode. */
const char* probe_cpp_build(void);

#ifdef __cplusplus
}
#endif

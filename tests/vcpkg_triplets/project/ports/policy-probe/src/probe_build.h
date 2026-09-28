#pragma once
/* What the compiler command line asked for. Include it before any other header, so that no
   system header has defined _FORTIFY_SOURCE yet. */

#define PROBE_STRING_(x) #x
#define PROBE_STRING(x) PROBE_STRING_(x)

#if defined(__apple_build_version__)
#define PROBE_COMPILER "apple-clang"
#elif defined(__clang__)
#define PROBE_COMPILER "clang-" PROBE_STRING(__clang_major__)
#elif defined(_MSC_VER)
#define PROBE_COMPILER "msvc"
#elif defined(__GNUC__)
#define PROBE_COMPILER "gcc"
#else
#define PROBE_COMPILER "unknown"
#endif

#if defined(__has_feature)
#if __has_feature(address_sanitizer)
#define PROBE_SANITIZER "address"
#elif __has_feature(thread_sanitizer)
#define PROBE_SANITIZER "thread"
#endif
#endif
#if !defined(PROBE_SANITIZER) && defined(__SANITIZE_ADDRESS__)
#define PROBE_SANITIZER "address"
#endif
#ifndef PROBE_SANITIZER
#define PROBE_SANITIZER "none"
#endif

#if defined(__SSP_STRONG__)
#define PROBE_SSP "strong"
#elif defined(__SSP_ALL__)
#define PROBE_SSP "all"
#elif defined(__SSP__)
#define PROBE_SSP "basic"
#else
#define PROBE_SSP "none"
#endif

#if defined(_FORTIFY_SOURCE)
#define PROBE_FORTIFY PROBE_STRING(_FORTIFY_SOURCE)
#else
#define PROBE_FORTIFY "0"
#endif

#define PROBE_BUILD                                                                            \
    "compiler=" PROBE_COMPILER " sanitizer=" PROBE_SANITIZER " ssp=" PROBE_SSP                \
    " fortify=" PROBE_FORTIFY

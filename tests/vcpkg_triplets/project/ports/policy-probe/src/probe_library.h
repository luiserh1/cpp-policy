#pragma once
/* The C++ standard library and its hardening mode (C++ only). <version> defines the macros each
   library identifies itself with. */
#include <version>

#if defined(_LIBCPP_VERSION)
#define PROBE_LIBRARY "libc++-" PROBE_STRING(_LIBCPP_VERSION)
#if !defined(_LIBCPP_HARDENING_MODE)
#define PROBE_HARDENING "none"
#elif _LIBCPP_HARDENING_MODE == _LIBCPP_HARDENING_MODE_DEBUG
#define PROBE_HARDENING "debug"
#elif _LIBCPP_HARDENING_MODE == _LIBCPP_HARDENING_MODE_EXTENSIVE
#define PROBE_HARDENING "extensive"
#elif _LIBCPP_HARDENING_MODE == _LIBCPP_HARDENING_MODE_FAST
#define PROBE_HARDENING "fast"
#else
#define PROBE_HARDENING "none"
#endif
#elif defined(__GLIBCXX__)
#define PROBE_LIBRARY "libstdc++-" PROBE_STRING(__GLIBCXX__)
#if defined(_GLIBCXX_ASSERTIONS)
#define PROBE_HARDENING "assertions"
#else
#define PROBE_HARDENING "none"
#endif
#elif defined(_MSVC_STL_UPDATE)
#define PROBE_LIBRARY "msvc-stl-" PROBE_STRING(_MSVC_STL_UPDATE)
#if defined(_MSVC_STL_HARDENING) && _MSVC_STL_HARDENING
#define PROBE_HARDENING "on"
#else
#define PROBE_HARDENING "none"
#endif
#else
#define PROBE_LIBRARY "unknown"
#define PROBE_HARDENING "unknown"
#endif

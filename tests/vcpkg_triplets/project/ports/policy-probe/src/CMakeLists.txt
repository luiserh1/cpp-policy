cmake_minimum_required(VERSION 3.29)
project(policy_probe LANGUAGES C CXX)

# A C file and a C++ file: vcpkg builds both kinds, and the C++ one uses the standard library.
add_library(policy_probe STATIC probe.c probe.cpp)
install(TARGETS policy_probe ARCHIVE DESTINATION lib)
install(FILES probe.h probe_build.h probe_library.h DESTINATION include)

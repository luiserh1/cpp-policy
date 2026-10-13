cmake_minimum_required(VERSION 3.29)
project(bypass_library_needs_policy LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

# A library that relies on a release this build's policy isn't.
cpp_policy_library(sample
    LAYER text
    SOURCES text/text.cpp
    NEEDS_POLICY 99.0.0)
cpp_policy_add_checks()

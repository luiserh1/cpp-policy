cmake_minimum_required(VERSION 3.29)
project(bypass_includes_none_twice LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
enable_testing()
cpp_policy_confine_includes(zlib.h TO server)
# Lines add up, so this one would do nothing.
cpp_policy_confine_includes(zlib.h TO NONE)
cpp_policy_add_checks()

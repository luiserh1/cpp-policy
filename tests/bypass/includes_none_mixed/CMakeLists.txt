cmake_minimum_required(VERSION 3.29)
project(bypass_includes_none_mixed LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
enable_testing()
# NONE and a module on one line say two things.
cpp_policy_confine_includes(zlib.h TO NONE server)
cpp_policy_add_checks()

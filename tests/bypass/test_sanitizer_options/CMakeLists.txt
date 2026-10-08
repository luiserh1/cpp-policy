cmake_minimum_required(VERSION 3.29)
project(bypass_test_sanitizer_options LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
enable_testing()
# A test may not switch a sanitizer's check off through its environment.
cpp_policy_add_tests(integration app SOURCES app.cpp ENVIRONMENT "ASAN_OPTIONS=detect_leaks=0")
cpp_policy_add_checks()

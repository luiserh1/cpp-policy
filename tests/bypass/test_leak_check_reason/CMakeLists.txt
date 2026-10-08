cmake_minimum_required(VERSION 3.29)
project(bypass_test_leak_check_reason LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
enable_testing()
cpp_policy_add_tests(integration app SOURCES app.cpp NO_LEAK_CHECK "macOS")
cpp_policy_add_checks()

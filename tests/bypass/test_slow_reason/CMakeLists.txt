cmake_minimum_required(VERSION 3.29)
project(bypass_test_slow_reason LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
enable_testing()
cpp_policy_add_tests(integration app SOURCES app.cpp TIMEOUT 120 SLOW "big")
cpp_policy_add_checks()

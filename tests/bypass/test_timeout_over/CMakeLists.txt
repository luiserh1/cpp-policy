cmake_minimum_required(VERSION 3.29)
project(bypass_test_timeout_over LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
enable_testing()
# More than 60 seconds without saying why.
cpp_policy_add_tests(integration app SOURCES app.cpp TIMEOUT 120)
cpp_policy_add_checks()

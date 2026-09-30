cmake_minimum_required(VERSION 3.29)
project(bypass_test_unnamed LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
enable_testing()
add_test(NAME smoke COMMAND app)
cpp_policy_add_checks()

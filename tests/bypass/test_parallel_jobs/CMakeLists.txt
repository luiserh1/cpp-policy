cmake_minimum_required(VERSION 3.29)
project(bypass_test_parallel_jobs LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
enable_testing()
# The number of jobs is the presets', not a project's.
cpp_policy_parallel_tests(8)
cpp_policy_add_checks()

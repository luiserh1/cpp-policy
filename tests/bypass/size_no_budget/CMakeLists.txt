cmake_minimum_required(VERSION 3.29)
project(bypass_size_no_budget LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
# No budget on any system: a notice, not an error.
cpp_policy_size_budget(app)
cpp_policy_add_checks()

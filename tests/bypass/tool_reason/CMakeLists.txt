cmake_minimum_required(VERSION 3.29)
project(bypass_tool_reason LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(recorder app.cpp)
cpp_policy_apply(recorder)
# A development program needs to say what it is for.
cpp_policy_tool(recorder "x")
cpp_policy_add_checks()

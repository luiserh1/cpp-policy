cmake_minimum_required(VERSION 3.29)
project(bypass_tool_noted LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(recorder app.cpp)
cpp_policy_apply(recorder)
# A development program: configured, and its reason said; no size budget is asked for.
cpp_policy_tool(recorder "records every frame the window draws, for its tests")
cpp_policy_add_checks()
message(STATUS "tool_noted: configured")

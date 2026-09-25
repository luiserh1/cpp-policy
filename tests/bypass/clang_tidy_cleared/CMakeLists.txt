cmake_minimum_required(VERSION 3.29)
project(bypass_clang_tidy_cleared LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
set_target_properties(app PROPERTIES CXX_CLANG_TIDY "")
cpp_policy_add_checks()

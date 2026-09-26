cmake_minimum_required(VERSION 3.29)
project(bypass_hardening_option LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
# clang-cl accepts both prefixes, so the audit must catch both.
target_compile_options(app PRIVATE /GS- -guard:cf-)
cpp_policy_add_checks()

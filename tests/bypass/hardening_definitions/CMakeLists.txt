cmake_minimum_required(VERSION 3.29)
project(bypass_hardening_definitions LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
target_compile_definitions(app PRIVATE _LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_NONE
    _FORTIFY_SOURCE=1)
cpp_policy_add_checks()

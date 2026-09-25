cmake_minimum_required(VERSION 3.29)
project(bypass_warning_option LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
target_compile_options(app PRIVATE -Wno-conversion)
cpp_policy_add_checks()

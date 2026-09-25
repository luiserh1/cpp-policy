cmake_minimum_required(VERSION 3.29)
project(bypass_unapplied LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
add_library(extra STATIC app.cpp)
cpp_policy_add_checks()

cmake_minimum_required(VERSION 3.29)
project(bypass_size_not_built_here LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
# A program said not to be built on the system that is building it.
cpp_policy_size_budget(app MACOS NOT_BUILT LINUX NOT_BUILT WINDOWS NOT_BUILT)
cpp_policy_add_checks()

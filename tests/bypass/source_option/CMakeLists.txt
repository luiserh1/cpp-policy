cmake_minimum_required(VERSION 3.29)
project(bypass_source_option LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
set_source_files_properties(app.cpp TARGET_DIRECTORY app PROPERTIES COMPILE_OPTIONS -w)
cpp_policy_add_checks()

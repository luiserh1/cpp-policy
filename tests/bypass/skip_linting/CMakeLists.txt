cmake_minimum_required(VERSION 3.29)
project(bypass_skip_linting LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
set_source_files_properties(app.cpp TARGET_DIRECTORY app PROPERTIES SKIP_LINTING ON)
cpp_policy_add_checks()

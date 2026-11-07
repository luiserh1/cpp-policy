cmake_minimum_required(VERSION 3.29)
project(bypass_confined_dirs LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

# Only cpp-policy sets the confined directories (POLICY.md 4, 6).
list(APPEND CPP_POLICY_CONFINED_DIRS src/fast)
add_executable(app app.cpp)
cpp_policy_apply(app)
cpp_policy_add_checks()

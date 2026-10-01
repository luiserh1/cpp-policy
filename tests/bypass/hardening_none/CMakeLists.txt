cmake_minimum_required(VERSION 3.29)
project(bypass_hardening_none LANGUAGES CXX)
# Set by the project itself, before the module's default.
set(CPP_POLICY_HARDENING none)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
cpp_policy_add_checks()

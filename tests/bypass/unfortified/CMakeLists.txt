cmake_minimum_required(VERSION 3.29)
project(bypass_unfortified LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
# Undefining _FORTIFY_SOURCE is refused; the policy's own pair (-U then -D_FORTIFY_SOURCE=3,
# in cpp_policy_apply) is not reported.
set_source_files_properties(app.cpp PROPERTIES COMPILE_OPTIONS "SHELL:-U_FORTIFY_SOURCE")
cpp_policy_add_checks()

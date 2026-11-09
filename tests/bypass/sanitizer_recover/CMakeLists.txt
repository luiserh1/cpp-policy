cmake_minimum_required(VERSION 3.29)
project(bypass_sanitizer_recover LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
# Recovering after a sanitizer's finding prints it and lets the test pass: refused, for one
# group of checks and for all of them.
target_compile_options(app PRIVATE -fsanitize-recover=undefined)
set_source_files_properties(app.cpp PROPERTIES COMPILE_OPTIONS "SHELL:-fsanitize-recover=all")
cpp_policy_add_checks()

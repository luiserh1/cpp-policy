cmake_minimum_required(VERSION 3.29)
project(bypass_unfortified_spellings LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
# The policy's own pair, copied behind -Wp,: only the pair itself, as two list elements, is
# exempt. And the macro as a word of its own, in one option and across two.
target_compile_options(app PRIVATE -Wp,$<$<NOT:$<CONFIG:Debug>>:-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3>)
target_compile_options(app PRIVATE "SHELL:-U _FORTIFY_SOURCE")
target_compile_options(app PRIVATE -D _FORTIFY_SOURCE=0)
cpp_policy_add_checks()

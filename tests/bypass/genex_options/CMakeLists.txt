cmake_minimum_required(VERSION 3.29)
project(bypass_genex_options LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
# The same options as protection_options, hidden in generator expressions and SHELL:.
target_compile_options(app PRIVATE $<$<CONFIG:Release>:-fno-stack-protector> $<1:-w>
    "SHELL:-fcf-protection=none" $<$<NOT:$<CONFIG:Debug>>:/guard:cf->)
target_compile_definitions(app PRIVATE $<1:_FORTIFY_SOURCE=1>)
cpp_policy_add_checks()

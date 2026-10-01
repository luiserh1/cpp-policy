cmake_minimum_required(VERSION 3.29)
project(bypass_protection_options LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
target_compile_options(app PRIVATE -fno-stack-protector -fcf-protection=none -D_FORTIFY_SOURCE=0
    -fno-sanitize=address -U_GLIBCXX_ASSERTIONS)
cpp_policy_add_checks()

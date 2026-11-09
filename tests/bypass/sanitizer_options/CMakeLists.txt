cmake_minimum_required(VERSION 3.29)
project(bypass_sanitizer_options LANGUAGES CXX)
set(CPP_POLICY_SANITIZERS ON CACHE BOOL "" FORCE)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
# Sanitizer options are the policy's: any other is refused, and so is a route into the
# compiler's internals. The policy's own options, which cpp_policy_apply has just added to
# this target, are not reported (reject.txt).
target_compile_options(app PRIVATE -fno-sanitize-address-use-after-scope)
target_compile_options(app PRIVATE "SHELL:-mllvm -asan-instrument-reads=0")
target_compile_options(app PRIVATE -Xclang -disable-llvm-passes)
set_source_files_properties(app.cpp PROPERTIES COMPILE_OPTIONS
    "$<$<CONFIG:Debug>:-fsanitize-address-use-after-return=never>")
cpp_policy_add_checks()

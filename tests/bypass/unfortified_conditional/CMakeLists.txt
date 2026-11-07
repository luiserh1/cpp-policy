cmake_minimum_required(VERSION 3.29)
project(bypass_unfortified_conditional LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
# A definition under a condition that doesn't hold restores nothing, and -Wp, passes options
# to the preprocessor: each of these leaves the release build without fortify.
target_compile_options(app PRIVATE -U_FORTIFY_SOURCE $<$<CONFIG:Debug>:-D_FORTIFY_SOURCE=3>
    -Wp,-U_FORTIFY_SOURCE -Wp,-D_FORTIFY_SOURCE=1)
cpp_policy_add_checks()

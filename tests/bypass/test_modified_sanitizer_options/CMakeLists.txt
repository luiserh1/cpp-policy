cmake_minimum_required(VERSION 3.29)
project(bypass_test_modified_sanitizer_options LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
enable_testing()
# ENVIRONMENT_MODIFICATION reaches the same variables as ENVIRONMENT, so it is refused the same.
add_test(NAME integration/app/starts COMMAND app)
set_tests_properties(integration/app/starts PROPERTIES LABELS integration
    ENVIRONMENT_MODIFICATION "ASAN_OPTIONS=set:detect_leaks=0")
cpp_policy_add_checks()

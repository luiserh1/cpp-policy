cmake_minimum_required(VERSION 3.29)
project(bypass_test_plain_sanitizer_options LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
enable_testing()
add_test(NAME integration/app/starts COMMAND app)
set_tests_properties(integration/app/starts PROPERTIES LABELS integration
    ENVIRONMENT "LSAN_OPTIONS=detect_leaks=0")
cpp_policy_add_checks()

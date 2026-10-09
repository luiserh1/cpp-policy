# A project that uses another policy project's library (cpp-policy's self-test of
# POLICY.md 11.7, run by tests/library/run.cmake). It has modules with the library's own
# names, lowlevel and app, which is why the library's includes carry its name.
cmake_minimum_required(VERSION 3.29)
project(user_project LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

# The self-test points FETCHCONTENT_SOURCE_DIR_GEOMETRY at its copy of the library's project,
# so nothing is fetched from this address.
cpp_policy_use_library(geometry
    GIT_REPOSITORY https://example.invalid/geometry.git
    GIT_TAG        89abcdef0123456789abcdef0123456789abcdef) # v1.2.0

add_executable(user src/main.cpp src/app/summary.cpp src/lowlevel/host.cpp)
target_include_directories(user PRIVATE src)
target_link_libraries(user PRIVATE geometry::geometry)
cpp_policy_apply(user)

# A test program that uses what the library offers to tests.
add_executable(user_samples tests/samples.cpp)
target_link_libraries(user_samples PRIVATE geometry::test_support)
cpp_policy_apply(user_samples)

enable_testing()
add_test(NAME integration/app/the_library_offers_test_support COMMAND user_samples)
set_tests_properties(integration/app/the_library_offers_test_support PROPERTIES
    LABELS integration)
add_test(NAME integration/app/the_library_answers COMMAND user)
set_tests_properties(integration/app/the_library_answers PROPERTIES LABELS integration
    PASS_REGULAR_EXPRESSION "area 12 on a host with a name, clock runs")

cpp_policy_layers(LAYER lowlevel LAYER app)
# Which of this project's modules may include the library. The self-test changes it to show
# that the audit holds it.
if(NOT DEFINED LIBRARY_USERS)
    set(LIBRARY_USERS app)
endif()
cpp_policy_confine_includes(geometry/ TO ${LIBRARY_USERS})
cpp_policy_add_checks()

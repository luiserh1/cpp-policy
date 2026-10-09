# A project that offers a library and has a program of its own (cpp-policy's self-test of
# POLICY.md 11.7, run by tests/library/run.cmake). A user of the library never runs this file.
cmake_minimum_required(VERSION 3.29)
project(geometry_project LANGUAGES CXX)

if(DEFINED POLICY_ROOT)
    # The self-test: this checkout of cpp-policy.
    include("${POLICY_ROOT}/cmake/CppPolicy.cmake")
else()
    include(FetchContent)
    FetchContent_Declare(cpp_policy
        GIT_REPOSITORY https://github.com/luiserh1/cpp-policy.git
        GIT_TAG        0123456789abcdef0123456789abcdef01234567) # v0.30.0
    FetchContent_MakeAvailable(cpp_policy)
endif()

# The library: lib/geometry/, declared in the one file its users include too.
include(library.cmake)

# The program, over it.
add_executable(areas src/main.cpp src/app/report.cpp)
target_include_directories(areas PRIVATE src)
target_link_libraries(areas PRIVATE geometry::geometry)
cpp_policy_apply(areas)

cpp_policy_layers(LAYER app)
cpp_policy_add_checks()

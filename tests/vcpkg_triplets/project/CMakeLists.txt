# cpp-policy self-test (tests/vcpkg_triplets/run.cmake): a project whose one dependency, the
# local vcpkg port in ports/, reports how vcpkg compiled it.
cmake_minimum_required(VERSION 3.29)

include("${POLICY_ROOT}/tools/vcpkg/setup.cmake")

project(PolicyProbe LANGUAGES CXX)

include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

find_path(PROBE_INCLUDE_DIR probe.h REQUIRED)
find_library(PROBE_LIBRARY policy_probe REQUIRED)
foreach(program IN ITEMS build_info overread)
    add_executable(${program} ${program}.cpp)
    cpp_policy_apply(${program})
    target_include_directories(${program} SYSTEM PRIVATE "${PROBE_INCLUDE_DIR}")
    target_link_libraries(${program} PRIVATE "${PROBE_LIBRARY}")
endforeach()

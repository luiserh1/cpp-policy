cmake_minimum_required(VERSION 3.29)
project(cpp_policy VERSION 0.29.0 LANGUAGES CXX)

include(cmake/CppPolicy.cmake)

# When consumed through FetchContent, only the functions above are provided.
# When built on its own, cpp-policy tests itself.
if(PROJECT_IS_TOP_LEVEL)
    # cmake/testing holds the operating-system code benchmark tests link (peak_memory.cpp, heap_bytes.cpp).
    set(CPP_POLICY_CONFINED_DIRS "tests/good/lowlevel;cmake/testing")
    # The audit fixtures and bad samples violate the policy on purpose. template/ is checked as
    # a generated project by tests/new_project, where it has its own layers and confined area.
    # tests/new_project holds files added to that generated project, checked there too: they
    # need its doctest. The vcpkg port in tests/vcpkg_triplets stands for a third-party
    # dependency (C code).
    list(APPEND CPP_POLICY_EXCLUDED_DIRS tests/audit tests/bad tests/bypass tests/format template
        tests/new_project tests/vcpkg_triplets/project/ports)
    enable_testing()
    cpp_policy_add_checks()
    add_subdirectory(tests)
endif()

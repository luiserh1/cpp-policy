cmake_minimum_required(VERSION 3.29)
project(cpp_policy VERSION 0.19.1 LANGUAGES CXX)

include(cmake/CppPolicy.cmake)

# When consumed through FetchContent, only the functions above are provided.
# When built on its own, cpp-policy tests itself.
if(PROJECT_IS_TOP_LEVEL)
    set(CPP_POLICY_CONFINED_DIRS "tests/good/lowlevel")
    # The audit fixtures and bad samples violate the policy on purpose. template/ is checked as
    # a generated project by tests/new_project, where it has its own layers and confined area.
    # The vcpkg port in tests/vcpkg_triplets stands for a third-party dependency (C code).
    list(APPEND CPP_POLICY_EXCLUDED_DIRS tests/audit tests/bad tests/bypass tests/format template
        tests/vcpkg_triplets/project/ports)
    enable_testing()
    cpp_policy_add_checks()
    add_subdirectory(tests)
endif()

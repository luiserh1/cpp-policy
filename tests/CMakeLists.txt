# --- Good code: must build with every check enabled and pass its tests -------
add_library(policy_good good/buffer.cpp good/lowlevel/packed_header.cpp)
target_include_directories(policy_good PUBLIC good)
cpp_policy_apply(policy_good)

add_executable(policy_good_test good/main.cpp)
target_link_libraries(policy_good_test PRIVATE policy_good)
cpp_policy_apply(policy_good_test)
add_test(NAME good/run COMMAND policy_good_test)

# --- Bad samples: each must be rejected with the check named in its EXPECT line
file(GLOB bad_samples CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/bad/*.cpp")
add_library(policy_bad_samples OBJECT EXCLUDE_FROM_ALL ${bad_samples})
cpp_policy_apply(policy_bad_samples)
# Only listed so they appear in compile_commands.json; the tests below run clang-tidy on them.
set_target_properties(policy_bad_samples PROPERTIES CXX_CLANG_TIDY "")

foreach(sample IN LISTS bad_samples)
    cmake_path(GET sample STEM name)
    file(STRINGS "${sample}" expect REGEX "^// EXPECT: ")
    if(NOT expect)
        message(FATAL_ERROR "${sample}: missing '// EXPECT: <check-name>' line")
    endif()
    string(REPLACE "// EXPECT: " "" check "${expect}")
    add_test(NAME bad/${name}
        COMMAND "${CPP_POLICY_CLANG_TIDY_EXE}" "--config-file=${CPP_POLICY_ROOT}/.clang-tidy"
                -p "${CMAKE_BINARY_DIR}" "${sample}")
    # The run must fail AND report the expected check as an error.
    set_tests_properties(bad/${name} PROPERTIES
        PASS_REGULAR_EXPRESSION "error: [^\n]*[[,]${check}[],]")
endforeach()

# --- Format fixtures: files that must already be formatted (clang-format must not change them)
file(GLOB format_fixtures "${CMAKE_CURRENT_SOURCE_DIR}/format/*.cpp")
foreach(fixture IN LISTS format_fixtures)
    cmake_path(GET fixture STEM name)
    add_test(NAME format/${name}
        COMMAND "${CPP_POLICY_CLANG_FORMAT_EXE}" --dry-run --Werror
                "--style=file:${CPP_POLICY_ROOT}/.clang-format" "${fixture}")
endforeach()

# --- Audit fixtures: each directory is a mini project; expect.txt holds a regex
file(GLOB audit_cases LIST_DIRECTORIES true "${CMAKE_CURRENT_SOURCE_DIR}/audit/*")
foreach(case IN LISTS audit_cases)
    if(NOT IS_DIRECTORY "${case}")
        continue()
    endif()
    cmake_path(GET case FILENAME name)
    file(READ "${case}/expect.txt" expect)
    string(STRIP "${expect}" expect)
    set(config "${CMAKE_CURRENT_BINARY_DIR}/audit_${name}.cmake")
    file(WRITE "${config}"
        "set(SOURCE_DIR [==[${case}]==])\n"
        "set(POLICY_ROOT [==[${CPP_POLICY_ROOT}]==])\n"
        "set(CONFINED_DIRS [==[src/lowlevel]==])\n"
        "set(EXCLUDED_DIRS [==[]==])\n")
    add_test(NAME audit/${name}
        COMMAND "${CMAKE_COMMAND}" -DCONFIG=${config} -P "${CPP_POLICY_ROOT}/cmake/scripts/audit_suppressions.cmake")
    set_tests_properties(audit/${name} PROPERTIES PASS_REGULAR_EXPRESSION "${expect}")
endforeach()

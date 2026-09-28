# clang-tidy on chosen files, with the policy's configuration (POLICY.md 8): the quick check
# after an edit, and pre-commit's check of the staged files. tools/hooks/tidy-files runs it.
#
#   cmake -DCONFIG=<build>/cpp_policy_config.cmake "-DFILES=a.cpp;b.hpp" -P tidy_files.cmake
#
# Files that aren't C++ sources, are in excluded directories or third-party code, or no longer
# exist are skipped. Third-party code is what .clang-tidy's ExcludeHeaderFilterRegex matches
# (a third_party/ directory at any depth, for example), read from it so the two agree.
# A source file this build doesn't compile (another platform's) is skipped with a note: it
# can't be parsed here, and CI checks it on its own system. Headers are checked on their own,
# with the compile flags of a similar source file (clang-tidy infers them). Exits with an error
# if any file has findings; the findings are printed as the build prints them.

cmake_minimum_required(VERSION 3.29)
include("${CMAKE_CURRENT_LIST_DIR}/source_files.cmake")
include("${CONFIG}")

if(NOT EXISTS "${BUILD_DIR}/compile_commands.json")
    message(FATAL_ERROR "tidy-files: ${BUILD_DIR}/compile_commands.json is missing; configure "
                        "the preset first (cmake --preset <preset>)")
endif()

# The sources this build compiles, as real paths.
file(READ "${BUILD_DIR}/compile_commands.json" database)
string(JSON entries LENGTH "${database}")
set(compiled "")
if(entries GREATER 0)
    math(EXPR last "${entries} - 1")
    foreach(index RANGE ${last})
        string(JSON path GET "${database}" ${index} file)
        file(REAL_PATH "${path}" path)
        list(APPEND compiled "${path}")
    endforeach()
endif()

# .clang-tidy's ExcludeHeaderFilterRegex: '(/_deps/|/third_party/|...)'.
file(STRINGS "${POLICY_ROOT}/.clang-tidy" third_party REGEX "^ExcludeHeaderFilterRegex:")
string(REGEX REPLACE "^ExcludeHeaderFilterRegex: *'(.*)'$" "\\1" third_party "${third_party}")
if(third_party STREQUAL "")
    message(FATAL_ERROR "tidy-files: no ExcludeHeaderFilterRegex in ${POLICY_ROOT}/.clang-tidy")
endif()

set(extensions "")
foreach(glob IN LISTS CPP_POLICY_SOURCE_GLOBS)
    string(REPLACE "*" "" extension "${glob}")
    list(APPEND extensions "${extension}")
endforeach()

set(checked 0)
set(failed "")
foreach(file IN LISTS FILES)
    file(REAL_PATH "${file}" path BASE_DIRECTORY "${SOURCE_DIR}")
    cmake_path(GET path EXTENSION LAST_ONLY extension)
    if(NOT EXISTS "${path}" OR NOT extension IN_LIST extensions)
        continue()
    endif()
    file(RELATIVE_PATH relative "${SOURCE_DIR}" "${path}")
    cpp_policy_in_dirs("${relative}" "${EXCLUDED_DIRS}" excluded)
    if(relative MATCHES "^\\.\\./" OR excluded OR "/${relative}" MATCHES "${third_party}")
        continue()
    endif()
    if(extension MATCHES "^\\.(cpp|cc|cxx)$" AND NOT path IN_LIST compiled)
        message("tidy-files: ${relative}: not built on this system, skipped (CI checks it)")
        continue()
    endif()
    execute_process(
        COMMAND "${CLANG_TIDY}" "--config-file=${POLICY_ROOT}/.clang-tidy" --quiet
                -p "${BUILD_DIR}" "${path}"
        WORKING_DIRECTORY "${SOURCE_DIR}"
        RESULT_VARIABLE result)
    math(EXPR checked "${checked} + 1")
    if(NOT result EQUAL 0)
        list(APPEND failed "${relative}")
    endif()
endforeach()

if(failed)
    list(JOIN failed "\n  " failed_list)
    message(FATAL_ERROR "tidy-files: clang-tidy findings in:\n  ${failed_list}")
endif()
message("tidy-files: OK (${checked} files)")

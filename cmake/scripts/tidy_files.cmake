# What the gate will say about chosen files, without the tests (POLICY.md 8): the format
# check, the audit's rules about one file (length, suppressions, `// boundary:`, test-case
# names) and clang-tidy with the policy's configuration. The quick check after an edit, and
# pre-commit's check of the staged files. tools/hooks/tidy-files runs it.
#
#   cmake -DCONFIG=<build>/cpp_policy_config.cmake "-DFILES=a.cpp;b.hpp" -P tidy_files.cmake
#
# Files that aren't C++ sources, are in excluded directories or third-party code, or no longer
# exist are skipped. Third-party code is what .clang-tidy's ExcludeHeaderFilterRegex matches
# (a third_party/ directory at any depth, for example), read from it so the two agree.
# A source file this build doesn't compile is first looked for again after configuring once
# more (a file added since the last configure). If it still isn't compiled (another platform's)
# it is skipped with a note and counted in the summary: it can't be parsed here, and CI checks
# it on its own system. A header is checked through a source of this build that includes it,
# with that source's own compile flags and only the header's findings shown: that is how the
# build sees it. A header no source includes directly is checked on its own, with the flags
# of a similar source file (clang-tidy infers them). Exits with an error if any file has
# findings; the findings are printed as the build prints them.

cmake_minimum_required(VERSION 3.29)
include("${CMAKE_CURRENT_LIST_DIR}/source_files.cmake")
include("${CONFIG}")

if(NOT EXISTS "${BUILD_DIR}/compile_commands.json")
    message(FATAL_ERROR "tidy-files: ${BUILD_DIR}/compile_commands.json is missing; configure "
                        "the preset first (cmake --preset <preset>)")
endif()

# The sources this build compiles, as real paths.
function(read_compiled out)
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
    set(${out} "${compiled}" PARENT_SCOPE)
endfunction()
read_compiled(compiled)
set(reconfigured FALSE)

# Test programs' sources, and test headers, are checked with the option the build
# gives them (cpp_policy_add_tests(); POLICY.md 13.4). The file is written when the project is
# configured.
set(TEST_SOURCES "")
set(TEST_TIDY_CHECKS "")
# The build's copy of the policy's .clang-tidy: on Windows it has one check fewer (Waiting
# W5, POLICY.md 12), and this must say what the build will say.
set(TIDY_CONFIG "${POLICY_ROOT}/.clang-tidy")
include("${BUILD_DIR}/cpp_policy_tests.cmake" OPTIONAL)
# A header is test code when it is in a test source's folder, or anywhere under the top-level
# folder the test sources are in (tests/support/ for sources in tests/unit/), unless that
# folder is src/: the program's headers keep every check even if a test sits among them.
function(read_tests)
    set(sources "")
    set(dirs "")
    set(roots "")
    foreach(source IN LISTS TEST_SOURCES)
        file(REAL_PATH "${source}" source)
        list(APPEND sources "${source}")
        cmake_path(GET source PARENT_PATH dir)
        list(APPEND dirs "${dir}")
        file(RELATIVE_PATH relative "${real_source_dir}" "${source}")
        if(relative MATCHES "^([^/]+)/" AND NOT CMAKE_MATCH_1 STREQUAL "src"
           AND NOT CMAKE_MATCH_1 STREQUAL "..")
            list(APPEND roots "${real_source_dir}/${CMAKE_MATCH_1}/")
        endif()
    endforeach()
    list(REMOVE_DUPLICATES roots)
    set(test_sources "${sources}" PARENT_SCOPE)
    set(test_dirs "${dirs}" PARENT_SCOPE)
    set(test_roots "${roots}" PARENT_SCOPE)
endfunction()
file(REAL_PATH "${SOURCE_DIR}" real_source_dir)
read_tests()

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

# A source of this build that includes the header directly: the include's text must be the
# end of the header's path, so that another module's header of the same name doesn't count.
function(including_source header out)
    set(${out} "" PARENT_SCOPE)
    cmake_path(GET header FILENAME name)
    string(REGEX REPLACE "([][+.*()^$?|\\\\])" "\\\\\\1" name_regex "${name}")
    foreach(source IN LISTS compiled)
        if(NOT EXISTS "${source}")
            continue()
        endif()
        file(STRINGS "${source}" includes REGEX "^[ \t]*#[ \t]*include[ \t]*\"([^\"]*/)?${name_regex}\"")
        foreach(line IN LISTS includes)
            if(line MATCHES "\"([^\"]+)\"")
                set(included "${CMAKE_MATCH_1}")
                string(REGEX REPLACE "^(\\.\\./|\\./)+" "" included "${included}")
                string(LENGTH "${header}" header_length)
                string(LENGTH "/${included}" included_length)
                if(header_length GREATER included_length)
                    math(EXPR start "${header_length} - ${included_length}")
                    string(SUBSTRING "${header}" ${start} -1 tail)
                    if(tail STREQUAL "/${included}")
                        set(${out} "${source}" PARENT_SCOPE)
                        return()
                    endif()
                endif()
            endif()
        endforeach()
    endforeach()
endfunction()

set(checked 0)
set(skipped 0)
set(failed "")
set(other_failures "")

# The checks that need no compiler first: they take a second, and the build would report
# them only at its end.
execute_process(
    COMMAND "${CMAKE_COMMAND}" "-DCONFIG=${CONFIG}" "-DFILES=${FILES}" -DMODE=check
            -P "${CMAKE_CURRENT_LIST_DIR}/format.cmake"
    WORKING_DIRECTORY "${SOURCE_DIR}"
    RESULT_VARIABLE result OUTPUT_QUIET ERROR_VARIABLE format_output)
if(NOT result EQUAL 0)
    message("${format_output}")
    list(APPEND other_failures
        "the format (fix it with: sh tools/hooks/tidy-files --format <file>...)")
endif()
execute_process(
    COMMAND "${CMAKE_COMMAND}" "-DCONFIG=${CONFIG}" "-DFILES=${FILES}"
            -P "${CMAKE_CURRENT_LIST_DIR}/audit_suppressions.cmake"
    WORKING_DIRECTORY "${SOURCE_DIR}"
    RESULT_VARIABLE result OUTPUT_QUIET ERROR_VARIABLE audit_output)
# The audit prints its notes (a file near its length limit) there too.
string(REGEX REPLACE "(^|\n)cpp-policy audit: OK[^\n]*\n?" "\\1" audit_output "${audit_output}")
if(NOT audit_output STREQUAL "")
    message("${audit_output}")
endif()
if(NOT result EQUAL 0)
    list(APPEND other_failures "the audit's rules")
endif()

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
    if(extension MATCHES "^\\.(cpp|cc|cxx)$" AND NOT path IN_LIST compiled AND NOT reconfigured)
        # A file added since the build was configured isn't in its list yet: configure again,
        # once, before deciding that this system doesn't build it.
        # Through the preset (build/<preset>), which carries the environment the build was
        # configured with; configuring the folder directly could pick another compiler.
        cmake_path(GET BUILD_DIR FILENAME preset)
        execute_process(COMMAND "${CMAKE_COMMAND}" --preset "${preset}"
            WORKING_DIRECTORY "${SOURCE_DIR}"
            RESULT_VARIABLE result OUTPUT_QUIET ERROR_VARIABLE configure_error)
        if(NOT result EQUAL 0)
            message("tidy-files: note: configuring again (cmake --preset ${preset}) failed, "
                    "so files added since the last configure can't be found:\n"
                    "${configure_error}")
        endif()
        set(reconfigured TRUE)
        read_compiled(compiled)
        include("${BUILD_DIR}/cpp_policy_tests.cmake" OPTIONAL)
        read_tests()
    endif()
    if(extension MATCHES "^\\.(cpp|cc|cxx)$" AND NOT path IN_LIST compiled)
        message("tidy-files: ${relative}: NOT CHECKED. This build doesn't compile it, even "
                "after configuring again: it is another system's file (CI checks it there), "
                "or CMakeLists.txt doesn't list it yet")
        math(EXPR skipped "${skipped} + 1")
        continue()
    endif()
    set(test_option "")
    cmake_path(GET path PARENT_PATH dir)
    if(path IN_LIST test_sources)
        set(test_option ${TEST_TIDY_CHECKS})
    elseif(NOT extension MATCHES "^\\.(cpp|cc|cxx)$")
        if(dir IN_LIST test_dirs)
            set(test_option ${TEST_TIDY_CHECKS})
        endif()
        foreach(root IN LISTS test_roots)
            string(FIND "${path}" "${root}" at)
            if(at EQUAL 0)
                set(test_option ${TEST_TIDY_CHECKS})
            endif()
        endforeach()
    endif()
    set(target "${path}")
    set(only "")
    if(NOT extension MATCHES "^\\.(cpp|cc|cxx)$")
        including_source("${path}" through)
        if(through)
            # As the build sees the header: in that source, with its flags and its checks.
            set(target "${through}")
            set(only "--line-filter=[{\"name\":\"${path}\"}]")
            set(test_option "")
            if(through IN_LIST test_sources)
                set(test_option ${TEST_TIDY_CHECKS})
            endif()
        endif()
    endif()
    execute_process(
        COMMAND "${CLANG_TIDY}" "--config-file=${TIDY_CONFIG}" ${test_option} ${only}
                --quiet -p "${BUILD_DIR}" "${target}"
        WORKING_DIRECTORY "${SOURCE_DIR}"
        RESULT_VARIABLE result)
    math(EXPR checked "${checked} + 1")
    if(NOT result EQUAL 0)
        list(APPEND failed "${relative}")
    endif()
endforeach()

if(failed OR other_failures)
    set(summary "")
    if(failed)
        list(JOIN failed "\n  " failed_list)
        string(APPEND summary "\nclang-tidy findings in:\n  ${failed_list}")
    endif()
    foreach(failure IN LISTS other_failures)
        string(APPEND summary "\n${failure}: see above")
    endforeach()
    message(FATAL_ERROR "tidy-files: FAILED${summary}")
endif()
if(skipped GREATER 0)
    message("tidy-files: OK (${checked} files; ${skipped} NOT CHECKED, listed above)")
else()
    message("tidy-files: OK (${checked} files)")
endif()

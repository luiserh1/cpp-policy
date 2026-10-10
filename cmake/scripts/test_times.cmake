# Names the tests that passed close to their time limit (POLICY.md 13.2): a test at 46 of
# its 60 seconds passes for weeks and then fails on a busy machine, and nothing had said so.
# The gate's launcher and CI run it after the tests:
#
#   cmake -DBUILD_DIR=<build/preset> [-DSHARE=<percent, 67 by default>] -P test_times.cmake
#
# It reads the limits from the test files CTest itself reads, and the times from CTest's log
# of the last run. It prints one line per such test and always succeeds: the limit is what
# fails a test.

cmake_minimum_required(VERSION 3.29)

if(NOT DEFINED SHARE)
    set(SHARE 67)
endif()
set(log "${BUILD_DIR}/Testing/Temporary/LastTest.log")
if(NOT EXISTS "${log}" OR NOT EXISTS "${BUILD_DIR}/CTestTestfile.cmake")
    return()
endif()

# CTest's test files are CMake code that calls these four commands; here they only record
# each test's limit.
set_property(GLOBAL PROPERTY policy_limits "")
function(add_test name)
endfunction()
function(set_directory_properties)
endfunction()
function(set_tests_properties)
    set(names "")
    set(limit "")
    set(reading names)
    set(previous "")
    foreach(argument IN LISTS ARGN)
        if(argument STREQUAL "PROPERTIES" AND reading STREQUAL "names")
            set(reading properties)
        elseif(reading STREQUAL "names")
            list(APPEND names "${argument}")
        elseif(previous STREQUAL "TIMEOUT")
            set(limit "${argument}")
        endif()
        set(previous "${argument}")
    endforeach()
    if(limit MATCHES "^[0-9]+$")
        foreach(name IN LISTS names)
            set_property(GLOBAL APPEND PROPERTY policy_limits "${name}|${limit}")
        endforeach()
    endif()
endfunction()
function(subdirs)
    foreach(directory IN LISTS ARGN)
        cmake_path(ABSOLUTE_PATH directory BASE_DIRECTORY "${policy_directory}" NORMALIZE)
        if(EXISTS "${directory}/CTestTestfile.cmake")
            set(policy_directory "${directory}")
            include("${directory}/CTestTestfile.cmake")
        endif()
    endforeach()
endfunction()
set(policy_directory "${BUILD_DIR}")
cmake_path(ABSOLUTE_PATH policy_directory NORMALIZE)
include("${policy_directory}/CTestTestfile.cmake")

get_property(limits GLOBAL PROPERTY policy_limits)
foreach(entry IN LISTS limits)
    string(REGEX MATCH "^(.*)\\|([0-9]+)$" _ "${entry}")
    string(MD5 key "${CMAKE_MATCH_1}")
    set(limit_${key} "${CMAKE_MATCH_2}")
endforeach()

# The log has, for each test: "<n>/<m> Test: <name>", its output, "Test time = <s> sec" and
# "Test Passed." A line of a test's own output that looks like one of these could only add a
# line here or drop one.
file(STRINGS "${log}" lines REGEX "^([0-9]+/[0-9]+ Test: |Test time = |Test Passed\\.)")
set(name "")
set(seconds "")
set(found 0)
foreach(line IN LISTS lines)
    if(line MATCHES "^[0-9]+/[0-9]+ Test: (.*)$")
        set(name "${CMAKE_MATCH_1}")
        set(seconds "")
    elseif(line MATCHES "^Test time = +([0-9]+)(\\.[0-9]+)? sec")
        set(seconds "${CMAKE_MATCH_1}")
    elseif(NOT name STREQUAL "" AND NOT seconds STREQUAL "")
        string(MD5 key "${name}")
        if(DEFINED limit_${key})
            math(EXPR threshold "${limit_${key}} * ${SHARE} / 100")
            if(seconds GREATER_EQUAL threshold)
                message("gate: close to its time limit: \"${name}\" took ${seconds} s of "
                    "${limit_${key}} (POLICY.md 13.2)")
                math(EXPR found "${found} + 1")
            endif()
        endif()
        set(name "")
    endif()
endforeach()
if(found GREATER 0)
    message("gate: ${found} passing test(s) used ${SHARE}% or more of their limit. Make "
        "them shorter or split them; or, with a reason, SLOW in cpp_policy_add_tests()")
endif()

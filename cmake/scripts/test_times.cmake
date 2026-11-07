# Names the tests that passed close to their time limit (POLICY.md 13.2): a test at 46 of
# its 60 seconds passes for weeks and then fails on a busy machine, and nothing had said so.
# The gate's launcher and CI run it after the tests:
#
#   cmake -DBUILD_DIR=<build/preset> [-DSHARE=<percent, 67 by default>] [-DREMEMBER=ON]
#         -P test_times.cmake
#
# It reads the limits from the test files CTest itself reads, and the times from CTest's log
# of the last run. It prints one line per such test: the limit is what fails a test.
#
# It also names the tests that timed out and passed on their second run: the presets give a
# test that timed out one more run (POLICY.md 7). With REMEMBER (the gate's launcher), each
# is remembered on this machine, across working copies, in
# <cpp_policy_cache_root>/retried/<project>.txt, one line each: the date, then the name. A
# test named there already fails: needing the second run twice is a finding, which a
# deadlock that happens only sometimes would otherwise pass as. Only then does it fail.

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
file(STRINGS "${log}" lines
    REGEX "^([0-9]+/[0-9]+ Test: |Test time = |Test Passed\\.|Test Failed\\.)")
set(name "")
set(seconds "")
set(found 0)
set(retried "")
foreach(line IN LISTS lines)
    if(line MATCHES "^[0-9]+/[0-9]+ Test: (.*)$")
        set(name "${CMAKE_MATCH_1}")
        set(seconds "")
    elseif(line MATCHES "^Test time = +([0-9]+)(\\.[0-9]+)? sec")
        set(seconds "${CMAKE_MATCH_1}")
    elseif(line MATCHES "^Test Failed\\.")
        # Only a timeout is run again, so a test that failed and then passed timed out.
        if(NOT name STREQUAL "")
            string(MD5 key "${name}")
            set(failed_${key} TRUE)
        endif()
        set(name "")
    elseif(NOT name STREQUAL "" AND NOT seconds STREQUAL "")
        string(MD5 key "${name}")
        if(failed_${key})
            message("gate: timed out and passed on a second run: \"${name}\" (POLICY.md 7)")
            list(APPEND retried "${name}")
        endif()
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
list(LENGTH retried again)
if(again GREATER 0)
    message("gate: ${again} test(s) needed a second run. Once is chance (a busy machine); "
        "the gate remembers it, and a second time fails it")
endif()
if(found GREATER 0)
    message("gate: ${found} passing test(s) used ${SHARE}% or more of their limit. Make "
        "them shorter or split them; or, with a reason, SLOW in cpp_policy_add_tests()")
endif()

if(REMEMBER AND again GREATER 0)
    include("${CMAKE_CURRENT_LIST_DIR}/tidy_cache_dir.cmake")
    cpp_policy_cache_root(root)
    set(project "")
    if(EXISTS "${BUILD_DIR}/CMakeCache.txt")
        file(STRINGS "${BUILD_DIR}/CMakeCache.txt" project REGEX "^CMAKE_PROJECT_NAME:STATIC=")
        string(REGEX REPLACE "^[^=]*=" "" project "${project}")
    endif()
    if(project STREQUAL "")
        set(project unnamed)
    endif()
    set(memory "${root}/retried/${project}.txt")
    set(known "")
    if(EXISTS "${memory}")
        file(STRINGS "${memory}" entries)
        foreach(entry IN LISTS entries)
            if(entry MATCHES "^[0-9-]+ (.+)$")
                string(MD5 key "${CMAKE_MATCH_1}")
                set(known_${key} TRUE)
            endif()
        endforeach()
    endif()
    string(TIMESTAMP today "%Y-%m-%d")
    set(repeated 0)
    foreach(name IN LISTS retried)
        string(MD5 key "${name}")
        if(known_${key})
            message("gate: needed a second run before, too: \"${name}\" (POLICY.md 7)")
            math(EXPR repeated "${repeated} + 1")
        else()
            file(APPEND "${memory}" "${today} ${name}\n")
        endif()
    endforeach()
    if(repeated GREATER 0)
        message("gate: ${repeated} test(s) needed a second run on this machine before. That is a "
            "finding: tell the owner. The record is ${memory}; a test's line goes once its "
            "cause is fixed")
        cmake_language(EXIT 1)
    endif()
endif()

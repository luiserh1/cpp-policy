# Registers a doctest program's test cases with CTest (POLICY.md 13). cpp_policy_add_tests()
# runs it after each build of the program:
#
#   cmake -DEXECUTABLE=<program> -DKIND=<kind> -DMODULE=<module> -DTIMEOUT=<seconds>
#         [-DENVIRONMENT=<VAR=value;...>] -DWORKING_DIR=<dir> -DCTEST_FILE=<file>
#         -P doctest_tests.cmake
#
# Each test case becomes the CTest test <kind>/<module>/<test case>, labelled with its kind,
# and also "regression" when the case is in doctest's "regression" suite. The script fails,
# and with it the build, on a skipped test case, a name doctest can't select exactly, two
# names that differ only in case, a suite other than "regression", or a program with no
# tests. The self-test passes LISTING_FILE instead of EXECUTABLE: a saved listing.

cmake_minimum_required(VERSION 3.29)

if(DEFINED LISTING_FILE)
    file(READ "${LISTING_FILE}" listing)
else()
    # --no-skip lists the skipped cases too, so that they can be refused.
    execute_process(COMMAND "${EXECUTABLE}" --list-test-cases --reporters=xml --no-skip=true
        WORKING_DIRECTORY "${WORKING_DIR}"
        RESULT_VARIABLE code OUTPUT_VARIABLE listing ERROR_VARIABLE errors)
    if(NOT code EQUAL 0)
        message(FATAL_ERROR "cpp-policy: ${EXECUTABLE} couldn't list its tests "
            "(exit code ${code}):\n${listing}${errors}")
    endif()
endif()

# Records one problem: its arguments are joined into one message, which must hold no ";".
function(problem)
    string(JOIN "" text ${ARGN})
    set(problems ${problems} "${text}" PARENT_SCOPE)
endfunction()

# A name may hold an apostrophe, which the listing escapes as &apos;. CMake splits lists at
# ";", so the other escapes lose theirs; their "&" is refused below as part of a name.
string(REPLACE "&apos;" "'" listing "${listing}")
string(REPLACE ";" "" listing "${listing}")
string(REGEX MATCHALL "<TestCase [^\n]*/>" cases "${listing}")
set(problems "")
set(seen "")
set(script "")
foreach(case IN LISTS cases)
    string(REGEX MATCH " name=\"([^\"]*)\"" _ "${case}")
    set(name "${CMAKE_MATCH_1}")
    set(suite "")
    if(case MATCHES " testsuite=\"([^\"]*)\"")
        set(suite "${CMAKE_MATCH_1}")
    endif()
    string(REGEX MATCH " filename=\"([^\"]*)\" line=\"([0-9]+)\"" _ "${case}")
    set(where "${CMAKE_MATCH_1}:${CMAKE_MATCH_2}")

    # Letters, digits, spaces and ' . : ( ) + = - _ only: doctest selects a test by a filter
    # in which , * ? and \ are special, and the XML listing escapes & < > ".
    if(NOT name MATCHES "^[A-Za-z0-9_'.:()+=-]([A-Za-z0-9 _'.:()+=-]*[A-Za-z0-9_'.:()+=-])?$")
        problem("${where}: test case \"${name}\": use only letters, digits, "
            "spaces and ' . : ( ) + = - _ in a name, with no space at either end")
        continue()
    endif()
    string(TOLOWER "${name}" lower)
    if(lower IN_LIST seen)
        problem("${where}: test case \"${name}\": another test case has the same "
            "name (ignoring case), and doctest would run both")
        continue()
    endif()
    list(APPEND seen "${lower}")
    if(case MATCHES " skipped=\"true\"")
        problem("${where}: test case \"${name}\" is skipped. Make it pass, or "
            "delete it and record the missing test in ROADMAP.md")
        continue()
    endif()
    set(labels "${KIND}")
    if(suite STREQUAL "regression")
        list(APPEND labels regression)
    elseif(NOT suite STREQUAL "")
        problem("${where}: test case \"${name}\" is in suite \"${suite}\". The only "
            "suite is \"regression\", for tests added with a bug fix")
        continue()
    endif()

    set(test "${KIND}/${MODULE}/${name}")
    string(APPEND script
        "add_test([==[${test}]==] [==[${EXECUTABLE}]==] [==[--test-case=${name}]==]"
        " --no-intro=true --no-version=true)\n"
        "set_tests_properties([==[${test}]==] PROPERTIES LABELS [==[${labels}]==]"
        " TIMEOUT ${TIMEOUT} WORKING_DIRECTORY [==[${WORKING_DIR}]==]")
    if(NOT "${ENVIRONMENT}" STREQUAL "")
        string(APPEND script " ENVIRONMENT [==[${ENVIRONMENT}]==]")
    endif()
    string(APPEND script ")\n")
endforeach()
if(NOT cases)
    problem("${EXECUTABLE}${LISTING_FILE} has no test cases")
endif()

if(problems)
    file(REMOVE "${CTEST_FILE}")
    list(JOIN problems "\n  " problems)
    message(FATAL_ERROR "cpp-policy: tests that CTest can't run as the policy requires "
        "(POLICY.md 13):\n  ${problems}")
endif()
file(WRITE "${CTEST_FILE}" "${script}")

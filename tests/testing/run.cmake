# cpp_policy_add_tests()'s registration script on a saved doctest listing (POLICY.md 13).
#
#   cmake -DPOLICY_ROOT=<dir> -DLISTING=<dir>/<case>.xml -DWORK=<dir> -P run.cmake
#
# <case>.expect next to the listing holds a regex the script's output must match. The case
# "ok" must succeed and write a CTest file; every other case must fail.

cmake_minimum_required(VERSION 3.29)
cmake_path(GET LISTING STEM case)
cmake_path(REPLACE_EXTENSION LISTING ".expect" OUTPUT_VARIABLE expect_file)
file(READ "${expect_file}" expect)
string(STRIP "${expect}" expect)
# \n in the file stands for a newline.
string(REPLACE "\\n" "\n" expect "${expect}")
file(REMOVE_RECURSE "${WORK}")
file(MAKE_DIRECTORY "${WORK}")
set(ctest_file "${WORK}/tests.cmake")

# A case whose name ends in _unit is registered as unit tests, the others as integration
# tests: the checks are the same, the tests written differ.
set(kind integration)
if(case MATCHES "_unit$")
    set(kind unit)
endif()
# A case whose name ends in _parallel is registered as cpp_policy_parallel_tests() makes it.
set(serial TRUE)
if(case MATCHES "_parallel$")
    set(serial FALSE)
endif()
execute_process(COMMAND "${CMAKE_COMMAND}" "-DLISTING_FILE=${LISTING}" -DKIND=${kind} -DMODULE=app
    -DTIMEOUT=10 -DSERIAL=${serial} "-DWORKING_DIR=${WORK}" "-DCTEST_FILE=${ctest_file}" "-DENVIRONMENT=A=1;B=2"
    -P "${POLICY_ROOT}/cmake/scripts/doctest_tests.cmake"
    RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
set(output "${out}${err}")
if(case MATCHES "^ok")
    if(NOT code EQUAL 0 OR NOT EXISTS "${ctest_file}")
        message(FATAL_ERROR "testing/${case}: the script failed (exit code ${code}):\n${output}")
    endif()
    file(READ "${ctest_file}" output)
    # Every test runs alone unless the project asked for several at a time.
    string(REGEX MATCHALL "set_tests_properties" all "${output}")
    string(REGEX MATCHALL " RUN_SERIAL TRUE " alone "${output}")
    list(LENGTH all all)
    list(LENGTH alone alone)
    if((serial AND NOT alone EQUAL all) OR (NOT serial AND NOT alone EQUAL 0))
        message(FATAL_ERROR "testing/${case}: ${alone} of ${all} tests are RUN_SERIAL:\n${output}")
    endif()
elseif(code EQUAL 0)
    message(FATAL_ERROR "testing/${case}: the script accepted the listing:\n${output}")
elseif(EXISTS "${ctest_file}")
    message(FATAL_ERROR "testing/${case}: the script failed but left a CTest file")
endif()
if(NOT output MATCHES "${expect}")
    message(FATAL_ERROR "testing/${case}: the output doesn't match '${expect}':\n${output}")
endif()
message("testing/${case}: OK")

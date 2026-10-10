# scripts/test_times.cmake on a made-up build folder (POLICY.md 13.2): it must name the
# passing tests that used two thirds or more of their own limit, and no other.
#
#   cmake -DPOLICY_ROOT=<dir> -DWORK=<dir> -P test_times.cmake

cmake_minimum_required(VERSION 3.29)
file(REMOVE_RECURSE "${WORK}")
file(MAKE_DIRECTORY "${WORK}/tests" "${WORK}/Testing/Temporary")
# As CMake writes them: a top file that names a folder, whose file has the tests.
file(WRITE "${WORK}/CTestTestfile.cmake" "subdirs(\"tests\")\n")
file(WRITE "${WORK}/tests/CTestTestfile.cmake" [=[
add_test([==[integration/app/quick]==] "program" [==[--test-case=quick]==])
set_tests_properties([==[integration/app/quick]==] PROPERTIES LABELS [==[integration]==] TIMEOUT 60 RUN_SERIAL TRUE)
add_test([==[integration/app/the walk (whole)]==] "program")
set_tests_properties([==[integration/app/the walk (whole)]==] PROPERTIES LABELS [==[integration]==] TIMEOUT 60)
add_test([==[integration/window/slow with a reason]==] "program")
set_tests_properties([==[integration/window/slow with a reason]==] PROPERTIES TIMEOUT 300 _BACKTRACE_TRIPLES "a;1;;b;2;")
add_test([==[integration/app/failed late]==] "program")
set_tests_properties([==[integration/app/failed late]==] PROPERTIES TIMEOUT 60)
add_test(plain "program")
]=])
set(log "")
foreach(test IN ITEMS "integration/app/quick|12.50|Passed" "integration/app/the walk (whole)|46.02|Passed"
        "integration/window/slow with a reason|61.00|Passed" "integration/app/failed late|59.00|Failed"
        "plain|500.00|Passed")
    string(REPLACE "|" ";" parts "${test}")
    list(GET parts 0 name)
    list(GET parts 1 seconds)
    list(GET parts 2 result)
    string(APPEND log "1/5 Testing: ${name}\n1/5 Test: ${name}\nCommand: \"program\"\nOutput:\n"
        "----------------------------------------------------------\nTest time = 1 sec, says the test\n"
        "<end of output>\nTest time =  ${seconds} sec\n"
        "----------------------------------------------------------\nTest ${result}.\n"
        "\"${name}\" end time: Oct 10 03:01 CEST\n\n")
endforeach()
file(WRITE "${WORK}/Testing/Temporary/LastTest.log" "${log}")

execute_process(COMMAND "${CMAKE_COMMAND}" "-DBUILD_DIR=${WORK}"
    -P "${POLICY_ROOT}/cmake/scripts/test_times.cmake"
    RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
set(output "${out}${err}")
if(NOT code EQUAL 0)
    message(FATAL_ERROR "testing/test_times: the script failed:\n${output}")
endif()
if(NOT output MATCHES "\"integration/app/the walk \\(whole\\)\" took 46 s of 60"
   OR NOT output MATCHES "gate: 1 passing test"
   OR output MATCHES "quick|slow with a reason|failed late|plain")
    message(FATAL_ERROR "testing/test_times: only the walk is close to its limit:\n${output}")
endif()
# A build folder with no test run says nothing.
file(REMOVE "${WORK}/Testing/Temporary/LastTest.log")
execute_process(COMMAND "${CMAKE_COMMAND}" "-DBUILD_DIR=${WORK}"
    -P "${POLICY_ROOT}/cmake/scripts/test_times.cmake"
    RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT code EQUAL 0 OR NOT "${out}${err}" STREQUAL "")
    message(FATAL_ERROR "testing/test_times: without a log it must say nothing:\n${out}${err}")
endif()
message("testing/test_times: OK")

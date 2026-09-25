# A probe for an item waiting on the toolchain (POLICY.md 12).
#
#   cmake -DCXX=<compiler> -DSOURCE=<probe.cpp> -DITEM=<Wn> -P probe.cmake
#
# The probe uses a feature the toolchain lacks, so it must fail to compile. The day it
# compiles, the feature has arrived: this script fails to say it is time to revisit.

cmake_minimum_required(VERSION 3.29)
execute_process(COMMAND "${CXX}" -std=c++23 -fsyntax-only "${SOURCE}"
    RESULT_VARIABLE failed OUTPUT_QUIET ERROR_QUIET)
if(NOT failed)
    message(FATAL_ERROR "${ITEM} is available now: ${SOURCE} compiles. Revisit ${ITEM} in "
        "POLICY.md 12: remove the workarounds marked 'Waiting ${ITEM}', then this probe.")
endif()
message("${ITEM}: still waiting")

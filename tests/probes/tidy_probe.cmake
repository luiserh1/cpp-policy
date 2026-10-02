# A probe for a clang-tidy defect the policy works around (POLICY.md 12).
#
#   cmake -DCLANG_TIDY=<clang-tidy> -DSOURCE=<probe.cpp> -DITEM=<Wn> -DCHECK=<check name>
#         -P tidy_probe.cmake
#
# The probe is correct code that the check reports by mistake. The day clang-tidy stops
# reporting it, the defect is fixed: this script fails to say it is time to revisit.

cmake_minimum_required(VERSION 3.29)
execute_process(COMMAND "${CLANG_TIDY}" "--checks=-*,${CHECK}" --quiet "${SOURCE}" -- -std=c++23
    OUTPUT_VARIABLE out ERROR_VARIABLE err)
# "[check]" or, with warnings as errors, "[check,-warnings-as-errors]".
string(FIND "${out}${err}" "[${CHECK}" found)
if(found EQUAL -1)
    message(FATAL_ERROR "${ITEM} is fixed: clang-tidy no longer reports ${SOURCE}. Revisit "
        "${ITEM} in POLICY.md 12: remove the workarounds marked 'Waiting ${ITEM}', then this "
        "probe.\n${out}${err}")
endif()
message("${ITEM}: still waiting")

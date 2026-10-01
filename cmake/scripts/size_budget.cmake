# A program's size budget (POLICY.md 13.5): cpp_policy_size_budget() runs it as the test
# benchmark/size/<program> in Release builds.
#
#   cmake -DPROGRAM=<file> -DSYSTEM=<MACOS|LINUX|WINDOWS> -DBUDGET=<bytes or empty>
#         -DSTRIP=<llvm-strip> -DSIZE=<llvm-size> -DWORK=<dir> -P size_budget.cmake
#
# The size is that of a stripped copy: what would ship. The symbol table left in the build's
# own file grows with names, not with code. The script prints the size, the budget, and a
# budget with the policy's 5% headroom. A program over its budget, or with no budget for this
# system, fails, with the copy's sections listed to show where the size is.

cmake_minimum_required(VERSION 3.29)
cmake_path(GET PROGRAM FILENAME name)
file(MAKE_DIRECTORY "${WORK}")
set(copy "${WORK}/${name}")
execute_process(COMMAND "${STRIP}" --strip-all -o "${copy}" "${PROGRAM}"
    RESULT_VARIABLE code ERROR_VARIABLE errors)
if(NOT code EQUAL 0)
    message(FATAL_ERROR "size budget: llvm-strip failed on ${PROGRAM}:\n${errors}")
endif()
file(SIZE "${copy}" size)
# 5% headroom, rounded up to whole KiB.
math(EXPR suggested "((${size} * 105 / 100) + 1023) / 1024 * 1024")

execute_process(COMMAND "${SIZE}" -A "${copy}" OUTPUT_VARIABLE sections ERROR_QUIET)
if("${BUDGET}" STREQUAL "")
    message(FATAL_ERROR "size budget: ${name} has no ${SYSTEM} budget. Stripped, it is ${size} "
        "bytes: with 5% headroom, add ${SYSTEM} ${suggested} to its cpp_policy_size_budget() "
        "(the owner approves budgets, POLICY.md 13.5).\n${sections}")
endif()
if(size GREATER BUDGET)
    math(EXPR over "${size} - ${BUDGET}")
    message(FATAL_ERROR "size budget: ${name} is ${size} bytes stripped, ${over} over its ${SYSTEM} "
        "budget of ${BUDGET}. Find what grew (the sections below; a link map has every "
        "function's size) and shrink it, or ask the owner to raise the budget to at least "
        "${suggested}, with the reason in CHANGELOG.md (POLICY.md 13.5).\n${sections}")
endif()
math(EXPR left "${BUDGET} - ${size}")
message("size budget: ${name} is ${size} bytes stripped; its ${SYSTEM} budget is ${BUDGET} "
    "(${left} left)")
# More than 10% headroom: the program shrank since the budget was set.
math(EXPR roomy "${size} * 110 / 100")
if(BUDGET GREATER roomy)
    message("size budget: it is well under its budget, which could come down to ${suggested}")
endif()

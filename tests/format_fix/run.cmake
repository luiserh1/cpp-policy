# policy-format-fix, checked on a throwaway project whose braced lists need trailing commas.
#
#   cmake -DPOLICY_ROOT=<dir> -DWORK=<dir> -DCLANG_FORMAT=<exe> -DCLANG_TIDY=<exe> -P run.cmake
#
# One list is on a single line too long for the column limit: it needs its comma only after
# clang-format has split it, the case that took projects several rounds by hand. Afterwards
# both the format check and readability-trailing-comma must pass, in one run of the fix.

cmake_minimum_required(VERSION 3.29)

file(REMOVE_RECURSE "${WORK}")
file(MAKE_DIRECTORY "${WORK}/src" "${WORK}/build")

# No standard headers: the compile command below is the only setup clang-tidy gets.
file(WRITE "${WORK}/src/table.hpp"
    "#pragma once\n"
    "struct Entry { int key; int value; };\n"
    "inline constexpr Entry first_entries[] = {{.key = 1, .value = 10}, {.key = 2, .value = 20}, {.key = 3, .value = 30}};\n")
file(WRITE "${WORK}/src/table.cpp"
    "#include \"table.hpp\"\n"
    "int lookup(int index) {\n"
    "    const int weights[] = {\n"
    "        100,\n"
    "        200\n"
    "    };\n"
    "    const int small[] = {1, 2,};\n"
    "    return weights[index] + small[index] + first_entries[index].value;\n"
    "}\n")
file(WRITE "${WORK}/build/compile_commands.json"
    "[{\"directory\": \"${WORK}/build\",\n"
    "  \"command\": \"clang++ -std=c++23 -c ${WORK}/src/table.cpp\",\n"
    "  \"file\": \"${WORK}/src/table.cpp\"}]\n")
set(config "${WORK}/config.cmake")
file(WRITE "${config}"
    "set(SOURCE_DIR [==[${WORK}/src]==])\n"
    "set(POLICY_ROOT [==[${POLICY_ROOT}]==])\n"
    "set(EXCLUDED_DIRS [==[]==])\n"
    "set(CLANG_FORMAT [==[${CLANG_FORMAT}]==])\n"
    "set(CLANG_TIDY [==[${CLANG_TIDY}]==])\n"
    "set(BUILD_DIR [==[${WORK}/build]==])\n")

set(format "${POLICY_ROOT}/cmake/scripts/format.cmake")
execute_process(COMMAND "${CMAKE_COMMAND}" -DCONFIG=${config} -DMODE=fix -P "${format}"
    RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT code EQUAL 0)
    message(FATAL_ERROR "format_fix: the fix failed\n${out}${err}")
endif()

execute_process(COMMAND "${CMAKE_COMMAND}" -DCONFIG=${config} -DMODE=check -P "${format}"
    RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT code EQUAL 0)
    message(FATAL_ERROR "format_fix: badly formatted after the fix\n${out}${err}")
endif()

execute_process(
    COMMAND "${CLANG_TIDY}" "--config-file=${POLICY_ROOT}/.clang-tidy"
            "--checks=-*,readability-trailing-comma" --quiet -p "${WORK}/build" "${WORK}/src/table.cpp"
    RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT code EQUAL 0)
    file(READ "${WORK}/src/table.hpp" header)
    file(READ "${WORK}/src/table.cpp" source)
    message(FATAL_ERROR "format_fix: trailing commas still wrong after one fix\n${out}${err}\n"
                        "--- table.hpp ---\n${header}--- table.cpp ---\n${source}")
endif()
message("format_fix: OK")

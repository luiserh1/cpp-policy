# policy-format-fix, checked on a throwaway project.
#
#   cmake -DPOLICY_ROOT=<dir> -DWORK=<dir> -DCLANG_FORMAT=<exe> -DCXX=<compiler> -P run.cmake
#
# It formats, and nothing else: the code must still compile afterwards. Until v0.27.0 it also
# let clang-tidy fix trailing commas, and that fix removed the comma after an empty braced
# value (Waiting W4, POLICY.md 12): `f(1, Options{}, 2)` became `f(1, Options{} 2)`. The file
# below has the three shapes that broke. With FILES, only the named file is touched.

cmake_minimum_required(VERSION 3.29)

file(REMOVE_RECURSE "${WORK}")
file(MAKE_DIRECTORY "${WORK}/src")

file(WRITE "${WORK}/src/table.cpp"
    "struct Options { int width{}; };\n"
    "int f(int a, Options options, int b) { return a + options.width + b; }\n"
    "int g(const Options& shown = {}, int more = 0) { return shown.width + more; }\n"
    "int lookup(int index) {\n"
    "    const Options two[] = {Options{}, Options{.width = 1}};\n"
    "        return f(1, Options{}, 2)+g()+two[index].width;\n"
    "}\n")
file(WRITE "${WORK}/src/other.cpp" "int   untouched( )   { return 0; }\n")
set(config "${WORK}/config.cmake")
file(WRITE "${config}"
    "set(SOURCE_DIR [==[${WORK}/src]==])\n"
    "set(POLICY_ROOT [==[${POLICY_ROOT}]==])\n"
    "set(EXCLUDED_DIRS [==[]==])\n"
    "set(CLANG_FORMAT [==[${CLANG_FORMAT}]==])\n")

set(format "${POLICY_ROOT}/cmake/scripts/format.cmake")
file(READ "${WORK}/src/other.cpp" other_before)
execute_process(COMMAND "${CMAKE_COMMAND}" -DCONFIG=${config} -DMODE=fix -DFILES=table.cpp
        -P "${format}"
    RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT code EQUAL 0)
    message(FATAL_ERROR "format_fix: the fix failed\n${out}${err}")
endif()
file(READ "${WORK}/src/other.cpp" other_after)
if(NOT other_after STREQUAL other_before)
    message(FATAL_ERROR "format_fix: with FILES=table.cpp, other.cpp was changed too")
endif()

execute_process(COMMAND "${CMAKE_COMMAND}" -DCONFIG=${config} -DMODE=check -DFILES=table.cpp
        -P "${format}"
    RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT code EQUAL 0)
    message(FATAL_ERROR "format_fix: badly formatted after the fix\n${out}${err}")
endif()
execute_process(COMMAND "${CMAKE_COMMAND}" -DCONFIG=${config} -DMODE=check -P "${format}"
    RESULT_VARIABLE code OUTPUT_QUIET ERROR_QUIET)
if(code EQUAL 0)
    message(FATAL_ERROR "format_fix: the check of every file must still report other.cpp")
endif()

execute_process(COMMAND "${CXX}" -std=c++23 -fsyntax-only "${WORK}/src/table.cpp"
    RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT code EQUAL 0)
    file(READ "${WORK}/src/table.cpp" source)
    message(FATAL_ERROR "format_fix: the code doesn't compile after the fix\n${out}${err}\n"
                        "--- table.cpp ---\n${source}")
endif()
message("format_fix: OK")

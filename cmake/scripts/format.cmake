# Format check / fix using the policy's .clang-format.
#
#   cmake -DCONFIG=<cpp_policy_config.cmake> -DMODE=check|fix -P format.cmake
#
# fix also settles readability-trailing-comma (POLICY.md 2.10), which depends on the layout:
# a list clang-format writes on several lines needs a trailing comma, and one on a single line
# must not have one. So it formats, lets clang-tidy fix the commas, and formats again. The
# second format is the last word: a comma keeps its list one element per line, so the commas
# stay right.

cmake_minimum_required(VERSION 3.29)
include("${CMAKE_CURRENT_LIST_DIR}/source_files.cmake")
include("${CONFIG}")

cpp_policy_collect_sources("${SOURCE_DIR}" "${EXCLUDED_DIRS}" files)

if(MODE STREQUAL "check")
    set(mode_args --dry-run --Werror)
elseif(MODE STREQUAL "fix")
    set(mode_args -i)
else()
    message(FATAL_ERROR "format.cmake: MODE must be 'check' or 'fix'")
endif()

function(run_clang_format)
    set(failed "")
    foreach(file IN LISTS files)
        execute_process(
            COMMAND "${CLANG_FORMAT}" ${mode_args} "--style=file:${POLICY_ROOT}/.clang-format" "${file}"
            WORKING_DIRECTORY "${SOURCE_DIR}"
            RESULT_VARIABLE result)
        if(NOT result EQUAL 0)
            list(APPEND failed "${file}")
        endif()
    endforeach()
    if(failed)
        list(JOIN failed "\n  " failed_list)
        if(MODE STREQUAL "check")
            message(FATAL_ERROR "cpp-policy format: badly formatted files:\n  ${failed_list}\n"
                                "Run: cmake --build --preset <preset> --target policy-format-fix")
        endif()
        message(FATAL_ERROR "cpp-policy format: clang-format failed on:\n  ${failed_list}\n"
                            "See its output above (usually a file it could not parse).")
    endif()
endfunction()

# clang-tidy with only the trailing-comma check, applying its fixes. It runs on the
# translation units; headers are fixed through them (the header filter of .clang-tidy).
function(fix_trailing_commas)
    if(NOT EXISTS "${BUILD_DIR}/compile_commands.json")
        message(FATAL_ERROR "cpp-policy format: ${BUILD_DIR}/compile_commands.json is missing, "
                            "so trailing commas can't be fixed. Configure the preset first.")
    endif()
    # Only files this build compiles: others (such as another platform's) can't be parsed
    # here, and this platform's gate doesn't check them either.
    file(READ "${BUILD_DIR}/compile_commands.json" database)
    string(JSON entries LENGTH "${database}")
    set(compiled "")
    if(entries GREATER 0)
        math(EXPR last "${entries} - 1")
        foreach(index RANGE ${last})
            string(JSON path GET "${database}" ${index} file)
            file(REAL_PATH "${path}" path)
            list(APPEND compiled "${path}")
        endforeach()
    endif()
    set(unparsed "")
    foreach(file IN LISTS files)
        file(REAL_PATH "${file}" path BASE_DIRECTORY "${SOURCE_DIR}")
        if(NOT path IN_LIST compiled)
            continue()
        endif()
        execute_process(
            COMMAND "${CLANG_TIDY}" "--config-file=${POLICY_ROOT}/.clang-tidy"
                    "--checks=-*,readability-trailing-comma" "--warnings-as-errors=-*" --fix
                    --quiet -p "${BUILD_DIR}" "${file}"
            WORKING_DIRECTORY "${SOURCE_DIR}"
            RESULT_VARIABLE result OUTPUT_QUIET ERROR_QUIET)
        if(NOT result EQUAL 0)
            list(APPEND unparsed "${file}")
        endif()
    endforeach()
    # A file that doesn't compile gets no fixes; formatting still goes on, and the build
    # reports the error.
    if(unparsed)
        list(JOIN unparsed "\n  " unparsed_list)
        message(WARNING "cpp-policy format: trailing commas not fixed in files that don't "
                        "compile:\n  ${unparsed_list}")
    endif()
endfunction()

run_clang_format()
if(MODE STREQUAL "fix")
    fix_trailing_commas()
    run_clang_format()
endif()

list(LENGTH files count)
message("cpp-policy format ${MODE}: OK (${count} files)")

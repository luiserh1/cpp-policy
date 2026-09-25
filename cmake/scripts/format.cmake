# Format check / fix using the policy's .clang-format.
#
#   cmake -DCONFIG=<cpp_policy_config.cmake> -DMODE=check|fix -P format.cmake

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

list(LENGTH files count)
if(failed)
    list(JOIN failed "\n  " failed_list)
    if(MODE STREQUAL "check")
        message(FATAL_ERROR "cpp-policy format: badly formatted files:\n  ${failed_list}\n"
                            "Run: cmake --build --preset <preset> --target policy-format-fix")
    endif()
    message(FATAL_ERROR "cpp-policy format: clang-format failed on:\n  ${failed_list}\n"
                        "See its output above (usually a file it could not parse).")
endif()
message("cpp-policy format ${MODE}: OK (${count} files)")

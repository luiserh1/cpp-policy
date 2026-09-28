# A changed .clang-tidy re-checks files that are already built.
#
#   cmake -DPOLICY_ROOT=<dir> -DWORK=<dir> -DCXX=<compiler> -DMAKE_PROGRAM=<ninja> -P run.cmake
#
# A throwaway project uses a copy of the policy. It builds clean; then the copy's .clang-tidy
# loses the option that lets std::bad_array_new_length escape a noexcept function, and the next
# build, with no source changed, must report bugprone-exception-escape. This is what happens
# to a project when an upgrade changes .clang-tidy.

cmake_minimum_required(VERSION 3.29)

set(policy "${WORK}/policy")
set(project "${WORK}/project")
file(REMOVE_RECURSE "${WORK}")
file(MAKE_DIRECTORY "${policy}" "${project}")
file(COPY "${POLICY_ROOT}/cmake" DESTINATION "${policy}")
file(COPY_FILE "${POLICY_ROOT}/.clang-tidy" "${policy}/.clang-tidy")

file(WRITE "${project}/CMakeLists.txt"
    "cmake_minimum_required(VERSION 3.29)\n"
    "project(tidy_rebuild LANGUAGES CXX)\n"
    "include(\"${policy}/cmake/CppPolicy.cmake\")\n"
    "add_library(buffers OBJECT buffers.cpp)\n"
    "cpp_policy_apply(buffers)\n")
file(COPY_FILE "${POLICY_ROOT}/tests/good/allocation.hpp" "${project}/allocation.hpp")
file(COPY_FILE "${POLICY_ROOT}/tests/good/allocation.cpp" "${project}/buffers.cpp")

function(build)
    execute_process(COMMAND "${CMAKE_COMMAND}" --build "${project}/build"
        RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
    set(code "${code}" PARENT_SCOPE)
    set(out "${out}${err}" PARENT_SCOPE)
endfunction()

execute_process(
    COMMAND "${CMAKE_COMMAND}" -S "${project}" -B "${project}/build" -G Ninja
            "-DCMAKE_MAKE_PROGRAM=${MAKE_PROGRAM}" "-DCMAKE_CXX_COMPILER=${CXX}"
            -DCPP_POLICY_CLANG_TIDY=ON
    RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT code EQUAL 0)
    message(FATAL_ERROR "tidy_rebuild: configuring failed\n${out}${err}")
endif()
build()
if(NOT code EQUAL 0)
    message(FATAL_ERROR "tidy_rebuild: the first build must pass\n${out}")
endif()

# The rule changes; no source does.
file(READ "${policy}/.clang-tidy" config)
string(REGEX REPLACE "\n[^\n]*IgnoredExceptions[^\n]*" "" stricter "${config}")
if(stricter STREQUAL config)
    message(FATAL_ERROR "tidy_rebuild: .clang-tidy has no IgnoredExceptions line to remove")
endif()
file(WRITE "${policy}/.clang-tidy" "${stricter}")
build()
string(FIND "${out}" "bugprone-exception-escape" found)
if(code EQUAL 0 OR found EQUAL -1)
    message(FATAL_ERROR "tidy_rebuild: after .clang-tidy changed, the build didn't re-check "
                        "buffers.cpp\n${out}")
endif()

# And back: the finding goes away without touching the source either.
file(WRITE "${policy}/.clang-tidy" "${config}")
build()
if(NOT code EQUAL 0)
    message(FATAL_ERROR "tidy_rebuild: restoring .clang-tidy must make the build pass\n${out}")
endif()
message("tidy_rebuild: OK")

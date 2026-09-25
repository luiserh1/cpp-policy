# Git hook behavior, checked in a throwaway repository (POLICY.md 8).
#
#   cmake -DPOLICY_ROOT=<dir> -DWORK=<dir> -DCXX=<compiler> -DMAKE_PROGRAM=<ninja>
#         -P run.cmake
#
# - configure warns while core.hooksPath is not set, and stops warning once it is;
# - pre-push runs the gate on a clean working folder and refuses a dirty one;
# - pre-commit warns about unstaged changes and still runs its checks.
# A stub `cmake` on PATH stands in for the real gate, so only the hooks' own logic runs.

cmake_minimum_required(VERSION 3.29)
find_package(Git REQUIRED)

set(repo "${WORK}/repo")
file(REMOVE_RECURSE "${WORK}")
file(MAKE_DIRECTORY "${repo}/tools" "${WORK}/stub")
file(COPY "${POLICY_ROOT}/tools/hooks" DESTINATION "${repo}/tools")
file(WRITE "${repo}/CMakeLists.txt"
    "cmake_minimum_required(VERSION 3.29)\n"
    "project(hooks_fixture LANGUAGES CXX)\n"
    "include([==[${POLICY_ROOT}/cmake/CppPolicy.cmake]==])\n"
    "cpp_policy_add_checks()\n")
file(WRITE "${repo}/tracked.txt" "committed\n")
file(WRITE "${WORK}/stub/cmake" "#!/bin/sh\necho \"stub cmake $*\"\n")
file(CHMOD "${WORK}/stub/cmake" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)

function(run)
    execute_process(COMMAND ${ARGN} WORKING_DIRECTORY "${repo}"
        RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
    set(code "${code}" PARENT_SCOPE)
    set(out "${out}${err}" PARENT_SCOPE)
endfunction()

# `condition` is a list (e.g. "code;EQUAL;0"): a string with spaces would reach if() as a
# single argument.
function(expect condition what)
    if(NOT (${condition}))
        message(FATAL_ERROR "hooks: ${what} (exit code ${code})\n--- output ---\n${out}")
    endif()
endfunction()

run("${GIT_EXECUTABLE}" init --quiet)
run("${GIT_EXECUTABLE}" add --all)
run("${GIT_EXECUTABLE}" -c user.name=test -c user.email=test@example.com commit --quiet -m init)
expect("code;EQUAL;0" "could not create the test repository")

set(configure "${CMAKE_COMMAND}" --fresh -S "${repo}" -B "${WORK}/build" -G Ninja
    "-DCMAKE_MAKE_PROGRAM=${MAKE_PROGRAM}" "-DCMAKE_CXX_COMPILER=${CXX}")

run(${configure})
string(FIND "${out}" "git hooks are not enabled" found)
expect("code;EQUAL;0;AND;found;GREATER;-1" "configure must warn while core.hooksPath is unset")

run("${GIT_EXECUTABLE}" config core.hooksPath tools/hooks)
run(${configure})
string(FIND "${out}" "git hooks are not enabled" found)
expect("code;EQUAL;0;AND;found;EQUAL;-1" "configure must not warn once core.hooksPath is set")

set(with_stub "${CMAKE_COMMAND}" -E env "PATH=${WORK}/stub:$ENV{PATH}" sh)

run(${with_stub} tools/hooks/pre-push)
string(FIND "${out}" "stub cmake --workflow" found)
expect("code;EQUAL;0;AND;found;GREATER;-1" "pre-push must run the gate on a clean working folder")

file(WRITE "${repo}/tracked.txt" "changed but not committed\n")
run(${with_stub} tools/hooks/pre-push)
string(FIND "${out}" "uncommitted changes" found)
expect("NOT;code;EQUAL;0;AND;found;GREATER;-1" "pre-push must refuse a working folder with uncommitted changes")

run(${with_stub} tools/hooks/pre-commit)
string(FIND "${out}" "unstaged changes" warned)
string(FIND "${out}" "stub cmake --build" checked)
expect("code;EQUAL;0;AND;warned;GREATER;-1;AND;checked;GREATER;-1"
    "pre-commit must warn about unstaged changes and still run its checks")

message("hooks: OK")

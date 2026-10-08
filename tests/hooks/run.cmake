# Git hook behavior, checked in a throwaway repository (POLICY.md 8).
#
#   cmake -DPOLICY_ROOT=<dir> -DWORK=<dir> -DCXX=<compiler> -DMAKE_PROGRAM=<ninja>
#         -P run.cmake
#
# - configure warns while core.hooksPath is not set, and stops warning once it is;
# - pre-push runs the gate on a clean working folder and refuses a dirty one;
# - pre-commit warns about unstaged changes and still runs its checks;
# - commit-msg accepts and rejects messages by its rules.
# On Windows the scripts run under the sh of Git for Windows, as git runs them there.
# A stub `cmake` on PATH stands in for the real gate, so only the hooks' own logic runs.

cmake_minimum_required(VERSION 3.29)
find_package(Git REQUIRED)

# Git exports GIT_DIR (and at times GIT_WORK_TREE and GIT_INDEX_FILE) to hooks. When pre-push runs
# the gate in a linked worktree, GIT_DIR is an absolute path to the real repository, and every git
# command below would act on it instead of the throwaway one (it once set core.bare there).
foreach(variable IN ITEMS GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY)
    unset(ENV{${variable}})
endforeach()

# The shell that runs the scripts. On Windows it is the one Git for Windows ships and runs
# hooks with, found next to git; another sh on PATH (a different toolkit's) would test
# something users don't run.
if(CMAKE_HOST_WIN32)
    cmake_path(GET GIT_EXECUTABLE PARENT_PATH git_bin)
    find_program(SH_EXECUTABLE sh
        HINTS "${git_bin}/../bin" "${git_bin}/../usr/bin" "${git_bin}/../../usr/bin"
              "${git_bin}/../../bin"
        NO_DEFAULT_PATH REQUIRED)
else()
    find_program(SH_EXECUTABLE sh REQUIRED)
endif()
# The throwaway repositories keep the line endings the test writes, whatever this machine's
# git configuration converts (Git for Windows defaults to CRLF on checkout).
set(ENV{GIT_CONFIG_COUNT} 1)
set(ENV{GIT_CONFIG_KEY_0} core.autocrlf)
set(ENV{GIT_CONFIG_VALUE_0} false)

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

# Runs a script with the stubs first on PATH. The shell adds the folder itself: its PATH is
# separated by ":" on every system, and under Git for Windows `pwd` gives the folder in the
# form that PATH needs (/c/..., not C:/...). No ";" in the command: it would split the list.
# In a hook of a linked worktree git exports GIT_DIR, naming the project's repository. The
# policy's commit, which the audit compares the CI pins with, must still be the policy's.
execute_process(COMMAND "${GIT_EXECUTABLE}" rev-parse --show-toplevel HEAD
    WORKING_DIRECTORY "${POLICY_ROOT}" RESULT_VARIABLE not_a_checkout
    OUTPUT_VARIABLE policy_git OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
if(NOT not_a_checkout)
    string(REGEX REPLACE "^.*\n" "" policy_commit "${policy_git}")
    run("${CMAKE_COMMAND}" -E env "GIT_DIR=${repo}/.git" ${configure})
    file(STRINGS "${WORK}/build/cpp_policy_config.cmake" pinned REGEX "^set\\(POLICY_COMMIT ")
    string(FIND "${pinned}" "${policy_commit}" found)
    expect("code;EQUAL;0;AND;found;GREATER;-1"
        "with GIT_DIR set, configure must still record the policy's own commit: ${pinned}")
endif()

set(with_stub "${SH_EXECUTABLE}" -c
    "PATH=\"$(cd \"$1\" && pwd):$PATH\" && export PATH && shift && exec sh \"$@\"" with-stub
    "${WORK}/stub")
# Git for Windows' own uname makes the hooks choose win-check.
if(CMAKE_HOST_WIN32)
    set(preset win-check)
else()
    set(preset check)
endif()

run(${with_stub} tools/hooks/pre-push)
string(FIND "${out}" "stub cmake --workflow" found)
expect("code;EQUAL;0;AND;found;GREATER;-1" "pre-push must run the gate on a clean working folder")

file(WRITE "${repo}/tracked.txt" "changed but not committed\n")
run(${with_stub} tools/hooks/pre-push)
string(FIND "${out}" "uncommitted changes" found)
expect("NOT;code;EQUAL;0;AND;found;GREATER;-1" "pre-push must refuse a working folder with uncommitted changes")

run(${with_stub} tools/hooks/pre-commit)
string(FIND "${out}" "unstaged changes" warned)
string(FIND "${out}" "stub cmake --build --preset ${preset} " checked)
expect("code;EQUAL;0;AND;warned;GREATER;-1;AND;checked;GREATER;-1"
    "pre-commit must warn about unstaged changes and still run its checks")

# Under Git for Windows, uname reports MINGW64_NT-...; both hooks must then use the
# win-check preset, which the `check` preset's condition disables there. A stub uname
# stands in for that shell, so the case is covered on every platform; on Windows the runs
# above already had the real one.
file(WRITE "${WORK}/stub/uname" "#!/bin/sh\necho MINGW64_NT-10.0-19045\n")
file(CHMOD "${WORK}/stub/uname" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
run(${with_stub} tools/hooks/pre-commit)
string(FIND "${out}" "stub cmake --build --preset win-check " checked)
expect("code;EQUAL;0;AND;checked;GREATER;-1"
    "pre-commit must use the win-check preset under Git for Windows")
run("${GIT_EXECUTABLE}" checkout -- tracked.txt)
run(${with_stub} tools/hooks/pre-push)
string(FIND "${out}" "stub cmake --workflow --preset win-check" found)
expect("code;EQUAL;0;AND;found;GREATER;-1" "pre-push must use the win-check preset under Git for Windows")

# commit-msg: one message per rule. Each case is "accept" or "reject" and a message.
function(check_message verdict text what)
    file(WRITE "${WORK}/message.txt" "${text}")
    run("${SH_EXECUTABLE}" tools/hooks/commit-msg "${WORK}/message.txt")
    if(verdict STREQUAL "accept")
        expect("code;EQUAL;0" "commit-msg must accept ${what}")
    else()
        string(FIND "${out}" "the message is kept in ${WORK}/message.txt" kept)
        expect("NOT;code;EQUAL;0;AND;kept;GREATER;-1"
            "commit-msg must reject ${what}, and say where the message is kept")
    endif()
endfunction()
set(why "\n\nWhy it changed.\n")
check_message(accept "fix(hooks): pick the win-check preset${why}" "type(scope): summary with a body")
check_message(accept "feat: add a check${why}" "a subject without a scope")
check_message(accept "feat(audit)!: fail on long files${why}" "a breaking change marker")
check_message(accept "docs: explain\n\nWhy.\n\nCo-Authored-By: A <a@example.com>\n" "a body followed by trailers")
check_message(accept "# a comment git drops\nci: pin actions${why}# another\n" "comment lines, which git drops")
check_message(accept "Merge branch 'main' into topic\n" "a merge message")
check_message(accept "Revert \"feat: add a check\"\n" "a revert message from git")
check_message(accept "fixup! feat: add a check\n" "a fixup! message")
check_message(reject "Add a check${why}" "a subject without a type")
check_message(reject "feature: add a check${why}" "an unknown type")
check_message(reject "fix(Hooks): pick a preset${why}" "an upper-case scope")
check_message(reject "fix:no space${why}" "a missing space after the colon")
string(REPEAT "x" 64 long)
# "fix: " is 5 characters.
check_message(reject "fix: ${long}xxxx${why}" "a subject of 73 characters")
check_message(accept "fix: ${long}xxx${why}" "a subject of 72 characters")
check_message(reject "fix: add a check\n" "a message without a body")
check_message(reject "fix: add a check\nWhy.\n" "a body not separated by a blank line")
check_message(reject "fix: add a check\n\nCo-Authored-By: A <a@example.com>\n" "a body of trailers only")

message("hooks: OK")

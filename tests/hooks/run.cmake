# Git hook behavior, checked in a throwaway repository (POLICY.md 8).
#
#   cmake -DPOLICY_ROOT=<dir> -DWORK=<dir> -DCXX=<compiler> -DMAKE_PROGRAM=<ninja>
#         -P run.cmake
#
# - configure warns while core.hooksPath is not set, and stops warning once it is;
# - pre-push runs the gate on a clean working folder and refuses a dirty one;
# - pre-commit checks the staged files only, and warns about a staged file with unstaged
#   changes;
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

# The gate's launcher lets one gate run at a time on the machine. This test may itself be
# running inside a gate that holds that lock, so the hooks it runs get a lock of their own.
set(ENV{CPP_POLICY_GATE_LOCK} "${WORK}/gate.lock")

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

# pre-commit hands the staged files to tidy-files, a stub here, and nothing else: a changed
# file that isn't staged is neither checked nor named.
file(WRITE "${repo}/tools/hooks/tidy-files" "#!/bin/sh\necho \"stub tidy-files $*\"\n")
run(${with_stub} tools/hooks/pre-commit)
string(FIND "${out}" "stub tidy-files" checked)
string(FIND "${out}" "tracked.txt" named)
expect("code;EQUAL;0;AND;checked;EQUAL;-1;AND;named;EQUAL;-1"
    "pre-commit with nothing staged must check nothing and name no unstaged file")
file(WRITE "${repo}/notes.txt" "a document\n")
run("${GIT_EXECUTABLE}" add notes.txt)
run(${with_stub} tools/hooks/pre-commit)
string(FIND "${out}" "stub" ran)
expect("code;EQUAL;0;AND;ran;EQUAL;-1"
    "pre-commit with no C++ file staged must run neither tidy-files nor cmake")
run("${GIT_EXECUTABLE}" reset --quiet -- notes.txt)
file(REMOVE "${repo}/notes.txt")
file(WRITE "${repo}/staged.cpp" "first\n")
run("${GIT_EXECUTABLE}" add staged.cpp)
run(${with_stub} tools/hooks/pre-commit)
string(FIND "${out}" "stub tidy-files staged.cpp" checked)
string(FIND "${out}" "tracked.txt" named)
string(FIND "${out}" "unstaged changes" warned)
expect("code;EQUAL;0;AND;checked;GREATER;-1;AND;named;EQUAL;-1;AND;warned;EQUAL;-1"
    "pre-commit must check the staged file only, without a warning")
file(WRITE "${repo}/staged.cpp" "second\n")
run(${with_stub} tools/hooks/pre-commit)
string(FIND "${out}" "unstaged changes too" warned)
string(FIND "${out}" "  staged.cpp" named)
expect("code;EQUAL;0;AND;warned;GREATER;-1;AND;named;GREATER;-1"
    "pre-commit must name a staged file that has unstaged changes too")
run("${GIT_EXECUTABLE}" reset --quiet -- staged.cpp)
file(REMOVE "${repo}/staged.cpp")
# Through git: rewriting the file left it changed on Windows, and pre-push then refused.
run("${GIT_EXECUTABLE}" checkout -- tools/hooks/tidy-files)

# Under Git for Windows, uname reports MINGW64_NT-...; pre-push and the gate must then use
# the win-check preset, which the `check` preset's condition disables there. A stub uname
# stands in for that shell, so the case is covered on every platform; on Windows the runs
# above already had the real one.
file(WRITE "${WORK}/stub/uname" "#!/bin/sh\necho MINGW64_NT-10.0-19045\n")
file(CHMOD "${WORK}/stub/uname" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
run("${GIT_EXECUTABLE}" checkout -- tracked.txt)
run(${with_stub} tools/hooks/pre-push)
string(FIND "${out}" "stub cmake --workflow --preset win-check" found)
expect("code;EQUAL;0;AND;found;GREATER;-1" "pre-push must use the win-check preset under Git for Windows")

# The gate's launcher: one final line, the workflow's own exit code, another workflow by
# name, and a lock left by a gate that is gone.
run(${with_stub} tools/hooks/gate)
string(FIND "${out}" "gate: passed (win-check)" found)
expect("code;EQUAL;0;AND;found;GREATER;-1" "the gate must end by saying that it passed")
run(${with_stub} tools/hooks/gate release)
string(FIND "${out}" "stub cmake --workflow --preset win-release" found)
expect("code;EQUAL;0;AND;found;GREATER;-1" "the gate must run the workflow it is given")
# 99999999 is no process: the launcher must take the lock over, not wait for it.
file(MAKE_DIRECTORY "$ENV{CPP_POLICY_GATE_LOCK}")
file(WRITE "$ENV{CPP_POLICY_GATE_LOCK}/pid" "99999999\n")
run(${with_stub} tools/hooks/gate)
string(FIND "${out}" "taking it over" found)
expect("code;EQUAL;0;AND;found;GREATER;-1" "a lock left by a gate that is gone must be taken over")
if(EXISTS "$ENV{CPP_POLICY_GATE_LOCK}")
    message(FATAL_ERROR "hooks: the gate left its lock behind")
endif()
# A lock folder that names no process, made over a minute ago, is taken over too.
file(MAKE_DIRECTORY "$ENV{CPP_POLICY_GATE_LOCK}")
execute_process(COMMAND "${SH_EXECUTABLE}" -c "touch -t 202001010000 \"$1\"" touch
    "$ENV{CPP_POLICY_GATE_LOCK}")
run(${with_stub} tools/hooks/gate)
string(FIND "${out}" "named no process for over a minute; taking it over" found)
expect("code;EQUAL;0;AND;found;GREATER;-1" "an old lock that names no process must be taken over")
# A lock path that is a file can never become a lock: the gate fails at once.
set(folder_lock "$ENV{CPP_POLICY_GATE_LOCK}")
set(ENV{CPP_POLICY_GATE_LOCK} "${WORK}/gate.lock.file")
file(WRITE "$ENV{CPP_POLICY_GATE_LOCK}" "")
run(${with_stub} tools/hooks/gate)
string(FIND "${out}" "is a file; CPP_POLICY_GATE_LOCK names a folder" found)
expect("code;EQUAL;2;AND;found;GREATER;-1" "a lock path that is a file must fail the gate at once")
set(ENV{CPP_POLICY_GATE_LOCK} "${folder_lock}")
file(WRITE "${WORK}/stub/cmake" "#!/bin/sh\necho \"stub cmake $*\"\nexit 3\n")
run(${with_stub} tools/hooks/gate)
string(FIND "${out}" "gate: FAILED (win-check, exit code 3)" found)
expect("code;EQUAL;3;AND;found;GREATER;-1"
    "a failing workflow must end the gate with its exit code and say that it failed")
# A workflow that failed is remembered until it passes: pre-push refuses meanwhile and names
# it, though its own gate (the check workflow) would pass.
# (A project's .gitignore has build/; this repository says it here.)
file(APPEND "${repo}/.git/info/exclude" "build/\n")
run(${with_stub} tools/hooks/gate release)
expect("code;EQUAL;3" "a failing release workflow must fail the gate")
file(WRITE "${WORK}/stub/cmake" "#!/bin/sh\necho \"stub cmake $*\"\n")
run(${with_stub} tools/hooks/pre-push)
string(FIND "${out}" "the win-release workflow failed in this folder" found)
string(FIND "${out}" "stub cmake" started)
expect("NOT;code;EQUAL;0;AND;found;GREATER;-1;AND;started;EQUAL;-1"
    "pre-push must refuse while a workflow that failed has not passed again")
run(${with_stub} tools/hooks/gate release)
file(REMOVE "${repo}/build/cpp_policy_gate_passed_win-check")
run(${with_stub} tools/hooks/pre-push)
string(FIND "${out}" "gate: passed (win-check)" found)
expect("code;EQUAL;0;AND;found;GREATER;-1"
    "once the workflow passes again, pre-push must run the gate and pass")
# That gate passed on this commit with nothing uncommitted: the next push doesn't run it
# again. A new commit does.
run(${with_stub} tools/hooks/pre-push)
string(FIND "${out}" "not run again" found)
string(FIND "${out}" "stub cmake" started)
expect("code;EQUAL;0;AND;found;GREATER;-1;AND;started;EQUAL;-1"
    "pre-push must not run the gate again on a commit it has just passed on")
run("${GIT_EXECUTABLE}" -c user.name=test -c user.email=test@example.com commit --quiet
    --allow-empty --no-verify -m "another commit")
run(${with_stub} tools/hooks/pre-push)
string(FIND "${out}" "stub cmake --workflow" started)
expect("code;EQUAL;0;AND;started;GREATER;-1" "pre-push must run the gate on a new commit")
# A project with a vcpkg.json and a shell without VCPKG_ROOT: the gate says so itself, at
# once, and doesn't start the workflow.
file(WRITE "${repo}/vcpkg.json" "{}\n")
set(vcpkg_root "$ENV{VCPKG_ROOT}")
unset(ENV{VCPKG_ROOT})
run(${with_stub} tools/hooks/gate)
string(FIND "${out}" "VCPKG_ROOT is not set" found)
string(FIND "${out}" "stub cmake" started)
expect("code;EQUAL;2;AND;found;GREATER;-1;AND;started;EQUAL;-1"
    "without VCPKG_ROOT the gate must stop before the workflow and name the variable")
file(WRITE "${repo}/code.cpp" "int main() {}\n")
run("${GIT_EXECUTABLE}" add vcpkg.json code.cpp)
run(${with_stub} tools/hooks/pre-commit)
string(FIND "${out}" "VCPKG_ROOT is not set" found)
string(FIND "${out}" "stub cmake" started)
expect("code;EQUAL;2;AND;found;GREATER;-1;AND;started;EQUAL;-1"
    "without VCPKG_ROOT pre-commit must stop before its checks and name the variable")
run("${GIT_EXECUTABLE}" reset --quiet -- vcpkg.json code.cpp)
file(REMOVE "${repo}/code.cpp")
set(ENV{VCPKG_ROOT} "${WORK}")
run(${with_stub} tools/hooks/gate)
string(FIND "${out}" "gate: passed" found)
expect("code;EQUAL;0;AND;found;GREATER;-1" "with VCPKG_ROOT set the gate must run")
set(ENV{VCPKG_ROOT} "${vcpkg_root}")
file(REMOVE "${repo}/vcpkg.json")

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

# tools/upgrade.sh, checked against a fake cpp-policy repository with two releases.
#
#   cmake -DPOLICY_ROOT=<dir> -DWORK=<dir> -P run.cmake
#
# - it moves the GIT_TAG pin and the CI gate pin to the new release's commit and tag, copies
#   the policy files (hooks executable), leaves other lines alone and shows the CHANGELOG entry;
# - it adds .claude/settings.json when the project has none;
# - in AGENTS.md it replaces everything above "## This project" and keeps the rest; a file
#   without that heading gets the release's part, the heading, and its old content below;
# - with a vcpkg.json, it copies tools/vcpkg/;
# - it refuses a working folder with uncommitted changes and an unknown tag, changing nothing.
# The gate isn't run (--no-gate): that needs a real project. On Windows the script runs under
# the sh of Git for Windows.

cmake_minimum_required(VERSION 3.29)
find_package(Git REQUIRED)

# Git exports GIT_DIR to hooks (see hooks/run.cmake): keep git on the throwaway repositories.
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

# Named cpp-policy: the script finds the pin by that name in GIT_REPOSITORY.
set(policy "${WORK}/cpp-policy")
set(project "${WORK}/project")
file(REMOVE_RECURSE "${WORK}")
file(MAKE_DIRECTORY "${policy}/tools/hooks" "${project}/tools/hooks" "${project}/.github/workflows")

set(git "${GIT_EXECUTABLE}" -c user.name=test -c user.email=test@example.com
    -c init.defaultBranch=main -c advice.detachedHead=false)

function(run dir)
    execute_process(COMMAND ${ARGN} WORKING_DIRECTORY "${dir}"
        RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
    set(code "${code}" PARENT_SCOPE)
    set(out "${out}${err}" PARENT_SCOPE)
endfunction()

function(expect condition what)
    if(NOT (${condition}))
        message(FATAL_ERROR "upgrade: ${what} (exit code ${code})\n--- output ---\n${out}")
    endif()
endfunction()

# Writes one release of the fake policy: every copied file says which release it is.
function(release version changelog)
    # The agent settings live under template/, as in the real repository.
    foreach(name IN ITEMS .clang-tidy .clang-format CMakePresets.json
                     template/.claude/settings.json tools/hooks/pre-commit tools/hooks/pre-push)
        file(WRITE "${policy}/${name}" "# ${name} of ${version}\n")
    endforeach()
    file(WRITE "${policy}/CHANGELOG.md" "# Changelog\n\n${changelog}")
    run("${policy}" ${git} add --all)
    run("${policy}" ${git} commit --quiet -m "Release ${version}")
    run("${policy}" ${git} tag -a "v${version}" -m "v${version}")
    expect("code;EQUAL;0" "could not tag the fake release ${version}")
endfunction()

run("${policy}" ${git} init --quiet)
release(1.0.0 "## 1.0.0 (2026-01-01)\n\nFirst.\n")
run("${policy}" ${git} rev-parse HEAD)
string(STRIP "${out}" old)
# Release 2.0.0 also adds a hook, like v0.8.0 added commit-msg, and the vcpkg files, like
# v0.15.0.
file(WRITE "${policy}/tools/hooks/commit-msg" "# commit-msg of 2.0.0\n")
set(vcpkg_files tools/vcpkg/setup.cmake tools/vcpkg/llvm.cmake
    tools/vcpkg/triplets/cpp-policy-asan.cmake tools/vcpkg/triplets/cpp-policy-tsan.cmake
    tools/vcpkg/triplets/cpp-policy-nosan.cmake)
foreach(name IN LISTS vcpkg_files)
    file(WRITE "${policy}/${name}" "# ${name} of 2.0.0\n")
endforeach()
# And the template of AGENTS.md, whose part above "## This project" the upgrade brings.
set(policy_part "# Instructions\n\n## Before you say you are done\n\nRun the gate of 2.0.0.\n\n## This project\n")
file(WRITE "${policy}/template/AGENTS.md.in" "${policy_part}")
# And its own upgrade.sh, which the one under test must hand over to: this script plus one
# line that says it ran.
file(READ "${POLICY_ROOT}/tools/upgrade.sh" script)
string(REPLACE "set -eu\n" "set -eu\necho \"upgrade.sh of 2.0.0 is running\"\n" script "${script}")
file(WRITE "${policy}/tools/upgrade.sh" "${script}")
release(2.0.0 "## 2.0.0 (2026-02-01)\n\nSecond: do the upgrade steps.\n\n## 1.0.0 (2026-01-01)\n\nFirst.\n")
run("${policy}" ${git} rev-parse HEAD)
string(STRIP "${out}" new)

# The project, on release 1.0.0, with dependencies loaded through tools/vcpkg/setup.cmake.
set(vcpkg_include "include(\"\${CMAKE_CURRENT_SOURCE_DIR}/tools/vcpkg/setup.cmake\")\n")
file(WRITE "${project}/vcpkg.json" "{ \"name\": \"fixture\", \"dependencies\": [] }\n")
file(WRITE "${project}/CMakeLists.txt"
    "cmake_minimum_required(VERSION 3.29)\n"
    "\n"
    "${vcpkg_include}"
    "\n"
    "project(fixture LANGUAGES CXX)\n"
    "include(FetchContent)\n"
    "FetchContent_Declare(cpp_policy\n"
    "    GIT_REPOSITORY file://${policy}/.git\n"
    "    GIT_TAG        ${old}) # v1.0.0\n"
    "FetchContent_MakeAvailable(cpp_policy)\n")
file(WRITE "${project}/.github/workflows/ci.yml"
    "on:\n"
    "  push:\n"
    "  workflow_dispatch:\n"
    "\n"
    "jobs:\n"
    "  gate:\n"
    "    uses: someone/cpp-policy/.github/workflows/gate.yml@${old} # v1.0.0\n"
    "    with:\n"
    "      vcpkg: true\n"
    "  benchmark:\n"
    "    uses: someone/cpp-policy/.github/workflows/benchmark.yml@${old} # v1.0.0\n")
# A workflow whose push has filters of its own is left alone, with a note.
set(own_filters "on:\n  push:\n    tags-ignore: ['v*']\n\njobs:\n  gate:\n"
    "    uses: someone/cpp-policy/.github/workflows/gate.yml@${old} # v1.0.0\n")
string(REPLACE ";" "" own_filters "${own_filters}")
file(WRITE "${project}/.github/workflows/nightly.yml" "${own_filters}")
# The project's own instructions and changelog. AGENTS.md is from before "## This project":
# policy and project mixed.
set(old_agents "# Fixture\n\nThe project's own words.\n\n## Before you say you are done\n\nRun the gate of 1.0.0.\n")
file(WRITE "${project}/AGENTS.md" "${old_agents}")
file(WRITE "${project}/CHANGELOG.md"
    "# Changelog\n\nPolicy: cpp-policy v1.0.0.\n\n## 0.1.0\n\nOn the policy v1.0.0 since the start.\n")
# Release 1.0.0's files, as the project copied them; .claude/settings.json is left out, as
# in a project generated before there was one.
run("${policy}" ${git} checkout --quiet v1.0.0 -- .)
foreach(name IN ITEMS .clang-tidy .clang-format CMakePresets.json tools/hooks/pre-commit
                     tools/hooks/pre-push)
    file(COPY_FILE "${policy}/${name}" "${project}/${name}")
endforeach()
run("${policy}" ${git} checkout --quiet main -- .)
run("${project}" ${git} init --quiet)
run("${project}" ${git} add --all)
run("${project}" ${git} commit --quiet -m init)
expect("code;EQUAL;0" "could not create the fake project")

set(upgrade "${SH_EXECUTABLE}" "${POLICY_ROOT}/tools/upgrade.sh")

# Refused: uncommitted changes.
file(APPEND "${project}/CMakeLists.txt" "# local edit\n")
run("${project}" ${upgrade} v2.0.0 --no-gate)
string(FIND "${out}" "uncommitted changes" found)
expect("NOT;code;EQUAL;0;AND;found;GREATER;-1" "it must refuse a working folder with uncommitted changes")
run("${project}" ${git} checkout --quiet -- CMakeLists.txt)

# Refused: a tag the policy doesn't have. Nothing may change.
run("${project}" ${upgrade} v9.9.9 --no-gate)
string(FIND "${out}" "can't fetch v9.9.9" found)
expect("NOT;code;EQUAL;0;AND;found;GREATER;-1" "it must fail on an unknown tag")
run("${project}" ${git} status --porcelain)
set(nothing "")
expect("out;STREQUAL;nothing" "an unknown tag must leave the project unchanged")

# The upgrade.
run("${project}" ${upgrade} v2.0.0 --no-gate)
expect("code;EQUAL;0" "the upgrade to v2.0.0 must succeed")
string(FIND "${out}" "Second: do the upgrade steps." changelog)
expect("changelog;GREATER;-1" "it must show the release's CHANGELOG entry")
string(FIND "${out}" "First." older)
expect("older;EQUAL;-1" "it must show only the new release's CHANGELOG entry")
file(READ "${project}/AGENTS.md" agents)
set(wanted "${policy_part}\n<!-- AGENTS.md as it was before cpp-policy v2.0.0, which put the policy's part\nabove. Keep what is this project's own, delete the rest, and remove this\ncomment. -->\n\n${old_agents}")
expect("agents;STREQUAL;wanted"
    "AGENTS.md without \"## This project\" must get the release's part, the heading, and its old content")
string(FIND "${out}" "Keep what is this project's own there" note)
expect("note;GREATER;-1" "it must say that AGENTS.md needs pruning once")
file(READ "${project}/CHANGELOG.md" project_changelog)
set(wanted "# Changelog\n\nPolicy: cpp-policy v2.0.0.\n\n## 0.1.0\n\nOn the policy v1.0.0 since the start.\n")
expect("project_changelog;STREQUAL;wanted" "the changelog's policy line must name v2.0.0, and only that line")
string(FIND "${out}" "update the line" reminder)
expect("reminder;EQUAL;-1" "it must not ask for a changelog line it has updated itself")

file(READ "${project}/CMakeLists.txt" cmake)
string(FIND "${cmake}" "GIT_TAG        ${new}) # v2.0.0\n" pinned)
string(FIND "${cmake}" "${old}" stale)
string(FIND "${cmake}" "GIT_REPOSITORY file://${policy}/.git\n" repository)
expect("pinned;GREATER;-1;AND;stale;EQUAL;-1;AND;repository;GREATER;-1"
    "GIT_TAG must pin v2.0.0's commit with its tag, and nothing else may change")
file(READ "${project}/.github/workflows/ci.yml" ci)
string(FIND "${ci}" "gate.yml@${new} # v2.0.0\n" pinned)
string(FIND "${ci}" "      vcpkg: true\n" untouched)
expect("pinned;GREATER;-1;AND;untouched;GREATER;-1" "the CI gate must be pinned to v2.0.0's commit")
string(FIND "${ci}" "benchmark.yml@${new} # v2.0.0\n" pinned)
expect("pinned;GREATER;-1" "the CI benchmark workflow must be pinned to v2.0.0's commit")
string(FIND "${ci}" "on:\n  push:\n    branches: ['**']\n  workflow_dispatch:\n" filtered)
expect("filtered;EQUAL;0" "a bare push trigger must get the branch filter, so a tag push runs nothing")
file(READ "${project}/.github/workflows/nightly.yml" nightly)
string(REPLACE "@${old}" "@${new}" nightly_wanted "${own_filters}")
string(REPLACE "# v1.0.0" "# v2.0.0" nightly_wanted "${nightly_wanted}")
expect("nightly;STREQUAL;nightly_wanted" "a push trigger with filters of its own must be left alone")
string(FIND "${out}" ".github/workflows/nightly.yml: check that a tag push starts no run" noted)
expect("noted;GREATER;-1" "a push trigger with filters of its own must be named in the output")
string(FIND "${out}" ".github/workflows/ci.yml: check" named)
expect("named;EQUAL;-1" "a bare push trigger, once filtered, must not be named")

foreach(name IN ITEMS .clang-tidy .clang-format CMakePresets.json
                     tools/hooks/pre-commit tools/hooks/pre-push)
    file(READ "${project}/${name}" content)
    set(wanted "# ${name} of 2.0.0\n")
    expect("content;STREQUAL;wanted" "${name} must be v2.0.0's copy")
endforeach()
file(READ "${project}/.claude/settings.json" content)
set(wanted "# template/.claude/settings.json of 2.0.0\n")
expect("content;STREQUAL;wanted" ".claude/settings.json must be v2.0.0's template/.claude/settings.json")
# Windows has no executable bit: Git for Windows runs a hook whatever its mode.
if(NOT CMAKE_HOST_WIN32)
    execute_process(COMMAND test -x "${project}/tools/hooks/pre-push" RESULT_VARIABLE code)
    expect("code;EQUAL;0" "the copied hooks must be executable")
endif()
file(READ "${project}/tools/hooks/commit-msg" content)
set(wanted "# commit-msg of 2.0.0\n")
expect("content;STREQUAL;wanted" "a hook the release adds must be copied")
string(FIND "${out}" "handing over to v2.0.0's own upgrade.sh" handed)
string(FIND "${out}" "upgrade.sh of 2.0.0 is running" ran)
expect("handed;GREATER;-1;AND;ran;GREATER;-1" "it must hand over to the release's own upgrade.sh")
string(FIND "${out}" "?? tools/hooks/commit-msg" listed)
expect("listed;GREATER;-1" "the changes shown must include a file the release adds")

# Once pruned, the next upgrade replaces the policy's part only.
file(WRITE "${project}/AGENTS.md"
    "# Old\n\nRun the gate of 1.0.0.\n\n## This project\n\nThe project's own words.\n")
run("${project}" ${git} add --all)
run("${project}" ${git} commit --quiet -m "upgraded")
run("${project}" ${upgrade} v2.0.0 --no-gate)
expect("code;EQUAL;0" "the upgrade of a pruned AGENTS.md must succeed")
file(READ "${project}/.github/workflows/ci.yml" ci)
string(REGEX MATCHALL "branches:" filters "${ci}")
list(LENGTH filters filters)
expect("filters;EQUAL;1" "a second upgrade must not add the branch filter again")
file(READ "${project}/AGENTS.md" agents)
set(wanted "${policy_part}\nThe project's own words.\n")
expect("agents;STREQUAL;wanted"
    "AGENTS.md must get the release's part above \"## This project\" and keep what is below")
run("${project}" ${git} checkout --quiet -- AGENTS.md)

# A project with a vcpkg.json gets the release's tools/vcpkg/, and the line that loads it stays.
foreach(name IN LISTS vcpkg_files)
    file(READ "${project}/${name}" content)
    set(wanted "# ${name} of 2.0.0\n")
    expect("content;STREQUAL;wanted" "${name} must be v2.0.0's copy")
endforeach()
string(FIND "${cmake}" "cmake_minimum_required(VERSION 3.29)\n\n${vcpkg_include}\nproject(fixture"
    kept)
expect("kept;GREATER;-1" "the line that loads vcpkg must stay as it was:\n${cmake}")

# --- A library's pin (POLICY.md 11.7): moved to a release's commit, with the tag beside it.
set(library "${WORK}/geometry")
file(MAKE_DIRECTORY "${library}")
run("${library}" ${git} init --quiet)
file(WRITE "${library}/library.cmake" "# release 1.0.0\n")
run("${library}" ${git} add --all)
run("${library}" ${git} commit --quiet -m "Release 1.0.0")
run("${library}" ${git} tag v1.0.0)
run("${library}" ${git} rev-parse HEAD)
string(STRIP "${out}" library_old)
file(WRITE "${library}/library.cmake" "# release 1.1.0\n")
run("${library}" ${git} commit --quiet -am "Release 1.1.0")
# An annotated tag, whose own object isn't the commit.
run("${library}" ${git} tag -a v1.1.0 -m v1.1.0)
run("${library}" ${git} rev-parse HEAD)
string(STRIP "${out}" library_new)
file(APPEND "${project}/CMakeLists.txt"
    "cpp_policy_use_library(geometry\n"
    "    GIT_REPOSITORY file://${library}/.git\n"
    "    GIT_TAG        ${library_old}) # v1.0.0\n"
    "cpp_policy_use_library(other\n"
    "    GIT_REPOSITORY file://${library}/.git\n"
    "    GIT_TAG        ${library_old}) # v1.0.0\n")
run("${project}" ${git} add --all)
run("${project}" ${git} commit --quiet -m "upgraded, and using two libraries")

run("${project}" ${upgrade} --library geometry v9.9.9 --no-gate)
string(FIND "${out}" "has no release v9.9.9" found)
expect("NOT;code;EQUAL;0;AND;found;GREATER;-1" "it must fail on a release the library doesn't have")
run("${project}" ${upgrade} --library missing v1.1.0 --no-gate)
string(FIND "${out}" "has no cpp_policy_use_library(missing" found)
expect("NOT;code;EQUAL;0;AND;found;GREATER;-1" "it must fail on a library the project doesn't use")
run("${project}" ${git} status --porcelain)
expect("out;STREQUAL;nothing" "a refused library upgrade must leave the project unchanged")

run("${project}" ${upgrade} --library geometry v1.1.0 --no-gate)
expect("code;EQUAL;0" "the library's upgrade to v1.1.0 must succeed")
file(READ "${project}/CMakeLists.txt" cmake)
string(FIND "${cmake}" "cpp_policy_use_library(geometry\n    GIT_REPOSITORY file://${library}/.git\n    GIT_TAG        ${library_new}) # v1.1.0\n" moved)
string(FIND "${cmake}" "cpp_policy_use_library(other\n    GIT_REPOSITORY file://${library}/.git\n    GIT_TAG        ${library_old}) # v1.0.0\n" kept)
string(FIND "${cmake}" "GIT_TAG        ${new}) # v2.0.0\n" policy_pin)
expect("moved;GREATER;-1;AND;kept;GREATER;-1;AND;policy_pin;GREATER;-1"
    "only the named library's pin must move, to the release's commit:\n${cmake}")

# --- The real layout: an upgrade to a release made of this repository's own files. The fake
# releases above say where each file is; this one has them where cpp-policy keeps them, so a
# path upgrade.sh gets wrong fails here.
set(real "${WORK}/real/cpp-policy")
set(real_project "${WORK}/real/project")
file(MAKE_DIRECTORY "${real}" "${real_project}/.github/workflows")
execute_process(COMMAND "${CMAKE_COMMAND}" -E env --unset=GIT_DIR "${GIT_EXECUTABLE}" ls-files
    WORKING_DIRECTORY "${POLICY_ROOT}" OUTPUT_VARIABLE tracked RESULT_VARIABLE code)
expect("code;EQUAL;0" "could not list this repository's files")
string(REPLACE "\n" ";" tracked "${tracked}")
foreach(name IN LISTS tracked)
    if(NOT name STREQUAL "" AND EXISTS "${POLICY_ROOT}/${name}")
        cmake_path(GET name PARENT_PATH folder)
        file(MAKE_DIRECTORY "${real}/${folder}")
        file(COPY_FILE "${POLICY_ROOT}/${name}" "${real}/${name}")
    endif()
endforeach()
run("${real}" ${git} init --quiet)
run("${real}" ${git} add --all)
run("${real}" ${git} commit --quiet -m "this repository's files")
run("${real}" ${git} tag v9.0.0)
run("${real}" ${git} rev-parse HEAD)
string(STRIP "${out}" real_commit)
file(WRITE "${real_project}/CMakeLists.txt"
    "cmake_minimum_required(VERSION 3.29)\n"
    "project(fixture LANGUAGES CXX)\n"
    "include(FetchContent)\n"
    "FetchContent_Declare(cpp_policy\n"
    "    GIT_REPOSITORY file://${real}/.git\n"
    "    GIT_TAG        ${old}) # v1.0.0\n"
    "FetchContent_MakeAvailable(cpp_policy)\n")
file(WRITE "${real_project}/vcpkg.json" "{ \"name\": \"fixture\", \"dependencies\": [] }\n")
file(WRITE "${real_project}/.github/workflows/ci.yml"
    "jobs:\n  gate:\n    uses: someone/cpp-policy/.github/workflows/gate.yml@${old} # v1.0.0\n")
file(WRITE "${real_project}/AGENTS.md" "${old_agents}")
file(WRITE "${real_project}/CHANGELOG.md" "# Changelog\n\nPolicy: cpp-policy v1.0.0.\n")
run("${real_project}" ${git} init --quiet)
run("${real_project}" ${git} add --all)
run("${real_project}" ${git} commit --quiet -m init)
# Without --no-gate, the upgrade ends with the local gate, through its launcher; a stub cmake
# stands in for the workflow.
file(WRITE "${WORK}/stub/cmake" "#!/bin/sh\necho \"stub cmake $*\"\n")
file(CHMOD "${WORK}/stub/cmake" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
# The launcher's lock is machine-wide, and this test may run inside a gate that holds it.
run("${real_project}" "${CMAKE_COMMAND}" -E env "VCPKG_ROOT=${WORK}/vcpkg"
    "CPP_POLICY_GATE_LOCK=${WORK}/gate.lock" ${SH_EXECUTABLE} -c
    "PATH=\"$(cd \"$1\" && pwd):$PATH\" && export PATH && shift && exec sh \"$@\"" with-stub
    "${WORK}/stub" "${POLICY_ROOT}/tools/upgrade.sh" v9.0.0)
expect("code;EQUAL;0" "the upgrade to a release with this repository's layout must succeed")
string(REGEX MATCH "stub cmake --workflow --preset (win-)?check[^\n]*\n[^\n]*gate: passed" gated
    "${out}")
set(none "")
expect("NOT;gated;STREQUAL;none" "the upgrade must end with the local gate, through its launcher")
foreach(pair IN ITEMS ".claude/settings.json=template/.claude/settings.json"
                      ".clang-tidy=.clang-tidy" "tools/hooks/gate=tools/hooks/gate"
                      "tools/vcpkg/setup.cmake=tools/vcpkg/setup.cmake")
    string(REPLACE "=" ";" pair "${pair}")
    list(GET pair 0 copy)
    list(GET pair 1 source)
    file(READ "${real_project}/${copy}" content)
    file(READ "${real}/${source}" wanted)
    expect("content;STREQUAL;wanted" "${copy} must be the release's ${source}")
endforeach()
file(READ "${real_project}/AGENTS.md" agents)
string(FIND "${agents}" "\n## This project\n" heading)
string(FIND "${agents}" "${old_agents}" kept)
expect("heading;GREATER;-1;AND;kept;GREATER;heading"
    "AGENTS.md must get the release's part, the heading, and the old file below it")

message("upgrade: OK")

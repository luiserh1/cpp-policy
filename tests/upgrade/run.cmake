# tools/upgrade.sh, checked against a fake cpp-policy repository with two releases.
#
#   cmake -DPOLICY_ROOT=<dir> -DWORK=<dir> -P run.cmake
#
# - it moves the GIT_TAG pin and the CI gate pin to the new release's commit and tag, copies
#   the policy files (hooks executable), leaves other lines alone and shows the CHANGELOG entry;
# - with a vcpkg.json, it copies tools/vcpkg/ and replaces the lines that loaded vcpkg before
#   v0.15.0 with an include of tools/vcpkg/setup.cmake;
# - it refuses a working folder with uncommitted changes, an unknown tag, and vcpkg lines it
#   doesn't know, changing nothing.
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
    foreach(name IN ITEMS .clang-tidy .clang-format CMakePresets.json tools/hooks/pre-commit
                     tools/hooks/pre-push)
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
# And its own upgrade.sh, which the one under test must hand over to: this script plus one
# line that says it ran.
file(READ "${POLICY_ROOT}/tools/upgrade.sh" script)
string(REPLACE "set -eu\n" "set -eu\necho \"upgrade.sh of 2.0.0 is running\"\n" script "${script}")
file(WRITE "${policy}/tools/upgrade.sh" "${script}")
release(2.0.0 "## 2.0.0 (2026-02-01)\n\nSecond: do the upgrade steps.\n\n## 1.0.0 (2026-01-01)\n\nFirst.\n")
run("${policy}" ${git} rev-parse HEAD)
string(STRIP "${out}" new)

# The project, on release 1.0.0, with dependencies loaded the way releases before v0.15.0 did.
set(old_vcpkg_lines
    "# vcpkg's toolchain is loaded here, before project(), so CMakePresets.json stays cpp-policy's\n"
    "# unchanged copy. Without VCPKG_ROOT its path would be broken, and CMake's own error doesn't say\n"
    "# why (cpp-policy POLICY.md 1.1).\n"
    "if(NOT DEFINED ENV{VCPKG_ROOT})\n"
    "    message(FATAL_ERROR \"VCPKG_ROOT is not set: set it to the vcpkg directory (README: Building).\")\n"
    "endif()\n"
    "set(CMAKE_TOOLCHAIN_FILE \"\$ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake\" CACHE FILEPATH\n"
    "    \"vcpkg's toolchain (the presets are cpp-policy's unchanged copy)\")\n")
string(JOIN "" old_vcpkg_lines ${old_vcpkg_lines})
file(WRITE "${project}/vcpkg.json" "{ \"name\": \"fixture\", \"dependencies\": [] }\n")
file(WRITE "${project}/CMakeLists.txt"
    "cmake_minimum_required(VERSION 3.29)\n"
    "\n"
    "${old_vcpkg_lines}"
    "\n"
    "project(fixture LANGUAGES CXX)\n"
    "include(FetchContent)\n"
    "FetchContent_Declare(cpp_policy\n"
    "    GIT_REPOSITORY file://${policy}/.git\n"
    "    GIT_TAG        ${old}) # v1.0.0\n"
    "FetchContent_MakeAvailable(cpp_policy)\n")
file(WRITE "${project}/.github/workflows/ci.yml"
    "jobs:\n"
    "  gate:\n"
    "    uses: someone/cpp-policy/.github/workflows/gate.yml@${old} # v1.0.0\n"
    "    with:\n"
    "      vcpkg: true\n")
# Release 1.0.0's files, as the project copied them.
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

# Refused: vcpkg loaded with other lines than the old releases gave. Nothing may change.
file(READ "${project}/CMakeLists.txt" cmake)
string(REPLACE "(README: Building)" "(see our wiki)" edited "${cmake}")
file(WRITE "${project}/CMakeLists.txt" "${edited}")
run("${project}" ${git} commit --quiet -am "our own vcpkg lines")
run("${project}" ${upgrade} v2.0.0 --no-gate)
string(FIND "${out}" "doesn't load vcpkg with the lines" found)
expect("NOT;code;EQUAL;0;AND;found;GREATER;-1" "it must refuse vcpkg lines it doesn't know")
run("${project}" ${git} status --porcelain)
expect("out;STREQUAL;nothing" "unknown vcpkg lines must leave the project unchanged")
run("${project}" ${git} reset --quiet --hard HEAD~1)

# The upgrade.
run("${project}" ${upgrade} v2.0.0 --no-gate)
expect("code;EQUAL;0" "the upgrade to v2.0.0 must succeed")
string(FIND "${out}" "Second: do the upgrade steps." changelog)
expect("changelog;GREATER;-1" "it must show the release's CHANGELOG entry")
string(FIND "${out}" "First." older)
expect("older;EQUAL;-1" "it must show only the new release's CHANGELOG entry")

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

foreach(name IN ITEMS .clang-tidy .clang-format CMakePresets.json tools/hooks/pre-commit
                     tools/hooks/pre-push)
    file(READ "${project}/${name}" content)
    set(wanted "# ${name} of 2.0.0\n")
    expect("content;STREQUAL;wanted" "${name} must be v2.0.0's copy")
endforeach()
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

# A project with a vcpkg.json gets the release's tools/vcpkg/, loaded by one include in place
# of the old lines, with the rest of CMakeLists.txt as it was.
foreach(name IN LISTS vcpkg_files)
    file(READ "${project}/${name}" content)
    set(wanted "# ${name} of 2.0.0\n")
    expect("content;STREQUAL;wanted" "${name} must be v2.0.0's copy")
endforeach()
string(FIND "${cmake}" "${old_vcpkg_lines}" stale)
string(FIND "${cmake}" "cmake_minimum_required(VERSION 3.29)\n\n# vcpkg is loaded before project()"
    replaced)
string(FIND "${cmake}"
    "include(\"\${CMAKE_CURRENT_SOURCE_DIR}/tools/vcpkg/setup.cmake\")\n\nproject(fixture" included)
expect("stale;EQUAL;-1;AND;replaced;GREATER;-1;AND;included;GREATER;-1"
    "the old vcpkg lines must become the include of tools/vcpkg/setup.cmake, in their place:\n${cmake}")

message("upgrade: OK")

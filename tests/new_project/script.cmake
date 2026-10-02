# tools/new-project.sh itself, the wrapper around new_project.cmake (which run.cmake covers):
# it must pin the project to the release the policy copy is checked out at and to the vcpkg
# baseline, make the folder a git repository with the hooks enabled, and refuse a policy copy
# that isn't at a release tag or has uncommitted changes.
#
#   cmake -DPOLICY_ROOT=<dir> -DWORK=<dir> -P script.cmake
#
# It runs on a copy of the policy's files in a throwaway repository tagged v9.9.9, and a
# throwaway repository stands in for vcpkg. On Windows the script runs under the sh of Git
# for Windows.

cmake_minimum_required(VERSION 3.29)
find_package(Git REQUIRED)

# Git exports GIT_DIR to hooks (see hooks/run.cmake): keep git on the throwaway repositories.
foreach(variable IN ITEMS GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY)
    unset(ENV{${variable}})
endforeach()
if(CMAKE_HOST_WIN32)
    cmake_path(GET GIT_EXECUTABLE PARENT_PATH git_bin)
    find_program(SH_EXECUTABLE sh
        HINTS "${git_bin}/../bin" "${git_bin}/../usr/bin" "${git_bin}/../../usr/bin"
              "${git_bin}/../../bin"
        NO_DEFAULT_PATH REQUIRED)
else()
    find_program(SH_EXECUTABLE sh REQUIRED)
endif()
set(ENV{GIT_CONFIG_COUNT} 1)
set(ENV{GIT_CONFIG_KEY_0} core.autocrlf)
set(ENV{GIT_CONFIG_VALUE_0} false)

set(policy "${WORK}/cpp-policy")
set(vcpkg "${WORK}/vcpkg")
set(dest "${WORK}/MyTool")
file(REMOVE_RECURSE "${WORK}")
file(MAKE_DIRECTORY "${policy}/cmake" "${vcpkg}")
file(COPY "${POLICY_ROOT}/template" "${POLICY_ROOT}/tools" DESTINATION "${policy}")
file(COPY "${POLICY_ROOT}/cmake/scripts" DESTINATION "${policy}/cmake")
foreach(name IN ITEMS .clang-tidy .clang-format CMakePresets.json .gitignore .gitattributes)
    file(COPY_FILE "${POLICY_ROOT}/${name}" "${policy}/${name}")
endforeach()
file(WRITE "${vcpkg}/README.md" "A stand-in for vcpkg.\n")
set(ENV{VCPKG_ROOT} "${vcpkg}")

set(git "${GIT_EXECUTABLE}" -c user.name=test -c user.email=test@example.com
    -c init.defaultBranch=main)

function(run dir)
    execute_process(COMMAND ${ARGN} WORKING_DIRECTORY "${dir}"
        RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
    set(code "${code}" PARENT_SCOPE)
    set(out "${out}${err}" PARENT_SCOPE)
endfunction()

function(expect condition what)
    if(NOT (${condition}))
        message(FATAL_ERROR "new-project.sh: ${what} (exit code ${code})\n--- output ---\n${out}")
    endif()
endfunction()

foreach(repo IN ITEMS "${policy}" "${vcpkg}")
    run("${repo}" ${git} init --quiet)
    run("${repo}" ${git} add --all)
    run("${repo}" ${git} commit --quiet -m "A release")
    expect("code;EQUAL;0" "could not create the throwaway repository ${repo}")
endforeach()
run("${vcpkg}" ${git} rev-parse HEAD)
string(STRIP "${out}" baseline)

set(new_project "${SH_EXECUTABLE}" "${policy}/tools/new-project.sh" "${dest}" MyTool)

# Refused: the policy copy is at no release tag.
run("${WORK}" ${new_project})
string(FIND "${out}" "which is no release tag" found)
expect("NOT;code;EQUAL;0;AND;found;GREATER;-1" "it must refuse a policy copy that isn't at a release tag")

run("${policy}" ${git} tag -a v9.9.9 -m v9.9.9)
run("${policy}" ${git} rev-parse HEAD)
string(STRIP "${out}" commit)

# Refused: uncommitted changes in the policy copy.
file(APPEND "${policy}/.clang-format" "# a local edit\n")
run("${WORK}" ${new_project})
string(FIND "${out}" "has uncommitted changes" found)
expect("NOT;code;EQUAL;0;AND;found;GREATER;-1" "it must refuse a policy copy with uncommitted changes")
run("${policy}" ${git} checkout --quiet -- .clang-format)

# The project.
run("${WORK}" ${new_project})
expect("code;EQUAL;0" "creating the project must succeed")
file(READ "${dest}/CMakeLists.txt" cmake)
string(FIND "${cmake}" "${commit}" pinned)
string(FIND "${cmake}" "v9.9.9" tagged)
expect("pinned;GREATER;-1;AND;tagged;GREATER;-1" "CMakeLists.txt must pin the release's commit and name its tag")
file(READ "${dest}/vcpkg.json" manifest)
string(FIND "${manifest}" "${baseline}" found)
expect("found;GREATER;-1" "vcpkg.json must have VCPKG_ROOT's commit as its baseline")
file(READ "${dest}/.github/workflows/ci.yml" ci)
string(FIND "${ci}" "gate.yml@${commit}" found)
expect("found;GREATER;-1" "the CI workflow must call the gate at the same commit")
run("${dest}" "${GIT_EXECUTABLE}" config core.hooksPath)
string(STRIP "${out}" hooks_path)
expect("hooks_path;STREQUAL;tools/hooks" "the project must be a git repository with the hooks enabled")
foreach(name IN ITEMS tools/hooks/pre-push tools/vcpkg/setup.cmake AGENTS.md ROADMAP.md CHANGELOG.md
                     src/main.cpp)
    if(NOT EXISTS "${dest}/${name}")
        message(FATAL_ERROR "new-project.sh: the project has no ${name}")
    endif()
endforeach()
file(READ "${dest}/tools/hooks/pre-push" hook)
string(FIND "${hook}" "\r" carriage_return)
expect("carriage_return;EQUAL;-1" "the copied hooks must keep their LF line endings")

message("new-project.sh: OK")

# Creates a project from cpp-policy's template (template/), pinned to one cpp-policy commit.
# tools/new-project.sh runs it; see there.
#
#   cmake -DPOLICY_ROOT=<dir> -DDEST=<dir> -DNAME=<Name> -DCOMMIT=<sha> -DTAG=<v1.2.3>
#         -DREPOSITORY=<url> -DVCPKG_BASELINE=<sha> -P new_project.cmake
#
# The project gets the release's policy files unchanged (.clang-tidy, .clang-format,
# CMakePresets.json, .gitignore, .gitattributes, tools/hooks/), agent settings, a CI workflow
# pinned to the same commit as CMakeLists.txt, a small program that shows each layer, and
# CHANGELOG.md and ROADMAP.md (POLICY.md 11.5). Every project uses vcpkg, at least for doctest
# (POLICY.md 13): it gets vcpkg.json with VCPKG_BASELINE as its baseline, and tools/vcpkg/,
# through which its CMakeLists.txt loads vcpkg.

cmake_minimum_required(VERSION 3.29)

foreach(variable IN ITEMS POLICY_ROOT DEST NAME COMMIT TAG REPOSITORY VCPKG_BASELINE)
    if(NOT DEFINED ${variable} OR "${${variable}}" STREQUAL "")
        message(FATAL_ERROR "new_project.cmake: ${variable} is required")
    endif()
endforeach()
if(NOT NAME MATCHES "^[A-Za-z][A-Za-z0-9]*$")
    message(FATAL_ERROR "new-project: the name must be letters and digits, starting with a "
                        "letter (MyTool): '${NAME}'")
endif()
if(EXISTS "${DEST}")
    file(GLOB existing "${DEST}/*" "${DEST}/.*")
    if(existing)
        message(FATAL_ERROR "new-project: ${DEST} exists and isn't empty")
    endif()
endif()

set(template "${POLICY_ROOT}/template")

# The names the files use: PROJECT_NAME as given (MyTool), TARGET in snake_case (my_tool),
# VCPKG_NAME as vcpkg requires (my-tool).
set(PROJECT_NAME "${NAME}")
string(REGEX REPLACE "([a-z0-9])([A-Z])" "\\1_\\2" TARGET "${NAME}")
string(TOLOWER "${TARGET}" TARGET)
string(REPLACE "_" "-" VCPKG_NAME "${TARGET}")
set(POLICY_COMMIT "${COMMIT}")
set(POLICY_TAG "${TAG}")
set(POLICY_REPOSITORY "${REPOSITORY}")
# gate.yml is called by owner/repository on GitHub.
if(REPOSITORY MATCHES "github\\.com[:/]([^/]+/[^/.]+)")
    set(POLICY_GITHUB "${CMAKE_MATCH_1}")
else()
    set(POLICY_GITHUB "luiserh1/cpp-policy")
endif()

file(READ "${template}/vcpkg-toolchain.cmake.in" VCPKG_TOOLCHAIN)
set(VCPKG_AGENTS " Each `vcpkg.json` entry needs\n  `\"default-features\": false` and a `\"$reason\"`.")

# The release's policy files, unchanged; the hooks stay executable.
file(MAKE_DIRECTORY "${DEST}/.claude" "${DEST}/.github/workflows")
foreach(name IN ITEMS .clang-tidy .clang-format CMakePresets.json .gitignore .gitattributes)
    file(COPY_FILE "${POLICY_ROOT}/${name}" "${DEST}/${name}")
endforeach()
file(COPY "${POLICY_ROOT}/tools/hooks" DESTINATION "${DEST}/tools"
    FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE
                     WORLD_READ WORLD_EXECUTE)

# The template: sources as they are, the rest with the names and pins filled in.
file(COPY "${template}/src" "${template}/tests" DESTINATION "${DEST}")
file(REMOVE "${DEST}/tests/CMakeLists.txt.in")
file(COPY_FILE "${template}/.claude/settings.json" "${DEST}/.claude/settings.json")
configure_file("${template}/CMakeLists.txt.in" "${DEST}/CMakeLists.txt" @ONLY)
configure_file("${template}/tests/CMakeLists.txt.in" "${DEST}/tests/CMakeLists.txt" @ONLY)
configure_file("${template}/AGENTS.md.in" "${DEST}/AGENTS.md" @ONLY)
configure_file("${template}/README.md.in" "${DEST}/README.md" @ONLY)
configure_file("${template}/CHANGELOG.md.in" "${DEST}/CHANGELOG.md" @ONLY)
configure_file("${template}/ROADMAP.md.in" "${DEST}/ROADMAP.md" @ONLY)
configure_file("${template}/ci.yml.in" "${DEST}/.github/workflows/ci.yml" @ONLY)
configure_file("${template}/vcpkg.json.in" "${DEST}/vcpkg.json" @ONLY)
# CMakeLists.txt loads vcpkg through these, unchanged like the hooks (POLICY.md 1.1).
file(COPY "${POLICY_ROOT}/tools/vcpkg" DESTINATION "${DEST}/tools")

# Every placeholder must have been filled in.
file(GLOB_RECURSE written "${DEST}/*")
foreach(file IN LISTS written)
    file(STRINGS "${file}" unfilled REGEX "@[A-Z_]+@")
    if(unfilled)
        message(FATAL_ERROR "new-project: ${file} still has a placeholder: ${unfilled}")
    endif()
endforeach()
message("new-project: created ${NAME} in ${DEST}")

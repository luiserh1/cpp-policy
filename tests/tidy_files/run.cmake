# tools/hooks/tidy-files and pre-commit's clang-tidy step, in a throwaway project that copies
# the policy's files and is configured through its presets, as a real project is.
#
#   cmake -DPOLICY_ROOT=<dir> -DWORK=<dir> -P run.cmake
#
# - tidy-files configures the preset if needed, checks C++ files and skips others;
# - a finding in a header fails it, and names the file;
# - third-party code (a nested third_party/) is skipped, as clang-tidy's header filter does;
# - a source the build doesn't compile (another platform's) is skipped with a note;
# - pre-commit fails while a file with findings is staged, and passes once it isn't.

cmake_minimum_required(VERSION 3.29)
find_package(Git REQUIRED)

# Git exports GIT_DIR to hooks (see hooks/run.cmake): keep git on the throwaway repository.
foreach(variable IN ITEMS GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY)
    unset(ENV{${variable}})
endforeach()

set(project "${WORK}/project")
file(REMOVE_RECURSE "${WORK}")
file(MAKE_DIRECTORY "${project}/src/app" "${project}/tools")
foreach(name IN ITEMS .clang-tidy .clang-format CMakePresets.json .gitignore .gitattributes)
    file(COPY_FILE "${POLICY_ROOT}/${name}" "${project}/${name}")
endforeach()
file(COPY "${POLICY_ROOT}/tools/hooks" DESTINATION "${project}/tools")

file(WRITE "${project}/CMakeLists.txt"
    "cmake_minimum_required(VERSION 3.29)\n"
    "project(tidy_files LANGUAGES CXX)\n"
    "include([==[${POLICY_ROOT}/cmake/CppPolicy.cmake]==])\n"
    "add_library(app OBJECT src/app/good.cpp)\n"
    "target_include_directories(app PRIVATE src)\n"
    "cpp_policy_apply(app)\n"
    "cpp_policy_add_checks()\n")
file(WRITE "${project}/src/app/good.hpp"
    "#pragma once\n\nnamespace app {\n\n[[nodiscard]] int twice(int value);\n\n} // namespace app\n")
file(WRITE "${project}/src/app/good.cpp"
    "#include \"app/good.hpp\"\n\nnamespace app {\n\nint twice(int value) {\n"
    "    return value * 2;\n}\n\n} // namespace app\n")
# Not listed in CMakeLists.txt, like a file built only on another system.
file(COPY_FILE "${project}/src/app/good.cpp" "${project}/src/app/elsewhere.cpp")
file(WRITE "${project}/notes.txt" "not C++\n")

set(git "${GIT_EXECUTABLE}" -c user.name=test -c user.email=test@example.com
    -c init.defaultBranch=main)
function(run)
    execute_process(COMMAND ${ARGN} WORKING_DIRECTORY "${project}"
        RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
    set(code "${code}" PARENT_SCOPE)
    set(out "${out}${err}" PARENT_SCOPE)
endfunction()
function(expect condition what)
    if(NOT (${condition}))
        message(FATAL_ERROR "tidy_files: ${what} (exit code ${code})\n--- output ---\n${out}")
    endif()
endfunction()
function(expect_output text what)
    string(FIND "${out}" "${text}" found)
    expect("found;GREATER;-1" "${what}")
endfunction()

run(${git} init --quiet)
run(${git} config core.hooksPath tools/hooks)

# Not configured yet: tidy-files configures the preset, checks the C++ files, skips the rest.
run(sh tools/hooks/tidy-files src/app/good.cpp src/app/good.hpp notes.txt)
expect("code;EQUAL;0" "clean files must pass")
expect_output("tidy-files: OK (2 files)" "it must check the two C++ files and skip notes.txt")

# A finding in a header.
file(WRITE "${project}/src/app/bad.hpp"
    "#pragma once\n\nnamespace app {\n\ninline int truncate(double value) {\n"
    "    return (int)value;\n}\n\n} // namespace app\n")
run(sh tools/hooks/tidy-files src/app/bad.hpp)
expect("NOT;code;EQUAL;0" "a finding must fail tidy-files")
expect_output("C-style casts" "clang-tidy's finding must be shown")
expect_output("src/app/bad.hpp" "the file with findings must be named")

# Third-party code in a nested directory is left alone, as clang-tidy's header filter leaves it.
file(MAKE_DIRECTORY "${project}/src/app/third_party")
file(COPY_FILE "${project}/src/app/bad.hpp" "${project}/src/app/third_party/vendor.hpp")
run(sh tools/hooks/tidy-files src/app/third_party/vendor.hpp)
expect("code;EQUAL;0" "third-party code must be skipped")
expect_output("tidy-files: OK (0 files)" "no file must be checked")

# A source this build doesn't compile.
run(sh tools/hooks/tidy-files src/app/elsewhere.cpp)
expect("code;EQUAL;0" "a source the build doesn't compile must be skipped, not fail")
expect_output("src/app/elsewhere.cpp: NOT CHECKED" "the skipped source must be reported")
expect_output("OK (0 files; 1 NOT CHECKED" "the summary must count the skipped source")

# A source added since the build was configured: tidy-files configures again and checks it.
file(COPY_FILE "${project}/src/app/good.cpp" "${project}/src/app/added.cpp")
file(APPEND "${project}/CMakeLists.txt" "target_sources(app PRIVATE src/app/added.cpp)\n")
run(sh tools/hooks/tidy-files src/app/added.cpp)
expect("code;EQUAL;0" "a source added after configuring must be checked")
expect_output("tidy-files: OK (1 files)" "the added source must be checked, not skipped")

# A header is checked through a source that includes it, with that source's flags: this one
# needs -I that only the build knows, and has a finding of its own.
file(MAKE_DIRECTORY "${project}/include_root/shared" "${project}/src/app")
file(WRITE "${project}/include_root/shared/limits.hpp"
    "#pragma once\n\nnamespace shared {\n\ninline constexpr int limit = 4;\n\n} // namespace shared\n")
file(WRITE "${project}/src/app/panel.hpp"
    "#pragma once\n\n#include \"shared/limits.hpp\"\n\nnamespace widgets {\n\n"
    "inline int clamp(double value) {\n    return (int)value + shared::limit;\n}\n\n"
    "[[nodiscard]] int panel();\n\n} // namespace widgets\n")
file(WRITE "${project}/src/app/panel.cpp"
    "#include \"app/panel.hpp\"\n\nnamespace widgets {\n\nint panel() {\n"
    "    return clamp(1.0);\n}\n\n} // namespace widgets\n")
file(APPEND "${project}/CMakeLists.txt"
    "add_library(panels OBJECT src/app/panel.cpp)\n"
    "target_include_directories(panels PRIVATE src include_root)\n"
    "cpp_policy_apply(panels)\n")
# The new source makes tidy-files configure again; it shows the header's finding too.
run(sh tools/hooks/tidy-files src/app/panel.cpp)
expect_output("C-style casts" "the source must be found after configuring again")
run(sh tools/hooks/tidy-files src/app/panel.hpp)
expect("NOT;code;EQUAL;0" "the header's finding must fail tidy-files")
expect_output("C-style casts" "the header's own finding must be shown")
string(FIND "${out}" "file not found" missing)
expect("missing;EQUAL;-1" "the header must be checked with the including source's flags")
file(WRITE "${project}/src/app/panel.hpp"
    "#pragma once\n\n#include \"shared/limits.hpp\"\n\nnamespace widgets {\n\n"
    "inline int clamp(int value) {\n    return value + shared::limit;\n}\n\n"
    "[[nodiscard]] int panel();\n\n} // namespace widgets\n")
file(WRITE "${project}/src/app/panel.cpp"
    "#include \"app/panel.hpp\"\n\nnamespace widgets {\n\nint panel() {\n"
    "    return clamp(1);\n}\n\n} // namespace widgets\n")
run(sh tools/hooks/tidy-files src/app/panel.hpp)
expect("code;EQUAL;0" "the corrected header must pass")
expect_output("tidy-files: OK (1 files)" "the corrected header must be checked")

# The format and the audit's rules about one file are reported too, before the gate would.
file(WRITE "${project}/src/app/untidy.cpp"
    "#include \"app/panel.hpp\"\n\nnamespace widgets {\n\nint   untidy( )   {\n"
    "    try {\n        return clamp(2);\n    } catch (...) {\n        return 0;\n    }\n}\n\n} // namespace widgets\n")
file(APPEND "${project}/CMakeLists.txt" "target_sources(panels PRIVATE src/app/untidy.cpp)\n")
run(sh tools/hooks/tidy-files src/app/untidy.cpp)
expect("NOT;code;EQUAL;0" "a badly formatted file must fail tidy-files")
expect_output("the format" "the format fault must be reported")
expect_output("boundary" "the audit's rule about catch (...) must be reported")
run(sh tools/hooks/tidy-files --format src/app/untidy.cpp)
expect("code;EQUAL;0" "tidy-files --format must format the file")
run(sh tools/hooks/tidy-files src/app/untidy.cpp)
string(FIND "${out}" "the format" still)
expect("still;EQUAL;-1" "after --format only the audit's rule must be left")
expect_output("boundary" "the audit's rule must still be reported")
file(REMOVE "${project}/src/app/untidy.cpp")
file(READ "${project}/CMakeLists.txt" lists)
string(REPLACE "target_sources(panels PRIVATE src/app/untidy.cpp)\n" "" lists "${lists}")
file(WRITE "${project}/CMakeLists.txt" "${lists}")

# pre-commit: the staged header with findings fails the commit's checks; unstaged, they pass.
run(${git} add CMakeLists.txt .clang-tidy .clang-format CMakePresets.json .gitignore
    .gitattributes tools src/app/good.hpp src/app/good.cpp src/app/bad.hpp)
run(sh tools/hooks/pre-commit)
expect("NOT;code;EQUAL;0" "pre-commit must fail while bad.hpp is staged")
expect_output("C-style casts" "pre-commit must show the finding in the staged header")
run(${git} rm --cached --quiet src/app/bad.hpp)
# A staged name with a space (a test asset) must reach tidy-files whole.
file(WRITE "${project}/an asset.txt" "not C++\n")
run(${git} add "an asset.txt" src/app/added.cpp)
run(sh tools/hooks/pre-commit)
expect("code;EQUAL;0" "pre-commit must pass once bad.hpp isn't staged")
expect_output("tidy-files: OK (3 files)" "pre-commit must run tidy-files on the staged files")
string(FIND "${out}" "does not refer to an existing path" split)
expect("split;EQUAL;-1" "a staged name with a space must not be split")

message("tidy_files: OK")

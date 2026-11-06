# The tidy cache (POLICY.md 8) skips clang-tidy only for a file whose inputs are all unchanged.
#
#   cmake -DPOLICY_ROOT=<dir> -DWORK=<dir> -DCXX=<compiler> -DMAKE_PROGRAM=<ninja> -P run.cmake
#
# A throwaway project with two sources and their headers, on a copy of the policy, is built in
# several folders with one cache. The wrapper's log says which files clang-tidy ran on ("run")
# and which it skipped ("hit"). Each input of the key is changed in turn, and only the files
# it concerns must be checked again; a finding must fail the build whatever the cache holds.

cmake_minimum_required(VERSION 3.29)

set(policy "${WORK}/policy")
set(cache "${WORK}/cache")
set(log "${WORK}/log.txt")
file(REMOVE_RECURSE "${WORK}")
file(MAKE_DIRECTORY "${policy}")
file(COPY "${POLICY_ROOT}/cmake" DESTINATION "${policy}")
file(COPY_FILE "${POLICY_ROOT}/.clang-tidy" "${policy}/.clang-tidy")

function(make_project dir)
    file(MAKE_DIRECTORY "${dir}")
    file(WRITE "${dir}/CMakeLists.txt"
        "cmake_minimum_required(VERSION 3.29)\n"
        "project(tidy_cache LANGUAGES CXX)\n"
        "include(\"${policy}/cmake/CppPolicy.cmake\")\n"
        "add_library(shapes OBJECT area.cpp perimeter.cpp)\n"
        "cpp_policy_apply(shapes)\n"
        "if(DEFINED EXTRA_DEFINITION)\n"
        "    target_compile_definitions(shapes PRIVATE \${EXTRA_DEFINITION})\n"
        "endif()\n")
    file(WRITE "${dir}/area.hpp"
        "#pragma once\n\n"
        "namespace shapes {\n\n"
        "[[nodiscard]] int area(int width, int height);\n\n"
        "} // namespace shapes\n")
    file(WRITE "${dir}/area.cpp"
        "#include \"area.hpp\"\n\n"
        "namespace shapes {\n\n"
        "int area(int width, int height) {\n"
        "    return width * height;\n"
        "}\n\n"
        "} // namespace shapes\n")
    file(WRITE "${dir}/perimeter.hpp"
        "#pragma once\n\n"
        "namespace shapes {\n\n"
        "[[nodiscard]] int perimeter(int width, int height);\n\n"
        "} // namespace shapes\n")
    file(WRITE "${dir}/perimeter.cpp"
        "#include \"perimeter.hpp\"\n\n"
        "namespace shapes {\n\n"
        "int perimeter(int width, int height) {\n"
        "    return 2 * (width + height);\n"
        "}\n\n"
        "} // namespace shapes\n")
endfunction()

function(configure dir)
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -S "${dir}" -B "${dir}/build" -G Ninja
                "-DCMAKE_MAKE_PROGRAM=${MAKE_PROGRAM}" "-DCMAKE_CXX_COMPILER=${CXX}"
                -DCPP_POLICY_CLANG_TIDY=ON ${ARGN}
        RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
    if(NOT code EQUAL 0)
        message(FATAL_ERROR "tidy_cache: configuring ${dir} failed\n${out}${err}")
    endif()
endfunction()

# Builds with the cache given (or "off") and sets `code`, `out` and `log_lines`, what the wrapper
# wrote to its log during this build.
function(build dir cache_dir)
    file(REMOVE "${log}")
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E env "CPP_POLICY_TIDY_CACHE=${cache_dir}"
                "CPP_POLICY_TIDY_CACHE_LOG=${log}"
                "${CMAKE_COMMAND}" --build "${dir}/build"
        RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
    set(lines "")
    if(EXISTS "${log}")
        file(STRINGS "${log}" lines)
    endif()
    set(code "${code}" PARENT_SCOPE)
    set(out "${out}${err}" PARENT_SCOPE)
    set(log_lines "${lines}" PARENT_SCOPE)
endfunction()

# expect(<what> <file name> run|hit ...): the log says that for each file named.
function(expect what)
    set(pairs "${ARGN}")
    while(pairs)
        list(POP_FRONT pairs name verdict)
        set(seen FALSE)
        foreach(line IN LISTS log_lines)
            if(line MATCHES "^${verdict} .*(/|\\\\)${name}$")
                set(seen TRUE)
            endif()
        endforeach()
        if(NOT seen)
            list(JOIN log_lines "\n" text)
            message(FATAL_ERROR "tidy_cache: ${what}: expected '${verdict} ${name}' in the "
                "wrapper's log, which says:\n${text}\nThe build said:\n${out}")
        endif()
    endwhile()
endfunction()

function(must_pass what)
    if(NOT code EQUAL 0)
        message(FATAL_ERROR "tidy_cache: ${what}: the build failed\n${out}")
    endif()
endfunction()

# 1. A first build checks every file and remembers each pass.
make_project("${WORK}/one")
configure("${WORK}/one")
build("${WORK}/one" "${cache}")
must_pass("the first build")
expect("the first build" area.cpp run perimeter.cpp run)
file(GLOB_RECURSE entries "${cache}/*")
list(FILTER entries EXCLUDE REGEX "/(tmp/[^/]*|pruned)$")
list(LENGTH entries count)
if(NOT count EQUAL 2)
    message(FATAL_ERROR "tidy_cache: the first build left ${count} entries, not 2: ${entries}")
endif()

# 2. The same project in another folder: a CI runner after the developer's gate.
make_project("${WORK}/two")
configure("${WORK}/two")
build("${WORK}/two" "${cache}")
must_pass("another folder")
expect("another folder" area.cpp hit perimeter.cpp hit)

# 3. A header changes: the file that includes it is checked again, the other isn't.
file(APPEND "${WORK}/two/area.hpp" "// A comment: the header's contents changed.\n")
build("${WORK}/two" "${cache}")
must_pass("a changed header")
expect("a changed header" area.cpp run)
foreach(line IN LISTS log_lines)
    if(line MATCHES "perimeter.cpp$")
        message(FATAL_ERROR "tidy_cache: a changed header rebuilt perimeter.cpp, which doesn't "
            "include it: ${line}")
    endif()
endforeach()

# 4. A compile flag changes: every file is checked again.
configure("${WORK}/two" -DEXTRA_DEFINITION=SHAPES_EXTRA=1)
build("${WORK}/two" "${cache}")
must_pass("a new definition")
expect("a new definition" area.cpp run perimeter.cpp run)

# 5. The configuration changes (as an upgrade changes it): every file is checked again.
file(APPEND "${policy}/.clang-tidy" "# A comment: the configuration's contents changed.\n")
build("${WORK}/two" "${cache}")
must_pass("a changed configuration")
expect("a changed configuration" area.cpp run perimeter.cpp run)

# 6. A finding in a header, with every file's earlier pass in the cache: the build fails.
file(READ "${WORK}/two/area.hpp" header)
file(APPEND "${WORK}/two/area.hpp" "inline int shapes_counter = 0;\n")
build("${WORK}/two" "${cache}")
if(code EQUAL 0)
    message(FATAL_ERROR "tidy_cache: a finding in a header passed with a full cache\n${out}")
endif()
expect("a finding" area.cpp run)
file(WRITE "${WORK}/two/area.hpp" "${header}")
build("${WORK}/two" "${cache}")
must_pass("the finding removed")
expect("the finding removed" area.cpp hit)

# 7. A folder whose path the configuration excludes from checks keeps entries of its own:
# clang-tidy skips its headers there, and checks them elsewhere. First an ordinary folder
# fills the cache with this project as it is now; the excluded one must not use it.
make_project("${WORK}/five")
configure("${WORK}/five")
build("${WORK}/five" "${cache}")
must_pass("an ordinary folder")
make_project("${WORK}/external/three")
configure("${WORK}/external/three")
build("${WORK}/external/three" "${cache}")
must_pass("a folder under external/")
expect("a folder under external/" area.cpp run perimeter.cpp run)
make_project("${WORK}/six")
configure("${WORK}/six")
build("${WORK}/six" "${cache}")
must_pass("another ordinary folder")
expect("another ordinary folder" area.cpp hit perimeter.cpp hit)

# 8. The cache turned off: clang-tidy runs every time, and nothing is written.
make_project("${WORK}/four")
configure("${WORK}/four")
build("${WORK}/four" off)
must_pass("the cache off")
expect("the cache off" area.cpp run perimeter.cpp run)
if(EXISTS "${WORK}/four/build/off")
    message(FATAL_ERROR "tidy_cache: with the cache off, a folder named 'off' was written")
endif()

message("tidy_cache: OK")

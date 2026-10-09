# One policy project used as a library by another (POLICY.md 11.7), on two throwaway projects:
# geometry/ offers a library and has a program of its own; user/ fetches it.
#
#   cmake -DPOLICY_ROOT=<dir> -DWORK=<dir> -DCXX=<compiler> -DMAKE_PROGRAM=<ninja>
#         -DBUILD_TYPE=<type> -DSANITIZERS=<ON|OFF> -DTHREAD_SANITIZER=<ON|OFF>
#         -DHARDENING=<level> -P run.cmake
#
# - the library's project passes its own build with clang-tidy, its audit and its format check;
# - the user builds the library in its own build, with its sanitizers and hardening and
#   without its warnings as errors or clang-tidy, links it and runs it, and passes its own
#   audit although it has modules with the library's names;
# - the user links the library's test support into a test of its own;
# - the user's audit fails when it includes a header internal to one of the library's modules
#   or when a module that isn't allowed to includes the library, and its
#   configuration fails when its vcpkg.json lacks a package the library needs or when the
#   library was checked with a cpp-policy older than the floor;
# - the library's audit fails when its code includes the program's.

cmake_minimum_required(VERSION 3.29)
find_package(Git REQUIRED)

file(REMOVE_RECURSE "${WORK}")
file(MAKE_DIRECTORY "${WORK}")

# A copy of a fixture with the policy's files, as a real project has them.
function(make_project fixture name)
    set(dest "${WORK}/${name}")
    file(COPY "${CMAKE_CURRENT_LIST_DIR}/${fixture}/" DESTINATION "${dest}")
    foreach(file IN ITEMS .clang-tidy .clang-format CMakePresets.json .gitignore .gitattributes)
        file(COPY_FILE "${POLICY_ROOT}/${file}" "${dest}/${file}")
    endforeach()
    file(COPY "${POLICY_ROOT}/tools/hooks" "${POLICY_ROOT}/tools/vcpkg" DESTINATION "${dest}/tools")
    # The audit asks that the hooks be enabled, which needs a repository.
    execute_process(COMMAND "${GIT_EXECUTABLE}" init --quiet WORKING_DIRECTORY "${dest}")
    execute_process(COMMAND "${GIT_EXECUTABLE}" config core.hooksPath tools/hooks
        WORKING_DIRECTORY "${dest}")
endfunction()

set(settings -G Ninja "-DCMAKE_MAKE_PROGRAM=${MAKE_PROGRAM}" "-DCMAKE_CXX_COMPILER=${CXX}"
    "-DCMAKE_BUILD_TYPE=${BUILD_TYPE}" "-DPOLICY_ROOT=${POLICY_ROOT}" -DCPP_POLICY_CLANG_TIDY=ON
    "-DCPP_POLICY_SANITIZERS=${SANITIZERS}" "-DCPP_POLICY_THREAD_SANITIZER=${THREAD_SANITIZER}"
    "-DCPP_POLICY_HARDENING=${HARDENING}")

function(run)
    execute_process(COMMAND ${ARGN} RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
    set(code "${code}" PARENT_SCOPE)
    set(out "${out}${err}" PARENT_SCOPE)
endfunction()
function(must_pass what)
    run(${ARGN})
    if(NOT code EQUAL 0)
        message(FATAL_ERROR "library: ${what} failed (exit code ${code})\n${out}")
    endif()
    set(out "${out}" PARENT_SCOPE)
endfunction()
function(must_fail what text)
    run(${ARGN})
    # CMake wraps its own messages: compare with the line breaks taken out.
    string(REGEX REPLACE "[ \t]*\n[ \t]*" " " flat "${out}")
    string(FIND "${flat}" "${text}" found)
    if(code EQUAL 0 OR found EQUAL -1)
        message(FATAL_ERROR "library: ${what}: expected a failure that says '${text}' "
            "(exit code ${code})\n${out}")
    endif()
endfunction()
set(checks --target all policy-audit policy-format-check)

# --- The library's own project.
make_project(geometry geometry)
must_pass("configuring the library's project"
    "${CMAKE_COMMAND}" -S "${WORK}/geometry" -B "${WORK}/geometry/build" ${settings})
must_pass("the library's project: build with clang-tidy, audit, format check"
    "${CMAKE_COMMAND}" --build "${WORK}/geometry/build" ${checks})

# --- Its user.
make_project(user user)
set(user_settings ${settings} "-DFETCHCONTENT_SOURCE_DIR_GEOMETRY=${WORK}/geometry")
must_pass("configuring the user"
    "${CMAKE_COMMAND}" -S "${WORK}/user" -B "${WORK}/user/build" ${user_settings})
if(NOT out MATCHES "using library 'geometry' at 89abcdef[0-9a-f]+ \\(checked with cpp-policy v0\\.30\\.0\\)")
    message(FATAL_ERROR "library: configuring the user didn't report the library and the "
        "cpp-policy that checked it:\n${out}")
endif()
must_pass("the user: build with clang-tidy, audit, format check"
    "${CMAKE_COMMAND}" --build "${WORK}/user/build" ${checks})
must_pass("the user's test, which calls the library"
    "${CMAKE_CTEST_COMMAND}" --test-dir "${WORK}/user/build" --output-on-failure)

# The library's files in the user's build: this build's hardening, and its sanitizers if it
# has any, but not its warnings as errors; the user's own files keep them.
file(READ "${WORK}/user/build/compile_commands.json" database)
string(JSON entries LENGTH "${database}")
math(EXPR last "${entries} - 1")
set(seen_library FALSE)
set(seen_own FALSE)
foreach(index RANGE ${last})
    string(JSON path GET "${database}" ${index} file)
    string(JSON command GET "${database}" ${index} command)
    if(path MATCHES "/lib/geometry/")
        set(seen_library TRUE)
        if(command MATCHES "-Werror")
            message(FATAL_ERROR "library: the library is compiled with the user's warnings "
                "as errors:\n${command}")
        endif()
        if(NOT command MATCHES "_LIBCPP_HARDENING_MODE=")
            message(FATAL_ERROR "library: the library is compiled without the user's "
                "hardening:\n${command}")
        endif()
        if(SANITIZERS AND NOT command MATCHES "fsanitize=address")
            message(FATAL_ERROR "library: the library is compiled without the user's "
                "sanitizers:\n${command}")
        endif()
    elseif(path MATCHES "/src/app/summary\\.cpp$")
        set(seen_own TRUE)
        if(NOT command MATCHES "-Werror")
            message(FATAL_ERROR "library: the user's own file lost its warnings as errors")
        endif()
    endif()
endforeach()
if(NOT seen_library OR NOT seen_own)
    message(FATAL_ERROR "library: the user's build doesn't compile the library's files and "
        "its own:\n${database}")
endif()
# And no clang-tidy on them: the build's rule for a library file has no clang-tidy step.
file(READ "${WORK}/user/build/build.ninja" ninja)
string(REGEX MATCH "build [^\n]*geometry[^\n]*area\\.cpp\\.o[^\n]*\n([^\n]*\n)*" rule "${ninja}")
string(REGEX REPLACE "\n\n.*" "" rule "${rule}")
if(rule MATCHES "clang-tidy")
    message(FATAL_ERROR "library: the user's build runs clang-tidy on the library:\n${rule}")
endif()

# --- A header internal to one of the library's modules.
file(READ "${WORK}/user/src/app/summary.cpp" source)
file(WRITE "${WORK}/user/src/app/summary.cpp"
    "#include \"geometry/lowlevel/internal/units.hpp\"\n${source}")
must_fail("the user's audit, with an include of an internal header"
    "src/app/summary.cpp:1: error: includes a header that is internal to the library 'geometry' (its module 'lowlevel')"
    "${CMAKE_COMMAND}" --build "${WORK}/user/build" --target policy-audit)
file(WRITE "${WORK}/user/src/app/summary.cpp" "${source}")

# --- A module that isn't allowed to include the library.
must_pass("configuring the user with another module allowed"
    "${CMAKE_COMMAND}" -S "${WORK}/user" -B "${WORK}/user/build" ${user_settings}
    -DLIBRARY_USERS=lowlevel)
must_fail("the user's audit, with app not allowed to include the library"
    "src/app/summary.cpp:3: error: includes <geometry/shapes/area.hpp>, which only these modules may include: lowlevel"
    "${CMAKE_COMMAND}" --build "${WORK}/user/build" --target policy-audit)

# --- A package the library needs, missing from the user's vcpkg.json.
make_project(user user_no_package)
file(WRITE "${WORK}/user_no_package/vcpkg.json" "{ \"name\": \"user-project\", \"dependencies\": [] }\n")
must_fail("configuring a user whose vcpkg.json lacks zlib"
    "library 'geometry' needs these packages, which this project's vcpkg.json doesn't list: zlib"
    "${CMAKE_COMMAND}" -S "${WORK}/user_no_package" -B "${WORK}/user_no_package/build"
    ${user_settings})

# --- A library checked with a cpp-policy older than the floor.
make_project(geometry geometry_old)
file(READ "${WORK}/geometry_old/CMakeLists.txt" lists)
string(REPLACE "# v0.30.0" "# v0.20.0" lists "${lists}")
file(WRITE "${WORK}/geometry_old/CMakeLists.txt" "${lists}")
make_project(user user_old_library)
must_fail("configuring a user of a library checked with v0.20.0"
    "library 'geometry' was checked with cpp-policy v0.20.0"
    "${CMAKE_COMMAND}" -S "${WORK}/user_old_library" -B "${WORK}/user_old_library/build"
    ${settings} "-DFETCHCONTENT_SOURCE_DIR_GEOMETRY=${WORK}/geometry_old")

# --- The library's code including the program's.
file(READ "${WORK}/geometry/lib/geometry/shapes/area.cpp" source)
string(REPLACE "#include \"geometry/lowlevel/clock.hpp\"\n"
    "#include \"app/report.hpp\"\n#include \"geometry/lowlevel/clock.hpp\"\n" source "${source}")
file(WRITE "${WORK}/geometry/lib/geometry/shapes/area.cpp" "${source}")
must_fail("the library's audit, with an include of the program"
    "lib/geometry/shapes/area.cpp:3: error: includes \"app/report.hpp\": the library's code includes only its own headers"
    "${CMAKE_COMMAND}" --build "${WORK}/geometry/build" --target policy-audit)

message("library: OK")

# The compile-time fortify check (cmake/fortify/fortify_check.hpp, POLICY.md 6): a release
# build of a policy target compiles as it is, and fails to compile when a route the configure
# checks don't see turns _FORTIFY_SOURCE off.
#
#   cmake -DPOLICY_ROOT=<dir> -DWORK=<dir> -DCXX=<compiler> -DMAKE_PROGRAM=<ninja> -P run.cmake

cmake_minimum_required(VERSION 3.29)
file(REMOVE_RECURSE "${WORK}")

function(build name)
    set(dir "${WORK}/${name}")
    execute_process(COMMAND "${CMAKE_COMMAND}" -S "${CMAKE_CURRENT_LIST_DIR}/project" -B "${dir}"
            -G Ninja "-DCMAKE_MAKE_PROGRAM=${MAKE_PROGRAM}" "-DCMAKE_CXX_COMPILER=${CXX}"
            -DCMAKE_BUILD_TYPE=Release "-DPOLICY_ROOT=${POLICY_ROOT}" ${ARGN}
        RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
    if(NOT code EQUAL 0)
        message(FATAL_ERROR "fortify: configuring '${name}' failed:\n${out}${err}")
    endif()
    execute_process(COMMAND "${CMAKE_COMMAND}" --build "${dir}"
        RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
    set(code "${code}" PARENT_SCOPE)
    set(out "${out}${err}" PARENT_SCOPE)
endfunction()

build(kept)
if(NOT code EQUAL 0)
    message(FATAL_ERROR "fortify: a release build with the policy's fortify failed:\n${out}")
endif()

# A flag variable is outside what the configure checks read for this, and -Wp, with the macro
# as its own argument is a spelling they don't know.
build(turned_off "-DCMAKE_CXX_FLAGS_RELEASE=-O3 -DNDEBUG -Wp,-U,_FORTIFY_SOURCE")
string(FIND "${out}" "cpp-policy: _FORTIFY_SOURCE is not 3 here" reported)
if(code EQUAL 0 OR reported EQUAL -1)
    message(FATAL_ERROR "fortify: a release build with fortify turned off must fail to compile "
        "and say why (exit code ${code}):\n${out}")
endif()

message("fortify: OK")

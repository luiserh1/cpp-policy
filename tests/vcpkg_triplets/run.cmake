# cpp-policy's triplets (tools/vcpkg/): vcpkg must build dependencies like the project.
#
#   cmake -DPOLICY_ROOT=<dir> -DWORK=<dir> -DLLVM_MAJOR=<n> -DCXX_COMPILER=<path>
#         -DBUILD_TYPE=<type> -DSANITIZERS=<ON|OFF> -DTHREAD_SANITIZER=<ON|OFF>
#         -DHARDENING=<mode> -P run.cmake
#
# Configures project/ with the outer build's compiler and options, as its preset would. vcpkg
# then builds project/ports/policy-probe, a small C and C++ library that reports how it was
# compiled, with the triplet tools/vcpkg/setup.cmake picks. Checks:
#   - the dependency was compiled by LLVM <n> (not Apple Clang or cl.exe), against the
#     project's standard library, with the preset's sanitizer and the policy's hardening:
#     library hardening, stack protection on Linux and macOS, and _FORTIFY_SOURCE=3 there in
#     Release builds;
#   - with AddressSanitizer, a one-byte overread inside the dependency stops the program. With
#     vcpkg's default triplets it goes unnoticed.

cmake_minimum_required(VERSION 3.29)

file(REMOVE_RECURSE "${WORK}")
file(MAKE_DIRECTORY "${WORK}")
set(build "${WORK}/build")

function(step what)
    execute_process(COMMAND ${ARGN} RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
    if(NOT code EQUAL 0)
        message(FATAL_ERROR "vcpkg_triplets: ${what} failed (exit code ${code})\n${out}${err}")
    endif()
    set(out "${out}${err}" PARENT_SCOPE)
endfunction()

step("configuring the project (vcpkg builds the dependency)"
    "${CMAKE_COMMAND}" -S "${CMAKE_CURRENT_LIST_DIR}/project" -B "${build}" -G Ninja
    "-DPOLICY_ROOT=${POLICY_ROOT}" "-DCMAKE_CXX_COMPILER=${CXX_COMPILER}"
    "-DCMAKE_BUILD_TYPE=${BUILD_TYPE}" "-DCPP_POLICY_SANITIZERS=${SANITIZERS}"
    "-DCPP_POLICY_THREAD_SANITIZER=${THREAD_SANITIZER}" "-DCPP_POLICY_HARDENING=${HARDENING}")
step("building the project" "${CMAKE_COMMAND}" --build "${build}")

function(program_path name out)
    file(GLOB found "${build}/${name}" "${build}/${name}.exe")
    if(NOT found)
        message(FATAL_ERROR "vcpkg_triplets: the project built no ${name} program")
    endif()
    list(GET found 0 found)
    set(${out} "${found}" PARENT_SCOPE)
endfunction()

# --- How the dependency was compiled.
program_path(build_info program)
step("running build_info" "${program}")
set(report "${out}")
if(NOT report MATCHES "dependency C: ([^\n]*)\ndependency C\\+\\+: ([^\n]*)\nproject: library=([^\n]*)")
    message(FATAL_ERROR "vcpkg_triplets: unexpected build_info output:\n${report}")
endif()
set(c_build "${CMAKE_MATCH_1}")
set(cpp_build "${CMAKE_MATCH_2}")
set(project_library "${CMAKE_MATCH_3}")

if(THREAD_SANITIZER)
    set(sanitizer thread)
elseif(SANITIZERS)
    set(sanitizer address)
else()
    set(sanitizer none)
endif()
set(expected "compiler=clang-${LLVM_MAJOR} " "sanitizer=${sanitizer} ")
if(NOT CMAKE_HOST_WIN32)
    list(APPEND expected "ssp=strong ")
    if(BUILD_TYPE STREQUAL "Release")
        list(APPEND expected "fortify=3")
    endif()
endif()
set(problems "")
foreach(part IN LISTS expected)
    foreach(file IN ITEMS c cpp)
        string(FIND "${${file}_build} " "${part}" found)
        if(found EQUAL -1)
            list(APPEND problems "the ${file} file lacks '${part}': ${${file}_build}")
        endif()
    endforeach()
endforeach()

string(FIND "${cpp_build}" "library=${project_library} " found)
if(found EQUAL -1)
    list(APPEND problems "the C++ file uses another standard library than the project "
                         "(${project_library}): ${cpp_build}")
endif()
if(project_library MATCHES "^libc\\+\\+")
    if(sanitizer STREQUAL "none")
        set(hardening fast)
    else()
        set(hardening debug)
    endif()
elseif(project_library MATCHES "^libstdc\\+\\+")
    set(hardening assertions)
else()
    set(hardening on)
endif()
string(FIND "${cpp_build} " "hardening=${hardening} " found)
if(found EQUAL -1)
    list(APPEND problems "the C++ file lacks 'hardening=${hardening}': ${cpp_build}")
endif()

if(problems)
    list(JOIN problems "\n  " problems)
    message(FATAL_ERROR "vcpkg_triplets: the dependency wasn't built like the project:\n  "
        "${problems}")
endif()
message("vcpkg_triplets: the dependency was built like the project: ${cpp_build}")

# --- AddressSanitizer inside the dependency.
if(SANITIZERS)
    program_path(overread program)
    execute_process(COMMAND "${program}" RESULT_VARIABLE code OUTPUT_VARIABLE out
        ERROR_VARIABLE out)
    if(code EQUAL 0 OR NOT out MATCHES "heap-buffer-overflow")
        message(FATAL_ERROR "vcpkg_triplets: AddressSanitizer missed the overread inside the "
            "dependency (exit code ${code}):\n${out}")
    endif()
    message("vcpkg_triplets: AddressSanitizer caught the overread inside the dependency")
endif()
message("vcpkg_triplets: OK")

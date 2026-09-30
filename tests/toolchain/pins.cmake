# Every file that names the LLVM major names the one the policy requires (POLICY.md 10.1).
#
#   cmake -DPOLICY_ROOT=<dir> -DLLVM_MAJOR=<n> -P pins.cmake
#
# Moving the major touches the compiler check, the presets' search paths, the vcpkg toolchain
# and the CI gate; this finds the places a move forgot. (llvm.cmake is checked by
# vcpkg/triplet_files.)

cmake_minimum_required(VERSION 3.29)
set(problems "")

function(check_numbers file regex)
    file(READ "${POLICY_ROOT}/${file}" text)
    string(REGEX MATCHALL "${regex}" found "${text}")
    if(NOT found)
        list(APPEND problems "${file}: nothing matches '${regex}'")
    endif()
    foreach(match IN LISTS found)
        string(REGEX REPLACE "${regex}" "\\1" number "${match}")
        if(NOT number EQUAL LLVM_MAJOR)
            list(APPEND problems "${file}: '${match}' names LLVM ${number}, not ${LLVM_MAJOR}")
        endif()
    endforeach()
    set(problems "${problems}" PARENT_SCOPE)
endfunction()

check_numbers(CMakePresets.json "llvm@([0-9]+)/bin")
check_numbers(CMakePresets.json "llvm-([0-9]+)/bin")
check_numbers(.github/workflows/gate.yml "LLVM_MAJOR: ([0-9]+)")
check_numbers(.github/workflows/gate.yml "LLVM_VERSION: ([0-9]+)\\.")

if(problems)
    list(JOIN problems "\n  " problems)
    message(FATAL_ERROR "toolchain_pins: files name another LLVM major:\n  ${problems}")
endif()
message("toolchain_pins: OK")

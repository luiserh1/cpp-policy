# cpp-policy's triplets (tools/vcpkg/) stay in step with each other and with the policy module.
#
#   cmake -DPOLICY_ROOT=<dir> -DLLVM_MAJOR=<n> -P files.cmake
#
# The three triplets can't share their code through an included file (vcpkg wouldn't notice a
# change to it), so they must differ only in the line that names their sanitizer. llvm.cmake
# can't read CppPolicy.cmake's LLVM version for the same reason, so it must repeat it.

cmake_minimum_required(VERSION 3.29)
set(dir "${POLICY_ROOT}/tools/vcpkg")
set(problems "")

set(reference "")
foreach(kind IN ITEMS asan tsan nosan)
    file(READ "${dir}/triplets/cpp-policy-${kind}.cmake" text)
    string(REGEX REPLACE "\nset\\(_cpp_policy_sanitizer (address|thread|none)\\)\n" "\n@@\n"
        text "${text}")
    string(FIND "${text}" "\n@@\n" marker)
    if(marker EQUAL -1)
        list(APPEND problems "cpp-policy-${kind}.cmake has no 'set(_cpp_policy_sanitizer ...)' line")
    elseif(reference STREQUAL "")
        set(reference "${text}")
    elseif(NOT text STREQUAL reference)
        list(APPEND problems "cpp-policy-${kind}.cmake differs from cpp-policy-asan.cmake in more "
                             "than its sanitizer line")
    endif()
endforeach()

file(STRINGS "${dir}/llvm.cmake" line REGEX "^set\\(_cpp_policy_llvm_major [0-9]+\\)$")
if(NOT line STREQUAL "set(_cpp_policy_llvm_major ${LLVM_MAJOR})")
    list(APPEND problems "llvm.cmake asks for another LLVM than CppPolicy.cmake (${LLVM_MAJOR}): "
                         "'${line}'")
endif()

if(problems)
    list(JOIN problems "\n  " problems)
    message(FATAL_ERROR "vcpkg_triplets: the triplet files are out of step:\n  ${problems}")
endif()
message("vcpkg_triplets: files OK")

# Loads vcpkg for a project that uses it (POLICY.md 1.1). The project's CMakeLists.txt includes
# this file before project(), where vcpkg installs the dependencies; the policy module is only
# fetched after project(), so this file is a copy the project keeps unchanged (the audit checks
# it, and upgrades replace it).
#
# The dependencies are built with the triplet in triplets/ that matches the preset: the same
# LLVM as the project, the same sanitizer, and the policy's hardening. With vcpkg's default
# triplets they would be built by the system's compiler (Apple Clang on macOS, MSVC's cl.exe
# on Windows) without any of it, and AddressSanitizer would miss an overread inside them.

if(NOT DEFINED ENV{VCPKG_ROOT})
    # Without it CMake's own error only shows a path starting with /scripts/.
    message(FATAL_ERROR "VCPKG_ROOT is not set: set it to the vcpkg directory (README: Building).")
endif()

# The presets set these before this file runs. UndefinedBehaviorSanitizer stays out of the
# dependencies: it would stop the program on a dependency's own undefined behavior, which the
# project can't fix; AddressSanitizer is what catches the project's mistakes at the boundary.
if(CPP_POLICY_THREAD_SANITIZER)
    set(_cpp_policy_triplet cpp-policy-tsan)
elseif(CPP_POLICY_SANITIZERS)
    set(_cpp_policy_triplet cpp-policy-asan)
else()
    set(_cpp_policy_triplet cpp-policy-nosan)
endif()

# FORCE: the triplet follows the sanitizer options even when a build folder is reconfigured
# with other ones.
set(VCPKG_OVERLAY_TRIPLETS "${CMAKE_CURRENT_LIST_DIR}/triplets" CACHE PATH
    "cpp-policy's triplets (tools/vcpkg/setup.cmake)" FORCE)
set(VCPKG_TARGET_TRIPLET "${_cpp_policy_triplet}" CACHE STRING
    "Chosen by tools/vcpkg/setup.cmake from the sanitizer options" FORCE)
unset(_cpp_policy_triplet)

# Not FORCE: a -DCMAKE_TOOLCHAIN_FILE given on the command line still wins.
set(CMAKE_TOOLCHAIN_FILE "$ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake" CACHE FILEPATH
    "vcpkg's toolchain (loaded by tools/vcpkg/setup.cmake)")

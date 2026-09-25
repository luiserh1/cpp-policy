# cpp-policy: applies the project policy (POLICY.md) to CMake targets.
#
# Usage from a consuming project:
#   FetchContent_Declare(cpp_policy GIT_REPOSITORY ... GIT_TAG vX.Y.Z)
#   FetchContent_MakeAvailable(cpp_policy)
#   cpp_policy_apply(my_target)      # once per target you own
#   cpp_policy_add_checks()          # once, adds the audit and format targets
#
# Options are normally set by CMakePresets.json, not by hand.

include_guard(GLOBAL)
include(CheckCXXCompilerFlag)

set(CPP_POLICY_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." CACHE INTERNAL "cpp-policy root directory")
cmake_path(NORMAL_PATH CPP_POLICY_ROOT)
set(CPP_POLICY_LLVM_MAJOR 23 CACHE INTERNAL "Required LLVM major version")

option(CPP_POLICY_SANITIZERS "Enable AddressSanitizer + UndefinedBehaviorSanitizer" OFF)
option(CPP_POLICY_CLANG_TIDY "Run clang-tidy as part of the build" OFF)
option(CPP_POLICY_EXCEPTIONS "Enable C++ exceptions and RTTI" ON)
set(CPP_POLICY_HARDENING "fast" CACHE STRING "Standard library hardening level: none, fast, debug")
set_property(CACHE CPP_POLICY_HARDENING PROPERTY STRINGS none fast debug)
set(CPP_POLICY_CONFINED_DIRS "src/lowlevel" CACHE STRING
    "Directories (relative to the project root) where suppressions and low-level code are allowed")
set(CPP_POLICY_EXCLUDED_DIRS "build;out;.git;third_party;external;vcpkg_installed" CACHE STRING
    "Directories (relative to the project root) that the audit and format checks skip")

# ---------------------------------------------------------------------------
# Toolchain verification
# ---------------------------------------------------------------------------
function(_cpp_policy_verify_toolchain)
    get_property(done GLOBAL PROPERTY _CPP_POLICY_TOOLCHAIN_VERIFIED)
    if(done)
        return()
    endif()

    if(NOT CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
        message(FATAL_ERROR
            "cpp-policy requires LLVM Clang ${CPP_POLICY_LLVM_MAJOR}.x, found "
            "'${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}' (${CMAKE_CXX_COMPILER}).\n"
            "On macOS, Apple Clang is not accepted. Install Homebrew LLVM, or put your "
            "LLVM ${CPP_POLICY_LLVM_MAJOR} bin directory first in PATH (README: Setup per platform).")
    endif()
    string(REGEX MATCH "^[0-9]+" major "${CMAKE_CXX_COMPILER_VERSION}")
    if(NOT major EQUAL CPP_POLICY_LLVM_MAJOR)
        message(FATAL_ERROR
            "cpp-policy requires LLVM Clang ${CPP_POLICY_LLVM_MAJOR}.x, found "
            "${CMAKE_CXX_COMPILER_VERSION} (${CMAKE_CXX_COMPILER}).")
    endif()

    # clang-tidy and clang-format must come from the same LLVM release as the compiler.
    cmake_path(GET CMAKE_CXX_COMPILER PARENT_PATH llvm_bin)
    find_program(CPP_POLICY_CLANG_TIDY_EXE NAMES clang-tidy HINTS "${llvm_bin}" NO_DEFAULT_PATH)
    find_program(CPP_POLICY_CLANG_FORMAT_EXE NAMES clang-format HINTS "${llvm_bin}" NO_DEFAULT_PATH)
    foreach(tool IN ITEMS CPP_POLICY_CLANG_TIDY_EXE CPP_POLICY_CLANG_FORMAT_EXE)
        if(NOT ${tool})
            message(FATAL_ERROR "cpp-policy: could not find ${tool} next to the compiler in ${llvm_bin}")
        endif()
    endforeach()

    set_property(GLOBAL PROPERTY _CPP_POLICY_TOOLCHAIN_VERIFIED TRUE)
endfunction()

# ---------------------------------------------------------------------------
# Per-target policy
# ---------------------------------------------------------------------------
function(cpp_policy_apply target)
    _cpp_policy_verify_toolchain()

    # "clang-cl" uses the MSVC command-line syntax.
    if(CMAKE_CXX_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC")
        set(msvc_cli TRUE)
    else()
        set(msvc_cli FALSE)
    endif()

    # Standard: C++23, no GNU/MS extensions.
    target_compile_features(${target} PRIVATE cxx_std_23)
    set_target_properties(${target} PROPERTIES
        CXX_EXTENSIONS OFF
        EXPORT_COMPILE_COMMANDS ON)

    # Warnings: always on, always errors. In clang-cl, -Wall means -Weverything, so use /W4.
    set(warnings
        -Wpedantic -Wshadow -Wnon-virtual-dtor -Wold-style-cast -Wcast-align -Wunused
        -Woverloaded-virtual -Wconversion -Wsign-conversion -Wnull-dereference
        -Wdouble-promotion -Wformat=2 -Wimplicit-fallthrough -Wzero-as-null-pointer-constant
        -Wextra-semi -Werror)
    if(msvc_cli)
        list(PREPEND warnings /W4)
    else()
        list(PREPEND warnings -Wall -Wextra)
    endif()
    target_compile_options(${target} PRIVATE ${warnings})

    # Exceptions and RTTI.
    if(NOT CPP_POLICY_EXCEPTIONS)
        if(msvc_cli)
            target_compile_options(${target} PRIVATE /EHs-c- /GR-)
            target_compile_definitions(${target} PRIVATE _HAS_EXCEPTIONS=0)
        else()
            target_compile_options(${target} PRIVATE -fno-exceptions -fno-rtti)
        endif()
    endif()

    # Standard library hardening. Each library ignores the other libraries' macros.
    if(CPP_POLICY_HARDENING STREQUAL "fast")
        target_compile_definitions(${target} PRIVATE
            _LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_FAST
            _GLIBCXX_ASSERTIONS
            _MSVC_STL_HARDENING=1)
    elseif(CPP_POLICY_HARDENING STREQUAL "debug")
        target_compile_definitions(${target} PRIVATE
            _LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_DEBUG
            _GLIBCXX_ASSERTIONS
            _MSVC_STL_HARDENING=1)
    elseif(NOT CPP_POLICY_HARDENING STREQUAL "none")
        message(FATAL_ERROR "cpp-policy: unknown CPP_POLICY_HARDENING '${CPP_POLICY_HARDENING}'")
    endif()

    # Low-cost security hardening for optimized builds (not available with clang-cl).
    if(NOT msvc_cli)
        target_compile_options(${target} PRIVATE
            $<$<NOT:$<CONFIG:Debug>>:-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3>)
        check_cxx_compiler_flag(-fstack-protector-strong CPP_POLICY_HAS_STACK_PROTECTOR)
        if(CPP_POLICY_HAS_STACK_PROTECTOR)
            target_compile_options(${target} PRIVATE -fstack-protector-strong)
        endif()
        check_cxx_compiler_flag(-fcf-protection CPP_POLICY_HAS_CF_PROTECTION)
        if(CPP_POLICY_HAS_CF_PROTECTION)
            target_compile_options(${target} PRIVATE -fcf-protection)
        endif()
    endif()

    # Sanitizers. See POLICY.md 7.3 for the Windows limitations.
    if(CPP_POLICY_SANITIZERS)
        if(msvc_cli)
            target_compile_options(${target} PRIVATE /fsanitize=address)
            set_target_properties(${target} PROPERTIES MSVC_RUNTIME_LIBRARY MultiThreadedDLL)
        else()
            set(san -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer)
            target_compile_options(${target} PRIVATE ${san})
            target_link_options(${target} PRIVATE ${san})
        endif()
    endif()

    # clang-tidy always uses the policy's configuration, whatever .clang-tidy the project has.
    if(CPP_POLICY_CLANG_TIDY)
        set_target_properties(${target} PROPERTIES CXX_CLANG_TIDY
            "${CPP_POLICY_CLANG_TIDY_EXE};--config-file=${CPP_POLICY_ROOT}/.clang-tidy")
    endif()
endfunction()

# ---------------------------------------------------------------------------
# Project-wide checks: suppression audit and format check/fix
# ---------------------------------------------------------------------------
function(cpp_policy_add_checks)
    _cpp_policy_verify_toolchain()
    if(TARGET policy-audit)
        return()
    endif()

    set(config "${CMAKE_BINARY_DIR}/cpp_policy_config.cmake")
    file(WRITE "${config}"
        "set(SOURCE_DIR [==[${CMAKE_SOURCE_DIR}]==])\n"
        "set(POLICY_ROOT [==[${CPP_POLICY_ROOT}]==])\n"
        "set(CONFINED_DIRS [==[${CPP_POLICY_CONFINED_DIRS}]==])\n"
        "set(EXCLUDED_DIRS [==[${CPP_POLICY_EXCLUDED_DIRS}]==])\n"
        "set(CLANG_FORMAT [==[${CPP_POLICY_CLANG_FORMAT_EXE}]==])\n")

    set(scripts "${CPP_POLICY_ROOT}/cmake/scripts")
    add_custom_target(policy-audit
        COMMAND "${CMAKE_COMMAND}" -DCONFIG=${config} -DCHECK_PROJECT_FILES=ON -P "${scripts}/audit_suppressions.cmake"
        COMMENT "cpp-policy: auditing suppressions"
        VERBATIM)
    add_custom_target(policy-format-check
        COMMAND "${CMAKE_COMMAND}" -DCONFIG=${config} -DMODE=check -P "${scripts}/format.cmake"
        COMMENT "cpp-policy: checking formatting"
        VERBATIM)
    add_custom_target(policy-format-fix
        COMMAND "${CMAKE_COMMAND}" -DCONFIG=${config} -DMODE=fix -P "${scripts}/format.cmake"
        COMMENT "cpp-policy: formatting sources"
        VERBATIM)
endfunction()

# cpp-policy: applies the project policy (POLICY.md) to CMake targets.
#
# Usage from a consuming project:
#   FetchContent_Declare(cpp_policy GIT_REPOSITORY ... GIT_TAG vX.Y.Z)
#   FetchContent_MakeAvailable(cpp_policy)
#   cpp_policy_apply(my_target)      # once per target you own
#   cpp_policy_add_tests(unit my_module SOURCES ... LIBRARIES ...)   # test programs
#   cpp_policy_size_budget(my_program MACOS <bytes> LINUX <bytes> WINDOWS <bytes>)
#   cpp_policy_add_checks()          # once, adds the audit and format targets
#
# Options are normally set by CMakePresets.json, not by hand.

include_guard(GLOBAL)
include(CheckCXXCompilerFlag)

set(CPP_POLICY_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." CACHE INTERNAL "cpp-policy root directory")
cmake_path(NORMAL_PATH CPP_POLICY_ROOT)
set(CPP_POLICY_LLVM_MAJOR 23 CACHE INTERNAL "Required LLVM major version")

option(CPP_POLICY_SANITIZERS "Enable AddressSanitizer + UndefinedBehaviorSanitizer" OFF)
option(CPP_POLICY_THREAD_SANITIZER "Enable ThreadSanitizer (not with CPP_POLICY_SANITIZERS)" OFF)
option(CPP_POLICY_CLANG_TIDY "Run clang-tidy as part of the build" OFF)
option(CPP_POLICY_EXCEPTIONS "Enable C++ exceptions and RTTI" ON)
set(CPP_POLICY_HARDENING "fast" CACHE STRING "Standard library hardening level: fast, debug")
set_property(CACHE CPP_POLICY_HARDENING PROPERTY STRINGS fast debug)
set(CPP_POLICY_CONFINED_DIRS "src/lowlevel" CACHE STRING
    "Directories (relative to the project root) where suppressions and low-level code are allowed")
set(CPP_POLICY_EXCLUDED_DIRS "build;out;.git;third_party;external;vcpkg_installed" CACHE STRING
    "Directories (relative to the project root) that the audit and format checks skip")
set(CPP_POLICY_TEST_KINDS unit integration benchmark CACHE INTERNAL "Test kinds (POLICY.md 13)")
set(CPP_POLICY_TEST_TIDY_CHECKS "--checks=-bugprone-unchecked-optional-access" CACHE INTERNAL
    "clang-tidy option added for test programs (POLICY.md 13.4)")

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
# AddressSanitizer runtime with clang-cl
# ---------------------------------------------------------------------------
# Returns the full path of a file in the compiler's runtime directories, or fails.
function(_cpp_policy_runtime_file name out)
    execute_process(COMMAND "${CMAKE_CXX_COMPILER}" "/clang:-print-file-name=${name}"
        OUTPUT_VARIABLE path OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    # clang prints the bare name back when it can't find the file.
    if(NOT IS_ABSOLUTE "${path}" OR NOT EXISTS "${path}")
        message(FATAL_ERROR "cpp-policy: ${CMAKE_CXX_COMPILER} can't find its AddressSanitizer "
            "runtime file ${name}; the LLVM installation is incomplete.")
    endif()
    cmake_path(NORMAL_PATH path)
    set(${out} "${path}" PARENT_SCOPE)
endfunction()

# The clang-cl driver adds the ASan runtime when it links, but CMake calls lld-link directly,
# so without these options every sanitized program fails to link with undefined __asan_*
# symbols. The options are what the driver passes for /fsanitize=address with /MD (LLVM 23).
# The runtime DLL is copied next to each program so ctest, a debugger and running the
# program by hand all find it without changing PATH.
function(_cpp_policy_windows_asan_runtime target)
    get_property(runtime GLOBAL PROPERTY _CPP_POLICY_ASAN_RUNTIME)
    if(NOT runtime)
        if(CMAKE_CXX_COMPILER_ARCHITECTURE_ID STREQUAL "x64")
            set(arch x86_64)
        elseif(CMAKE_CXX_COMPILER_ARCHITECTURE_ID STREQUAL "ARM64")
            set(arch aarch64)
        else()
            message(FATAL_ERROR "cpp-policy: AddressSanitizer with clang-cl supports x64 and ARM64, "
                "not '${CMAKE_CXX_COMPILER_ARCHITECTURE_ID}'")
        endif()
        _cpp_policy_runtime_file("clang_rt.asan_dynamic-${arch}.lib" lib)
        _cpp_policy_runtime_file("clang_rt.asan_dynamic_runtime_thunk-${arch}.lib" thunk)
        _cpp_policy_runtime_file("clang_rt.asan_dynamic-${arch}.dll" dll)
        set(runtime "${lib};${thunk};${dll}")
        set_property(GLOBAL PROPERTY _CPP_POLICY_ASAN_RUNTIME "${runtime}")
    endif()
    list(GET runtime 0 lib)
    list(GET runtime 1 thunk)
    list(GET runtime 2 dll)

    get_target_property(type ${target} TYPE)
    if(type MATCHES "^(EXECUTABLE|SHARED_LIBRARY|MODULE_LIBRARY)$")
        target_link_options(${target} PRIVATE
            "${lib}" "/wholearchive:${thunk}" "/include:__asan_seh_interceptor")
        add_custom_command(TARGET ${target} POST_BUILD
            COMMAND "${CMAKE_COMMAND}" "-DSOURCE=${dll}" "-DDESTINATION=$<TARGET_FILE_DIR:${target}>"
                    -P "${CPP_POLICY_ROOT}/cmake/scripts/copy_runtime.cmake"
            VERBATIM)
    endif()
endfunction()

# ---------------------------------------------------------------------------
# Per-target policy
# ---------------------------------------------------------------------------
function(cpp_policy_apply target)
    _cpp_policy_verify_toolchain()
    # Checked at the end of configuration (_cpp_policy_verify_targets).
    set_target_properties(${target} PROPERTIES CPP_POLICY_APPLIED TRUE)
    # Another project's library, built here (cpp_policy_use_library, POLICY.md 11.7): it gets
    # this build's standard, hardening and sanitizers, which must be the same in everything
    # that is linked together, but not its warnings as errors or its clang-tidy. The
    # library's own gate checked the code; this project can't edit it.
    get_target_property(as_dependency ${target} CPP_POLICY_LIBRARY_DEPENDENCY)

    # "clang-cl" uses the MSVC command-line syntax.
    if(CMAKE_CXX_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC")
        set(msvc_cli TRUE)
    else()
        set(msvc_cli FALSE)
    endif()

    # clang-cl: without this, clang-tidy never sees the slash-form options (/EHsc, /D..., /W4).
    # CMake passes it --extra-arg-before=--driver-mode=cl, but clang-tidy drops the arguments
    # after "--" that look like input files before it applies that, and in GCC mode every
    # slash-form option looks like a path. A copy among the compile options is read in time
    # (verified with LLVM 23.1.2). tests/clang_cl/slash_options.cpp fails without it.
    if(msvc_cli)
        target_compile_options(${target} PRIVATE --driver-mode=cl)
    endif()

    # Standard: C++23, no GNU/MS extensions.
    target_compile_features(${target} PRIVATE cxx_std_23)
    # Waiting W1 (POLICY.md 12): modules are not used yet. Without this, CMake scans every
    # C++23 file for them and adds a @<file>.modmap argument that only exists after a build,
    # which breaks tools that read compile_commands.json first (clangd, clang-tidy on unbuilt
    # files).
    set_target_properties(${target} PROPERTIES
        CXX_EXTENSIONS OFF
        CXX_SCAN_FOR_MODULES OFF
        EXPORT_COMPILE_COMMANDS ON)

    # Warnings: always on, always errors. In clang-cl, -Wall means -Weverything, so use /W4.
    set(warnings
        -Wpedantic -Wshadow -Wnon-virtual-dtor -Wold-style-cast -Wcast-align -Wunused
        -Woverloaded-virtual -Wconversion -Wsign-conversion -Wnull-dereference
        -Wdouble-promotion -Wformat=2 -Wimplicit-fallthrough -Wzero-as-null-pointer-constant
        -Wextra-semi -Werror
        # A designated initializer may leave fields out: they take their default member
        # initializer or zero, at every optimization level (POLICY.md 2.10).
        -Wno-missing-designated-field-initializers)
    if(msvc_cli)
        list(PREPEND warnings /W4)
    else()
        list(PREPEND warnings -Wall -Wextra)
    endif()
    if(NOT as_dependency)
        target_compile_options(${target} PRIVATE ${warnings})
    endif()

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
    else()
        # There is no "none": hardening costs less than can be measured (POLICY.md 14.1).
        message(FATAL_ERROR "cpp-policy: CPP_POLICY_HARDENING must be 'fast' or 'debug', not "
                            "'${CPP_POLICY_HARDENING}' (POLICY.md 7.2)")
    endif()

    # Low-cost security hardening for optimized builds (POLICY.md 7, 7.4).
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
    else()
        # Control Flow Guard checks every indirect call against the table of valid targets.
        # Compiling with the flag instruments the calls; linking with it writes the table and
        # the PE flag, and lld-link, which CMake calls directly, won't do that on its own.
        # Stack cookies need nothing here: clang-cl compiles with -stack-protector 2 (strong)
        # by default, and the audit rejects /GS-. tests/hardening/pe_flags.cmake checks the
        # result on every sanitized or release build.
        target_compile_options(${target} PRIVATE $<$<NOT:$<CONFIG:Debug>>:/guard:cf>)
        target_link_options(${target} PRIVATE $<$<NOT:$<CONFIG:Debug>>:/guard:cf>)
    endif()

    # Sanitizers. See POLICY.md 7.3 for the Windows limitations.
    if(CPP_POLICY_SANITIZERS)
        if(msvc_cli)
            target_compile_options(${target} PRIVATE /fsanitize=address)
            set_target_properties(${target} PROPERTIES MSVC_RUNTIME_LIBRARY MultiThreadedDLL)
            _cpp_policy_windows_asan_runtime(${target})
        else()
            set(san -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer)
            target_compile_options(${target} PRIVATE ${san})
            target_link_options(${target} PRIVATE ${san})
        endif()
    endif()

    # ThreadSanitizer finds data races (POLICY.md 2.8). It can't share a build with ASan.
    if(CPP_POLICY_THREAD_SANITIZER)
        if(CPP_POLICY_SANITIZERS)
            message(FATAL_ERROR "cpp-policy: CPP_POLICY_THREAD_SANITIZER can't be combined with "
                "CPP_POLICY_SANITIZERS; use the tsan preset")
        endif()
        if(msvc_cli)
            message(FATAL_ERROR "cpp-policy: ThreadSanitizer is not available with clang-cl")
        endif()
        set(tsan -fsanitize=thread -fno-omit-frame-pointer)
        target_compile_options(${target} PRIVATE ${tsan})
        target_link_options(${target} PRIVATE ${tsan})
    endif()

    # clang-tidy always uses the policy's configuration, whatever .clang-tidy the project has.
    if(CPP_POLICY_CLANG_TIDY AND NOT as_dependency)
        _cpp_policy_tidy_config(config)
        set_target_properties(${target} PROPERTIES CXX_CLANG_TIDY
            "${CPP_POLICY_CLANG_TIDY_EXE};--config-file=${config}")
    endif()
endfunction()

# The policy's .clang-tidy as clang-tidy reads it: a copy in the build folder, named after a
# hash of its contents. The build doesn't know objects depend on that file, so after a change
# (an upgrade to a release with other rules) files already built would keep their old results.
# configure_file re-runs CMake when the original changes; the copy's new name changes every
# clang-tidy command; and the generator rebuilds whatever command changed.
function(_cpp_policy_tidy_config out)
    set(source "${CPP_POLICY_ROOT}/.clang-tidy")
    file(SHA256 "${source}" hash)
    string(SUBSTRING "${hash}" 0 16 hash)
    set(dir "${CMAKE_BINARY_DIR}/cpp_policy_tidy")
    configure_file("${source}" "${dir}/${hash}.clang-tidy" COPYONLY)
    file(GLOB copies "${dir}/*.clang-tidy")
    list(REMOVE_ITEM copies "${dir}/${hash}.clang-tidy")
    if(copies)
        file(REMOVE ${copies})
    endif()
    set(${out} "${dir}/${hash}.clang-tidy" PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# Target verification: the policy can't be bypassed from CMake
# ---------------------------------------------------------------------------
# Lists the targets defined in `dir` and its subdirectories, skipping fetched
# dependencies (inside the build tree) and the excluded directories.
function(_cpp_policy_project_targets dir out)
    get_property(targets DIRECTORY "${dir}" PROPERTY BUILDSYSTEM_TARGETS)
    get_property(subdirs DIRECTORY "${dir}" PROPERTY SUBDIRECTORIES)
    foreach(sub IN LISTS subdirs)
        cmake_path(IS_PREFIX CMAKE_BINARY_DIR "${sub}" NORMALIZE in_build_tree)
        cmake_path(RELATIVE_PATH sub BASE_DIRECTORY "${CMAKE_SOURCE_DIR}" OUTPUT_VARIABLE rel)
        set(excluded FALSE)
        foreach(dir_name IN LISTS CPP_POLICY_EXCLUDED_DIRS)
            if(rel STREQUAL dir_name OR rel MATCHES "^${dir_name}/")
                set(excluded TRUE)
            endif()
        endforeach()
        if(NOT in_build_tree AND NOT excluded)
            _cpp_policy_project_targets("${sub}" sub_targets)
            list(APPEND targets ${sub_targets})
        endif()
    endforeach()
    set(${out} ${targets} PARENT_SCOPE)
endfunction()

# Lists the tests added with add_test() in `dir` and its subdirectories, with the same
# directories skipped as for targets. (Tests from cpp_policy_add_tests() are registered at
# build time and aren't listed.)
function(_cpp_policy_project_tests dir out)
    get_property(tests DIRECTORY "${dir}" PROPERTY TESTS)
    set(found "")
    foreach(test IN LISTS tests)
        list(APPEND found "${dir}|${test}")
    endforeach()
    get_property(subdirs DIRECTORY "${dir}" PROPERTY SUBDIRECTORIES)
    foreach(sub IN LISTS subdirs)
        cmake_path(IS_PREFIX CMAKE_BINARY_DIR "${sub}" NORMALIZE in_build_tree)
        cmake_path(RELATIVE_PATH sub BASE_DIRECTORY "${CMAKE_SOURCE_DIR}" OUTPUT_VARIABLE rel)
        set(excluded FALSE)
        foreach(dir_name IN LISTS CPP_POLICY_EXCLUDED_DIRS)
            if(rel STREQUAL dir_name OR rel MATCHES "^${dir_name}/")
                set(excluded TRUE)
            endif()
        endforeach()
        if(NOT in_build_tree AND NOT excluded)
            _cpp_policy_project_tests("${sub}" sub_tests)
            list(APPEND found ${sub_tests})
        endif()
    endforeach()
    set(${out} ${found} PARENT_SCOPE)
endfunction()

# Whether a standard-library hardening or fortify definition (NAME or NAME=value) keeps the
# policy's protection: the levels the policy itself sets, or stronger.
function(_cpp_policy_definition_weakens definition out)
    set(weakens FALSE)
    if(definition MATCHES "^(_LIBCPP_HARDENING_MODE|_GLIBCXX_ASSERTIONS|_MSVC_STL_HARDENING|_FORTIFY_SOURCE)(=([^>]*))?")
        set(name "${CMAKE_MATCH_1}")
        set(value "${CMAKE_MATCH_3}")
        if(name STREQUAL "_LIBCPP_HARDENING_MODE")
            if(NOT value MATCHES "^_LIBCPP_HARDENING_MODE_(FAST|EXTENSIVE|DEBUG)$")
                set(weakens TRUE)
            endif()
        elseif(name STREQUAL "_FORTIFY_SOURCE")
            if(NOT value STREQUAL "3")
                set(weakens TRUE)
            endif()
        elseif(value STREQUAL "0")
            set(weakens TRUE)
        endif()
    endif()
    set(${out} ${weakens} PARENT_SCOPE)
endfunction()

# Appends a problem to the list named by `out_list` for each option that turns warnings off,
# or weakens a protection the policy turns on: the stack protector, fortify, control-flow
# protection, standard-library hardening, the sanitizers, and clang-cl's hardening. clang-cl
# accepts either prefix, so both are checked.
# (The parameter must not be called `problems`: it would shadow the caller's list.)
function(_cpp_policy_check_options what options out_list)
    set(found ${${out_list}})
    foreach(option IN LISTS options)
        if(option STREQUAL "-Wno-missing-designated-field-initializers")
            # The policy's own (cpp_policy_apply, POLICY.md 2.10).
        elseif(option MATCHES "-Wno-|/wd[0-9]" OR option MATCHES "^[-/]w$" OR option STREQUAL "/W0")
            list(APPEND found "${what} turns warnings off: ${option}")
        elseif(option MATCHES "^[-/](GS|guard:cf|sdl)-$"
               OR option MATCHES "^-fno-stack-protector$|^-fstack-protector$"
               OR (option MATCHES "^-fcf-protection=" AND NOT option MATCHES "^-fcf-protection=full$")
               OR option MATCHES "^-fno-sanitize="
               OR option MATCHES "^[-/]U(_LIBCPP_HARDENING_MODE|_GLIBCXX_ASSERTIONS|_MSVC_STL_HARDENING)$")
            list(APPEND found "${what} turns hardening off: ${option}")
        elseif(option MATCHES "^[-/]D(.*)$")
            _cpp_policy_definition_weakens("${CMAKE_MATCH_1}" weakens)
            if(weakens)
                list(APPEND found "${what} turns hardening off: ${option}")
            endif()
        endif()
    endforeach()
    set(${out_list} ${found} PARENT_SCOPE)
endfunction()

# The same for compile definitions (target_compile_definitions, add_compile_definitions).
function(_cpp_policy_check_definitions what definitions out_list)
    set(found ${${out_list}})
    foreach(definition IN LISTS definitions)
        _cpp_policy_definition_weakens("${definition}" weakens)
        if(weakens)
            list(APPEND found "${what} turns hardening off: ${definition}")
        endif()
    endforeach()
    set(${out_list} ${found} PARENT_SCOPE)
endfunction()

# Runs once, after the whole project is configured (deferred by cpp_policy_add_checks).
function(_cpp_policy_verify_targets)
    set(problems "")
    # The test programs (cpp_policy_add_tests), which have one clang-tidy check fewer; their
    # sources are written down for tidy-files, which checks files outside the build.
    get_property(test_targets GLOBAL PROPERTY CPP_POLICY_TEST_TARGETS)
    get_property(test_sources GLOBAL PROPERTY CPP_POLICY_TEST_SOURCES)
    file(WRITE "${CMAKE_BINARY_DIR}/cpp_policy_tests.cmake"
        "set(TEST_SOURCES [==[${test_sources}]==])\n"
        "set(TEST_TIDY_CHECKS [==[${CPP_POLICY_TEST_TIDY_CHECKS}]==])\n")
    foreach(var IN ITEMS CMAKE_CXX_FLAGS CMAKE_CXX_FLAGS_DEBUG CMAKE_CXX_FLAGS_RELEASE
                         CMAKE_CXX_FLAGS_RELWITHDEBINFO CMAKE_CXX_FLAGS_MINSIZEREL)
        separate_arguments(flags NATIVE_COMMAND "${${var}}")
        _cpp_policy_check_options("${var}" "${flags}" problems)
    endforeach()

    _cpp_policy_project_targets("${CMAKE_SOURCE_DIR}" targets)
    foreach(target IN LISTS targets)
        get_target_property(type ${target} TYPE)
        if(NOT type MATCHES "^(EXECUTABLE|STATIC_LIBRARY|SHARED_LIBRARY|MODULE_LIBRARY|OBJECT_LIBRARY)$")
            continue()
        endif()
        get_target_property(applied ${target} CPP_POLICY_APPLIED)
        if(NOT applied)
            list(APPEND problems "target '${target}' does not call cpp_policy_apply()")
            continue()
        endif()
        foreach(property IN ITEMS COMPILE_OPTIONS INTERFACE_COMPILE_OPTIONS)
            get_target_property(options ${target} ${property})
            if(options)
                _cpp_policy_check_options("target '${target}' (${property})" "${options}" problems)
            endif()
        endforeach()
        foreach(property IN ITEMS COMPILE_DEFINITIONS INTERFACE_COMPILE_DEFINITIONS)
            get_target_property(definitions ${target} ${property})
            if(definitions)
                _cpp_policy_check_definitions("target '${target}' (${property})" "${definitions}"
                    problems)
            endif()
        endforeach()
        get_target_property(as_dependency ${target} CPP_POLICY_LIBRARY_DEPENDENCY)
        if(CPP_POLICY_CLANG_TIDY AND NOT as_dependency)
            get_target_property(tidy ${target} CXX_CLANG_TIDY)
            _cpp_policy_tidy_config(config)
            set(expected "${CPP_POLICY_CLANG_TIDY_EXE};--config-file=${config}")
            if(target IN_LIST test_targets)
                list(APPEND expected "${CPP_POLICY_TEST_TIDY_CHECKS}")
            endif()
            if(NOT tidy STREQUAL "${expected}")
                list(APPEND problems "target '${target}' changes CXX_CLANG_TIDY")
            endif()
        endif()
        get_target_property(sources ${target} SOURCES)
        foreach(source IN LISTS sources)
            get_source_file_property(skip "${source}" TARGET_DIRECTORY ${target} SKIP_LINTING)
            if(skip)
                list(APPEND problems "target '${target}': ${source} sets SKIP_LINTING")
            endif()
            foreach(property IN ITEMS COMPILE_OPTIONS COMPILE_FLAGS)
                get_source_file_property(options "${source}" TARGET_DIRECTORY ${target} ${property})
                if(options)
                    separate_arguments(options NATIVE_COMMAND "${options}")
                    _cpp_policy_check_options("target '${target}': ${source}" "${options}" problems)
                endif()
            endforeach()
            get_source_file_property(definitions "${source}" TARGET_DIRECTORY ${target}
                COMPILE_DEFINITIONS)
            if(definitions)
                _cpp_policy_check_definitions("target '${target}': ${source}" "${definitions}"
                    problems)
            endif()
        endforeach()
    endforeach()

    if(problems)
        list(JOIN problems "\n  " problem_list)
        message(FATAL_ERROR "cpp-policy: the policy is bypassed in CMake:\n  ${problem_list}\n"
            "Every target must call cpp_policy_apply() and keep its settings (POLICY.md 6).")
    endif()
    _cpp_policy_verify_tests()
endfunction()

# Tests added with add_test() instead of cpp_policy_add_tests() (a program run with arguments,
# a script) follow the same names and labels (POLICY.md 13). cpp-policy's own self-test is
# exempt: it tests CMake scripts and tools, not a program's modules.
function(_cpp_policy_verify_tests)
    if(CMAKE_PROJECT_NAME STREQUAL "cpp_policy")
        return()
    endif()
    list(JOIN CPP_POLICY_TEST_KINDS "|" kinds)
    set(problems "")
    _cpp_policy_project_tests("${CMAKE_SOURCE_DIR}" tests)
    foreach(entry IN LISTS tests)
        string(REPLACE "|" ";" entry "${entry}")
        list(GET entry 0 dir)
        list(GET entry 1 test)
        if(NOT test MATCHES "^(${kinds})/[a-z0-9_]+/.")
            list(JOIN CPP_POLICY_TEST_KINDS ", " kind_list)
            list(APPEND problems
                "test '${test}' isn't named <kind>/<module>/<case> (kinds: ${kind_list})")
            continue()
        endif()
        get_property(labels TEST "${test}" DIRECTORY "${dir}" PROPERTY LABELS)
        if(NOT CMAKE_MATCH_1 IN_LIST labels)
            list(APPEND problems "test '${test}' doesn't have the label '${CMAKE_MATCH_1}'")
        endif()
        get_property(environment TEST "${test}" DIRECTORY "${dir}" PROPERTY ENVIRONMENT)
        foreach(variable IN LISTS environment)
            if(variable MATCHES "^(ASAN|LSAN|UBSAN|TSAN|MSAN)_OPTIONS=")
                list(APPEND problems "test '${test}' sets ${variable}: sanitizer options "
                    "aren't a test's to set (POLICY.md 5)")
            endif()
        endforeach()
    endforeach()
    if(problems)
        list(JOIN problems "\n  " problem_list)
        message(FATAL_ERROR "cpp-policy: tests outside the policy's names and labels:\n  "
            "${problem_list}\nUse cpp_policy_add_tests(), or name and label the test as it "
            "would (POLICY.md 13).")
    endif()
endfunction()

# ---------------------------------------------------------------------------
# Git hooks: they only run once a clone points git at them (POLICY.md 8)
# ---------------------------------------------------------------------------
function(_cpp_policy_check_git_hooks)
    find_package(Git QUIET)
    if(NOT Git_FOUND OR NOT EXISTS "${CMAKE_SOURCE_DIR}/tools/hooks")
        return()
    endif()
    execute_process(COMMAND "${GIT_EXECUTABLE}" rev-parse --show-toplevel
        WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
        RESULT_VARIABLE failed OUTPUT_VARIABLE top
        OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    if(failed)
        return()
    endif()
    # Only a project at the root of its own repository: not one nested in another repository.
    file(REAL_PATH "${top}" top)
    file(REAL_PATH "${CMAKE_SOURCE_DIR}" source)
    if(NOT top STREQUAL source)
        return()
    endif()
    execute_process(COMMAND "${GIT_EXECUTABLE}" config --get core.hooksPath
        WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
        OUTPUT_VARIABLE hooks_path OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    if(NOT hooks_path STREQUAL "tools/hooks")
        message(WARNING "cpp-policy: the git hooks are not enabled in this clone, so commits and "
            "pushes skip the checks. Enable them once with:\n  git config core.hooksPath tools/hooks")
    endif()
endfunction()

# ---------------------------------------------------------------------------
# Dependencies: vcpkg.json entries and the licenses of what vcpkg installed (POLICY.md 1.1)
# ---------------------------------------------------------------------------
function(_cpp_policy_check_dependencies)
    if(NOT EXISTS "${CMAKE_SOURCE_DIR}/vcpkg.json")
        return()
    endif()
    # Set by vcpkg's toolchain file, which has already installed everything by now.
    set(installed "")
    if(DEFINED VCPKG_INSTALLED_DIR)
        foreach(triplet IN ITEMS ${VCPKG_TARGET_TRIPLET} ${VCPKG_HOST_TRIPLET})
            list(APPEND installed "${VCPKG_INSTALLED_DIR}/${triplet}")
        endforeach()
        list(REMOVE_DUPLICATES installed)
    endif()
    execute_process(
        COMMAND "${CMAKE_COMMAND}" "-DMANIFEST=${CMAKE_SOURCE_DIR}/vcpkg.json"
                "-DINSTALLED_DIRS=${installed}" -P "${CPP_POLICY_ROOT}/cmake/scripts/dependencies.cmake"
        RESULT_VARIABLE failed OUTPUT_VARIABLE output ERROR_VARIABLE output)
    if(failed)
        message(FATAL_ERROR "cpp-policy: the dependencies break the policy (POLICY.md 1.1):\n${output}")
    endif()
endfunction()

# ---------------------------------------------------------------------------
# The commit of cpp-policy in use, for the audit's CI pin check. Empty when cpp-policy isn't
# the root of its own git checkout (then the check is skipped).
# ---------------------------------------------------------------------------
function(_cpp_policy_commit out)
    set(${out} "" PARENT_SCOPE)
    find_package(Git QUIET)
    if(NOT Git_FOUND)
        return()
    endif()
    # Git exports GIT_DIR (and GIT_WORK_TREE, GIT_INDEX_FILE) to hooks. In a linked worktree
    # GIT_DIR names the project's repository, and git would answer with the project's commit
    # instead of the policy's when pre-commit configures the build.
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E env --unset=GIT_DIR --unset=GIT_WORK_TREE
                --unset=GIT_INDEX_FILE --unset=GIT_COMMON_DIR --unset=GIT_OBJECT_DIRECTORY
                "${GIT_EXECUTABLE}" rev-parse --show-toplevel HEAD
        WORKING_DIRECTORY "${CPP_POLICY_ROOT}"
        RESULT_VARIABLE failed OUTPUT_VARIABLE output
        OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    if(failed)
        return()
    endif()
    string(REPLACE "\n" ";" output "${output}")
    list(GET output 0 top)
    list(GET output 1 commit)
    file(REAL_PATH "${top}" top)
    file(REAL_PATH "${CPP_POLICY_ROOT}" root)
    if(top STREQUAL root)
        set(${out} "${commit}" PARENT_SCOPE)
    endif()
endfunction()

# ---------------------------------------------------------------------------
# Layers (POLICY.md 11.1): the project's modules under src/, from the lowest layer up.
#   cpp_policy_layers(LAYER lowlevel LAYER message LAYER app server)
# Call it before cpp_policy_add_checks(); the audit checks every #include against it.
# ---------------------------------------------------------------------------
function(cpp_policy_layers)
    if(TARGET policy-audit)
        message(FATAL_ERROR "cpp-policy: call cpp_policy_layers() before cpp_policy_add_checks()")
    endif()
    set(layers "")      # one entry per layer: its modules, comma-separated
    set(current "")     # the layer being read
    set(started FALSE)
    set(all_modules "")
    foreach(argument IN LISTS ARGN)
        if(argument STREQUAL "LAYER")
            if(started AND current STREQUAL "")
                message(FATAL_ERROR "cpp-policy: cpp_policy_layers() has an empty LAYER")
            endif()
            if(started)
                list(APPEND layers "${current}")
            endif()
            set(current "")
            set(started TRUE)
        elseif(NOT started)
            message(FATAL_ERROR "cpp-policy: cpp_policy_layers() must start with LAYER")
        elseif(NOT argument MATCHES "^[a-z0-9_]+$")
            message(FATAL_ERROR "cpp-policy: '${argument}' isn't a module name (a directory under src/)")
        elseif(argument IN_LIST all_modules)
            message(FATAL_ERROR "cpp-policy: module '${argument}' is in more than one layer")
        else()
            list(APPEND all_modules "${argument}")
            if(current STREQUAL "")
                set(current "${argument}")
            else()
                string(APPEND current ",${argument}")
            endif()
        endif()
    endforeach()
    if(current STREQUAL "")
        message(FATAL_ERROR "cpp-policy: cpp_policy_layers() needs LAYER followed by module names")
    endif()
    list(APPEND layers "${current}")
    set_property(GLOBAL PROPERTY CPP_POLICY_LAYERS "${layers}")
endfunction()

# ---------------------------------------------------------------------------
# A library that other policy projects use (POLICY.md 11.7). Its code is in
# lib/<name>/<module>/, next to this call's file, and every include of it is written
# "<name>/<module>/<header>". The call goes in library.cmake at the repository's root, which
# the project's CMakeLists.txt includes and which a user's cpp_policy_use_library() includes
# too, so that file holds nothing but what defines the library: find_package() for what it
# links, its list of sources, and this call.
#   cpp_policy_library(tonematcher
#       LAYER lowlevel
#       LAYER image naming
#       SOURCES lowlevel/process.cpp image/image.cpp naming/pieces.cpp
#       DEPENDENCIES zlib
#       LINK ZLIB::ZLIB)
# LAYER: the library's modules from the lowest layer up, as in cpp_policy_layers(); the audit
# holds them, and refuses an include from the library into src/. SOURCES: relative to
# lib/<name>/. DEPENDENCIES: the vcpkg packages it needs, which a user's vcpkg.json must
# list. TEST_SUPPORT: files of the library's modules that only tests use, which become
# <name>::test_support, with TEST_LINK for what they link (doctest::doctest). LINK: the
# targets it links, PUBLIC. It defines the target <name>_library, which
# everyone links by its alias <name>::<name>; the name <name> is left for a program.
# ---------------------------------------------------------------------------
set(CPP_POLICY_LIBRARY_FLOOR 0.30.0 CACHE INTERNAL
    "The oldest cpp-policy release a library may pin for this release to use it (POLICY.md 11.7)")

function(cpp_policy_library name)
    set(usage "cpp_policy_library(<name> LAYER <module>... [LAYER <module>...]... "
              "SOURCES <file>... [DEPENDENCIES <vcpkg package>...] [LINK <target>...] "
              "[TEST_SUPPORT <file>...] [TEST_LINK <target>...])")
    string(JOIN "" usage ${usage})
    if(NOT name MATCHES "^[a-z][a-z0-9_]*$")
        message(FATAL_ERROR "cpp-policy: a library's name is lower case letters, digits and "
            "'_' ('${name}'): it is a folder under lib/ and the start of every include")
    endif()
    # The layers, as cpp_policy_layers() reads them; then the other lists.
    set(layers "")
    set(current "")
    set(modules "")
    set(sources "")
    set(dependencies "")
    set(link "")
    set(test_support "")
    set(test_link "")
    set(reading "")
    foreach(argument IN LISTS ARGN)
        if(argument STREQUAL "LAYER")
            if(reading STREQUAL "layer" AND current STREQUAL "")
                message(FATAL_ERROR "cpp-policy: cpp_policy_library() has an empty LAYER")
            endif()
            if(NOT current STREQUAL "")
                list(APPEND layers "${current}")
            endif()
            set(current "")
            set(reading layer)
        elseif(argument MATCHES "^(SOURCES|DEPENDENCIES|LINK|TEST_SUPPORT|TEST_LINK)$")
            string(TOLOWER "${argument}" reading)
        elseif(reading STREQUAL "layer")
            if(NOT argument MATCHES "^[a-z0-9_]+$")
                message(FATAL_ERROR "cpp-policy: '${argument}' isn't a module name (a folder "
                    "under lib/${name}/)")
            elseif(argument IN_LIST modules)
                message(FATAL_ERROR "cpp-policy: module '${argument}' is in more than one layer")
            endif()
            list(APPEND modules "${argument}")
            if(current STREQUAL "")
                set(current "${argument}")
            else()
                string(APPEND current ",${argument}")
            endif()
        elseif(reading STREQUAL "sources")
            list(APPEND sources "${argument}")
        elseif(reading STREQUAL "dependencies")
            list(APPEND dependencies "${argument}")
        elseif(reading STREQUAL "link")
            list(APPEND link "${argument}")
        elseif(reading STREQUAL "test_support")
            list(APPEND test_support "${argument}")
        elseif(reading STREQUAL "test_link")
            list(APPEND test_link "${argument}")
        else()
            message(FATAL_ERROR "cpp-policy: usage: ${usage}")
        endif()
    endforeach()
    if(NOT current STREQUAL "")
        list(APPEND layers "${current}")
    endif()
    if(layers STREQUAL "" OR sources STREQUAL "")
        message(FATAL_ERROR "cpp-policy: usage: ${usage}")
    endif()
    # The target is <name>_library and the file lib<name>.a: the project's program is often
    # called <name> too. Everyone links the alias, <name>::<name>.
    set(target ${name}_library)
    if(TARGET ${target})
        message(FATAL_ERROR "cpp-policy: the library '${name}' is declared already")
    endif()

    # This call's file, not this function's: library.cmake, wherever it was fetched to.
    set(root "${CMAKE_CURRENT_LIST_DIR}")
    set(files "")
    foreach(source IN LISTS sources)
        if(NOT source MATCHES "^([a-z0-9_]+)/" OR NOT CMAKE_MATCH_1 IN_LIST modules)
            message(FATAL_ERROR "cpp-policy: library '${name}': source '${source}' isn't in one "
                "of its modules (${modules}); SOURCES are relative to lib/${name}/")
        endif()
        list(APPEND files "${root}/lib/${name}/${source}")
    endforeach()
    # What the library offers to tests, its own and its users': never part of the library.
    set(test_files "")
    set(test_compiled FALSE)
    foreach(source IN LISTS test_support)
        if(NOT source MATCHES "^([a-z0-9_]+)/" OR NOT CMAKE_MATCH_1 IN_LIST modules)
            message(FATAL_ERROR "cpp-policy: library '${name}': test support '${source}' isn't "
                "in one of its modules (${modules}); TEST_SUPPORT is relative to lib/${name}/")
        elseif(source IN_LIST sources)
            message(FATAL_ERROR "cpp-policy: library '${name}': '${source}' is in SOURCES and "
                "in TEST_SUPPORT; what tests use isn't part of the library")
        endif()
        list(APPEND test_files "${root}/lib/${name}/${source}")
        if(source MATCHES "\\.(cpp|cc|cxx)$")
            set(test_compiled TRUE)
        endif()
    endforeach()

    add_library(${target} STATIC ${files})
    add_library(${name}::${name} ALIAS ${target})
    set_target_properties(${target} PROPERTIES OUTPUT_NAME ${name})
    if(link)
        target_link_libraries(${target} PUBLIC ${link})
    endif()
    get_property(used GLOBAL PROPERTY _CPP_POLICY_USING_LIBRARY)
    if(used)
        # For the user its headers are a dependency's: the user's warnings as errors and
        # clang-tidy don't apply inside them, whatever folder they were fetched to.
        target_include_directories(${target} SYSTEM PUBLIC "${root}/lib")
    else()
        target_include_directories(${target} PUBLIC "${root}/lib")
    endif()
    if(used)
        # In a user's build (cpp_policy_use_library).
        if(NOT used STREQUAL name)
            message(FATAL_ERROR "cpp-policy: cpp_policy_use_library(${used}) fetched a library "
                "that calls itself '${name}'")
        endif()
        set_target_properties(${target} PROPERTIES CPP_POLICY_LIBRARY_DEPENDENCY TRUE)
        set_property(GLOBAL PROPERTY _CPP_POLICY_USED_DEPENDENCIES "${dependencies}")
    else()
        # In the library's own project: checked like the rest of it.
        get_property(own GLOBAL PROPERTY CPP_POLICY_LIBRARY)
        if(own)
            message(FATAL_ERROR "cpp-policy: a project offers one library ('${own}' is "
                "declared already)")
        endif()
        if(TARGET policy-audit)
            message(FATAL_ERROR
                "cpp-policy: include library.cmake before cpp_policy_add_checks()")
        endif()
        set_property(GLOBAL PROPERTY CPP_POLICY_LIBRARY "${name}")
        set_property(GLOBAL PROPERTY CPP_POLICY_LIBRARY_LAYERS "${layers}")
    endif()
    cpp_policy_apply(${target})

    # <name>::test_support, for the tests of the library's project and of its users.
    if(test_files)
        set(support ${name}_test_support)
        if(test_compiled)
            add_library(${support} STATIC ${test_files})
            target_link_libraries(${support} PUBLIC ${target} ${test_link})
            if(used)
                set_target_properties(${support} PROPERTIES CPP_POLICY_LIBRARY_DEPENDENCY TRUE)
            endif()
            cpp_policy_apply(${support})
            if(NOT used)
                cpp_policy_test_support(${support})
            endif()
        else()
            # Headers only: nothing to compile, so nothing to apply.
            add_library(${support} INTERFACE)
            target_link_libraries(${support} INTERFACE ${target} ${test_link})
        endif()
        add_library(${name}::test_support ALIAS ${support})
    endif()
endfunction()

# ---------------------------------------------------------------------------
# Uses another policy project's library (POLICY.md 11.7): fetches its repository at a pinned
# commit and includes its library.cmake, nothing else of it.
#   cpp_policy_use_library(tonematcher
#       GIT_REPOSITORY https://github.com/luiserh1/ToneMatcher.git
#       GIT_TAG        0123456789abcdef0123456789abcdef01234567)   # v0.4.0
#   target_link_libraries(app_core PRIVATE tonematcher::tonematcher)
# The library is compiled in this build, with this build's compiler, standard, hardening and
# sanitizers, and isn't checked again: no warnings as errors, no clang-tidy, no audit. Its
# own gate did that. Configuration fails if the library's project pins a cpp-policy older
# than CPP_POLICY_LIBRARY_FLOOR, or if this project's vcpkg.json lacks a package the library
# needs. Which modules may include it: cpp_policy_confine_includes(<name>/ TO <module>...).
# ---------------------------------------------------------------------------
function(cpp_policy_use_library name)
    cmake_parse_arguments(PARSE_ARGV 1 arg "" "GIT_REPOSITORY;GIT_TAG" "")
    set(usage "cpp_policy_use_library(<name> GIT_REPOSITORY <url> GIT_TAG <commit>)")
    if(arg_UNPARSED_ARGUMENTS OR NOT arg_GIT_REPOSITORY OR NOT arg_GIT_TAG)
        message(FATAL_ERROR "cpp-policy: usage: ${usage}")
    endif()
    string(LENGTH "${arg_GIT_TAG}" tag_length)
    if(NOT arg_GIT_TAG MATCHES "^[0-9a-f]+$" OR NOT tag_length EQUAL 40)
        message(FATAL_ERROR "cpp-policy: cpp_policy_use_library(${name}): GIT_TAG must be a "
            "commit (40 hexadecimal digits), with the release in a comment beside it: a tag "
            "can be moved to other code later (POLICY.md 10)")
    endif()
    if(TARGET ${name}_library)
        message(FATAL_ERROR "cpp-policy: the library '${name}' is used already")
    endif()
    include(FetchContent)
    # SOURCE_SUBDIR names a folder that isn't there, so that the repository is fetched and
    # its CMakeLists.txt isn't run: that file is the library's own project (vcpkg, tests,
    # checks, programs), and only library.cmake is for others.
    FetchContent_Declare(${name}
        GIT_REPOSITORY "${arg_GIT_REPOSITORY}"
        GIT_TAG "${arg_GIT_TAG}"
        SOURCE_SUBDIR cpp-policy-fetches-only)
    FetchContent_MakeAvailable(${name})
    set(source "${${name}_SOURCE_DIR}")
    if(NOT EXISTS "${source}/library.cmake")
        message(FATAL_ERROR "cpp-policy: ${arg_GIT_REPOSITORY} at ${arg_GIT_TAG} has no "
            "library.cmake: that project doesn't offer a library (POLICY.md 11.7)")
    endif()

    # The cpp-policy release the library's own gate ran: the comment beside its pin.
    set(release "")
    if(EXISTS "${source}/CMakeLists.txt")
        file(STRINGS "${source}/CMakeLists.txt" lines)
        set(after_repository FALSE)
        foreach(line IN LISTS lines)
            if(line MATCHES "GIT_REPOSITORY.*cpp-policy")
                set(after_repository TRUE)
            endif()
            if(after_repository AND line MATCHES "GIT_TAG[ \t]+[0-9a-f]+.*#[ \t]*v([0-9]+\\.[0-9]+\\.[0-9]+)")
                set(release "${CMAKE_MATCH_1}")
                break()
            endif()
        endforeach()
    endif()
    if(release STREQUAL "")
        message(FATAL_ERROR "cpp-policy: library '${name}': its CMakeLists.txt doesn't pin "
            "cpp-policy by commit with the release in a comment (GIT_TAG <commit> # v1.2.3), "
            "so the release that checked it isn't known")
    elseif(release VERSION_LESS CPP_POLICY_LIBRARY_FLOOR)
        message(FATAL_ERROR "cpp-policy: library '${name}' was checked with cpp-policy "
            "v${release}; this release uses libraries checked with "
            "v${CPP_POLICY_LIBRARY_FLOOR} or later. Pin a newer release of the library "
            "(POLICY.md 11.7)")
    endif()

    set_property(GLOBAL APPEND PROPERTY CPP_POLICY_USED_LIBRARIES "${name}")
    set_property(GLOBAL PROPERTY _CPP_POLICY_USING_LIBRARY "${name}")
    set_property(GLOBAL PROPERTY _CPP_POLICY_USED_DEPENDENCIES "")
    include("${source}/library.cmake")
    set_property(GLOBAL PROPERTY _CPP_POLICY_USING_LIBRARY "")
    if(NOT TARGET ${name}_library)
        message(FATAL_ERROR "cpp-policy: ${source}/library.cmake didn't declare the library "
            "'${name}' with cpp_policy_library()")
    endif()

    # vcpkg manifests don't travel through FetchContent: this project lists what the library
    # needs, each with its reason (POLICY.md 1.1).
    get_property(needed GLOBAL PROPERTY _CPP_POLICY_USED_DEPENDENCIES)
    if(needed)
        set(listed "")
        if(EXISTS "${CMAKE_SOURCE_DIR}/vcpkg.json")
            file(READ "${CMAKE_SOURCE_DIR}/vcpkg.json" manifest)
            string(JSON count ERROR_VARIABLE none LENGTH "${manifest}" dependencies)
            if(NOT none AND count GREATER 0)
                math(EXPR last "${count} - 1")
                foreach(index RANGE ${last})
                    string(JSON kind TYPE "${manifest}" dependencies ${index})
                    if(kind STREQUAL "OBJECT")
                        string(JSON package ERROR_VARIABLE none GET "${manifest}" dependencies
                            ${index} name)
                    else()
                        string(JSON package GET "${manifest}" dependencies ${index})
                    endif()
                    list(APPEND listed "${package}")
                endforeach()
            endif()
        endif()
        set(missing "")
        foreach(package IN LISTS needed)
            if(NOT package IN_LIST listed)
                list(APPEND missing "${package}")
            endif()
        endforeach()
        if(missing)
            list(JOIN missing ", " missing)
            message(FATAL_ERROR "cpp-policy: library '${name}' needs these packages, which "
                "this project's vcpkg.json doesn't list: ${missing} (POLICY.md 11.7)")
        endif()
    endif()
    message(STATUS "cpp-policy: using library '${name}' at ${arg_GIT_TAG} "
        "(checked with cpp-policy v${release})")
endfunction()

# ---------------------------------------------------------------------------
# Dependencies kept in their modules (POLICY.md 11.6): the headers named may be included only
# from the modules after TO. A name ending in "/" stands for every header under it, and one
# ending in "*" for every header whose name starts so (a library whose headers are in no
# folder of their own: imgui*).
#   cpp_policy_confine_includes(httplib.h TO server)
#   cpp_policy_confine_includes(nlohmann/ zlib.h TO backend SOURCES_ONLY)
#   cpp_policy_confine_includes(tonematcher/ TO NONE)
# With SOURCES_ONLY, only those modules' source files may include them, not their headers, so
# no other module gets them through a header either. TO NONE: no module may. Lines add up, so
# NONE for a directory and a line for one folder under it leaves that folder to its modules
# and the rest to nobody. Call it before cpp_policy_add_checks().
# ---------------------------------------------------------------------------
function(cpp_policy_confine_includes)
    if(TARGET policy-audit)
        message(FATAL_ERROR
            "cpp-policy: call cpp_policy_confine_includes() before cpp_policy_add_checks()")
    endif()
    set(usage "cpp_policy_confine_includes(<header, directory/ or prefix*>... TO <module>...|NONE [SOURCES_ONLY])")
    set(headers "")
    set(modules "")
    set(sources_only "")
    set(reading headers)
    foreach(argument IN LISTS ARGN)
        if(argument STREQUAL "TO" AND reading STREQUAL "headers")
            set(reading modules)
        elseif(argument STREQUAL "SOURCES_ONLY" AND reading STREQUAL "modules")
            set(sources_only "sources")
        elseif(reading STREQUAL "headers")
            if(NOT argument MATCHES "^[A-Za-z0-9_+.-]+(/[A-Za-z0-9_+.-]+)*[/*]?$")
                message(FATAL_ERROR "cpp-policy: '${argument}' isn't a header name, a "
                                    "directory ending in '/' or a prefix ending in '*': ${usage}")
            endif()
            list(APPEND headers "${argument}")
        elseif(argument STREQUAL "NONE")
            list(APPEND modules NONE)
        elseif(NOT argument MATCHES "^[a-z0-9_]+(/[a-z0-9_]+)?$")
            message(FATAL_ERROR "cpp-policy: '${argument}' isn't a module name (a directory "
                                "under src/, or <library>/<module> for one under lib/): ${usage}")
        else()
            list(APPEND modules "${argument}")
        endif()
    endforeach()
    if(headers STREQUAL "" OR modules STREQUAL "")
        message(FATAL_ERROR "cpp-policy: ${usage}")
    endif()
    if(NONE IN_LIST modules)
        list(LENGTH modules module_count)
        if(module_count GREATER 1 OR NOT sources_only STREQUAL "")
            message(FATAL_ERROR "cpp-policy: NONE stands alone after TO, with no module and "
                                "no SOURCES_ONLY: ${usage}")
        endif()
    endif()
    # The same name kept from everybody on one line and given to a module on another says
    # two things. (A wider NONE line with a narrower line under it is the way to open one
    # folder of a library.)
    get_property(earlier GLOBAL PROPERTY CPP_POLICY_CONFINED_INCLUDES)
    foreach(entry IN LISTS earlier)
        string(REPLACE "|" ";" parts "${entry};")
        list(GET parts 0 entry_headers)
        list(GET parts 1 entry_modules)
        string(REPLACE "," ";" entry_headers "${entry_headers}")
        set(entry_is_none FALSE)
        if(entry_modules STREQUAL "NONE")
            set(entry_is_none TRUE)
        endif()
        set(this_is_none FALSE)
        if(NONE IN_LIST modules)
            set(this_is_none TRUE)
        endif()
        if(entry_is_none STREQUAL this_is_none)
            continue()
        endif()
        foreach(header IN LISTS headers)
            if(header IN_LIST entry_headers)
                message(FATAL_ERROR "cpp-policy: '${header}' is confined TO NONE on one line "
                    "and to modules on another; lines add up, so remove one (POLICY.md 11.6)")
            endif()
        endforeach()
    endforeach()
    list(JOIN headers "," headers)
    list(JOIN modules "," modules)
    set_property(GLOBAL APPEND PROPERTY CPP_POLICY_CONFINED_INCLUDES
        "${headers}|${modules}|${sources_only}")
endfunction()

# ---------------------------------------------------------------------------
# Tests (POLICY.md 13): one doctest program per kind and module.
#   cpp_policy_add_tests(unit message SOURCES test_sanitize.cpp LIBRARIES sls_core)
#   cpp_policy_add_tests(integration server SOURCES test_server.cpp LIBRARIES sls_core
#                        TIMEOUT 30 ENVIRONMENT "HELPER=$<TARGET_FILE:helper>")
# The program is test_<kind>_<module>, with doctest's main() from cpp-policy. After each build,
# every test case becomes a CTest test named <kind>/<module>/<test case> and labelled with
# its kind; a unit program is one CTest test that runs all its cases in one process
# (scripts/doctest_tests.cmake). A unit program has 60 seconds; integration and
# benchmark tests 60, or TIMEOUT; above 60 and up to 600 with SLOW "<reason>", shown at every
# configure. Tests run one at a time unless the project calls cpp_policy_parallel_tests()
# first; ALONE keeps a program's tests apart then. Benchmark programs also get cpp_policy::peak_heap_bytes()
# and peak_memory_bytes(), and nanobench when the project uses it, and are built everywhere (so clang-tidy checks them)
# but run only in builds without sanitizers, which distort memory and time.
# ---------------------------------------------------------------------------
function(_cpp_policy_testing_library)
    if(TARGET cpp_policy_testing)
        return()
    endif()
    add_library(cpp_policy_testing STATIC "${CPP_POLICY_ROOT}/cmake/testing/peak_memory.cpp"
        "${CPP_POLICY_ROOT}/cmake/testing/heap_bytes.cpp")
    target_include_directories(cpp_policy_testing PUBLIC "${CPP_POLICY_ROOT}/cmake/testing/include")
    if(WIN32)
        target_link_libraries(cpp_policy_testing PRIVATE psapi)
    endif()
    cpp_policy_apply(cpp_policy_testing)
endfunction()

# Unit and integration tests several at a time (the presets give CTest 4 jobs). Without this
# call every test runs alone, as before. Benchmarks always run alone, and so do the tests of
# a program declared SLOW or ALONE (a fixed port, a shared folder). Call it before the first
# cpp_policy_add_tests().
function(cpp_policy_parallel_tests)
    get_property(added GLOBAL PROPERTY CPP_POLICY_TESTS_ADDED)
    if(added OR ARGN)
        message(FATAL_ERROR "cpp-policy: call cpp_policy_parallel_tests(), with no arguments, "
            "before the first cpp_policy_add_tests()")
    endif()
    set_property(GLOBAL PROPERTY CPP_POLICY_PARALLEL_TESTS TRUE)
    message(STATUS "cpp-policy: unit and integration tests run several at a time")
endfunction()

# The presets give CTest several jobs. A test added with add_test() runs alone all the same:
# only cpp_policy_add_tests() knows which tests may share the machine. Run when the top
# CMakeLists.txt has been read, over every directory.
function(_cpp_policy_plain_tests_alone directory)
    get_property(tests DIRECTORY "${directory}" PROPERTY TESTS)
    if(tests)
        set_tests_properties(${tests} DIRECTORY "${directory}" PROPERTIES RUN_SERIAL TRUE)
    endif()
    get_property(children DIRECTORY "${directory}" PROPERTY SUBDIRECTORIES)
    foreach(child IN LISTS children)
        _cpp_policy_plain_tests_alone("${child}")
    endforeach()
endfunction()
get_property(_cpp_policy_deferred GLOBAL PROPERTY CPP_POLICY_PLAIN_TESTS_DEFERRED)
if(NOT _cpp_policy_deferred AND NOT CMAKE_SCRIPT_MODE_FILE)
    set_property(GLOBAL PROPERTY CPP_POLICY_PLAIN_TESTS_DEFERRED TRUE)
    cmake_language(DEFER DIRECTORY "${CMAKE_SOURCE_DIR}"
        CALL _cpp_policy_plain_tests_alone "${CMAKE_SOURCE_DIR}")
endif()

function(cpp_policy_add_tests kind module)
    cmake_parse_arguments(PARSE_ARGV 2 arg "ALONE" "TIMEOUT;NO_LEAK_CHECK;SLOW"
        "SOURCES;LIBRARIES;ENVIRONMENT")
    set(usage "cpp_policy_add_tests(<kind> <module> SOURCES <file>... [LIBRARIES <target>...] "
              "[TIMEOUT <seconds>] [SLOW <reason>] [ALONE] [ENVIRONMENT <VAR=value>...] "
              "[NO_LEAK_CHECK <reason>])")
    string(JOIN "" usage ${usage})
    if(arg_UNPARSED_ARGUMENTS OR NOT arg_SOURCES)
        message(FATAL_ERROR "cpp-policy: usage: ${usage}")
    endif()
    # The sanitizers' options are the presets'. A test that set its own could switch a check
    # off where nothing shows it (POLICY.md 5).
    foreach(variable IN LISTS arg_ENVIRONMENT)
        if(variable MATCHES "^(ASAN|LSAN|UBSAN|TSAN|MSAN)_OPTIONS=")
            message(FATAL_ERROR "cpp-policy: ${kind} tests for '${module}' set ${variable}: "
                "sanitizer options aren't a test's to set. Where LeakSanitizer reports what "
                "the operating system keeps (a window on macOS), use NO_LEAK_CHECK \"<reason>\" "
                "(POLICY.md 5)")
        endif()
    endforeach()
    if(DEFINED arg_NO_LEAK_CHECK)
        if(kind STREQUAL "unit")
            message(FATAL_ERROR "cpp-policy: NO_LEAK_CHECK isn't for unit tests: a test that "
                "needs the operating system's windows is an integration test (POLICY.md 5, 13.1)")
        endif()
        string(STRIP "${arg_NO_LEAK_CHECK}" leak_reason)
        string(LENGTH "${leak_reason}" reason_length)
        if(reason_length LESS 20)
            message(FATAL_ERROR "cpp-policy: NO_LEAK_CHECK needs its reason, in a sentence: "
                "what reports the leaks, and that none is the project's (POLICY.md 5)")
        endif()
        # Shown at every configure, so that it is never switched off unseen.
        message(NOTICE "cpp-policy: LeakSanitizer is OFF for the ${kind} tests of '${module}': "
            "${leak_reason}")
        # After the presets' own ASAN_OPTIONS: a test's environment replaces the variable.
        list(APPEND arg_ENVIRONMENT "ASAN_OPTIONS=detect_leaks=0")
        set_property(GLOBAL APPEND PROPERTY CPP_POLICY_NO_LEAK_CHECK "${kind}/${module}")
    endif()
    if(NOT kind IN_LIST CPP_POLICY_TEST_KINDS)
        message(FATAL_ERROR "cpp-policy: test kind '${kind}' isn't one of: ${CPP_POLICY_TEST_KINDS}")
    endif()
    if(NOT module MATCHES "^[a-z0-9_]+$")
        message(FATAL_ERROR "cpp-policy: '${module}' isn't a module name (a directory under src/)")
    endif()
    if(kind STREQUAL "unit")
        if(DEFINED arg_TIMEOUT)
            message(FATAL_ERROR "cpp-policy: a module's unit tests have a fixed limit of 60 "
                "seconds together; a slow test is an integration test (POLICY.md 13)")
        endif()
        set(timeout 60)
    elseif(DEFINED arg_TIMEOUT)
        if(NOT arg_TIMEOUT MATCHES "^[1-9][0-9]*$" OR arg_TIMEOUT GREATER 600)
            message(FATAL_ERROR "cpp-policy: TIMEOUT is 1 to 60 seconds, or up to 600 with "
                "SLOW \"<reason>\" (POLICY.md 13.2)")
        endif()
        if(arg_TIMEOUT GREATER 60 AND NOT DEFINED arg_SLOW)
            message(FATAL_ERROR "cpp-policy: ${kind} tests for '${module}' ask for "
                "${arg_TIMEOUT} seconds: more than 60 needs SLOW \"<reason>\", which says "
                "why a test of this program can't be shorter or split (POLICY.md 13.2)")
        endif()
        set(timeout ${arg_TIMEOUT})
    else()
        set(timeout 60)
    endif()
    if(DEFINED arg_SLOW)
        if(kind STREQUAL "unit")
            message(FATAL_ERROR "cpp-policy: SLOW isn't for unit tests: a slow test is an "
                "integration test (POLICY.md 13)")
        endif()
        if(timeout LESS 61)
            message(FATAL_ERROR "cpp-policy: SLOW goes with a TIMEOUT above 60 seconds; "
                "${kind} tests for '${module}' have ${timeout}")
        endif()
        string(STRIP "${arg_SLOW}" slow_reason)
        string(LENGTH "${slow_reason}" reason_length)
        if(reason_length LESS 20)
            message(FATAL_ERROR "cpp-policy: SLOW needs its reason, in a sentence: why a "
                "test of this program can't be shorter or split (POLICY.md 13.2)")
        endif()
        # Shown at every configure, like every other exception.
        message(NOTICE "cpp-policy: the ${kind} tests of '${module}' may take ${timeout} "
            "seconds each, not 60: ${slow_reason}")
    endif()
    # Which of this program's tests may run beside others (POLICY.md 13.2): none, unless the
    # project has asked for it; and then not benchmarks, whose measures another test would
    # disturb, nor a program that is SLOW or says ALONE.
    get_property(parallel GLOBAL PROPERTY CPP_POLICY_PARALLEL_TESTS)
    set(serial TRUE)
    if(parallel AND NOT kind STREQUAL "benchmark" AND NOT DEFINED arg_SLOW AND NOT arg_ALONE)
        set(serial FALSE)
    endif()
    set_property(GLOBAL PROPERTY CPP_POLICY_TESTS_ADDED TRUE)
    set(target test_${kind}_${module})
    if(TARGET ${target})
        message(FATAL_ERROR "cpp-policy: ${kind} tests for '${module}' are already added; "
            "give one call all their SOURCES")
    endif()

    if(NOT TARGET doctest::doctest)
        find_package(doctest CONFIG GLOBAL)
        if(NOT doctest_FOUND)
            message(FATAL_ERROR "cpp-policy: tests use doctest: add it to vcpkg.json "
                "(POLICY.md 13)")
        endif()
    endif()
    # doctest includes the standard headers (<ostream> among them) only with libc++; with the
    # other libraries it declares what it needs in namespace std itself, which the standard
    # doesn't allow, and printing a std::string_view then fails to compile with Microsoft's
    # library unless the test includes <ostream>. This makes doctest include them everywhere.
    if(NOT TARGET cpp_policy_doctest_main)
        add_library(cpp_policy_doctest_main OBJECT "${CPP_POLICY_ROOT}/cmake/testing/doctest_main.cpp")
        target_link_libraries(cpp_policy_doctest_main PRIVATE doctest::doctest)
        target_compile_definitions(cpp_policy_doctest_main PRIVATE DOCTEST_CONFIG_USE_STD_HEADERS)
        cpp_policy_apply(cpp_policy_doctest_main)
    endif()

    add_executable(${target} ${arg_SOURCES})
    target_link_libraries(${target} PRIVATE ${arg_LIBRARIES} cpp_policy_doctest_main doctest::doctest)
    target_compile_definitions(${target} PRIVATE DOCTEST_CONFIG_USE_STD_HEADERS)
    if(kind STREQUAL "benchmark")
        _cpp_policy_testing_library()
        target_link_libraries(${target} PRIVATE cpp_policy_testing)
        # Speed benchmarks use nanobench when the project lists it in vcpkg.json (POLICY.md 14.2):
        # its implementation is compiled once, like doctest's main().
        if(NOT TARGET nanobench::nanobench)
            find_package(nanobench CONFIG QUIET GLOBAL)
        endif()
        if(TARGET nanobench::nanobench)
            if(NOT TARGET cpp_policy_nanobench)
                add_library(cpp_policy_nanobench OBJECT
                    "${CPP_POLICY_ROOT}/cmake/testing/nanobench_impl.cpp")
                target_link_libraries(cpp_policy_nanobench PRIVATE nanobench::nanobench)
                cpp_policy_apply(cpp_policy_nanobench)
            endif()
            target_link_libraries(${target} PRIVATE cpp_policy_nanobench nanobench::nanobench)
        endif()
    endif()
    cpp_policy_apply(${target})
    # In a test, REQUIRE(value.has_value()) is the check before *value, but clang-tidy can't
    # see that REQUIRE stops the test, so it reports every such dereference. Library hardening
    # stops the program on an empty optional anyway (POLICY.md 13.4). tidy-files gives these
    # sources the same option (cpp_policy_tests.cmake, written with the target checks).
    set_property(GLOBAL APPEND PROPERTY CPP_POLICY_TEST_TARGETS ${target})
    foreach(source IN LISTS arg_SOURCES)
        cmake_path(ABSOLUTE_PATH source BASE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" NORMALIZE)
        set_property(GLOBAL APPEND PROPERTY CPP_POLICY_TEST_SOURCES "${source}")
    endforeach()
    if(CPP_POLICY_CLANG_TIDY)
        get_target_property(tidy ${target} CXX_CLANG_TIDY)
        set_target_properties(${target} PROPERTIES CXX_CLANG_TIDY
            "${tidy};${CPP_POLICY_TEST_TIDY_CHECKS}")
    endif()
    if(kind STREQUAL "benchmark" AND (CPP_POLICY_SANITIZERS OR CPP_POLICY_THREAD_SANITIZER))
        return()
    endif()

    # Registered after cpp_policy_apply(): on Windows, its post-build step copies the ASan
    # runtime that the program needs to list its tests.
    set(ctest_file "${CMAKE_CURRENT_BINARY_DIR}/${target}_tests.cmake")
    add_custom_command(TARGET ${target} POST_BUILD
        BYPRODUCTS "${ctest_file}"
        COMMAND "${CMAKE_COMMAND}" "-DEXECUTABLE=$<TARGET_FILE:${target}>" "-DKIND=${kind}"
                "-DMODULE=${module}" "-DTIMEOUT=${timeout}" "-DSERIAL=${serial}"
                "-DENVIRONMENT=${arg_ENVIRONMENT}"
                "-DWORKING_DIR=${CMAKE_CURRENT_BINARY_DIR}" "-DCTEST_FILE=${ctest_file}"
                -P "${CPP_POLICY_ROOT}/cmake/scripts/doctest_tests.cmake"
        COMMENT "cpp-policy: registering the tests of ${target}"
        VERBATIM)
    set(include_file "${CMAKE_CURRENT_BINARY_DIR}/${target}_include.cmake")
    file(WRITE "${include_file}"
        "if(EXISTS [==[${ctest_file}]==])\n"
        "    include([==[${ctest_file}]==])\n"
        "else()\n"
        "    add_test([==[${kind}/${module}/(not built)]==] [==[${target}-not-built]==])\n"
        "endif()\n")
    set_property(DIRECTORY APPEND PROPERTY TEST_INCLUDE_FILES "${include_file}")
endfunction()

# ---------------------------------------------------------------------------
# Code that only tests use, in a target of its own (helpers shared by several test programs):
#   add_library(test_support STATIC tests/support/scene.cpp)
#   cpp_policy_apply(test_support)
#   cpp_policy_test_support(test_support)
# Its sources are then checked as test code, by the build and by tidy-files alike
# (POLICY.md 13.4). Call it after cpp_policy_apply().
# ---------------------------------------------------------------------------
function(cpp_policy_test_support)
    foreach(target IN LISTS ARGN)
        if(NOT TARGET ${target})
            message(FATAL_ERROR "cpp-policy: cpp_policy_test_support(): no target '${target}'")
        endif()
        get_target_property(applied ${target} CPP_POLICY_APPLIED)
        if(NOT applied)
            message(FATAL_ERROR "cpp-policy: call cpp_policy_apply(${target}) before "
                "cpp_policy_test_support(${target})")
        endif()
        get_property(known GLOBAL PROPERTY CPP_POLICY_TEST_TARGETS)
        if(target IN_LIST known)
            continue()
        endif()
        set_property(GLOBAL APPEND PROPERTY CPP_POLICY_TEST_TARGETS ${target})
        get_target_property(sources ${target} SOURCES)
        get_target_property(source_dir ${target} SOURCE_DIR)
        foreach(source IN LISTS sources)
            cmake_path(ABSOLUTE_PATH source BASE_DIRECTORY "${source_dir}" NORMALIZE)
            set_property(GLOBAL APPEND PROPERTY CPP_POLICY_TEST_SOURCES "${source}")
        endforeach()
        if(CPP_POLICY_CLANG_TIDY)
            get_target_property(tidy ${target} CXX_CLANG_TIDY)
            set_target_properties(${target} PROPERTIES CXX_CLANG_TIDY
                "${tidy};${CPP_POLICY_TEST_TIDY_CHECKS}")
        endif()
    endforeach()
endfunction()

# ---------------------------------------------------------------------------
# Size budgets (POLICY.md 13.5): the most a program may weigh, stripped, on each system.
#   cpp_policy_size_budget(my_tool MACOS 109568 LINUX 93184 WINDOWS 285696)
# In Release builds without sanitizers it adds the test benchmark/size/<program>, which
# strips a copy of the program with llvm-strip and fails if it is larger than this system's
# budget, or if this system has none. Raising a budget needs the owner's approval.
# ---------------------------------------------------------------------------
function(cpp_policy_size_budget target)
    cmake_parse_arguments(PARSE_ARGV 1 arg "" "MACOS;LINUX;WINDOWS" "")
    if(arg_UNPARSED_ARGUMENTS OR NOT TARGET ${target})
        message(FATAL_ERROR "cpp-policy: usage: cpp_policy_size_budget(<program target> "
            "[MACOS <bytes>] [LINUX <bytes>] [WINDOWS <bytes>])")
    endif()
    get_target_property(type ${target} TYPE)
    if(NOT type STREQUAL "EXECUTABLE")
        message(FATAL_ERROR "cpp-policy: cpp_policy_size_budget(): '${target}' isn't a program")
    endif()
    foreach(system IN ITEMS MACOS LINUX WINDOWS)
        if(DEFINED arg_${system} AND NOT arg_${system} MATCHES "^[1-9][0-9]*$")
            message(FATAL_ERROR "cpp-policy: the ${system} budget of '${target}' isn't a number "
                "of bytes: '${arg_${system}}'")
        endif()
    endforeach()
    if(NOT CMAKE_BUILD_TYPE STREQUAL "Release" OR CPP_POLICY_SANITIZERS
       OR CPP_POLICY_THREAD_SANITIZER)
        return()
    endif()
    if(APPLE)
        set(budget "${arg_MACOS}")
        set(system MACOS)
    elseif(WIN32)
        set(budget "${arg_WINDOWS}")
        set(system WINDOWS)
    else()
        set(budget "${arg_LINUX}")
        set(system LINUX)
    endif()
    cmake_path(GET CMAKE_CXX_COMPILER PARENT_PATH llvm_bin)
    find_program(CPP_POLICY_STRIP_EXE NAMES llvm-strip HINTS "${llvm_bin}" NO_DEFAULT_PATH)
    find_program(CPP_POLICY_SIZE_EXE NAMES llvm-size HINTS "${llvm_bin}" NO_DEFAULT_PATH)
    if(NOT CPP_POLICY_STRIP_EXE OR NOT CPP_POLICY_SIZE_EXE)
        message(FATAL_ERROR "cpp-policy: llvm-strip and llvm-size must be next to the compiler "
            "in ${llvm_bin}")
    endif()
    add_test(NAME benchmark/size/${target}
        COMMAND "${CMAKE_COMMAND}" "-DPROGRAM=$<TARGET_FILE:${target}>" "-DSYSTEM=${system}"
                "-DBUDGET=${budget}" "-DSTRIP=${CPP_POLICY_STRIP_EXE}" "-DSIZE=${CPP_POLICY_SIZE_EXE}"
                "-DWORK=${CMAKE_CURRENT_BINARY_DIR}/cpp_policy_size"
                -P "${CPP_POLICY_ROOT}/cmake/scripts/size_budget.cmake")
    set_tests_properties(benchmark/size/${target} PROPERTIES LABELS benchmark TIMEOUT 60)
    # And said after each link: CTest hides a passing test's output, so nobody saw how close
    # a program was to its budget (ToneMatcher's was 160 bytes under, unknown to all).
    add_custom_command(TARGET ${target} POST_BUILD
        COMMAND "${CMAKE_COMMAND}" "-DPROGRAM=$<TARGET_FILE:${target}>" "-DSYSTEM=${system}"
                "-DBUDGET=${budget}" "-DSTRIP=${CPP_POLICY_STRIP_EXE}" "-DSIZE=${CPP_POLICY_SIZE_EXE}"
                "-DWORK=${CMAKE_CURRENT_BINARY_DIR}/cpp_policy_size" -DREPORT_ONLY=ON
                -P "${CPP_POLICY_ROOT}/cmake/scripts/size_budget.cmake"
        VERBATIM)
endfunction()

# ---------------------------------------------------------------------------
# Project-wide checks: suppression audit and format check/fix
# ---------------------------------------------------------------------------
function(cpp_policy_add_checks)
    _cpp_policy_verify_toolchain()
    if(TARGET policy-audit)
        return()
    endif()
    cmake_language(DEFER DIRECTORY "${CMAKE_SOURCE_DIR}" CALL _cpp_policy_verify_targets)
    _cpp_policy_check_git_hooks()
    _cpp_policy_check_dependencies()

    # The test presets point LeakSanitizer at this copy: build/<preset>/ is the same path in
    # every project, while the policy's own folder is not.
    configure_file("${CPP_POLICY_ROOT}/cmake/sanitizers/lsan.supp"
        "${CMAKE_BINARY_DIR}/cpp_policy_lsan.supp" COPYONLY)

    _cpp_policy_commit(policy_commit)
    get_property(layers GLOBAL PROPERTY CPP_POLICY_LAYERS)
    get_property(confined_includes GLOBAL PROPERTY CPP_POLICY_CONFINED_INCLUDES)
    get_property(library GLOBAL PROPERTY CPP_POLICY_LIBRARY)
    get_property(library_layers GLOBAL PROPERTY CPP_POLICY_LIBRARY_LAYERS)
    get_property(used_libraries GLOBAL PROPERTY CPP_POLICY_USED_LIBRARIES)
    # A library's lowlevel module is a confined area like src/lowlevel (POLICY.md 4).
    set(confined_dirs "${CPP_POLICY_CONFINED_DIRS}")
    if(library)
        list(APPEND confined_dirs "lib/${library}/lowlevel")
    endif()
    set(config "${CMAKE_BINARY_DIR}/cpp_policy_config.cmake")
    file(WRITE "${config}"
        "set(SOURCE_DIR [==[${CMAKE_SOURCE_DIR}]==])\n"
        "set(POLICY_ROOT [==[${CPP_POLICY_ROOT}]==])\n"
        "set(POLICY_COMMIT [==[${policy_commit}]==])\n"
        "set(CONFINED_DIRS [==[${confined_dirs}]==])\n"
        "set(EXCLUDED_DIRS [==[${CPP_POLICY_EXCLUDED_DIRS}]==])\n"
        "set(LAYERS [==[${layers}]==])\n"
        "set(CONFINED_INCLUDES [==[${confined_includes}]==])\n"
        "set(LIBRARY [==[${library}]==])\n"
        "set(LIBRARY_LAYERS [==[${library_layers}]==])\n"
        "set(USED_LIBRARIES [==[${used_libraries}]==])\n"
        "set(CLANG_FORMAT [==[${CPP_POLICY_CLANG_FORMAT_EXE}]==])\n"
        "set(CLANG_TIDY [==[${CPP_POLICY_CLANG_TIDY_EXE}]==])\n"
        "set(BUILD_DIR [==[${CMAKE_BINARY_DIR}]==])\n")

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

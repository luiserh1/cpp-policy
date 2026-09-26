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
option(CPP_POLICY_THREAD_SANITIZER "Enable ThreadSanitizer (not with CPP_POLICY_SANITIZERS)" OFF)
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
            COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${dll}" "$<TARGET_FILE_DIR:${target}>"
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
    if(CPP_POLICY_CLANG_TIDY)
        set_target_properties(${target} PROPERTIES CXX_CLANG_TIDY
            "${CPP_POLICY_CLANG_TIDY_EXE};--config-file=${CPP_POLICY_ROOT}/.clang-tidy")
    endif()
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

# Appends a problem to the list named by `out_list` for each option that turns warnings or
# clang-cl's hardening off. clang-cl accepts either prefix, so both are checked.
# (The parameter must not be called `problems`: it would shadow the caller's list.)
function(_cpp_policy_check_options what options out_list)
    set(found ${${out_list}})
    foreach(option IN LISTS options)
        if(option MATCHES "-Wno-|/wd[0-9]" OR option MATCHES "^[-/]w$" OR option STREQUAL "/W0")
            list(APPEND found "${what} turns warnings off: ${option}")
        elseif(option MATCHES "^[-/](GS|guard:cf|sdl)-$")
            list(APPEND found "${what} turns hardening off: ${option}")
        endif()
    endforeach()
    set(${out_list} ${found} PARENT_SCOPE)
endfunction()

# Runs once, after the whole project is configured (deferred by cpp_policy_add_checks).
function(_cpp_policy_verify_targets)
    set(problems "")
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
        if(CPP_POLICY_CLANG_TIDY)
            get_target_property(tidy ${target} CXX_CLANG_TIDY)
            if(NOT tidy STREQUAL "${CPP_POLICY_CLANG_TIDY_EXE};--config-file=${CPP_POLICY_ROOT}/.clang-tidy")
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
        endforeach()
    endforeach()

    if(problems)
        list(JOIN problems "\n  " problem_list)
        message(FATAL_ERROR "cpp-policy: the policy is bypassed in CMake:\n  ${problem_list}\n"
            "Every target must call cpp_policy_apply() and keep its settings (POLICY.md 6).")
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

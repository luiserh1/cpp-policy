# --- Good code: must build with every check enabled and pass its tests -------
add_library(policy_good good/numbers.cpp good/shapes.cpp good/tally.cpp good/idioms.cpp
    good/allocation.cpp
    good/lowlevel/byte_view.cpp good/lowlevel/c_library.cpp)
target_include_directories(policy_good PUBLIC good)
# A C library, included the way vcpkg's are: a system directory, excluded from clang-tidy's
# header filter by its /third_party/ path.
target_include_directories(policy_good SYSTEM PRIVATE good/third_party)
cpp_policy_apply(policy_good)

add_executable(policy_good_test good/main.cpp)
target_link_libraries(policy_good_test PRIVATE policy_good)
cpp_policy_apply(policy_good_test)
add_test(NAME good/run COMMAND policy_good_test)

# --- clang-cl: slash-form options must reach the compiler and clang-tidy. If they don't,
# this target fails to build (see the comment in the source).
if(CMAKE_CXX_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC")
    add_executable(policy_clang_cl_slash_options clang_cl/slash_options.cpp)
    target_compile_options(policy_clang_cl_slash_options PRIVATE /DCPP_POLICY_SLASH_OPTION)
    cpp_policy_apply(policy_clang_cl_slash_options)
    add_test(NAME clang_cl/slash_options COMMAND policy_clang_cl_slash_options)

    # Hardening (POLICY.md 7.4) is applied to every configuration but Debug: the program's
    # PE header must show Control Flow Guard and lld-link's ASLR and no-execute defaults.
    if(NOT CMAKE_BUILD_TYPE STREQUAL "Debug")
        cmake_path(GET CMAKE_CXX_COMPILER PARENT_PATH llvm_bin)
        find_program(CPP_POLICY_READOBJ_EXE NAMES llvm-readobj HINTS "${llvm_bin}" NO_DEFAULT_PATH)
        if(NOT CPP_POLICY_READOBJ_EXE)
            message(FATAL_ERROR "cpp-policy tests: llvm-readobj not found next to the compiler in ${llvm_bin}")
        endif()
        add_test(NAME hardening/pe_flags
            COMMAND "${CMAKE_COMMAND}" "-DREADOBJ=${CPP_POLICY_READOBJ_EXE}"
                    "-DBINARY=$<TARGET_FILE:policy_good_test>"
                    -P "${CMAKE_CURRENT_SOURCE_DIR}/hardening/pe_flags.cmake")
    endif()
endif()

# --- LeakSanitizer: a deliberate leak must be reported (ASan builds on macOS and Linux).
# The dev and check test presets turn leak detection on (it is off by default on macOS);
# the test only appends abort_on_error=0, so it fails if the preset stops doing that.
if(CPP_POLICY_SANITIZERS AND NOT CMAKE_CXX_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC")
    add_executable(policy_leak leak/leak.cpp)
    cpp_policy_apply(policy_leak)
    add_test(NAME leak/detected COMMAND policy_leak)
    set_tests_properties(leak/detected PROPERTIES
        PASS_REGULAR_EXPRESSION "LeakSanitizer: detected memory leaks"
        ENVIRONMENT_MODIFICATION "ASAN_OPTIONS=string_append::abort_on_error=0")
    # A false positive inside macOS: must pass only because the presets apply the policy's
    # suppression list (cmake/sanitizers/lsan.supp).
    if(APPLE)
        add_executable(policy_leak_os_false_positive leak/os_false_positive.cpp)
        cpp_policy_apply(policy_leak_os_false_positive)
        add_test(NAME leak/os_false_positive COMMAND policy_leak_os_false_positive)
        # libdispatch's reuse cache: must pass only because the presets turn off the nano
        # malloc zone, on the Macs where the zone hides it (macOS 27 on Apple silicon; GitHub's
        # macos-15 runners don't report it either way, so there is no test that the zone on
        # reproduces it).
        add_executable(policy_leak_nano_zone leak/nano_zone.cpp)
        cpp_policy_apply(policy_leak_nano_zone)
        add_test(NAME leak/nano_zone_off COMMAND policy_leak_nano_zone)
    endif()
endif()

# --- ThreadSanitizer: a deliberate race must be reported (only in a TSan build)
if(CPP_POLICY_THREAD_SANITIZER)
    add_executable(policy_tsan_race tsan/race.cpp)
    cpp_policy_apply(policy_tsan_race)
    add_test(NAME tsan/race COMMAND policy_tsan_race)
    # On macOS sanitizers abort after a report by default, and CTest counts an abort as a
    # failure whatever the output says; exit normally so the report can be matched.
    set_tests_properties(tsan/race PROPERTIES
        PASS_REGULAR_EXPRESSION "ThreadSanitizer: data race"
        ENVIRONMENT "TSAN_OPTIONS=abort_on_error=0")
endif()

# --- Bad samples: each must be rejected with the check named in its EXPECT line
file(GLOB bad_samples CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/bad/*.cpp")
add_library(policy_bad_samples OBJECT EXCLUDE_FROM_ALL ${bad_samples})
# Never built (EXCLUDE_FROM_ALL): the target only puts the samples in compile_commands.json,
# so the tests below can run clang-tidy on them with the policy's flags.
cpp_policy_apply(policy_bad_samples)
target_include_directories(policy_bad_samples SYSTEM PRIVATE good/third_party)

foreach(sample IN LISTS bad_samples)
    cmake_path(GET sample STEM name)
    file(STRINGS "${sample}" expect REGEX "^// EXPECT: ")
    if(NOT expect)
        message(FATAL_ERROR "${sample}: missing '// EXPECT: <check-name>' line")
    endif()
    string(REPLACE "// EXPECT: " "" check "${expect}")
    add_test(NAME bad/${name}
        COMMAND "${CPP_POLICY_CLANG_TIDY_EXE}" "--config-file=${CPP_POLICY_ROOT}/.clang-tidy"
                -p "${CMAKE_BINARY_DIR}" "${sample}")
    # The output must report the expected check as an error. A pass regex overrides
    # the exit code; an "error:" line from clang-tidy implies the run failed.
    set_tests_properties(bad/${name} PROPERTIES
        PASS_REGULAR_EXPRESSION "error: [^\n]*[[,]${check}[],]")
endforeach()

# --- Format fixtures: files that must already be formatted (clang-format must not change them)
file(GLOB format_fixtures CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/format/*.cpp")
foreach(fixture IN LISTS format_fixtures)
    cmake_path(GET fixture STEM name)
    add_test(NAME format/${name}
        COMMAND "${CPP_POLICY_CLANG_FORMAT_EXE}" --dry-run --Werror
                "--style=file:${CPP_POLICY_ROOT}/.clang-format" "${fixture}")
endforeach()

# --- policy-format-fix: one run must leave formatting and trailing commas both right
add_test(NAME format/fix_trailing_commas
    COMMAND "${CMAKE_COMMAND}" "-DPOLICY_ROOT=${CPP_POLICY_ROOT}"
            "-DWORK=${CMAKE_CURRENT_BINARY_DIR}/format_fix"
            "-DCLANG_FORMAT=${CPP_POLICY_CLANG_FORMAT_EXE}" "-DCLANG_TIDY=${CPP_POLICY_CLANG_TIDY_EXE}"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/format_fix/run.cmake")

# --- Check build presets: a failing file mustn't stop the build (one run reports everything)
add_test(NAME presets/keep_going
    COMMAND "${CMAKE_COMMAND}" "-DPOLICY_ROOT=${CPP_POLICY_ROOT}"
            "-DWORK=${CMAKE_CURRENT_BINARY_DIR}/keep_going" "-DCXX=${CMAKE_CXX_COMPILER}"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/keep_going/run.cmake")

# --- A changed .clang-tidy must re-check files that are already built
add_test(NAME tidy/rebuild_on_config_change
    COMMAND "${CMAKE_COMMAND}" "-DPOLICY_ROOT=${CPP_POLICY_ROOT}"
            "-DWORK=${CMAKE_CURRENT_BINARY_DIR}/tidy_rebuild" "-DCXX=${CMAKE_CXX_COMPILER}"
            "-DMAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/tidy_rebuild/run.cmake")

# --- Audit fixtures: each directory is a mini project.
#   expect.txt    regex the audit output must match (include "file:line:" to pin the line)
#   options.cmake optional; appended to the generated config to override its defaults
#                 (e.g. set(CHECK_PROJECT_FILES ON) or a different EXCLUDED_DIRS)
file(GLOB audit_cases CONFIGURE_DEPENDS LIST_DIRECTORIES true "${CMAKE_CURRENT_SOURCE_DIR}/audit/*")
foreach(case IN LISTS audit_cases)
    if(NOT IS_DIRECTORY "${case}")
        continue()
    endif()
    cmake_path(GET case FILENAME name)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${case}/expect.txt")
    file(READ "${case}/expect.txt" expect)
    string(STRIP "${expect}" expect)
    # A pass regex is a list: ";" would split it into alternatives that pass on their own.
    # "." still matches the semicolon.
    string(REPLACE ";" "." expect "${expect}")
    set(config "${CMAKE_CURRENT_BINARY_DIR}/audit_${name}.cmake")
    file(WRITE "${config}"
        "set(SOURCE_DIR [==[${case}]==])\n"
        "set(POLICY_ROOT [==[${CPP_POLICY_ROOT}]==])\n"
        "set(CONFINED_DIRS [==[src/lowlevel]==])\n"
        "set(EXCLUDED_DIRS [==[]==])\n")
    if(EXISTS "${case}/options.cmake")
        set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${case}/options.cmake")
        file(APPEND "${config}" "include([==[${case}/options.cmake]==])\n")
    endif()
    add_test(NAME audit/${name}
        COMMAND "${CMAKE_COMMAND}" -DCONFIG=${config} -P "${CPP_POLICY_ROOT}/cmake/scripts/audit_suppressions.cmake")
    set_tests_properties(audit/${name} PROPERTIES PASS_REGULAR_EXPRESSION "${expect}")
endforeach()

# --- CMake bypass fixtures: each directory is a mini project that configures with the
# policy (clang-tidy on); expect.txt holds a regex its configure output must match.
file(GLOB bypass_cases CONFIGURE_DEPENDS LIST_DIRECTORIES true "${CMAKE_CURRENT_SOURCE_DIR}/bypass/*")
foreach(case IN LISTS bypass_cases)
    if(NOT IS_DIRECTORY "${case}")
        continue()
    endif()
    cmake_path(GET case FILENAME name)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${case}/expect.txt")
    file(READ "${case}/expect.txt" expect)
    string(STRIP "${expect}" expect)
    # A pass regex is a list: ";" would split it into alternatives that pass on their own.
    # "." still matches the semicolon.
    string(REPLACE ";" "." expect "${expect}")
    add_test(NAME bypass/${name}
        COMMAND "${CMAKE_COMMAND}" --fresh -S "${case}" -B "${CMAKE_CURRENT_BINARY_DIR}/bypass_${name}"
                -G Ninja "-DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
                "-DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}" -DCPP_POLICY_CLANG_TIDY=ON
                "-DPOLICY_ROOT=${CPP_POLICY_ROOT}")
    set_tests_properties(bypass/${name} PROPERTIES PASS_REGULAR_EXPRESSION "${expect}")
endforeach()

# --- Git hooks: run in a throwaway repository with a stub gate (they are POSIX shell scripts;
# Git for Windows runs them with its own sh, which this test doesn't cover).
if(NOT WIN32)
    add_test(NAME hooks/behavior
        COMMAND "${CMAKE_COMMAND}" "-DPOLICY_ROOT=${CPP_POLICY_ROOT}"
                "-DWORK=${CMAKE_CURRENT_BINARY_DIR}/hooks" "-DCXX=${CMAKE_CXX_COMPILER}"
                "-DMAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}" -P "${CMAKE_CURRENT_SOURCE_DIR}/hooks/run.cmake")
    # Always run as if from a hook in a linked worktree: GIT_DIR points elsewhere (a decoy in
    # the build folder), and the test must still act only on its throwaway repository.
    set_tests_properties(hooks/behavior PROPERTIES
        ENVIRONMENT "GIT_DIR=${CMAKE_CURRENT_BINARY_DIR}/hooks_decoy.git")

    # tools/upgrade.sh against a fake cpp-policy with two releases (same GIT_DIR decoy).
    add_test(NAME upgrade/behavior
        COMMAND "${CMAKE_COMMAND}" "-DPOLICY_ROOT=${CPP_POLICY_ROOT}"
                "-DWORK=${CMAKE_CURRENT_BINARY_DIR}/upgrade" -P "${CMAKE_CURRENT_SOURCE_DIR}/upgrade/run.cmake")
    set_tests_properties(upgrade/behavior PROPERTIES
        ENVIRONMENT "GIT_DIR=${CMAKE_CURRENT_BINARY_DIR}/upgrade_decoy.git")
endif()

# --- Dependency fixtures: each directory has a vcpkg.json, optionally a fake vcpkg install
# tree (installed/<triplet>/share/<port>/vcpkg.spdx.json), and expect.txt, a regex the
# dependency check's output must match.
file(GLOB deps_cases CONFIGURE_DEPENDS LIST_DIRECTORIES true "${CMAKE_CURRENT_SOURCE_DIR}/deps/*")
foreach(case IN LISTS deps_cases)
    if(NOT IS_DIRECTORY "${case}")
        continue()
    endif()
    cmake_path(GET case FILENAME name)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${case}/expect.txt")
    file(READ "${case}/expect.txt" expect)
    string(STRIP "${expect}" expect)
    # A pass regex is a list: ";" would split it into alternatives that pass on their own.
    # "." still matches the semicolon.
    string(REPLACE ";" "." expect "${expect}")
    file(GLOB installed LIST_DIRECTORIES true "${case}/installed/*")
    add_test(NAME deps/${name}
        COMMAND "${CMAKE_COMMAND}" "-DMANIFEST=${case}/vcpkg.json" "-DINSTALLED_DIRS=${installed}"
                -P "${CPP_POLICY_ROOT}/cmake/scripts/dependencies.cmake")
    set_tests_properties(deps/${name} PROPERTIES PASS_REGULAR_EXPRESSION "${expect}")
endforeach()

# --- Waiting-on-the-toolchain probes (POLICY.md 12): each must still fail to compile. They
# are about libc++, the macOS standard library, so they only run there.
if(APPLE)
    file(GLOB probes CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/probes/w*.cpp")
    foreach(probe IN LISTS probes)
        cmake_path(GET probe STEM name)
        string(REGEX MATCH "^w[0-9]+" item "${name}")
        string(TOUPPER "${item}" item)
        add_test(NAME waiting/${name}
            COMMAND "${CMAKE_COMMAND}" "-DCXX=${CMAKE_CXX_COMPILER}" "-DSOURCE=${probe}"
                    "-DITEM=${item}" -P "${CMAKE_CURRENT_SOURCE_DIR}/probes/probe.cmake")
    endforeach()
endif()

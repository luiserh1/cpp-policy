# Suppression audit (POLICY.md section 5).
#
#   cmake -DCONFIG=<cpp_policy_config.cmake> [-DCHECK_PROJECT_FILES=ON] -P audit_suppressions.cmake
#
# Fails if any NOLINT:
#   - is outside a confined directory,
#   - does not name specific checks (bare or wildcard),
#   - has no reason: `NOLINT(check-name): reason`.
# Fails if any diagnostic pragma (#pragma, _Pragma or __pragma form):
#   - is outside a confined directory,
#   - has no reason in a trailing comment: `#pragma ... ignored "-Wx" // reason`.
# Fails if any `clang-format off` has no reason: `// clang-format off: reason`.
# Fails if a header (.h .hpp .hh .hxx) lacks `#pragma once` or uses an include guard.
# Fails if a file has more than 350 lines, or 500 under tests/ (POLICY.md 11.3).
# Fails if a test case under tests/ has a character in its name that doctest's filter or the
# XML listing treats specially (POLICY.md 13.2).
# Fails if a file of the library a project offers (LIBRARY, in lib/<name>/<module>/) includes
# anything of the program, a higher layer of the library, or its own headers by another name
# than "<name>/<module>/<header>" (POLICY.md 11.7).
# With FILES, checks only those files, and only the rules about one file.
# Fails if an #include in src/ points to a higher layer (LAYERS, from cpp_policy_layers()),
# uses a relative path, or leaves a confined module; if src/ has two or more modules and
# no layers; or if a module is in no layer (POLICY.md 11.1).
# Fails if a file in src/ includes a header that CONFINED_INCLUDES (from
# cpp_policy_confine_includes()) keeps in other modules, or in source files only; or if that
# names a module src/ doesn't have (POLICY.md 11.6).
# Fails if dynamic_cast or typeid lacks `// rtti: reason`, or catch (...) lacks
# `// boundary: which`, on the same line (POLICY.md 3).
# With CHECK_PROJECT_FILES, also fails if the project's .clang-tidy, .clang-format,
# CMakePresets.json, git hooks (tools/hooks/) or, with a vcpkg.json, vcpkg files (tools/vcpkg/)
# differ from the policy's, or its .gitignore / .gitattributes lack any line of the policy's
# copies.
# With POLICY_COMMIT set (the commit of cpp-policy the build uses), also fails if a GitHub
# Actions workflow calls cpp-policy's gate at any other commit.

cmake_minimum_required(VERSION 3.29)
include("${CMAKE_CURRENT_LIST_DIR}/source_files.cmake")
include("${CONFIG}")

set(errors 0)
macro(report file line message)
    message("${file}:${line}: error: ${message}")
    math(EXPR errors "${errors} + 1")
endmacro()

cpp_policy_collect_sources("${SOURCE_DIR}" "${EXCLUDED_DIRS}" files)
# A source file may have 350 lines; a test source, under tests/, 500: it is mostly tables of
# cases and expected text, and its length doesn't mean mixed responsibilities (POLICY.md 11.3).
set(max_file_lines 350)
set(max_test_file_lines 500)

# With FILES (a list of paths), only the rules about one file are checked, and only for
# those of the project's sources: tidy-files uses it for the files just edited. The rules
# about the project as a whole (layers declared, policy files, CI pins) are the build's.
set(per_file FALSE)
set(checked_files "${files}")
if(DEFINED FILES)
    set(per_file TRUE)
    set(checked_files "")
    foreach(file IN LISTS FILES)
        file(REAL_PATH "${file}" path BASE_DIRECTORY "${SOURCE_DIR}")
        file(RELATIVE_PATH relative "${SOURCE_DIR}" "${path}")
        if(relative IN_LIST files)
            list(APPEND checked_files "${relative}")
        endif()
    endforeach()
endif()

# Layers (POLICY.md 11.1). LAYERS lists the layers from the lowest up; each is a
# comma-separated list of modules (directories under src/). layer_of_<module> is its number.
if(NOT DEFINED LAYERS)
    set(LAYERS "")
endif()
set(modules "")
foreach(file IN LISTS files)
    if(file MATCHES "^src/([^/]+)/")
        list(APPEND modules "${CMAKE_MATCH_1}")
    endif()
endforeach()
list(REMOVE_DUPLICATES modules)
set(layer_number 0)
foreach(layer IN LISTS LAYERS)
    math(EXPR layer_number "${layer_number} + 1")
    string(REPLACE "," ";" layer_modules "${layer}")
    foreach(module IN LISTS layer_modules)
        set(layer_of_${module} ${layer_number})
    endforeach()
endforeach()
list(LENGTH modules module_count)

# The library a project offers (POLICY.md 11.7): LIBRARY is its name, LIBRARY_LAYERS its
# layers, like LAYERS. Its modules are the folders under lib/<name>/, and for the rules
# about dependencies' headers they are called <name>/<module>.
if(NOT DEFINED LIBRARY)
    set(LIBRARY "")
endif()
if(NOT DEFINED LIBRARY_LAYERS)
    set(LIBRARY_LAYERS "")
endif()
# The libraries this project uses (cpp_policy_use_library): their internal headers aren't
# for it.
if(NOT DEFINED USED_LIBRARIES)
    set(USED_LIBRARIES "")
endif()
set(library_modules "")
set(all_modules "${modules}")
if(NOT LIBRARY STREQUAL "")
    foreach(file IN LISTS files)
        if(file MATCHES "^lib/${LIBRARY}/([^/]+)/")
            list(APPEND library_modules "${CMAKE_MATCH_1}")
            list(APPEND all_modules "${LIBRARY}/${CMAKE_MATCH_1}")
        elseif(file MATCHES "^lib/" AND NOT per_file)
            report("${file}" 1
                "lib/ holds the library's modules only, as lib/${LIBRARY}/<module>/<file> (POLICY.md 11.7)")
        endif()
    endforeach()
    list(REMOVE_DUPLICATES library_modules)
    list(REMOVE_DUPLICATES all_modules)
    set(layer_number 0)
    foreach(layer IN LISTS LIBRARY_LAYERS)
        math(EXPR layer_number "${layer_number} + 1")
        string(REPLACE "," ";" layer_modules "${layer}")
        foreach(module IN LISTS layer_modules)
            set(library_layer_of_${module} ${layer_number})
        endforeach()
    endforeach()
    if(NOT per_file)
        foreach(module IN LISTS library_modules)
            if(NOT DEFINED library_layer_of_${module})
                report("lib/${LIBRARY}/${module}" 1
                    "module '${module}' is in none of the library's layers; add it to cpp_policy_library() (POLICY.md 11.7)")
            endif()
        endforeach()
        if(LIBRARY IN_LIST modules)
            report("src/${LIBRARY}" 1
                "a module of the program has the library's name, so \"${LIBRARY}/...\" would mean two things (POLICY.md 11.7)")
        endif()
    endif()
endif()

# Dependencies kept in their modules (POLICY.md 11.6). Each entry of CONFINED_INCLUDES is
# "<headers>|<modules>|<sources or empty>", the first two comma-separated.
if(NOT DEFINED CONFINED_INCLUDES)
    set(CONFINED_INCLUDES "")
endif()
foreach(entry IN LISTS CONFINED_INCLUDES)
    string(REPLACE "|" ";" parts "${entry};")
    list(GET parts 1 entry_modules)
    string(REPLACE "," ";" entry_modules "${entry_modules}")
    foreach(module IN LISTS entry_modules)
        if(NOT module STREQUAL "NONE" AND NOT module IN_LIST all_modules AND NOT per_file)
            report("src/${module}" 1
                "cpp_policy_confine_includes() names module '${module}', which the project doesn't have (POLICY.md 11.6)")
        endif()
    endforeach()
endforeach()
if(LAYERS STREQUAL "" AND module_count GREATER 1 AND NOT per_file)
    string(REPLACE ";" ", " module_names "${modules}")
    report("CMakeLists.txt" 1
        "src/ has ${module_count} modules (${module_names}) but no layers; declare them from the lowest up with cpp_policy_layers() (POLICY.md 11.1)")
endif()
if(NOT LAYERS STREQUAL "" AND NOT per_file)
    foreach(module IN LISTS modules)
        if(NOT DEFINED layer_of_${module})
            report("src/${module}" 1 "module '${module}' is in no layer; add it to cpp_policy_layers() (POLICY.md 11.1)")
        endif()
    endforeach()
endif()

foreach(file IN LISTS checked_files)
    cpp_policy_in_dirs("${file}" "${CONFINED_DIRS}" confined)
    set(file_lines_limit ${max_file_lines})
    if(file MATCHES "^tests/")
        set(file_lines_limit ${max_test_file_lines})
    endif()
    cpp_policy_read_lines("${SOURCE_DIR}/${file}" lines)
    set(number 0)
    set(has_pragma_once FALSE)
    set(directives "")
    foreach(line IN LISTS lines)
        math(EXPR number "${number} + 1")

        # Remember the first two preprocessor directives to recognize an include guard.
        if(line MATCHES "^[ \t]*#[ \t]*pragma[ \t]+once")
            set(has_pragma_once TRUE)
        endif()
        list(LENGTH directives directive_count)
        if(directive_count LESS 2 AND line MATCHES "^[ \t]*#[ \t]*([a-z]+)[ \t]*([A-Za-z0-9_]*)")
            list(APPEND directives "${CMAKE_MATCH_1} ${CMAKE_MATCH_2}")
        endif()

        if(line MATCHES "NOLINT(NEXTLINE|BEGIN|END)?(\\(([^)]*)\\))?(.*)$")
            set(kind "${CMAKE_MATCH_1}")
            set(checks "${CMAKE_MATCH_3}")
            set(rest "${CMAKE_MATCH_4}")
            string(STRIP "${checks}" checks)
            if(NOT confined)
                report("${file}" ${number} "suppression outside a confined area (${CONFINED_DIRS})")
            endif()
            if(checks STREQUAL "")
                report("${file}" ${number} "suppression must name the specific check: NOLINT${kind}(check-name)")
            elseif(checks MATCHES "\\*")
                report("${file}" ${number} "wildcard suppressions are not allowed: '${checks}'")
            endif()
            if(NOT kind STREQUAL "END" AND NOT rest MATCHES "^:[ \t]*[^ \t]")
                report("${file}" ${number} "suppression must give a reason: NOLINT${kind}(check-name): reason")
            endif()
        endif()

        # A pragma can also be written as an operator (_Pragma, __pragma), for example in a macro.
        if(line MATCHES "#[ \t]*pragma[ \t]+(clang|GCC)[ \t]+diagnostic[ \t]+ignored"
           OR line MATCHES "#[ \t]*pragma[ \t]+warning[ \t]*\\([ \t]*disable"
           OR line MATCHES "_Pragma[ \t]*\\([ \t]*\"[ \t]*(clang|GCC)[ \t]+diagnostic[ \t]+ignored"
           OR line MATCHES "__pragma[ \t]*\\([ \t]*warning[ \t]*\\([ \t]*disable")
            if(NOT confined)
                report("${file}" ${number} "diagnostic pragma outside a confined area (${CONFINED_DIRS})")
            endif()
            if(NOT line MATCHES "//[ \t]*[^ \t]")
                report("${file}" ${number} "diagnostic pragma must give a reason in a trailing comment: // reason")
            endif()
        endif()

        # Formatting may be switched off anywhere, but only with a reason.
        if(line MATCHES "clang-format[ \t]+off(.*)$")
            if(NOT CMAKE_MATCH_1 MATCHES "^:[ \t]*[^ \t*]")
                report("${file}" ${number} "clang-format off must give a reason: // clang-format off: reason")
            endif()
        endif()

        # Includes in src/ are written from the src/ root and never point to a higher layer;
        # a confined module includes only itself (POLICY.md 11.1).
        if(file MATCHES "^src/" AND line MATCHES "^[ \t]*#[ \t]*include[ \t]*\"([^\"]+)\"")
            set(included "${CMAKE_MATCH_1}")
            set(own "")
            if(file MATCHES "^src/([^/]+)/")
                set(own "${CMAKE_MATCH_1}")
            endif()
            set(target "")
            if(included MATCHES "^([^/]+)/")
                set(target "${CMAKE_MATCH_1}")
            endif()
            if(included MATCHES "^\\.\\.?/" OR included MATCHES "/\\.\\./")
                report("${file}" ${number}
                    "includes \"${included}\" by a relative path; write it from the src/ root: \"module/header\"")
            elseif(NOT included MATCHES "/" AND NOT own STREQUAL "")
                report("${file}" ${number}
                    "includes \"${included}\" without its module; write it from the src/ root: \"${own}/${included}\"")
            elseif(NOT own STREQUAL "" AND target IN_LIST modules AND NOT target STREQUAL own)
                cpp_policy_in_dirs("${file}" "${CONFINED_DIRS}" own_confined)
                if(own_confined)
                    report("${file}" ${number}
                        "src/${own} is confined: it may include only its own headers, not \"${included}\"")
                elseif(DEFINED layer_of_${own} AND DEFINED layer_of_${target}
                       AND layer_of_${target} GREATER layer_of_${own})
                    report("${file}" ${number}
                        "includes \"${included}\" from a higher layer: '${own}' is layer ${layer_of_${own}}, '${target}' is layer ${layer_of_${target}} (POLICY.md 11.1)")
                endif()
            endif()
        endif()

        # A dependency's headers stay in the modules it is confined to (POLICY.md 11.6).
        if(NOT CONFINED_INCLUDES STREQUAL "" AND file MATCHES "^(src|lib)/"
           AND line MATCHES "^[ \t]*#[ \t]*include[ \t]*[<\"]([^>\"]+)[>\"]")
            set(included "${CMAKE_MATCH_1}")
            set(own "")
            if(file MATCHES "^src/([^/]+)/")
                set(own "${CMAKE_MATCH_1}")
            elseif(file MATCHES "^lib/([^/]+/[^/]+)/")
                set(own "${CMAKE_MATCH_1}")
            endif()
            # (Its variables must not be the file's: "confined", set once per file above,
            # says whether the file is in a confined area.)
            # Several lines may name one header: each allows some modules, in any file or in
            # source files only. The include is allowed if one line allows it here.
            set(header_is_confined FALSE)
            set(allowed FALSE)
            set(allowed_modules "")
            set(sources_only_here "")
            foreach(entry IN LISTS CONFINED_INCLUDES)
                string(REPLACE "|" ";" parts "${entry};")
                list(GET parts 0 entry_headers)
                list(GET parts 1 entry_modules)
                list(GET parts 2 entry_sources)
                string(REPLACE "," ";" entry_headers "${entry_headers}")
                string(REPLACE "," ";" entry_module_list "${entry_modules}")
                set(matches FALSE)
                foreach(header IN LISTS entry_headers)
                    string(LENGTH "${header}" header_length)
                    string(SUBSTRING "${included}" 0 ${header_length} start)
                    if(included STREQUAL header OR (header MATCHES "/$" AND start STREQUAL header))
                        set(matches TRUE)
                    elseif(header MATCHES "^(.*)\\*$")
                        # A prefix: every header whose name starts so.
                        set(prefix "${CMAKE_MATCH_1}")
                        string(LENGTH "${prefix}" prefix_length)
                        string(SUBSTRING "${included}" 0 ${prefix_length} start)
                        if(start STREQUAL prefix)
                            set(matches TRUE)
                        endif()
                    endif()
                endforeach()
                if(matches)
                    set(header_is_confined TRUE)
                    if(NOT entry_modules STREQUAL "NONE")
                        list(APPEND allowed_modules ${entry_module_list})
                    endif()
                    if(own IN_LIST entry_module_list)
                        if(entry_sources STREQUAL "sources" AND file MATCHES "\\.(h|hpp|hh|hxx)$")
                            set(sources_only_here "${entry_modules}")
                        else()
                            set(allowed TRUE)
                        endif()
                    endif()
                endif()
            endforeach()
            if(header_is_confined AND NOT allowed)
                if(NOT sources_only_here STREQUAL "")
                    report("${file}" ${number}
                        "includes <${included}> in a header; only source files of ${sources_only_here} may include it (POLICY.md 11.6)")
                elseif(allowed_modules STREQUAL "")
                    report("${file}" ${number}
                        "includes <${included}>, which no module may include: it is confined TO NONE (POLICY.md 11.6)")
                else()
                    list(REMOVE_DUPLICATES allowed_modules)
                    list(JOIN allowed_modules "," allowed_modules)
                    report("${file}" ${number}
                        "includes <${included}>, which only these modules may include: ${allowed_modules} (POLICY.md 11.6)")
                endif()
            endif()
        endif()

        # A test case's name, read here so that a bad one is found before the test program
        # is compiled and linked: the registration of the tests applies the same rule
        # (doctest_tests.cmake, POLICY.md 13.2). A placeholder for ";" or "\\" has a "<",
        # which the rule refuses like the character itself.
        if(file MATCHES "^tests/"
           AND line MATCHES "^[ \t]*(TEST_CASE|TEST_CASE_FIXTURE|TEST_CASE_TEMPLATE|SCENARIO)[ \t]*\\([^\"]*\"([^\"]*)\"")
            set(test_name "${CMAKE_MATCH_2}")
            if(NOT test_name MATCHES "^[A-Za-z0-9_'.:()+=-]([A-Za-z0-9 _'.:()+=-]*[A-Za-z0-9_'.:()+=-])?$")
                string(REPLACE "<SEMI>" "<a semicolon>" shown "${test_name}")
                report("${file}" ${number}
                    "test case \"${shown}\": use only letters, digits, spaces and ' . : ( ) + = - _ in a name, with no space at either end (POLICY.md 13.2)")
            endif()
        endif()

        # A used library's internal headers (<library>/<module>/internal/...) are its own.
        if(NOT USED_LIBRARIES STREQUAL ""
           AND line MATCHES "^[ \t]*#[ \t]*include[ \t]*[<\"]([^/>\"]+)/([^/>\"]+)/internal/[^>\"]*[>\"]"
           AND CMAKE_MATCH_1 IN_LIST USED_LIBRARIES)
            report("${file}" ${number}
                "includes a header that is internal to the library '${CMAKE_MATCH_1}' (its module '${CMAKE_MATCH_2}'); use what the library offers outside internal/ (POLICY.md 11.7)")
        endif()

        # A library's files include the library's headers by their full name, never the
        # program's, and keep the library's own layers (POLICY.md 11.7).
        if(NOT LIBRARY STREQUAL "" AND file MATCHES "^lib/${LIBRARY}/([^/]+)/"
           AND line MATCHES "^[ \t]*#[ \t]*include[ \t]*\"([^\"]+)\"")
            set(included "${CMAKE_MATCH_1}")
            string(REGEX MATCH "^lib/${LIBRARY}/([^/]+)/" _ "${file}")
            set(own "${CMAKE_MATCH_1}")
            if(included MATCHES "^\\.\\.?/" OR included MATCHES "/\\.\\./")
                report("${file}" ${number}
                    "includes \"${included}\" by a relative path; write it from the library's root: \"${LIBRARY}/module/header\"")
            elseif(NOT included MATCHES "^${LIBRARY}/([^/]+)/")
                report("${file}" ${number}
                    "includes \"${included}\": the library's code includes only its own headers, as \"${LIBRARY}/<module>/<header>\", and nothing of the program in src/ (POLICY.md 11.7)")
            else()
                set(target "${CMAKE_MATCH_1}")
                cpp_policy_in_dirs("${file}" "${CONFINED_DIRS}" own_confined)
                if(NOT target STREQUAL own AND included MATCHES "^${LIBRARY}/[^/]+/internal/")
                    report("${file}" ${number}
                        "includes \"${included}\", which is internal to the module '${target}' (POLICY.md 11.7)")
                elseif(NOT target STREQUAL own AND own_confined)
                    report("${file}" ${number}
                        "lib/${LIBRARY}/${own} is confined: it may include only its own headers, not \"${included}\"")
                elseif(NOT target STREQUAL own AND DEFINED library_layer_of_${own}
                       AND DEFINED library_layer_of_${target}
                       AND library_layer_of_${target} GREATER library_layer_of_${own})
                    report("${file}" ${number}
                        "includes \"${included}\" from a higher layer: '${own}' is layer ${library_layer_of_${own}} of the library, '${target}' is layer ${library_layer_of_${target}} (POLICY.md 11.7)")
                endif()
            endif()
        endif()

        # Constructs allowed only with a reason on the same line (POLICY.md 3). Only the code
        # before any // is searched, so a comment that mentions them doesn't count.
        string(FIND "${line}" "//" comment_at)
        if(comment_at EQUAL -1)
            set(code "${line}")
            set(comment "")
        else()
            string(SUBSTRING "${line}" 0 ${comment_at} code)
            string(SUBSTRING "${line}" ${comment_at} -1 comment)
        endif()
        if(code MATCHES "(^|[^A-Za-z0-9_])(dynamic_cast[ \t]*<|typeid[ \t]*\\()"
           AND NOT comment MATCHES "^//[ \t]*rtti:[ \t]*[^ \t]")
            report("${file}" ${number} "dynamic_cast and typeid need a reason on the same line: // rtti: reason")
        endif()
        if(code MATCHES "catch[ \t]*\\([ \t]*\\.\\.\\.[ \t]*\\)"
           AND NOT comment MATCHES "^//[ \t]*boundary:[ \t]*[^ \t]")
            report("${file}" ${number} "catch (...) is only for thread and program boundaries; name it on the same line: // boundary: which")
        endif()
    endforeach()

    # File size (POLICY.md 11.3). The last element is empty when the file ends in a newline.
    list(LENGTH lines line_count)
    if(line_count GREATER 0)
        list(GET lines -1 last_line)
        if(last_line STREQUAL "")
            math(EXPR line_count "${line_count} - 1")
        endif()
    endif()
    if(line_count GREATER file_lines_limit)
        math(EXPR first_over "${file_lines_limit} + 1")
        report("${file}" ${first_over}
            "${line_count} lines, over the limit of ${file_lines_limit}; split the file by responsibility (POLICY.md 11.3)")
    elseif(per_file)
        # After an edit, say so while the split is still cheap: before the next feature.
        math(EXPR left "${file_lines_limit} - ${line_count}")
        if(left LESS 50)
            message("${file}: note: ${line_count} lines, ${left} left before the limit of ${file_lines_limit}; split it before adding to it (POLICY.md 11.3)")
        endif()
    endif()

    if(file MATCHES "\\.(h|hpp|hh|hxx)$")
        if(NOT has_pragma_once)
            report("${file}" 1 "header must use #pragma once")
        endif()
        list(LENGTH directives directive_count)
        if(directive_count EQUAL 2)
            list(GET directives 0 first)
            list(GET directives 1 second)
            # Two ifs: in one, ${CMAKE_MATCH_1} would be expanded before the MATCHES runs.
            if(first MATCHES "^ifndef (.+)$")
                if(second STREQUAL "define ${CMAKE_MATCH_1}")
                    report("${file}" 1 "include guards are not allowed; use #pragma once")
                endif()
            endif()
        endif()
    endif()
endforeach()

# The project's config files exist for editors (clangd); the build always uses the
# policy's copies. A local edit would silently disagree with the build, so reject it.
# The git hooks run the gate, so an edited hook would weaken it without anyone noticing.
# REAL_PATH, not NORMAL_PATH: POLICY_ROOT may end in a slash, SOURCE_DIR doesn't.
file(REAL_PATH "${SOURCE_DIR}" source_norm)
file(REAL_PATH "${POLICY_ROOT}" policy_norm)
if(CHECK_PROJECT_FILES AND NOT per_file AND NOT source_norm STREQUAL policy_norm)
    set(policy_files .clang-tidy .clang-format CMakePresets.json tools/hooks/pre-commit
                     tools/hooks/pre-push tools/hooks/commit-msg tools/hooks/tidy-files
                     tools/hooks/gate)
    # A project that uses vcpkg loads it through the policy's files (POLICY.md 1.1); an edited
    # triplet would build the dependencies differently from the project.
    if(EXISTS "${SOURCE_DIR}/vcpkg.json")
        list(APPEND policy_files tools/vcpkg/setup.cmake tools/vcpkg/llvm.cmake
            tools/vcpkg/triplets/cpp-policy-asan.cmake tools/vcpkg/triplets/cpp-policy-tsan.cmake
            tools/vcpkg/triplets/cpp-policy-nosan.cmake)
    endif()
    foreach(name IN LISTS policy_files)
        if(NOT EXISTS "${SOURCE_DIR}/${name}")
            report("${name}" 1 "missing; copy it from cpp-policy (${POLICY_ROOT}/${name})")
        else()
            file(SHA256 "${SOURCE_DIR}/${name}" local_hash)
            file(SHA256 "${POLICY_ROOT}/${name}" policy_hash)
            if(NOT local_hash STREQUAL policy_hash)
                report("${name}" 1 "differs from cpp-policy's copy; policy files must not be edited locally")
            endif()
        endif()
    endforeach()
endif()

# The policy's .gitignore and .gitattributes are the required minimum: a project's copies
# must contain every line of them (comments and blank lines aside) and may add their own.
if(CHECK_PROJECT_FILES AND NOT per_file)
    foreach(name IN ITEMS .gitignore .gitattributes)
        if(NOT EXISTS "${SOURCE_DIR}/${name}")
            report("${name}" 1 "missing; start from cpp-policy's copy (${POLICY_ROOT}/${name})")
            continue()
        endif()
        file(STRINGS "${SOURCE_DIR}/${name}" project_lines)
        list(TRANSFORM project_lines STRIP)
        file(STRINGS "${POLICY_ROOT}/${name}" required_lines REGEX "^[ \t]*[^# \t]")
        foreach(required IN LISTS required_lines)
            string(STRIP "${required}" required)
            if(NOT required IN_LIST project_lines)
                report("${name}" 1 "missing required line '${required}' (see cpp-policy's ${name})")
            endif()
        endforeach()
    endforeach()
endif()

# A project's CI must run the same policy as its build: the reusable workflows it calls
# (cpp-policy/.github/workflows/gate.yml@<ref>, benchmark.yml@<ref>) must be pinned to the commit the build uses
# (POLICY.md 8). A tag or branch name fails too: it can move.
if(POLICY_COMMIT AND NOT per_file AND NOT source_norm STREQUAL policy_norm)
    file(GLOB workflows RELATIVE "${SOURCE_DIR}"
        "${SOURCE_DIR}/.github/workflows/*.yml" "${SOURCE_DIR}/.github/workflows/*.yaml")
    foreach(workflow IN LISTS workflows)
        cpp_policy_read_lines("${SOURCE_DIR}/${workflow}" lines)
        set(number 0)
        foreach(line IN LISTS lines)
            math(EXPR number "${number} + 1")
            if(line MATCHES "cpp-policy/\\.github/workflows/([a-z_-]+)\\.ya?ml@([^ \t#]+)"
               AND NOT CMAKE_MATCH_2 STREQUAL POLICY_COMMIT)
                set(called "${CMAKE_MATCH_1}")
                set(ref "${CMAKE_MATCH_2}")
                report("${workflow}" ${number}
                    "calls cpp-policy's ${called} at '${ref}', but the build uses ${POLICY_COMMIT}; pin both to the same commit")
            endif()
        endforeach()
    endforeach()
endif()

list(LENGTH checked_files count)
if(errors GREATER 0)
    message(FATAL_ERROR "cpp-policy audit: ${errors} violation(s) in ${count} file(s)")
endif()
message("cpp-policy audit: OK (${count} files)")

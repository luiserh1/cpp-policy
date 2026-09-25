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
# With CHECK_PROJECT_FILES, also fails if the project's .clang-tidy, .clang-format or git hooks
# (tools/hooks/) differ from the policy's, or its .gitignore / .gitattributes lack any line of
# the policy's copies.

cmake_minimum_required(VERSION 3.29)
include("${CMAKE_CURRENT_LIST_DIR}/source_files.cmake")
include("${CONFIG}")

set(errors 0)
macro(report file line message)
    message("${file}:${line}: error: ${message}")
    math(EXPR errors "${errors} + 1")
endmacro()

cpp_policy_collect_sources("${SOURCE_DIR}" "${EXCLUDED_DIRS}" files)

foreach(file IN LISTS files)
    cpp_policy_in_dirs("${file}" "${CONFINED_DIRS}" confined)
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
    endforeach()

    if(file MATCHES "\\.(h|hpp|hh|hxx)$")
        if(NOT has_pragma_once)
            report("${file}" 1 "header must use #pragma once")
        endif()
        list(LENGTH directives directive_count)
        if(directive_count EQUAL 2)
            list(GET directives 0 first)
            list(GET directives 1 second)
            if(first MATCHES "^ifndef (.+)$" AND second STREQUAL "define ${CMAKE_MATCH_1}")
                report("${file}" 1 "include guards are not allowed; use #pragma once")
            endif()
        endif()
    endif()
endforeach()

# The project's config files exist for editors (clangd); the build always uses the
# policy's copies. A local edit would silently disagree with the build, so reject it.
# The git hooks run the gate, so an edited hook would weaken it without anyone noticing.
cmake_path(NORMAL_PATH SOURCE_DIR OUTPUT_VARIABLE source_norm)
cmake_path(NORMAL_PATH POLICY_ROOT OUTPUT_VARIABLE policy_norm)
if(CHECK_PROJECT_FILES AND NOT source_norm STREQUAL policy_norm)
    foreach(name IN ITEMS .clang-tidy .clang-format tools/hooks/pre-commit tools/hooks/pre-push)
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
if(CHECK_PROJECT_FILES)
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

list(LENGTH files count)
if(errors GREATER 0)
    message(FATAL_ERROR "cpp-policy audit: ${errors} violation(s) in ${count} file(s)")
endif()
message("cpp-policy audit: OK (${count} files)")

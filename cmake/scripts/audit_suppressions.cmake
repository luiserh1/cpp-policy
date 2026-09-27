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
# Fails if a file has more than 350 lines (POLICY.md 11.3).
# Fails if an #include in src/ points to a higher layer (LAYERS, from cpp_policy_layers()),
# uses a relative path, or leaves a confined module; if src/ has two or more modules and
# no layers; or if a module is in no layer (POLICY.md 11.1).
# Fails if dynamic_cast or typeid lacks `// rtti: reason`, or catch (...) lacks
# `// boundary: which`, on the same line (POLICY.md 3).
# With CHECK_PROJECT_FILES, also fails if the project's .clang-tidy, .clang-format or git hooks
# (tools/hooks/) differ from the policy's, or its .gitignore / .gitattributes lack any line of
# the policy's copies.
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
set(max_file_lines 350)

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
if(LAYERS STREQUAL "" AND module_count GREATER 1)
    string(REPLACE ";" ", " module_names "${modules}")
    report("CMakeLists.txt" 1
        "src/ has ${module_count} modules (${module_names}) but no layers; declare them from the lowest up with cpp_policy_layers() (POLICY.md 11.1)")
endif()
if(NOT LAYERS STREQUAL "")
    foreach(module IN LISTS modules)
        if(NOT DEFINED layer_of_${module})
            report("src/${module}" 1 "module '${module}' is in no layer; add it to cpp_policy_layers() (POLICY.md 11.1)")
        endif()
    endforeach()
endif()

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
    if(line_count GREATER max_file_lines)
        math(EXPR first_over "${max_file_lines} + 1")
        report("${file}" ${first_over}
            "${line_count} lines, over the limit of ${max_file_lines}; split the file by responsibility (POLICY.md 11.3)")
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
if(CHECK_PROJECT_FILES AND NOT source_norm STREQUAL policy_norm)
    foreach(name IN ITEMS .clang-tidy .clang-format tools/hooks/pre-commit tools/hooks/pre-push
                          tools/hooks/commit-msg)
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

# A project's CI must run the same policy as its build: the reusable gate it calls
# (cpp-policy/.github/workflows/gate.yml@<ref>) must be pinned to the commit the build uses
# (POLICY.md 8). A tag or branch name fails too: it can move.
if(POLICY_COMMIT AND NOT source_norm STREQUAL policy_norm)
    file(GLOB workflows RELATIVE "${SOURCE_DIR}"
        "${SOURCE_DIR}/.github/workflows/*.yml" "${SOURCE_DIR}/.github/workflows/*.yaml")
    foreach(workflow IN LISTS workflows)
        cpp_policy_read_lines("${SOURCE_DIR}/${workflow}" lines)
        set(number 0)
        foreach(line IN LISTS lines)
            math(EXPR number "${number} + 1")
            if(line MATCHES "cpp-policy/\\.github/workflows/gate\\.ya?ml@([^ \t#]+)"
               AND NOT CMAKE_MATCH_1 STREQUAL POLICY_COMMIT)
                set(ref "${CMAKE_MATCH_1}")
                report("${workflow}" ${number}
                    "calls cpp-policy's gate at '${ref}', but the build uses ${POLICY_COMMIT}; pin both to the same commit")
            endif()
        endforeach()
    endforeach()
endif()

list(LENGTH files count)
if(errors GREATER 0)
    message(FATAL_ERROR "cpp-policy audit: ${errors} violation(s) in ${count} file(s)")
endif()
message("cpp-policy audit: OK (${count} files)")

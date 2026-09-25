# Suppression audit (POLICY.md section 5).
#
#   cmake -DCONFIG=<cpp_policy_config.cmake> [-DCHECK_SYNC=ON] -P audit_suppressions.cmake
#
# Fails if any NOLINT or diagnostic pragma:
#   - is outside a confined directory,
#   - does not name specific checks (bare or wildcard),
#   - has no reason: `NOLINT(check-name): reason`.
# With CHECK_SYNC, also fails if the project's .clang-tidy / .clang-format differ from the policy's.

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
    foreach(line IN LISTS lines)
        math(EXPR number "${number} + 1")

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

        if(line MATCHES "#[ \t]*pragma[ \t]+(clang|GCC)[ \t]+diagnostic[ \t]+ignored"
           OR line MATCHES "#[ \t]*pragma[ \t]+warning[ \t]*\\([ \t]*disable")
            if(NOT confined)
                report("${file}" ${number} "diagnostic pragma outside a confined area (${CONFINED_DIRS})")
            endif()
        endif()
    endforeach()
endforeach()

# The project's config files exist for editors (clangd); the build always uses the
# policy's copies. A local edit would silently disagree with the build, so reject it.
cmake_path(NORMAL_PATH SOURCE_DIR OUTPUT_VARIABLE source_norm)
cmake_path(NORMAL_PATH POLICY_ROOT OUTPUT_VARIABLE policy_norm)
if(CHECK_SYNC AND NOT source_norm STREQUAL policy_norm)
    foreach(name IN ITEMS .clang-tidy .clang-format)
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

list(LENGTH files count)
if(errors GREATER 0)
    message(FATAL_ERROR "cpp-policy audit: ${errors} violation(s) in ${count} file(s)")
endif()
message("cpp-policy audit: OK (${count} files)")

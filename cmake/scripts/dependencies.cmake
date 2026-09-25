# Dependency check (POLICY.md 1.1).
#
#   cmake -DMANIFEST=<vcpkg.json> [-DINSTALLED_DIRS=<dir>;...] -P dependencies.cmake
#
# INSTALLED_DIRS are vcpkg's per-triplet install directories (<vcpkg_installed>/<triplet>).
# Fails if a dependency in the manifest:
#   - is a plain name instead of an object,
#   - doesn't turn default features off ("default-features": false),
#   - doesn't say why it is there ("$reason": "...").
# Fails if an installed package (dependencies of dependencies included) has a license
# outside the allowed list, or none declared.

cmake_minimum_required(VERSION 3.29)

# Permissive licenses (SPDX identifiers). Adding one is a policy change, made in cpp-policy.
set(allowed_licenses
    MIT BSD-2-Clause BSD-3-Clause Apache-2.0 BSL-1.0 Zlib ISC 0BSD Unlicense CC0-1.0)

set(errors 0)
macro(report message)
    message("error: ${message}")
    math(EXPR errors "${errors} + 1")
endmacro()

# --- The manifest -----------------------------------------------------------------------
file(READ "${MANIFEST}" manifest)
string(JSON count ERROR_VARIABLE no_dependencies LENGTH "${manifest}" dependencies)
if(no_dependencies)
    set(count 0)
endif()
if(count GREATER 0)
    math(EXPR last "${count} - 1")
    foreach(i RANGE ${last})
        string(JSON type TYPE "${manifest}" dependencies ${i})
        if(NOT type STREQUAL "OBJECT")
            string(JSON name GET "${manifest}" dependencies ${i})
            report("vcpkg.json: dependency '${name}' must be an object with \"default-features\": false and a \"$reason\"")
            continue()
        endif()
        string(JSON name GET "${manifest}" dependencies ${i} name)
        string(JSON features ERROR_VARIABLE missing GET "${manifest}" dependencies ${i} default-features)
        if(missing OR NOT features STREQUAL "OFF")
            report("vcpkg.json: dependency '${name}' must set \"default-features\": false; list the features it needs in \"features\"")
        endif()
        string(JSON reason ERROR_VARIABLE missing GET "${manifest}" dependencies ${i} "$reason")
        string(STRIP "${reason}" reason)
        if(missing OR reason STREQUAL "")
            report("vcpkg.json: dependency '${name}' must say why it is needed: \"$reason\": \"...\"")
        endif()
    endforeach()
endif()

# --- Licenses of everything installed ---------------------------------------------------
# An SPDX expression is allowed when one of its OR alternatives has only allowed licenses
# (joined by AND). "WITH <exception>" only grants extra permissions, so it is ignored.
function(license_allowed expression out)
    string(REGEX REPLACE "[()]" " " expression "${expression}")
    string(REGEX REPLACE " WITH [^ ]+" "" expression "${expression}")
    string(REPLACE " OR " ";" alternatives "${expression}")
    foreach(alternative IN LISTS alternatives)
        string(REPLACE " AND " ";" licenses "${alternative}")
        set(all_allowed TRUE)
        foreach(license IN LISTS licenses)
            string(STRIP "${license}" license)
            if(NOT license IN_LIST allowed_licenses)
                set(all_allowed FALSE)
            endif()
        endforeach()
        if(all_allowed)
            set(${out} TRUE PARENT_SCOPE)
            return()
        endif()
    endforeach()
    set(${out} FALSE PARENT_SCOPE)
endfunction()

foreach(dir IN LISTS INSTALLED_DIRS)
    file(GLOB packages LIST_DIRECTORIES true "${dir}/share/*")
    foreach(package_dir IN LISTS packages)
        cmake_path(GET package_dir FILENAME package)
        set(spdx "${package_dir}/vcpkg.spdx.json")
        if(NOT EXISTS "${spdx}")
            continue()
        endif()
        # The SPDX document lists the port itself (named like the directory) among others.
        file(READ "${spdx}" document)
        string(JSON entries LENGTH "${document}" packages)
        set(license "")
        math(EXPR last "${entries} - 1")
        foreach(i RANGE ${last})
            string(JSON entry_name GET "${document}" packages ${i} name)
            if(entry_name STREQUAL package)
                string(JSON license ERROR_VARIABLE missing GET "${document}" packages ${i} licenseConcluded)
            endif()
        endforeach()
        if(license STREQUAL "" OR license STREQUAL "NOASSERTION" OR license MATCHES "NOTFOUND$")
            report("${package}: no license declared; review it before depending on it")
            continue()
        endif()
        license_allowed("${license}" allowed)
        if(NOT allowed)
            report("${package}: license '${license}' is not allowed (allowed: ${allowed_licenses})")
        endif()
    endforeach()
endforeach()

if(errors GREATER 0)
    message(FATAL_ERROR "cpp-policy dependencies: ${errors} problem(s) (POLICY.md 1.1)")
endif()
message("cpp-policy dependencies: OK")

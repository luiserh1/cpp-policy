# Helpers shared by the cpp-policy scripts (run with cmake -P).

set(CPP_POLICY_SOURCE_GLOBS *.cpp *.cc *.cxx *.h *.hpp *.hh *.hxx *.ipp *.ixx *.cppm)

# True if relative path `rel` is inside one of the directories in `dirs`.
function(cpp_policy_in_dirs rel dirs out)
    set(${out} FALSE PARENT_SCOPE)
    foreach(dir IN LISTS dirs)
        cmake_path(NORMAL_PATH dir)
        string(REGEX REPLACE "/$" "" dir "${dir}")
        string(LENGTH "${dir}/" len)
        string(SUBSTRING "${rel}" 0 ${len} prefix)
        if(prefix STREQUAL "${dir}/")
            set(${out} TRUE PARENT_SCOPE)
            return()
        endif()
    endforeach()
endfunction()

# Lists C++ source files under `root` (relative paths), skipping `excluded` directories.
function(cpp_policy_collect_sources root excluded out)
    set(patterns "")
    foreach(glob IN LISTS CPP_POLICY_SOURCE_GLOBS)
        list(APPEND patterns "${root}/${glob}")
    endforeach()
    file(GLOB_RECURSE files RELATIVE "${root}" ${patterns})
    set(result "")
    foreach(file IN LISTS files)
        cpp_policy_in_dirs("${file}" "${excluded}" skip)
        # Build directories created by presets are excluded by name anywhere in the path.
        if(NOT skip AND NOT file MATCHES "(^|/)CMakeFiles/")
            list(APPEND result "${file}")
        endif()
    endforeach()
    list(SORT result)
    set(${out} "${result}" PARENT_SCOPE)
endfunction()

# Reads a file as a list of lines. Characters that CMake lists treat specially
# (";", "[", "]", "\") are replaced by placeholders so line numbers stay exact.
function(cpp_policy_read_lines path out)
    file(READ "${path}" content)
    string(REPLACE "\\" "<BSL>" content "${content}")
    string(REPLACE ";" "<SEMI>" content "${content}")
    string(REPLACE "[" "<LBR>" content "${content}")
    string(REPLACE "]" "<RBR>" content "${content}")
    string(REPLACE "\r\n" "\n" content "${content}")
    string(REPLACE "\n" ";" content "${content}")
    set(${out} "${content}" PARENT_SCOPE)
endfunction()

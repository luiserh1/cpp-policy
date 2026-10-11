# Source file helpers for the cpp-policy scripts (run with cmake -P): which files
# count as C++ sources, and how to read them line by line.

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
    # The excluded directories at the top (build/, out/, .git/) are not walked at all: they
    # can hold a hundred times the files of the project (build trees, an agent's worktrees),
    # and listing them first made the audit take minutes beside a build.
    file(GLOB entries LIST_DIRECTORIES true RELATIVE "${root}" "${root}/*")
    set(patterns "")
    foreach(entry IN LISTS entries)
        if(IS_DIRECTORY "${root}/${entry}")
            cpp_policy_in_dirs("${entry}/" "${excluded}" skip)
            if(NOT skip AND NOT entry STREQUAL "CMakeFiles")
                foreach(glob IN LISTS CPP_POLICY_SOURCE_GLOBS)
                    list(APPEND patterns "${root}/${entry}/${glob}")
                endforeach()
            endif()
        endif()
    endforeach()
    foreach(glob IN LISTS CPP_POLICY_SOURCE_GLOBS)
        list(APPEND files_at_root "${root}/${glob}")
    endforeach()
    file(GLOB files RELATIVE "${root}" ${files_at_root})
    if(patterns)
        file(GLOB_RECURSE nested RELATIVE "${root}" ${patterns})
        list(APPEND files ${nested})
    endif()
    set(result "")
    foreach(file IN LISTS files)
        cpp_policy_in_dirs("${file}" "${excluded}" skip)
        # CMake's own CMakeFiles/ folders (compiler probe sources) are skipped at any depth.
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

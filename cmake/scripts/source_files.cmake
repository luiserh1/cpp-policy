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

# Drops the drafts from `files` (relative to `root`): files git doesn't track that no target of
# the build in `build_dir` compiles. An agent's half-written file failed the gate's audit and
# format check twice in Alfar, though nothing compiled it. A new source the build compiles is
# kept, tracked or not; outside a git checkout nothing is dropped. Names what it dropped.
function(cpp_policy_drop_drafts root build_dir files out)
    set(${out} "${files}" PARENT_SCOPE)
    find_program(CPP_POLICY_GIT git)
    if(NOT CPP_POLICY_GIT OR NOT EXISTS "${build_dir}/compile_commands.json")
        return()
    endif()
    execute_process(COMMAND "${CPP_POLICY_GIT}" -c core.quotePath=false ls-files --others
                            --exclude-standard
        WORKING_DIRECTORY "${root}" RESULT_VARIABLE failed OUTPUT_VARIABLE untracked
        ERROR_QUIET)
    if(failed OR untracked STREQUAL "")
        return()
    endif()
    string(REPLACE "\n" ";" untracked "${untracked}")
    file(READ "${build_dir}/compile_commands.json" database)
    string(JSON entries LENGTH "${database}")
    set(compiled "")
    if(entries GREATER 0)
        math(EXPR last "${entries} - 1")
        foreach(index RANGE ${last})
            string(JSON path GET "${database}" ${index} file)
            if(EXISTS "${path}")
                file(REAL_PATH "${path}" path)
                list(APPEND compiled "${path}")
            endif()
        endforeach()
    endif()
    set(kept "")
    set(dropped "")
    file(REAL_PATH "${root}" real_root)
    foreach(file IN LISTS files)
        if(file IN_LIST untracked AND NOT "${real_root}/${file}" IN_LIST compiled)
            list(APPEND dropped "${file}")
        else()
            list(APPEND kept "${file}")
        endif()
    endforeach()
    if(dropped)
        list(JOIN dropped ", " names)
        message("cpp-policy: not checked, as drafts (git doesn't track them and nothing "
                "compiles them): ${names}")
    endif()
    set(${out} "${kept}" PARENT_SCOPE)
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

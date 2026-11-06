# clang-tidy, skipped for a file that already passed with the same inputs (POLICY.md 8). The
# build runs it in clang-tidy's place:
#   cmake -P tidy_cache.cmake -- <source dir> <build dir> <clang-tidy> <its options>... <file>
#         -- <compile command>
#
# The key is everything clang-tidy reads for that file: the program itself (its path, size and
# time), its options, the policy's configuration, the compile command, and the path and
# contents of every file the compile includes, as the compiler lists them now. Only passes are
# kept: a file with a finding is checked again every time. The source and build folders are
# replaced by placeholders, so that two checkouts of one commit (a developer's and a CI
# runner's) share their entries; not when either folder's path matches the configuration's
# ExcludeHeaderFilterRegex, since clang-tidy would then skip that folder's headers in one
# checkout and check them in another.
#
# The cache's folder: tidy_cache_dir.cmake. CPP_POLICY_TIDY_CACHE_LOG names a file to which
# each run adds a line, "hit <file>" or "run <file>" (the self-tests read it).
cmake_minimum_required(VERSION 3.29)
include("${CMAKE_CURRENT_LIST_DIR}/tidy_cache_dir.cmake")

set(args "")
set(after_marker FALSE)
math(EXPR last "${CMAKE_ARGC} - 1")
foreach(index RANGE 1 ${last})
    set(argument "${CMAKE_ARGV${index}}")
    if(after_marker)
        list(APPEND args "${argument}")
    elseif(argument STREQUAL "--")
        set(after_marker TRUE)
    endif()
endforeach()
list(POP_FRONT args source_dir build_dir)

# clang-tidy's own command, up to and with the file; then the compile command.
list(FIND args "--" split)
list(SUBLIST args 0 ${split} tidy)
math(EXPR first_compile "${split} + 1")
list(SUBLIST args ${first_compile} -1 compile)
list(GET tidy -1 source)

cpp_policy_tidy_cache_dir(cache)

# Files are checked several at a time, and on Windows two appends at once lost a line: the
# log is written under a lock.
function(note what)
    if(DEFINED ENV{CPP_POLICY_TIDY_CACHE_LOG})
        set(log "$ENV{CPP_POLICY_TIDY_CACHE_LOG}")
        file(LOCK "${log}.lock" GUARD FUNCTION TIMEOUT 60)
        file(APPEND "${log}" "${what} ${source}\n")
    endif()
endfunction()

# Runs clang-tidy, remembers a pass under `entry` when there is one, and ends with its result.
macro(run_tidy_and_exit)
    note(run)
    execute_process(COMMAND ${tidy} -- ${compile} RESULT_VARIABLE code)
    if(code EQUAL 0 AND DEFINED entry)
        file(MAKE_DIRECTORY "${shard_dir}")
        file(TOUCH "${entry}")
    endif()
    cmake_language(EXIT ${code})
endmacro()

if(cache STREQUAL "off")
    run_tidy_and_exit()
endif()

# Adds options to a compile command, before a "--" that ends its options when it has one
# (clang-cl's command does: what follows is the file).
function(before_inputs command_var)
    set(command "${${command_var}}")
    list(FIND command "--" end)
    if(end EQUAL -1)
        list(APPEND command ${ARGN})
    else()
        list(INSERT command ${end} ${ARGN})
    endif()
    set(${command_var} "${command}" PARENT_SCOPE)
endfunction()

# The files the compile reads now: the compile command, writing only its list of includes.
list(GET compile 0 compiler)
cmake_path(GET compiler STEM compiler_name)
string(TOLOWER "${compiler_name}" compiler_name)
string(SHA256 scratch_name "${args}")
file(MAKE_DIRECTORY "${cache}/tmp")
set(dependencies "")
set(skip_next FALSE)
set(listing_command "")
if(compiler_name STREQUAL "clang-cl")
    # clang-cl has no -M: it preprocesses, and /showIncludes names each file it opens.
    foreach(argument IN LISTS compile)
        if(NOT argument MATCHES "^[-/](c|FS|showIncludes|Fo.*|Fd.*)$")
            list(APPEND listing_command "${argument}")
        endif()
    endforeach()
    before_inputs(listing_command /E /showIncludes)
    execute_process(COMMAND ${listing_command}
        RESULT_VARIABLE listed OUTPUT_QUIET ERROR_VARIABLE listing)
    string(REPLACE "\r" "" listing "${listing}")
    string(REPLACE "\n" ";" listing "${listing}")
    list(APPEND dependencies "${source}")
    foreach(line IN LISTS listing)
        if(line MATCHES "^Note: including file: *(.*)$")
            file(TO_CMAKE_PATH "${CMAKE_MATCH_1}" path)
            list(APPEND dependencies "${path}")
        endif()
    endforeach()
else()
    foreach(argument IN LISTS compile)
        if(skip_next)
            set(skip_next FALSE)
        elseif(argument MATCHES "^-(o|MT|MF|MQ)$")
            set(skip_next TRUE)
        elseif(NOT argument MATCHES "^-(c|MD|MMD)$")
            list(APPEND listing_command "${argument}")
        endif()
    endforeach()
    set(listing "${cache}/tmp/${scratch_name}.d")
    before_inputs(listing_command -M -MF "${listing}")
    execute_process(COMMAND ${listing_command} RESULT_VARIABLE listed OUTPUT_QUIET ERROR_QUIET)
    if(listed EQUAL 0)
        file(READ "${listing}" text)
        string(REPLACE "\\\n" " " text "${text}")
        string(REPLACE "\\ " "<space>" text "${text}")
        string(REGEX REPLACE "^[^:]*: *" "" text "${text}")
        string(REGEX REPLACE "[ \t\r\n]+" ";" text "${text}")
        foreach(dependency IN LISTS text)
            if(NOT dependency STREQUAL "")
                string(REPLACE "<space>" " " dependency "${dependency}")
                list(APPEND dependencies "${dependency}")
            endif()
        endforeach()
    endif()
    file(REMOVE "${listing}")
endif()
if(NOT listed EQUAL 0)
    # The compile itself will fail and say why: there is nothing to remember.
    run_tidy_and_exit()
endif()

list(GET tidy 0 tidy_exe)
file(REAL_PATH "${tidy_exe}" tidy_file)
file(SIZE "${tidy_file}" tidy_size)
file(TIMESTAMP "${tidy_file}" tidy_time "%Y-%m-%dT%H:%M:%S" UTC)
set(key "program ${tidy_file} ${tidy_size} ${tidy_time}\ntidy ${tidy}\ncompile ${compile}\n")
set(excluded "")
foreach(option IN LISTS tidy)
    if(option MATCHES "^--config-file=(.*)$")
        set(config "${CMAKE_MATCH_1}")
        file(SHA256 "${config}" config_hash)
        string(APPEND key "config ${config_hash}\n")
        file(STRINGS "${config}" excluded REGEX "^ExcludeHeaderFilterRegex:")
        string(REGEX REPLACE "^ExcludeHeaderFilterRegex: *'(.*)'$" "\\1" excluded "${excluded}")
    endif()
endforeach()
foreach(dependency IN LISTS dependencies)
    file(SHA256 "${dependency}" hash)
    string(APPEND key "file ${dependency} ${hash}\n")
endforeach()

# Placeholders for the two folders, the longer first when one holds the other. On Windows
# CMake gives clang-tidy the file with backslashes and the folders with slashes: the key uses
# slashes throughout, or the folders would never be found in it.
string(REPLACE "\\" "/" key "${key}")
set(shared TRUE)
if(NOT excluded STREQUAL "" AND ("${source_dir}/" MATCHES "${excluded}"
                                 OR "${build_dir}/" MATCHES "${excluded}"))
    set(shared FALSE)
endif()
if(shared)
    string(LENGTH "${source_dir}" source_length)
    string(LENGTH "${build_dir}" build_length)
    if(build_length GREATER source_length)
        string(REPLACE "${build_dir}" "<build>" key "${key}")
        string(REPLACE "${source_dir}" "<source>" key "${key}")
    else()
        string(REPLACE "${source_dir}" "<source>" key "${key}")
        string(REPLACE "${build_dir}" "<build>" key "${key}")
    endif()
endif()
string(SHA256 fingerprint "${key}")
string(SUBSTRING "${fingerprint}" 0 2 shard)
set(shard_dir "${cache}/${shard}")
set(entry "${shard_dir}/${fingerprint}")

if(EXISTS "${entry}")
    # Its time says when it was last used: entries unused for 30 days are removed.
    file(TOUCH_NOCREATE "${entry}")
    note(hit)
    cmake_language(EXIT 0)
endif()
run_tidy_and_exit()

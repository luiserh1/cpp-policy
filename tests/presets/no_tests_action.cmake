# Every test preset fails a run that selects no test (POLICY.md 13.2): `ctest -R` with a
# mistyped name used to pass with nothing run. A preset may have the setting itself or
# inherit it.
#
#   cmake -DPOLICY_ROOT=<dir> -P no_tests_action.cmake

cmake_minimum_required(VERSION 3.29)
file(READ "${POLICY_ROOT}/CMakePresets.json" presets)
string(JSON count LENGTH "${presets}" testPresets)
math(EXPR last "${count} - 1")

# The setting of the preset at `index`, or of the one it inherits from.
function(no_tests_action name out)
    foreach(index RANGE ${last})
        string(JSON candidate GET "${presets}" testPresets ${index} name)
        if(candidate STREQUAL name)
            string(JSON action ERROR_VARIABLE missing
                GET "${presets}" testPresets ${index} execution noTestsAction)
            if(missing)
                string(JSON parent ERROR_VARIABLE orphan GET "${presets}" testPresets ${index} inherits)
                if(orphan)
                    set(action "")
                else()
                    no_tests_action("${parent}" action)
                endif()
            endif()
            set(${out} "${action}" PARENT_SCOPE)
            return()
        endif()
    endforeach()
    set(${out} "" PARENT_SCOPE)
endfunction()

set(failures "")
foreach(index RANGE ${last})
    string(JSON name GET "${presets}" testPresets ${index} name)
    no_tests_action("${name}" action)
    if(NOT action STREQUAL "error")
        list(APPEND failures "${name}")
    endif()
endforeach()
if(failures)
    list(JOIN failures ", " failures)
    message(FATAL_ERROR "presets: these test presets don't set noTestsAction to error: ${failures}")
endif()
message("presets: OK (${count} test presets)")

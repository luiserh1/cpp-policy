# The check build presets keep going after a failing file, so one run reports every finding.
#
#   cmake -DPOLICY_ROOT=<dir> -DWORK=<dir> -DCXX=<compiler> -P run.cmake
#
# A throwaway project with three files that don't compile is built with the native tool options
# of the policy's check and win-check build presets, one file at a time. All three errors must
# be reported; with Ninja's default, the build stops after the first.

cmake_minimum_required(VERSION 3.29)

file(READ "${POLICY_ROOT}/CMakePresets.json" policy_presets)
string(JSON count LENGTH "${policy_presets}" buildPresets)
math(EXPR last "${count} - 1")

foreach(preset IN ITEMS check win-check)
    # The preset's native tool options, as a JSON array.
    set(options "")
    foreach(index RANGE ${last})
        string(JSON name GET "${policy_presets}" buildPresets ${index} name)
        if(name STREQUAL preset)
            string(JSON options ERROR_VARIABLE missing GET "${policy_presets}" buildPresets ${index}
                nativeToolOptions)
        endif()
    endforeach()
    if(options STREQUAL "")
        message(FATAL_ERROR "keep_going: the ${preset} build preset has no nativeToolOptions")
    endif()

    set(dir "${WORK}/${preset}")
    file(REMOVE_RECURSE "${dir}")
    file(MAKE_DIRECTORY "${dir}")
    file(WRITE "${dir}/CMakeLists.txt"
        "cmake_minimum_required(VERSION 3.29)\n"
        "project(keep_going LANGUAGES CXX)\n"
        "add_library(broken OBJECT one.cpp two.cpp three.cpp)\n")
    foreach(file IN ITEMS one two three)
        file(WRITE "${dir}/${file}.cpp" "#error broken_${file}\n")
    endforeach()
    file(WRITE "${dir}/CMakePresets.json"
        "{\"version\": 6,\n"
        " \"configurePresets\": [{\"name\": \"p\", \"generator\": \"Ninja\",\n"
        "   \"binaryDir\": \"\${sourceDir}/build\",\n"
        "   \"cacheVariables\": {\"CMAKE_CXX_COMPILER\": \"${CXX}\"}}],\n"
        " \"buildPresets\": [{\"name\": \"p\", \"configurePreset\": \"p\",\n"
        "   \"nativeToolOptions\": ${options}}]}\n")

    execute_process(COMMAND "${CMAKE_COMMAND}" --preset p WORKING_DIRECTORY "${dir}"
        RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
    if(NOT code EQUAL 0)
        message(FATAL_ERROR "keep_going: configuring the throwaway project failed\n${out}${err}")
    endif()
    # One file at a time, so files built in parallel can't make it pass by accident.
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E env CMAKE_BUILD_PARALLEL_LEVEL=1
                "${CMAKE_COMMAND}" --build --preset p
        WORKING_DIRECTORY "${dir}" RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
    foreach(file IN ITEMS one two three)
        string(FIND "${out}${err}" "broken_${file}" found)
        if(found EQUAL -1)
            message(FATAL_ERROR "keep_going: the ${preset} build preset stopped before ${file}.cpp\n"
                                "${out}${err}")
        endif()
    endforeach()
endforeach()
message("keep_going: OK")

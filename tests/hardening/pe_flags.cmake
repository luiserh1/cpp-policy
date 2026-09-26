# Checks that a program built with clang-cl carries the hardening the policy asks for
# (POLICY.md 7.4), by reading its PE header and load configuration:
#
#   cmake -DREADOBJ=<llvm-readobj> -DBINARY=<exe or dll> -P pe_flags.cmake
#
# - GUARD_CF with a non-empty function table: Control Flow Guard was compiled and linked
#   in. The load config's CF_INSTRUMENTED flag alone proves nothing: the MSVC runtime sets
#   it in every program, guarded or not.
# - DYNAMIC_BASE, HIGH_ENTROPY_VA, NX_COMPAT: lld-link's defaults (ASLR and no-execute
#   data), checked so that a change in those defaults is noticed.

cmake_minimum_required(VERSION 3.29)

execute_process(COMMAND "${READOBJ}" --file-headers --coff-load-config "${BINARY}"
    RESULT_VARIABLE code OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(code)
    message(FATAL_ERROR "pe_flags: ${READOBJ} failed on ${BINARY} (exit code ${code})\n${err}")
endif()

set(missing "")
foreach(flag IN ITEMS GUARD_CF DYNAMIC_BASE HIGH_ENTROPY_VA NX_COMPAT)
    if(NOT out MATCHES "IMAGE_DLL_CHARACTERISTICS_${flag}")
        list(APPEND missing "${flag}")
    endif()
endforeach()
if(NOT out MATCHES "GuardCFFunctionCount: ([0-9]+)" OR CMAKE_MATCH_1 EQUAL 0)
    list(APPEND missing "a non-empty Control Flow Guard function table")
endif()

if(missing)
    list(JOIN missing ", " missing)
    message(FATAL_ERROR "pe_flags: ${BINARY} lacks ${missing}\n--- llvm-readobj ---\n${out}")
endif()
message("pe_flags: OK")

# cpp-policy triplet (POLICY.md 1.1): dependencies built like the project, for the host system.
# tools/vcpkg/setup.cmake picks cpp-policy-asan, -tsan or -nosan from the preset's sanitizer
# options. The three files differ only in the next line (a self-test checks it), and include
# nothing: vcpkg keys its binary cache on this file's hash and llvm.cmake's, and wouldn't notice
# a change to an included file.
set(_cpp_policy_sanitizer address)

set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "${CMAKE_CURRENT_LIST_DIR}/../llvm.cmake")

# The host's architecture and system: the policy doesn't cross-compile.
cmake_host_system_information(RESULT _cpp_policy_platform QUERY OS_PLATFORM)
if(_cpp_policy_platform MATCHES "^(x86_64|AMD64|amd64)$")
    set(VCPKG_TARGET_ARCHITECTURE x64)
elseif(_cpp_policy_platform MATCHES "^(arm64|aarch64|ARM64)$")
    set(VCPKG_TARGET_ARCHITECTURE arm64)
else()
    message(FATAL_ERROR "cpp-policy triplets support x64 and arm64, not '${_cpp_policy_platform}'")
endif()
if(CMAKE_HOST_APPLE)
    set(VCPKG_CMAKE_SYSTEM_NAME Darwin)
    if(VCPKG_TARGET_ARCHITECTURE STREQUAL "x64")
        set(VCPKG_OSX_ARCHITECTURES x86_64)
    else()
        set(VCPKG_OSX_ARCHITECTURES arm64)
    endif()
elseif(CMAKE_HOST_UNIX)
    set(VCPKG_CMAKE_SYSTEM_NAME Linux)
endif()

# The flags mirror cmake/CppPolicy.cmake: the preset's sanitizer (never UBSan, see setup.cmake),
# standard library hardening (debug with a sanitizer, as the dev, check and tsan presets have
# it; fast otherwise), stack protection, and for optimized builds _FORTIFY_SOURCE or Control
# Flow Guard.
if(CMAKE_HOST_WIN32)
    set(_cpp_policy_flags "")
    if(_cpp_policy_sanitizer STREQUAL "address")
        set(_cpp_policy_flags "/fsanitize=address")
        # The win-check preset builds RelWithDebInfo with the release C runtime, which is all
        # AddressSanitizer supports (POLICY.md 7.3): only the release build is needed.
        set(VCPKG_BUILD_TYPE release)
    elseif(_cpp_policy_sanitizer STREQUAL "thread")
        message(FATAL_ERROR "cpp-policy: ThreadSanitizer is not available with clang-cl")
    endif()
    set(VCPKG_C_FLAGS "${_cpp_policy_flags}")
    set(VCPKG_CXX_FLAGS "${_cpp_policy_flags} /D_MSVC_STL_HARDENING=1")
    set(VCPKG_C_FLAGS_RELEASE "/guard:cf")
    set(VCPKG_CXX_FLAGS_RELEASE "/guard:cf")
    set(VCPKG_LINKER_FLAGS_RELEASE "/guard:cf")
else()
    set(_cpp_policy_flags "-fstack-protector-strong")
    if(VCPKG_TARGET_ARCHITECTURE STREQUAL "x64")
        string(APPEND _cpp_policy_flags " -fcf-protection")
    endif()
    set(_cpp_policy_link "")
    set(_cpp_policy_mode FAST)
    if(NOT _cpp_policy_sanitizer STREQUAL "none")
        set(_cpp_policy_link "-fsanitize=${_cpp_policy_sanitizer}")
        string(APPEND _cpp_policy_flags " ${_cpp_policy_link} -fno-omit-frame-pointer")
        set(_cpp_policy_mode DEBUG)
    endif()
    set(VCPKG_C_FLAGS "${_cpp_policy_flags}")
    set(VCPKG_CXX_FLAGS "${_cpp_policy_flags} -D_GLIBCXX_ASSERTIONS")
    string(APPEND VCPKG_CXX_FLAGS
        " -D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_${_cpp_policy_mode}")
    set(VCPKG_C_FLAGS_RELEASE "-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3")
    set(VCPKG_CXX_FLAGS_RELEASE "-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3")
    set(VCPKG_LINKER_FLAGS "${_cpp_policy_link}")
endif()

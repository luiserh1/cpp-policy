# cpp-policy's toolchain for dependencies (POLICY.md 1.1). The triplets in triplets/ load it:
# vcpkg builds each dependency with the same LLVM as the project, then vcpkg's own toolchain
# for the platform adds the triplet's flags.
#
# vcpkg keys its binary cache on this file's hash, the triplet's and the compiler's, so a
# change here rebuilds the dependencies. For the same reason this file includes nothing of
# cpp-policy's: vcpkg wouldn't notice a change to an included file.

# CPP_POLICY_LLVM_MAJOR in cmake/CppPolicy.cmake; a self-test keeps the two equal.
set(_cpp_policy_llvm_major 23)

# The folders the presets put first in PATH, so this finds the compiler the project uses. On
# Windows vcpkg builds with a clean environment, where the presets' PATH is gone.
if(CMAKE_HOST_WIN32)
    set(_cpp_policy_c_names clang-cl)
    set(_cpp_policy_cxx_names clang-cl)
    set(_cpp_policy_llvm_dirs "C:/Program Files/LLVM/bin")
else()
    set(_cpp_policy_c_names clang)
    set(_cpp_policy_cxx_names clang++)
    set(_cpp_policy_llvm_dirs /opt/homebrew/opt/llvm/bin /usr/local/opt/llvm/bin
        /usr/lib/llvm-${_cpp_policy_llvm_major}/bin)
endif()
find_program(CPP_POLICY_DEPS_C_COMPILER NAMES ${_cpp_policy_c_names}
    HINTS ${_cpp_policy_llvm_dirs} REQUIRED)
find_program(CPP_POLICY_DEPS_CXX_COMPILER NAMES ${_cpp_policy_cxx_names}
    HINTS ${_cpp_policy_llvm_dirs} REQUIRED)
execute_process(COMMAND "${CPP_POLICY_DEPS_CXX_COMPILER}" --version
    OUTPUT_VARIABLE _cpp_policy_version ERROR_QUIET)
if(NOT _cpp_policy_version MATCHES "clang version ${_cpp_policy_llvm_major}\\.")
    message(FATAL_ERROR "cpp-policy: dependencies are built with LLVM ${_cpp_policy_llvm_major}, "
        "like the project, but ${CPP_POLICY_DEPS_CXX_COMPILER} is:\n${_cpp_policy_version}"
        "Install LLVM ${_cpp_policy_llvm_major} where the presets look for it "
        "(cpp-policy README: Setup per platform).")
endif()
set(CMAKE_C_COMPILER "${CPP_POLICY_DEPS_C_COMPILER}")
set(CMAKE_CXX_COMPILER "${CPP_POLICY_DEPS_CXX_COMPILER}")

# With clang-cl, CMake calls lld-link directly, and lld-link doesn't add the AddressSanitizer
# runtime as the clang-cl driver would: without it every link step of a sanitized dependency
# (CMake's own compiler check included) fails with undefined __asan_* symbols. These are the
# options cmake/CppPolicy.cmake gives the project's programs.
if(CMAKE_HOST_WIN32 AND VCPKG_C_FLAGS MATCHES "/fsanitize=address")
    if(VCPKG_TARGET_ARCHITECTURE STREQUAL "x64")
        set(_cpp_policy_arch x86_64)
    elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
        set(_cpp_policy_arch aarch64)
    else()
        message(FATAL_ERROR "cpp-policy: AddressSanitizer with clang-cl supports x64 and arm64, "
            "not '${VCPKG_TARGET_ARCHITECTURE}'")
    endif()
    set(_cpp_policy_asan_options "")
    foreach(_cpp_policy_name IN ITEMS asan_dynamic asan_dynamic_runtime_thunk)
        set(_cpp_policy_file "clang_rt.${_cpp_policy_name}-${_cpp_policy_arch}.lib")
        execute_process(COMMAND "${CPP_POLICY_DEPS_C_COMPILER}"
            "/clang:-print-file-name=${_cpp_policy_file}"
            OUTPUT_VARIABLE _cpp_policy_path OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
        # clang prints the bare name back when it can't find the file.
        if(NOT IS_ABSOLUTE "${_cpp_policy_path}" OR NOT EXISTS "${_cpp_policy_path}")
            message(FATAL_ERROR "cpp-policy: ${CPP_POLICY_DEPS_C_COMPILER} can't find its "
                "AddressSanitizer runtime file ${_cpp_policy_file}; the LLVM installation is "
                "incomplete.")
        endif()
        # Forward slashes, which lld-link accepts: backslashes don't survive the linker flags
        # (C:\Program Files\... arrived as C:Program Files...).
        cmake_path(SET _cpp_policy_path "${_cpp_policy_path}")
        if(_cpp_policy_name STREQUAL "asan_dynamic")
            string(APPEND _cpp_policy_asan_options " \"${_cpp_policy_path}\"")
        else()
            string(APPEND _cpp_policy_asan_options " \"/wholearchive:${_cpp_policy_path}\"")
        endif()
    endforeach()
    string(APPEND _cpp_policy_asan_options " /include:__asan_seh_interceptor")
    foreach(_cpp_policy_kind IN ITEMS EXE SHARED MODULE)
        string(APPEND CMAKE_${_cpp_policy_kind}_LINKER_FLAGS_INIT "${_cpp_policy_asan_options}")
    endforeach()
    # CMake's compiler checks build in the Debug configuration unless told otherwise, even in a
    # Release build, and Debug means the debug C runtime (/MDd), which AddressSanitizer rejects.
    set(CMAKE_TRY_COMPILE_CONFIGURATION Release)
endif()

# vcpkg's toolchain for the platform, which applies the triplet's VCPKG_*_FLAGS. vcpkg.cmake
# always loads this file, so vcpkg's scripts folder is the parent of the includer's folder.
cmake_path(GET CMAKE_PARENT_LIST_FILE PARENT_PATH _cpp_policy_buildsystems)
cmake_path(GET _cpp_policy_buildsystems PARENT_PATH _cpp_policy_scripts)
if(CMAKE_HOST_WIN32)
    include("${_cpp_policy_scripts}/toolchains/windows.cmake")
elseif(CMAKE_HOST_APPLE)
    include("${_cpp_policy_scripts}/toolchains/osx.cmake")
else()
    include("${_cpp_policy_scripts}/toolchains/linux.cmake")
endif()

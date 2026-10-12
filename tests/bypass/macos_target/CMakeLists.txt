cmake_minimum_required(VERSION 3.29)
# A build for another macOS than the policy's: what a project gets without the presets, where
# the target is the machine's own.
set(CMAKE_OSX_DEPLOYMENT_TARGET 15.0)
project(bypass_macos_target LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
if(NOT APPLE)
    # The rule is for Macs only; the other systems have nothing to refuse.
    message(STATUS "cpp-policy builds for macOS: not checked on this system")
endif()
cpp_policy_add_checks()

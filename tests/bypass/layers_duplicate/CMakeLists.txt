cmake_minimum_required(VERSION 3.29)
project(bypass_layers_duplicate LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
cpp_policy_layers(LAYER lowlevel LAYER server lowlevel)
cpp_policy_add_checks()

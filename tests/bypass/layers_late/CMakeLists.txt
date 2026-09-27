cmake_minimum_required(VERSION 3.29)
project(bypass_layers_late LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
cpp_policy_add_checks()
# Too late: the audit's configuration is already written.
cpp_policy_layers(LAYER lowlevel)

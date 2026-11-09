cmake_minimum_required(VERSION 3.29)
project(bypass_sanitizer_ignorelist LANGUAGES CXX)
include("${POLICY_ROOT}/cmake/CppPolicy.cmake")

add_executable(app app.cpp)
cpp_policy_apply(app)
# A sanitizer ignore list switches checks off by function or file for the whole build, with no
# reason per line: refused, in each of its spellings and the old name.
target_compile_options(app PRIVATE -fsanitize-ignorelist=ignore.txt)
target_compile_options(app PRIVATE "SHELL:-fsanitize-system-ignorelist=ignore.txt")
set_source_files_properties(app.cpp PROPERTIES COMPILE_OPTIONS "-fsanitize-blacklist=ignore.txt")
cpp_policy_add_checks()

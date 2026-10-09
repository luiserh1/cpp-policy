# The library this project offers (POLICY.md 11.7). Its own CMakeLists.txt includes this file,
# and so does a project that uses it, so nothing here is about tests, checks or programs.
cpp_policy_library(geometry
    LAYER lowlevel
    LAYER shapes
    LAYER testing
    SOURCES
        lowlevel/clock.cpp
        shapes/area.cpp
    # What tests use, the library's own and its users': geometry::test_support.
    TEST_SUPPORT
        testing/samples.hpp
        testing/samples.cpp
    # Declared for the self-test of the check; this library links nothing.
    DEPENDENCIES zlib)

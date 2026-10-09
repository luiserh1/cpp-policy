# The library this project offers (POLICY.md 11.7). Its own CMakeLists.txt includes this file,
# and so does a project that uses it, so nothing here is about tests, checks or programs.
cpp_policy_library(geometry
    LAYER lowlevel
    LAYER shapes
    SOURCES
        lowlevel/clock.cpp
        shapes/area.cpp
    # Declared for the self-test of the check; this library links nothing.
    DEPENDENCIES zlib)

# Where the tidy cache is (POLICY.md 8), for tidy_cache.cmake and for CppPolicy.cmake, which
# prunes it: CPP_POLICY_TIDY_CACHE when set ("off" turns the cache off), or else "tidy" in
# cpp_policy_cache_root().
# The user's cache folder for cpp-policy, one per user and machine, shared by every checkout
# on it: the tidy cache, and the tests that needed a second run (test_times.cmake).
function(cpp_policy_cache_root out)
    if(CMAKE_HOST_APPLE)
        set(dir "$ENV{HOME}/Library/Caches/cpp-policy")
    elseif(CMAKE_HOST_WIN32)
        set(dir "$ENV{LOCALAPPDATA}/cpp-policy")
    elseif(DEFINED ENV{XDG_CACHE_HOME})
        set(dir "$ENV{XDG_CACHE_HOME}/cpp-policy")
    else()
        set(dir "$ENV{HOME}/.cache/cpp-policy")
    endif()
    file(TO_CMAKE_PATH "${dir}" dir)
    set(${out} "${dir}" PARENT_SCOPE)
endfunction()

function(cpp_policy_tidy_cache_dir out)
    if(DEFINED ENV{CPP_POLICY_TIDY_CACHE})
        set(dir "$ENV{CPP_POLICY_TIDY_CACHE}")
        if(NOT dir STREQUAL "off")
            file(TO_CMAKE_PATH "${dir}" dir)
        endif()
    else()
        cpp_policy_cache_root(root)
        set(dir "${root}/tidy")
    endif()
    set(${out} "${dir}" PARENT_SCOPE)
endfunction()

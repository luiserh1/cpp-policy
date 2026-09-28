# The library's sources are in src/, next to this file: the self-test downloads nothing.
vcpkg_cmake_configure(SOURCE_PATH "${CMAKE_CURRENT_LIST_DIR}/src")
vcpkg_cmake_install()
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(WRITE "${CURRENT_PACKAGES_DIR}/share/${PORT}/copyright" "cpp-policy self-test fixture (MIT)\n")

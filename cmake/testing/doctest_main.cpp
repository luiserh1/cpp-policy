// doctest's runner: main() and doctest's implementation, compiled once per build and linked
// into every test program cpp_policy_add_tests() makes (POLICY.md 13). It is kept out of the
// test files on purpose: compiled into the same file as the tests, doctest's implementation
// lets the static analyzer follow its string class and report leaks that aren't there.
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

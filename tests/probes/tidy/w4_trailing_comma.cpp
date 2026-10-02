// Waiting W4 (POLICY.md 12): clang-tidy's readability-trailing-comma reports the comma after an
// empty braced aggregate whose members have default member initializers as that list's own
// trailing comma, here in the middle of a list, where its fix would remove a comma the syntax
// needs. (Without the default member initializer in Inner it isn't reported.) The probe passes
// while clang-tidy still reports it.
struct Inner {
    int a{};
};
struct Outer {
    int first;
    Inner inner;
    int last;
};
Outer make() {
    return Outer{.first = 1, .inner = {}, .last = 2};
}

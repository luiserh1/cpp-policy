// Waiting W4 (POLICY.md 12): clang-tidy's readability-trailing-comma reports the comma after an
// empty braced value as that value's own trailing comma: here in a call's arguments, where its
// fix removes a comma the syntax needs. The same happens in a default argument, in an array's
// elements and in a designated initializer. The probe passes while clang-tidy still reports it.
struct Options {
    int width{};
};
int f(int a, Options options, int b) {
    return a + options.width + b;
}
int call() {
    return f(1, Options{}, 2);
}

int add(int a, int b);
[[clang::no_sanitize("undefined")]] int add(int a, int b) { return a + b; } // overflow wanted

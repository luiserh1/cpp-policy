__attribute__((no_address_safety_analysis)) int a(int x) { return x; } // reason given
[[clang::disable_sanitizer_instrumentation]] int b(int x) { return x; } // reason given
[[gnu::no_stack_protector]] int c(int x) { return x; } // reason given
__attribute__((nocf_check)) int d(int x) { return x; } // reason given
__declspec(safebuffers) int e(int x) { return x; } // reason given
__declspec(guard(nocf)) int f(int x) { return x; } // reason given
__attribute__((no_sanitize_address)) int g(int x) { return x; } // reason given

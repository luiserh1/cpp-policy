// POLICY 2.3: platform-dependent integer widths (long is 32 bits on Windows).
// EXPECT: google-runtime-int
long total(long a, long b) {
    return a + b;
}

// POLICY 2.5: const by default for locals that are not modified.
// EXPECT: misc-const-correctness
int doubled(int x) {
    int result = x * 2;
    return result;
}

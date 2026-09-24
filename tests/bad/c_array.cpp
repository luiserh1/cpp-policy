// POLICY 2.2: C arrays.
// EXPECT: cppcoreguidelines-avoid-c-arrays
int first() {
    const int values[3] = {1, 2, 3};
    return values[0];
}

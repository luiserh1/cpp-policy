// POLICY 2.3: C-style casts.
// EXPECT: modernize-avoid-c-style-cast
int truncate(double d) {
    return (int)d;
}

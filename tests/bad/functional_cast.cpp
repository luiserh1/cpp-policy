// POLICY 2.3: functional casts on non-class types.
// EXPECT: modernize-avoid-c-style-cast
int truncate(double d) {
    return int(d);
}

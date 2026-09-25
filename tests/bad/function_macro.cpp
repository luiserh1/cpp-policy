// POLICY 2.4: function-like macros.
// EXPECT: cppcoreguidelines-macro-usage
#define SQUARE(x) ((x) * (x))
int area(int side) {
    return SQUARE(side);
}

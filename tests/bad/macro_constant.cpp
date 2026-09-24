// POLICY 2.4: macros for constants.
// EXPECT: cppcoreguidelines-macro-usage
#define MAX_ITEMS 16

int limit() {
    return MAX_ITEMS;
}

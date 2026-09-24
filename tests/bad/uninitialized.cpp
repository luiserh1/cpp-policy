// POLICY 2.5: uninitialized variables.
// EXPECT: cppcoreguidelines-init-variables
int compute(bool flag) {
    int value;
    if (flag) {
        value = 1;
    } else {
        value = 2;
    }
    return value;
}

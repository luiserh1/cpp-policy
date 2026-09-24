// POLICY 2.1: owning raw pointers / new.
// EXPECT: cppcoreguidelines-owning-memory
int* make() {
    return new int{42};
}

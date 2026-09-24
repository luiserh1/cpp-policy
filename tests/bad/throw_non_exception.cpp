// POLICY 3: exceptions derive from std::exception.
// EXPECT: bugprone-std-exception-baseclass
void fail() {
    throw 42;
}

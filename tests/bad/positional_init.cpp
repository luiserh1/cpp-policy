// POLICY 2.10: an aggregate built positionally (use designated initializers, or give a
// small value type a constructor).
// EXPECT: modernize-use-designated-initializers
struct Size {
    int width;
    int height;
};
Size make_size() {
    return Size{4, 2};
}

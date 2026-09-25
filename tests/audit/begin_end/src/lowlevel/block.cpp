// NOLINTBEGIN(cppcoreguidelines-pro-bounds-pointer-arithmetic): caller guarantees size >= 3
int second(const int* p) { return *(p + 1); }
int third(const int* p) { return *(p + 2); }
// NOLINTEND(cppcoreguidelines-pro-bounds-pointer-arithmetic)

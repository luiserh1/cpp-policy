int f(const int* p) {
    return *(p + 1); // NOLINT(cppcoreguidelines-pro-bounds-pointer-arithmetic)
}

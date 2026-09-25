// Lines 1-4 contain ; [ ] and \ which CMake lists treat specially.
constexpr int values[2] = {1, 2}; // [x]; y
constexpr char slash = '\\';
constexpr char open = '[';
int f(const int* p) { return *(p + 1); } // NOLINT

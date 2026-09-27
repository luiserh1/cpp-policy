// POLICY 2.10: a reference data member (use a pointer set from a reference).
// EXPECT: cppcoreguidelines-avoid-const-or-ref-data-members
struct Options {
    int width = 0;
};
class Grid {
public:
    explicit Grid(const Options& options) : options_{options} {}
    int width() const { return options_.width; }

private:
    const Options& options_;
};

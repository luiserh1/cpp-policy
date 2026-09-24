// POLICY 2.6: single-argument constructors must be explicit.
// EXPECT: cppcoreguidelines-explicit-constructor
class Meters {
public:
    Meters(double value) : value_{value} {}
    [[nodiscard]] double value() const { return value_; }

private:
    double value_;
};

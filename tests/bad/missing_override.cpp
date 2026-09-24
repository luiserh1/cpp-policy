// POLICY 2.6: overrides use `override`.
// EXPECT: modernize-use-override
class Base {
public:
    Base() = default;
    Base(const Base&) = default;
    Base(Base&&) = default;
    Base& operator=(const Base&) = default;
    Base& operator=(Base&&) = default;
    virtual ~Base() = default;
    [[nodiscard]] virtual int id() const { return 0; }
};

class Derived : public Base {
public:
    [[nodiscard]] virtual int id() const { return 1; }
};

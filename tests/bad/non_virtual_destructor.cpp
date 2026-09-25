// POLICY 2.6: a base class with virtual functions needs a virtual destructor.
// EXPECT: cppcoreguidelines-virtual-class-destructor
class Base {
public:
    Base() = default;
    Base(const Base&) = default;
    Base(Base&&) = default;
    Base& operator=(const Base&) = default;
    Base& operator=(Base&&) = default;
    ~Base() = default;
    [[nodiscard]] virtual int id() const { return 0; }
};

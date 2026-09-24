// POLICY 2.6: no protected data members.
// EXPECT: cppcoreguidelines-non-private-member-variables-in-classes
class Widget {
public:
    [[nodiscard]] int size() const { return size_; }

protected:
    int size_ = 0;
};

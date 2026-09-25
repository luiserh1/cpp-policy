// POLICY 2.7: naming convention (types are PascalCase).
// EXPECT: readability-identifier-naming
class message_queue {
public:
    [[nodiscard]] int size() const { return size_; }

private:
    int size_ = 0;
};

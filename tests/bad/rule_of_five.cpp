// POLICY 2.6: rule of zero/five.
// EXPECT: cppcoreguidelines-special-member-functions
class Handle {
public:
    Handle() = default;
    Handle(const Handle& other) : id_{other.id_} {}
    ~Handle() { id_ = 0; }

private:
    int id_ = 0;
};

// POLICY 2.3: typedef.
// EXPECT: modernize-use-using
typedef unsigned int Id;

Id next(Id id) {
    return id + 1;
}

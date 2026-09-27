// No reason given for either.
void use(Base* base) {
    auto* derived = dynamic_cast<Derived*>(base);
    const auto& type = typeid(*base); // a comment, but not a reason
}

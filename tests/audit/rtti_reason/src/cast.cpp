// Comments may mention dynamic_cast<T> and typeid(x) freely.
void use(Base* base) {
    auto* derived = dynamic_cast<Derived*>(base); // rtti: plugin types are only known at run time
    const auto& type = typeid(*base);             // rtti: logged for diagnostics
    auto* other = my_dynamic_cast<Derived>(base);
}

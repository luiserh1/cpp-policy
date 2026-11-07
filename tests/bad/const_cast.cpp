// POLICY 2.3: const_cast outside a confined area.
// EXPECT: cppcoreguidelines-pro-type-const-cast
#include <string>

void append(const std::string& text) {
    const_cast<std::string&>(text) += "!";
}

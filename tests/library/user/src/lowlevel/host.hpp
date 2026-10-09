#pragma once

#include <string_view>

namespace lowlevel {

// This project's own lowlevel module: the library has one of the same name.
[[nodiscard]] std::string_view host_note();

} // namespace lowlevel

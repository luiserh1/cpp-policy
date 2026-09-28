#pragma once

#include <optional>
#include <string>
#include <string_view>

namespace lowlevel {

// The value of an environment variable, or nothing if it isn't set.
[[nodiscard]] std::optional<std::string> environment_variable(std::string_view name);

} // namespace lowlevel

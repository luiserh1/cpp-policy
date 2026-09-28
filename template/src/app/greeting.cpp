#include "app/greeting.hpp"

#include <format>

namespace app {

std::expected<std::string, GreetingError> greeting(std::string_view name) {
    if (name.empty()) {
        return std::unexpected{GreetingError::empty_name};
    }
    if (name.size() > max_name_length) {
        return std::unexpected{GreetingError::name_too_long};
    }
    return std::format("Hello, {}!", name);
}

std::string_view describe(GreetingError error) {
    switch (error) {
    case GreetingError::empty_name:
        return "the name is empty";
    case GreetingError::name_too_long:
        return "the name is too long";
    }
    return "unknown error";
}

} // namespace app

#include "app/greeting.hpp"
#include "check.hpp"
#include "lowlevel/environment.hpp"

#include <string>

namespace {

void run(test::Checker& check) {
    check.expect(app::greeting("Ada") == "Hello, Ada!", "a name is greeted");
    check.expect(app::greeting("").error() == app::GreetingError::empty_name,
                 "an empty name is an error");
    const std::string long_name(app::max_name_length + 1, 'x');
    check.expect(app::greeting(long_name).error() == app::GreetingError::name_too_long,
                 "a name over the limit is an error");

    check.expect(lowlevel::environment_variable("PATH").has_value(), "PATH is set");
    check.expect(!lowlevel::environment_variable("NO_SUCH_VARIABLE_4B1D").has_value(),
                 "an unset variable is nothing");
}

} // namespace

int main() {
    return test::run_tests(run);
}

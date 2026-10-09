// A test of the user's that takes its input from the library's test support.
#include "geometry/testing/samples.hpp"

#include "geometry/shapes/area.hpp"

#include <cstdlib>

int main() {
    const auto area = geometry::shapes::area(geometry::testing::sample_rectangle());
    return area.has_value() && *area == 12 ? EXIT_SUCCESS : EXIT_FAILURE;
}

#include "shapes.hpp"

namespace policy_sample {

std::vector<std::unique_ptr<Shape>> make_squares(std::span<const double> sides) {
    std::vector<std::unique_ptr<Shape>> shapes;
    shapes.reserve(sides.size());
    for (const double side : sides) {
        shapes.push_back(std::make_unique<Square>(side));
    }
    return shapes;
}

} // namespace policy_sample

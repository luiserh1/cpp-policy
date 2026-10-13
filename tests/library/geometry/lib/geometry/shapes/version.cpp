#include "geometry/shapes/area.hpp"

namespace geometry::shapes {

namespace {

constexpr std::string_view library_version = GEOMETRY_VERSION;

} // namespace

std::string_view version() {
    return library_version;
}

} // namespace geometry::shapes

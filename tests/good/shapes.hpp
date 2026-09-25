#pragma once

#include <memory>
#include <span>
#include <vector>

namespace policy_sample {

// A polymorphic base: copy and move are protected, so a Shape& can't be copied
// by accident, which would copy only the Shape part of a Square ("slicing").
class Shape {
public:
    Shape() = default;
    virtual ~Shape() = default;

    [[nodiscard]] virtual double area() const = 0;

protected:
    Shape(const Shape&) = default;
    Shape(Shape&&) = default;
    Shape& operator=(const Shape&) = default;
    Shape& operator=(Shape&&) = default;
};

class Square final : public Shape {
public:
    explicit Square(double side) : side_{side} {}
    [[nodiscard]] double area() const override { return side_ * side_; }

private:
    double side_;
};

// Ownership -> std::unique_ptr, created with std::make_unique.
[[nodiscard]] std::vector<std::unique_ptr<Shape>> make_squares(std::span<const double> sides);

} // namespace policy_sample

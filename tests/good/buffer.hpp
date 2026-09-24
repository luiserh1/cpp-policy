#pragma once

#include <cstdint>
#include <expected>
#include <memory>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace policy_sample {

enum class ParseError : std::uint8_t { empty, invalid_digit, overflow };

// Expected failure -> std::expected, not an exception.
[[nodiscard]] std::expected<int, ParseError> parse_int(std::string_view text);

// Non-owning view of a buffer -> std::span, not pointer + length.
[[nodiscard]] long long sum(std::span<const int> values);

class Shape {
public:
    Shape() = default;
    Shape(const Shape&) = default;
    Shape(Shape&&) = default;
    Shape& operator=(const Shape&) = default;
    Shape& operator=(Shape&&) = default;
    virtual ~Shape() = default;

    [[nodiscard]] virtual double area() const = 0;
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

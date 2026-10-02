// Benchmarks added to the generated project by tests/new_project/run.cmake: the benchmark kind
// must be built (and checked by clang-tidy) in every build, and run in Release builds. The
// project lists nanobench in vcpkg.json, so cpp_policy_add_tests() links it.
#include "app/greeting.hpp"

#include <cpp_policy/heap_bytes.hpp>
#include <cpp_policy/peak_memory.hpp>
#include <doctest/doctest.h>
#include <nanobench.h>

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>

namespace {

// Greets `count` names: the generated program's unit of work.
std::size_t greet_many(int count) {
    std::size_t total = 0;
    for (int i = 0; i < count; ++i) {
        const auto text = app::greeting("name " + std::to_string(i));
        if (text) {
            total += text->size();
        }
    }
    return total;
}

// A struct with members that have no default member initializer, built by naming only some
// (POLICY.md 2.10).
struct Row {
    const char* what;
    int count;
    std::string name;
    std::size_t at_least;
};

std::optional<std::size_t> greeted(const Row& row) {
    if (row.count <= 0) {
        return std::nullopt;
    }
    return greet_many(row.count);
}

} // namespace

// A table loop with eight assertions (cognitive complexity doesn't count them) and an optional
// read after REQUIRE (not reported in test programs), POLICY.md 13.4.
TEST_CASE("a table of greetings") {
    const std::array rows{
        Row{.what = "one", .count = 1, .at_least = 1},
        Row{.what = "ten", .count = 10, .at_least = 10},
    };
    for (const Row& row : rows) {
        CAPTURE(row.what);
        const auto total = greeted(row);
        REQUIRE(total.has_value());
        REQUIRE(row.count > 0);
        CHECK(*total >= row.at_least);
        CHECK(*total > 0);
        CHECK(row.name.empty());
        CHECK(row.what != nullptr);
        CHECK(row.at_least > 0);
        CHECK(row.count <= 10);
    }
}

TEST_CASE("memory stays flat as the number of greetings grows") {
    CHECK(greet_many(10'000) > 0);
    const auto first = cpp_policy::peak_memory_bytes();
    REQUIRE(first.has_value());
    CHECK(greet_many(40'000) > 0);
    const auto second = cpp_policy::peak_memory_bytes();
    REQUIRE(second.has_value());
    CHECK(*second <= *first + (*first / 10));
}

TEST_CASE("the heap stays flat as the number of greetings grows") {
    CHECK(greet_many(1'000) > 0); // anything set up once comes first
    cpp_policy::reset_peak_heap_bytes();
    CHECK(greet_many(1'000) > 0);
    const std::uint64_t few = cpp_policy::peak_heap_bytes();
    cpp_policy::reset_peak_heap_bytes();
    CHECK(greet_many(5'000) > 0);
    const std::uint64_t many = cpp_policy::peak_heap_bytes();
    CHECK(few > 0); // the counter is active: doctest itself holds some heap
    CHECK(many <= few + 1024);
}

TEST_CASE("greeting speed") {
    ankerl::nanobench::Bench bench;
    bench.title("greeting").unit("greeting").minEpochIterations(1000);
    bench.run("a short name", [] {
        auto text = app::greeting("Ada");
        ankerl::nanobench::doNotOptimizeAway(text);
    });
    CHECK_FALSE(bench.results().empty());
}

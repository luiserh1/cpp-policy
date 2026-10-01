// Benchmarks added to the generated project by tests/new_project/run.cmake: the benchmark kind
// must be built (and checked by clang-tidy) in every build, and run in Release builds. The
// project lists nanobench in vcpkg.json, so cpp_policy_add_tests() links it.
#include "app/greeting.hpp"

#include <cpp_policy/peak_memory.hpp>
#include <doctest/doctest.h>
#include <nanobench.h>

#include <cstddef>
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

} // namespace

TEST_CASE("memory stays flat as the number of greetings grows") {
    CHECK(greet_many(10'000) > 0);
    const auto first = cpp_policy::peak_memory_bytes();
    REQUIRE(first.has_value());
    CHECK(greet_many(40'000) > 0);
    const auto second = cpp_policy::peak_memory_bytes();
    REQUIRE(second.has_value());
    CHECK(*second <= *first + (*first / 10));
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

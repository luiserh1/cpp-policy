// The server recipe of POLICY.md 13.5 on a thread pool, the shape that broke the first recipe:
// each thread allocates a small table the first time it serves a request, as cpp-httplib's
// threads do, so the live heap rises until every thread has served one. A round here reaches
// 10 of the 32 threads, so warming up takes four rounds; one unmeasured round is not enough.
// The test warms up until a round leaves live_heap_bytes() no higher, and then the live heap
// must stay the same to the byte. A handler that keeps 64 bytes per request must never settle.
#include "cpp_policy/heap_bytes.hpp"

#include <array>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <mutex>
#include <print>
#include <set>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr std::size_t thread_count = 32;
constexpr std::size_t requests_per_connection = 100;
constexpr std::size_t requests_per_round = 1000;
constexpr int max_warm_up_rounds = 40;

// Requests go to the threads in turn, a connection of 100 at a time, so every run is the same.
class Pool {
public:
    explicit Pool(bool leaky) : leaky_{leaky} {
        workers_.reserve(thread_count);
        for (std::size_t index = 0; index < thread_count; ++index) {
            workers_.emplace_back(
                [this, index](const std::stop_token& stop) { work(index, stop); });
        }
    }

    // Serves one round and returns when every request is done and its memory freed.
    void round() {
        std::unique_lock lock{mutex_};
        for (std::size_t sent = 0; sent < requests_per_round; sent += requests_per_connection) {
            pending_.at(next_thread_) += requests_per_connection;
            next_thread_ = (next_thread_ + 1) % thread_count;
        }
        outstanding_ = requests_per_round;
        wake_.notify_all();
        done_.wait(lock, [this] { return outstanding_ == 0; });
    }

private:
    void work(std::size_t index, const std::stop_token& stop) {
        try {
            std::unique_lock lock{mutex_};
            while (wake_.wait(lock, stop, [this, index] { return pending_.at(index) > 0; })) {
                --pending_.at(index);
                lock.unlock();
                const std::size_t served = serve();
                lock.lock();
                if (leaky_) {
                    kept_.emplace_back(64, static_cast<char>('a' + (served % 26)));
                }
                if (--outstanding_ == 0) {
                    done_.notify_all();
                }
            }
        } catch (const std::exception& e) {
            std::println(stderr, "heap_pool: a worker stopped: {}", e.what());
        } catch (...) { // boundary: top of a thread
            std::println(stderr, "heap_pool: a worker stopped");
        }
    }

    // One request: a table allocated once per thread, and a body allocated and freed.
    static std::size_t serve() {
        thread_local const std::set<std::string> methods{
            "a method name too long for the small-string buffer: GET",
            "a method name too long for the small-string buffer: POST",
            "a method name too long for the small-string buffer: PUT",
        };
        const std::string body(512, 'x');
        return methods.size() + body.size();
    }

    bool leaky_;
    std::mutex mutex_;
    std::condition_variable_any wake_;
    std::condition_variable_any done_;
    std::array<std::size_t, thread_count> pending_{};
    std::size_t next_thread_{0};
    std::size_t outstanding_{0};
    std::vector<std::string> kept_;
    std::vector<std::jthread> workers_;
};

// Rounds until one leaves the live heap no higher than it found it: 0 if none did.
int warm_up(Pool& pool) {
    for (int rounds = 1; rounds <= max_warm_up_rounds; ++rounds) {
        const std::uint64_t before = cpp_policy::live_heap_bytes();
        pool.round();
        if (cpp_policy::live_heap_bytes() <= before) {
            return rounds;
        }
    }
    return 0;
}

int run() {
    bool ok = true;
    {
        Pool pool{false};
        const int rounds = warm_up(pool);
        const std::uint64_t settled = cpp_policy::live_heap_bytes();
        for (int i = 0; i < 5; ++i) {
            pool.round();
        }
        const std::uint64_t later = cpp_policy::live_heap_bytes();
        std::println("heap_pool: settled after {} rounds at {} bytes; {} after 5 more", rounds,
                     settled, later);
        if (rounds < 2) {
            std::println(stderr, "heap_pool: the warm-up didn't see the per-thread tables");
            ok = false;
        }
        if (later != settled) {
            std::println(stderr, "heap_pool: the live heap moved after the warm-up");
            ok = false;
        }
    }
    {
        Pool pool{true};
        const int rounds = warm_up(pool);
        if (rounds != 0) {
            std::println(stderr,
                         "heap_pool: a handler that keeps 64 bytes per request settled "
                         "after {} rounds",
                         rounds);
            ok = false;
        }
    }
    return ok ? EXIT_SUCCESS : EXIT_FAILURE;
}

} // namespace

int main() {
    try {
        return run();
    } catch (const std::exception& e) {
        std::fputs("unhandled exception: ", stderr);
        std::fputs(e.what(), stderr);
        std::fputs("\n", stderr);
    } catch (...) { // boundary: test program
        std::fputs("unhandled unknown exception\n", stderr);
    }
    return EXIT_FAILURE;
}

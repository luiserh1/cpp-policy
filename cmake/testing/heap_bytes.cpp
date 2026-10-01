// Counts the C++ heap by replacing the global operator new and operator delete
// (POLICY.md 13.5). Only the four functions the others call by default are replaced: array,
// nothrow and sized forms reach them. Each block counts at the size the allocator reports for
// it, so the delete needs no size. Sanitizers bring their own operator new, so in those
// builds nothing is replaced and the counters stay at 0. Code like this belongs in a confined
// area (POLICY.md 4); cpp-policy keeps it here so that projects' tests don't need their own.
#include "cpp_policy/heap_bytes.hpp"

#include <atomic>

#ifdef __has_feature
#if __has_feature(address_sanitizer) || __has_feature(thread_sanitizer)
#define CPP_POLICY_HEAP_NOT_COUNTED
#endif
#endif

#ifndef CPP_POLICY_HEAP_NOT_COUNTED
#include <cstddef>
#include <cstdlib>
#include <new>

#ifdef _WIN32
#include <malloc.h>
#elifdef __APPLE__
#include <malloc/malloc.h>
#else
#include <malloc.h>
#endif
#endif

namespace {

// NOLINTBEGIN(cppcoreguidelines-avoid-non-const-global-variables): the counters outlive every
// object, since operator delete runs during static destruction too
constinit std::atomic<std::uint64_t> live_bytes{0};
constinit std::atomic<std::uint64_t> peak_bytes{0};
// NOLINTEND(cppcoreguidelines-avoid-non-const-global-variables)

#ifndef CPP_POLICY_HEAP_NOT_COUNTED

void count_allocated(std::uint64_t size) noexcept {
    const std::uint64_t now = live_bytes.fetch_add(size, std::memory_order_relaxed) + size;
    std::uint64_t peak = peak_bytes.load(std::memory_order_relaxed);
    while (now > peak && !peak_bytes.compare_exchange_weak(peak, now, std::memory_order_relaxed)) {
    }
}

void count_freed(std::uint64_t size) noexcept {
    live_bytes.fetch_sub(size, std::memory_order_relaxed);
}

// NOLINTBEGIN(cppcoreguidelines-no-malloc,cppcoreguidelines-owning-memory,bugprone-unhandled-exception-at-new): this is the allocator: operator new can only be built on the C runtime's
[[nodiscard]] void* allocate(std::size_t size) noexcept {
    void* const block = std::malloc(size == 0 ? 1 : size);
    if (block != nullptr) {
#ifdef _WIN32
        count_allocated(_msize(block));
#elifdef __APPLE__
        count_allocated(malloc_size(block));
#else
        count_allocated(malloc_usable_size(block));
#endif
    }
    return block;
}

[[nodiscard]] void* allocate_aligned(std::size_t size, std::size_t alignment) noexcept {
    const std::size_t wanted = size == 0 ? 1 : size;
#ifdef _WIN32
    void* const block = _aligned_malloc(wanted, alignment);
    if (block != nullptr) {
        count_allocated(_aligned_msize(block, alignment, 0));
    }
    return block;
#else
    void* block = nullptr;
    // posix_memalign needs at least a pointer's alignment.
    const std::size_t at_least = alignment < sizeof(void*) ? sizeof(void*) : alignment;
    if (posix_memalign(&block, at_least, wanted) != 0) {
        return nullptr;
    }
#ifdef __APPLE__
    count_allocated(malloc_size(block));
#else
    count_allocated(malloc_usable_size(block));
#endif
    return block;
#endif
}

void release(void* block) noexcept {
    if (block == nullptr) {
        return;
    }
#ifdef _WIN32
    count_freed(_msize(block));
#elifdef __APPLE__
    count_freed(malloc_size(block));
#else
    count_freed(malloc_usable_size(block));
#endif
    std::free(block);
}

void release_aligned(void* block, [[maybe_unused]] std::size_t alignment) noexcept {
#ifdef _WIN32
    if (block == nullptr) {
        return;
    }
    count_freed(_aligned_msize(block, alignment, 0));
    _aligned_free(block);
#else
    release(block); // posix_memalign's blocks are freed with free()
#endif
}
// NOLINTEND(cppcoreguidelines-no-malloc,cppcoreguidelines-owning-memory,bugprone-unhandled-exception-at-new)

#endif

} // namespace

#ifndef CPP_POLICY_HEAP_NOT_COUNTED

// NOLINTBEGIN(misc-new-delete-overloads,cert-dcl54-cpp,cppcoreguidelines-owning-memory,readability-inconsistent-declaration-parameter-name): the replacements; the array, nothrow and sized forms are the standard library's, which call these
void* operator new(std::size_t size) {
    void* const block = allocate(size);
    if (block == nullptr) {
        throw std::bad_alloc{};
    }
    return block;
}

void* operator new(std::size_t size, std::align_val_t alignment) {
    void* const block = allocate_aligned(size, static_cast<std::size_t>(alignment));
    if (block == nullptr) {
        throw std::bad_alloc{};
    }
    return block;
}

void operator delete(void* block) noexcept {
    release(block);
}

void operator delete(void* block, std::align_val_t alignment) noexcept {
    release_aligned(block, static_cast<std::size_t>(alignment));
}
// NOLINTEND(misc-new-delete-overloads,cert-dcl54-cpp,cppcoreguidelines-owning-memory,readability-inconsistent-declaration-parameter-name)

#endif

namespace cpp_policy {

std::uint64_t live_heap_bytes() noexcept {
    return live_bytes.load(std::memory_order_relaxed);
}

std::uint64_t peak_heap_bytes() noexcept {
    return peak_bytes.load(std::memory_order_relaxed);
}

void reset_peak_heap_bytes() noexcept {
    peak_bytes.store(live_bytes.load(std::memory_order_relaxed), std::memory_order_relaxed);
}

} // namespace cpp_policy

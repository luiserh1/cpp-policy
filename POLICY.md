# C++ Project Policy

> **Status:** DRAFT v0.1, under review. Nothing here is enforced yet.
> Items marked **[REVIEW]** need an explicit decision.

This document defines the restricted, modern subset of C++ used by every
project that consumes `cpp-policy`. Most rules are enforced mechanically
(compiler warnings, clang-tidy, the suppression audit). This document is the
human-readable reference and the source of truth when a tool and this text
disagree.

---

## 1. Toolchain

| Item | Requirement |
|---|---|
| Language standard | **C++23**, compiler extensions **off** (`CMAKE_CXX_EXTENSIONS OFF`) |
| Compiler | **LLVM Clang** on all platforms: `clang++` on macOS/Linux, `clang-cl` on Windows |
| LLVM version | **23.x** (clang, clang-tidy and clang-format from the same release) **[REVIEW]** |
| Build system | CMake ≥ 3.29, driven only through `CMakePresets.json` |
| Generator | Ninja |
| Dependencies | vcpkg in manifest mode (`vcpkg.json`), only when a project needs them |

Notes:
- On macOS use Homebrew LLVM, not Apple Clang. Apple Clang has a different
  version scheme and doesn't ship clang-tidy.
- clang-tidy and clang-format are located next to the compiler, so all three
  always come from the same LLVM release.
- GCC and MSVC's own compiler (`cl.exe`) are not supported. They may be
  added later as extra build jobs without changing these rules.

## 2. Language subset

The baseline is the C++ Core Guidelines. The table lists what is banned in
normal code and what to use instead.

### 2.1 Memory and ownership

| Banned | Use instead |
|---|---|
| `new` / `delete`, `malloc` / `free` | Values, containers, `std::make_unique`, `std::make_shared` |
| Owning raw pointers | `std::unique_ptr` (default), `std::shared_ptr` (only for real shared ownership) |
| Raw pointer parameters that may be null *and* are required | References (`T&`, `const T&`) |
| Non-owning raw pointers | Allowed, meaning "optional, non-owning, may be null" |

### 2.2 Arrays, buffers and strings

| Banned | Use instead |
|---|---|
| C arrays `T x[N]` | `std::array<T, N>` |
| Pointer + length parameters | `std::span<T>` |
| Pointer arithmetic, `p[i]` on raw pointers | `std::span`, iterators, ranges, `std::mdspan` |
| `const char*` for strings | `std::string_view` (non-owning), `std::string` (owning) |
| Variadic C functions (`printf`, `va_arg`) | `std::format`, `std::print`, variadic templates |

### 2.3 Types and casts

| Banned | Use instead |
|---|---|
| C-style casts `(T)x`, functional casts `T(x)` on non-class types | `static_cast`, and in confined areas only: `reinterpret_cast`, `const_cast` |
| `reinterpret_cast` for type punning | `std::bit_cast`, `std::memcpy`, `std::start_lifetime_as` |
| Unions for type punning | `std::variant` (sum types), `std::bit_cast` (punning) |
| Implicit narrowing conversions | Brace initialization, explicit `static_cast`, `std::in_range` checks |
| `NULL`, `0` as a pointer | `nullptr` |
| `typedef` | `using` |

### 2.4 Preprocessor

| Banned | Use instead |
|---|---|
| Macros for constants | `constexpr` variables |
| Function-like macros | `constexpr` / `consteval` functions, templates |
| Include guards | `#pragma once` **[REVIEW]** |

Macros are still allowed for platform detection, build configuration and
include directives.

### 2.5 Initialization and declarations

- Always initialize variables. Uninitialized locals are an error.
- Prefer brace initialization `T x{...}`, except where it would select an
  `initializer_list` constructor unintentionally (for example, `std::vector<int> v(10)`).
- `auto` is allowed when the type is obvious from the right-hand side or
  irrelevant. It is not required everywhere.
- One declaration per line.
- `const` by default for locals that are not modified.

### 2.6 Classes

- Follow the **rule of zero**: prefer members that manage themselves. If you
  must write one special member function, write or `= default` / `= delete`
  all five.
- Single-argument constructors and conversion operators are `explicit`.
- Virtual functions in derived classes use `override` or `final`, never a
  repeated `virtual`.
- Base classes with virtual functions have a public virtual or protected
  non-virtual destructor.
- No `protected` data members.

## 3. Error handling

| Situation | Mechanism |
|---|---|
| Expected, recoverable failure (file not found, invalid input, parse error) | Return `std::expected<T, E>` |
| "No value" that is not an error | `std::optional<T>` |
| Truly exceptional failure (broken invariant in a dependency, out of memory, constructor cannot establish its invariant) | Throw an exception derived from `std::exception` |
| Programming bug (precondition violated) | `assert` / contract check in debug; a crash is acceptable |

- **Exceptions and RTTI are enabled** by default. A project may disable them
  through a `cpp-policy` option, for example for embedded targets.
- `dynamic_cast` and `typeid` are discouraged. Prefer virtual functions or
  `std::variant` + `std::visit`.
- Never ignore a returned `std::expected`. Functions returning it are
  `[[nodiscard]]`.
- `catch (...)` is only allowed at thread or program boundaries, and must log or
  rethrow.

## 4. Confined low-level areas

Some code legitimately needs banned constructs: custom allocators, memory
pools, lock-free structures, C API interop, memory-mapped I/O, hot parsing
loops.

- Such code lives only in designated directories. The default is `src/lowlevel/`.
  A project may declare more in its CMake configuration.
- Confined code exposes a **safe interface** (for example `std::span`,
  RAII types). Callers outside the area never see raw pointers or casts.
- Each confined file starts with a comment explaining why it needs to be
  there.

## 5. Suppressions

A suppression is any `NOLINT`, `NOLINTNEXTLINE`, `NOLINTBEGIN/END`, or
`#pragma clang diagnostic ignored`.

Rules, enforced by `tools/audit-suppressions`:

1. A suppression **must name the specific check**. A bare `// NOLINT` is rejected.
2. A suppression **must give a reason** after the check name:
   `// NOLINT(cppcoreguidelines-pro-bounds-pointer-arithmetic): parsing packed header in-place`
3. Suppressions are **only allowed inside confined areas** (section 4).
4. Wildcard suppressions (`NOLINT(*)`, `NOLINT(cppcoreguidelines-*)`) are rejected.

If code outside a confined area cannot satisfy a rule, either the code
moves into a confined area behind a safe interface, or the rule is
discussed and changed in `cpp-policy`. It is never silenced locally.

## 6. Policy files

The following files define enforcement and must not be weakened in a project:

- `.clang-tidy`, `.clang-format`
- `CMakePresets.json` and any CMake code that sets compile flags
- `tools/` scripts, git hook scripts
- `AGENTS.md`, `CLAUDE.md`, agent settings

A project may only **add** checks or **tighten** rules locally. Relaxing a rule
requires a change in `cpp-policy` itself.

## 7. Build configurations

| Preset | Purpose | Settings |
|---|---|---|
| `dev` | Daily work | Debug, warnings as errors, AddressSanitizer + UndefinedBehaviorSanitizer, standard library hardening (debug level) |
| `release` | Shipping | Optimized, warnings as errors, standard library hardening (fast level), `_FORTIFY_SOURCE=3`, `-fstack-protector-strong`, `-fcf-protection` where supported |
| `check` | The gate | Full build + full clang-tidy + format check + tests under sanitizers + suppression audit |

### 7.1 Warnings

Always on, always errors: `-Wall -Wextra -Wpedantic -Wshadow -Wnon-virtual-dtor
-Wold-style-cast -Wcast-align -Wunused -Woverloaded-virtual -Wconversion
-Wsign-conversion -Wnull-dereference -Wdouble-promotion -Wformat=2
-Wimplicit-fallthrough -Wzero-as-null-pointer-constant -Wextra-semi -Werror`.
With `clang-cl`, `/W4` replaces `-Wall -Wextra` (in `clang-cl`, `-Wall` means
`-Weverything`).

### 7.2 Standard library hardening

Each platform uses a different standard library, so the policy sets the
switch for all of them (each library ignores the others):

| Library | Where | Switch |
|---|---|---|
| libc++ | macOS | `_LIBCPP_HARDENING_MODE` |
| libstdc++ | Linux | `_GLIBCXX_ASSERTIONS` |
| Microsoft STL | Windows | `_MSVC_STL_HARDENING` |

### 7.3 Sanitizers on Windows (`clang-cl`)

Known limitations:
- AddressSanitizer **crashes on any `throw`**, even if caught. Code paths
  that throw can only be sanitizer-tested on macOS/Linux.
- ASan does not work with the debug C runtime, so the Windows `dev` preset
  uses the release runtime (`/MD`) with debug info.
- UBSan is not enabled on Windows.

## 8. Enforcement layers

| Layer | When | What |
|---|---|---|
| Editor (clangd) | While typing | clang-tidy diagnostics, formatting |
| Agent hook (Claude Code) | After each file edit | clang-tidy on the edited file |
| Git pre-commit | On commit | Format check, clang-tidy on changed files |
| Git pre-push | On push | Full `tools/check` |
| CI (future) | On push / PR | Same `tools/check` on all three OSes |

`tools/check` is the only definition of "passes the policy". Every other
layer is a faster subset of it.

### 8.1 What is not checked by tools

These rules rely on review (and on agents following `AGENTS.md`):
- `const char*` used as a string type (section 2.2)
- `catch (...)` only at boundaries (section 3); tools do enforce that
  exceptions never escape `main` or `noexcept` functions
- `dynamic_cast` / `typeid` being discouraged (section 3)

Every other rule in section 2 has a sample in `tests/bad/` proving it is
rejected.

## 9. AI agents

- Agent instructions live in `AGENTS.md`. `CLAUDE.md` only imports it.
- Agents must run `tools/check` before declaring work complete.
- Agents must not add suppressions, edit policy files (section 6), or bypass
  git hooks (`--no-verify`). Where the agent supports permission rules, this is
  also enforced technically.

## 10. Versioning

- `cpp-policy` uses semantic versioning. Projects pin a tag.
- **Major:** a new rule or tightened rule that can break existing code.
- **Minor:** new optional features, new presets, tooling improvements.
- **Patch:** fixes that don't change what passes or fails.

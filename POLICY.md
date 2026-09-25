# C++ Project Policy

> **Version:** the `project()` version in `CMakeLists.txt`; changes are listed in
> `CHANGELOG.md`. Enforced by the `cpp-policy` module, clang-tidy config and self-tests.

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
| LLVM version | **23.x** (clang, clang-tidy and clang-format from the same release) |
| Build system | CMake ≥ 3.29, driven only through `CMakePresets.json` |
| Generator | Ninja |
| Dependencies | vcpkg in manifest mode (`vcpkg.json`), only when a project needs them (section 1.1) |

Notes:
- On macOS use Homebrew LLVM, not Apple Clang. Apple Clang has a different
  version scheme and doesn't ship clang-tidy.
- clang-tidy and clang-format are located next to the compiler, so all three
  always come from the same LLVM release.
- GCC and MSVC's own compiler (`cl.exe`) are not supported. They may be
  added later as extra build jobs without changing these rules.

### 1.1 Dependencies

Prefer the standard library. Add a library only when it saves real work the
project would otherwise have to write and maintain. When one is needed:

- **License:** permissive open source only: MIT, BSD-2-Clause, BSD-3-Clause,
  Apache-2.0, BSL-1.0, Zlib, ISC, 0BSD, Unlicense, CC0-1.0. No GPL: projects
  link statically, so the GPL would cover the whole program. LGPL or any other
  license needs a review and a change to this list, made in cpp-policy.
- **Lightweight:** few dependencies of its own; header-only or small is
  better. Optional features stay off: every dependency sets
  `"default-features": false` and lists the features it uses in `"features"`.
- **Alive:** maintained (recent releases) and available in vcpkg's registry.
- **Recorded:** every dependency says why it is there, in a `"$reason"` field
  (vcpkg ignores fields that start with `$`).

```json
"dependencies": [
  {
    "name": "cpp-httplib",
    "default-features": false,
    "$reason": "HTTP server; header-only, MIT"
  }
]
```

Supply chain:
- Versions change only when a commit moves `builtin-baseline`. Before moving
  it, read what changed in the ports the project uses, and why.
- Don't use vcpkg binary caches you don't control: they replace the
  hash-checked build from source.
- cpp-policy itself is pinned by commit, not only by tag (section 10).

*Enforcement:* configuration fails if a `vcpkg.json` dependency is a plain
name, lacks `"default-features": false` or a `"$reason"`, or if any installed
package (dependencies of dependencies included) declares a license outside
the list, or none. Licenses come from the SPDX files vcpkg writes for every
package. Being lightweight and alive is review.

**`VCPKG_ROOT`:** the presets load vcpkg's toolchain from `$env{VCPKG_ROOT}`.
When the variable is missing (a new machine, CI, a git app that doesn't load
the shell profile), CMake's error only shows a path starting with `/scripts/`.
The policy module can't check it, since it is loaded after `project()`, which
is where the error happens. Projects that use vcpkg put this first in their
`CMakeLists.txt`:

```cmake
if(NOT DEFINED ENV{VCPKG_ROOT})
    message(FATAL_ERROR "VCPKG_ROOT is not set: set it to the vcpkg directory (README: Building).")
endif()
```

## 2. Language subset

The baseline is the C++ Core Guidelines. The table lists what is banned in
normal code and what to use instead.

### 2.1 Memory and ownership

| Banned | Use instead |
|---|---|
| `new` / `delete`, `malloc` / `free` | Values, containers, `std::make_unique`, `std::make_shared` |
| Owning raw pointers | `std::unique_ptr` (default), `std::shared_ptr` (only for real shared ownership) |
| Raw pointer parameters for arguments that must always be present | References (`T&`, `const T&`) |
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
| `reinterpret_cast` for type punning | `std::bit_cast`, `std::memcpy` |
| Unions for type punning | `std::variant` (sum types), `std::bit_cast` (punning) |
| Implicit narrowing conversions | Brace initialization, explicit `static_cast`, `std::in_range` checks |
| `NULL`, `0` as a pointer | `nullptr` |
| `typedef` | `using` |
| `short`, `long`, `long long` (and their `unsigned` forms) | `<cstdint>` fixed-width types (`std::int32_t`, `std::uint16_t`…) where the size matters; `std::size_t` for sizes and indexes; plain `int` for small counters and arithmetic |

`long` is 64 bits on macOS and Linux but 32 bits on Windows, so code that
stores a large value in a `long` works on one platform and silently truncates
on another. `int` is 32 bits on every supported platform.

### 2.4 Preprocessor

| Banned | Use instead |
|---|---|
| Macros for constants | `constexpr` variables |
| Function-like macros | `constexpr` / `consteval` functions, templates |
| Include guards | `#pragma once` (the audit requires it in every header) |

Macros are still allowed for platform detection, build configuration and
include directives.

**Modules are not used yet.** Code uses `#include`, not C++20 modules or
C++23 `import std`. Reasons, as of LLVM 23 and CMake 4.4:
- CMake's `import std` support is still experimental (behind
  `CMAKE_EXPERIMENTAL_CXX_IMPORT_STD`), and the policy promises reproducible
  builds.
- clang-tidy, the main enforcement layer, needs the compiled module files,
  and its integration with CMake for modules is immature.
- `clang-cl` with the Microsoft standard library lags behind the other
  platforms.
- Third-party libraries are headers anyway.

To be revisited when CMake makes `import std` stable.

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

### 2.7 Naming

| Kind | Style | Example |
|---|---|---|
| Classes, structs, enums, type aliases, template parameters | `PascalCase` | `LocalServer`, `Error`, `Sink` |
| Namespaces, functions, variables, parameters, constants, enum values | `snake_case` | `sls::server`, `max_message_bytes`, `Error::too_large` |
| Private and protected data members | `snake_case_` | `sink_`, `mutex_` |
| Public data members (plain structs) | `snake_case` | `Options::port` |
| Macros (where allowed) | `UPPER_CASE` | |
| File names | `snake_case` | `local_server.cpp` |

Enforced by clang-tidy (`readability-identifier-naming`), except file names,
which rely on review.

### 2.8 Concurrency

Most code runs on one thread. Add a thread only for a reason: blocking work
that must not stop the rest (a server loop, waiting for a signal), or a hot
spot that measurements show benefits from it.

| Banned | Use instead |
|---|---|
| `std::thread`, `detach()` | `std::jthread`: it joins when destroyed and can be asked to stop (`std::stop_token`) |
| Data written by one thread while another reads or writes it, without synchronization | A mutex that guards the data, a `std::atomic`, or no sharing: each thread owns its data and hands results over when it ends |
| `std::lock_guard`, manual `lock()` / `unlock()` | `std::scoped_lock` |
| Functions that are not thread-safe (`localtime`, `strtok`, `rand`…) | Their reentrant forms (`localtime_r` / `localtime_s`) or the C++ alternatives |
| Atomics beyond simple flags and counters, lock-free structures | Confined areas only (section 4) |

Rules:
- Keep critical sections short: prepare outside the lock, lock only to touch
  the shared data.
- Don't call code you don't control (callbacks, another object's virtual
  functions) while holding a lock; that is how deadlocks start. When two locks
  are needed, take them together with one `std::scoped_lock`.
- **Every thread function catches all exceptions at its top.** An exception
  that escapes a thread ends the program through `std::terminate`; `main`'s
  handlers never see it. Store it (`std::exception_ptr`) and rethrow it where
  the thread is joined, or report it there.
- A class that is safe to use from several threads says so in a comment.

*Enforcement:* clang-tidy rejects functions that are not thread-safe
(`concurrency-mt-unsafe`) and `std::lock_guard` (`modernize-use-scoped-lock`).
Data races are found at run time by ThreadSanitizer, in the `tsan` preset
(section 7), wherever tests exercise the code from several threads. The rest
is review (section 8.1). Parallel computation (parallel algorithms, thread
pools) is not covered yet.

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
- Never ignore a returned `std::expected` (enforced by clang-tidy). Mark
  functions that return it `[[nodiscard]]` so the compiler warns too.
- `catch (...)` is only allowed at thread or program boundaries, and must log or
  rethrow. Every thread function has such a boundary (section 2.8).

## 4. Confined low-level areas

Some code legitimately needs banned constructs: custom allocators, memory
pools, lock-free structures, C API interop, memory-mapped I/O, hot parsing
loops.

- Such code lives only in designated directories. The default is `src/lowlevel/`.
  A project may declare more in its CMake configuration.
- Confined code exposes a **safe interface** (for example `std::span`,
  RAII types). Callers outside the area never see raw pointers or casts.
- Each confined source file (`.cpp`) starts with a comment explaining why it
  needs to be there. Its header is the safe interface and needs no such
  comment.

## 5. Suppressions

A suppression is any of:
- a clang-tidy comment: `NOLINT`, `NOLINTNEXTLINE`, `NOLINTBEGIN` / `NOLINTEND`;
- a diagnostic pragma that turns a compiler warning off, in any spelling:
  `#pragma clang diagnostic ignored`, `#pragma warning(disable…)`, or the
  operator forms `_Pragma(...)` and `__pragma(...)`;
- a formatting switch: `// clang-format off`.

Rules, enforced by the suppression audit (the `policy-audit` target,
`cmake/scripts/audit_suppressions.cmake`):

1. A `NOLINT` **must name the specific check**. A bare `// NOLINT` is rejected.
2. Every suppression **must give a reason**:
   - `// NOLINT(cppcoreguidelines-pro-bounds-pointer-arithmetic): parsing packed header in-place`
     (`NOLINTEND` is exempt: its `NOLINTBEGIN` gives the reason);
   - `#pragma clang diagnostic ignored "-Wold-style-cast" // SIG_ERR is a C cast`;
   - `// clang-format off: columns aligned by hand`.
3. `NOLINT` and diagnostic pragmas are **only allowed inside confined areas**
   (section 4). `clang-format off` is allowed anywhere, since it only affects
   layout.
4. Wildcard suppressions (`NOLINT(*)`, `NOLINT(cppcoreguidelines-*)`) are rejected.

If code outside a confined area cannot satisfy a rule, either the code
moves into a confined area behind a safe interface, or the rule is
discussed and changed in `cpp-policy`. It is never silenced locally.

## 6. Policy files

The following files define enforcement and must not be weakened in a project:

- `.clang-tidy`, `.clang-format`
- `CMakePresets.json` and any CMake code that sets compile flags
- the git hooks in `tools/hooks/`, and any other `tools/` scripts
- `AGENTS.md`, agent settings (`.claude/settings.json`)

Rules can't be switched off from CMake either. At the end of configuration
the module checks that every target the project builds (fetched dependencies
and excluded directories aside) calls `cpp_policy_apply()` and keeps its
settings: no options that turn warnings off (`-Wno-…`, `/wd…`, `-w`) on
targets, source files or `CMAKE_CXX_FLAGS`, no `SKIP_LINTING`, and no changes
to `CXX_CLANG_TIDY`. Configuration fails otherwise.

Projects can't change the rules locally: their `.clang-tidy`,
`.clang-format` and git hooks (`tools/hooks/pre-commit`, `pre-push`) must
match the policy's (the audit compares them byte for byte), and the build
always uses the policy's copies of the configuration files. A project may only tighten what the module's options allow
(for example `CPP_POLICY_EXCEPTIONS OFF`). Any other change, stricter or
looser, is made in `cpp-policy` itself.

### 6.1 Repository files

- **`.gitignore` and `.gitattributes`:** cpp-policy's copies are the required
  minimum. A project's files must contain every line of them and may add their
  own (the audit checks it). They ignore build output, personal and editor
  state, and OS clutter, and force LF line endings on every platform.
- **Committed:** everything that defines the build and the rules:
  `CMakePresets.json`, `.clang-tidy`, `.clang-format`, `.gitignore`,
  `.gitattributes`, `vcpkg.json` (with its baseline, which pins dependency
  versions), `AGENTS.md` and agent settings.
- **Nothing editor-specific is committed** (`.vscode/`, `.idea/`, `.vs/`). The
  shared ground is `CMakePresets.json`, which Visual Studio, VS Code, CLion and
  Qt Creator read, and the generated `compile_commands.json`, which clangd
  reads in any editor.

## 7. Build configurations

| Preset | Purpose | Settings |
|---|---|---|
| `dev` | Daily work | Debug, warnings as errors, AddressSanitizer (with leak detection) + UndefinedBehaviorSanitizer, standard library hardening (debug level) |
| `release` | Shipping | Optimized, warnings as errors, standard library hardening (fast level), `_FORTIFY_SOURCE=3`, `-fstack-protector-strong`, `-fcf-protection` where supported |
| `check` | The gate | Full build + full clang-tidy + format check + tests under sanitizers + suppression audit |
| `debug` | Step-through debugging | Debug, no sanitizers, standard library hardening (debug level) |
| `tsan` | Data races | Debug, ThreadSanitizer, standard library hardening (debug level); macOS and Linux only |

Windows presets carry a `win-` prefix. On Windows, `win-dev` and `win-check`
are optimized (`RelWithDebInfo`, see 7.3), so `win-debug` is the one to step
through. The `release` workflow runs the tests on the optimized build, where
some bugs only appear; it is meant for CI rather than every push. So is the
`tsan` workflow: ThreadSanitizer can't be combined with AddressSanitizer, so
it needs a build of its own, and `clang-cl` doesn't provide it.

Test presets:
- Every test has a 60-second timeout, so a hung test fails instead of holding
  up a push (CTest's own default is 25 minutes). A project may set a shorter
  `TIMEOUT` on its tests.
- The `dev` and `check` test presets turn on AddressSanitizer's leak
  detection (`ASAN_OPTIONS=detect_leaks=1`). It is on by default on Linux and
  off on macOS; `clang-cl` doesn't provide it.

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
| Agent hook (Claude Code), planned | After each file edit | clang-tidy on the edited file |
| Git pre-commit | On commit | Suppression audit and format check; warns when files have unstaged changes, since it checks the working folder |
| Git pre-push | On push | The full gate (below); refuses to run with uncommitted changes, so it tests exactly what is pushed |
| CI, planned | On push / PR | The same gate on all three OSes |

The git hooks come from cpp-policy (`tools/hooks/`); projects copy them
unchanged and enable them once per clone with `git config core.hooksPath
tools/hooks`. Configuration warns while a clone hasn't done so.

The gate is `cmake --workflow --preset check` (`win-check` on Windows):
configure, build with clang-tidy, audit, format check, and tests under
sanitizers. It is the only definition of "passes the policy". Every other
layer is a faster subset of it.

### 8.1 What is not checked by tools

These rules rely on review (and on agents following `AGENTS.md`):
- `const char*` used as a string type (section 2.2)
- File names in `snake_case` (section 2.7)
- Pointer + length parameters (section 2.2): no check flags the signature,
  but indexing the pointer is caught as pointer arithmetic
- `catch (...)` only at boundaries (section 3); tools do enforce that
  exceptions never escape `main` or `noexcept` functions
- `dynamic_cast` / `typeid` being discouraged (section 3)
- `[[nodiscard]]` on functions returning `std::expected` (section 3); ignoring
  the result is enforced, the attribute itself is not
- The "why" comment at the top of confined source files (section 4)
- Concurrency (section 2.8): `std::thread` and `detach()`, lock scope and
  order, and the catch at the top of every thread function; data races are
  found at run time by the `tsan` preset only where tests exercise them
- Project structure (section 11): layer dependency direction and file size
  limits are planned audit checks; the helper extraction rule and comment
  accuracy will always rely on review

Every other rule in section 2, and the function size limits of section 11.3,
has a sample in `tests/bad/` proving clang-tidy rejects it (one of them in a
header, proving headers are checked). The rules enforced by the audit, such
as `#pragma once` and suppressions, have fixtures in `tests/audit/`.

## 9. AI agents

- Agent instructions live in `AGENTS.md`. Projects don't have a `CLAUDE.md`:
  Claude Code (v2.1.277 or later) reads `AGENTS.md` directly, but only when no
  `CLAUDE.md` exists, so adding one would hide `AGENTS.md` from it. Agent
  settings deny creating `CLAUDE.md`.
- Agents must run the gate (`cmake --workflow --preset check`, section 8)
  before declaring work complete.
- Agents must not add suppressions, edit policy files (section 6), or bypass
  git hooks (`--no-verify`).
- Where the agent supports permission rules, they back these rules up, but
  only partly: they block the agent's own file-editing tools and the
  `--no-verify` flag, not every shell command that could do the same (such as
  `sed -i` on a policy file, or `git -c core.hooksPath=…`). What an agent
  can't be stopped from doing is caught afterwards: the audit rejects edited
  copies of the policy files and hooks, configuration rejects weakened build
  settings, and CI (planned) will run the gate again. Agent settings are a
  guide, not a security boundary.

## 10. Versioning

- `cpp-policy` uses semantic versioning. Projects pin a tag.
- The version is defined once, in `project(cpp_policy VERSION ...)` in
  `CMakeLists.txt`. A release commit sets it, adds the release to
  `CHANGELOG.md` (each change with its reason), updates the tag in the
  `README.md` example, and is tagged `v<version>`.
- **Major:** a new rule or tightened rule that can break existing code.
- **Minor:** new optional features, new presets, tooling improvements.
- **Patch:** fixes that don't change what passes or fails.
- **Before 1.0**, the minor version takes the major's role: `0.x` to
  `0.(x+1)` may break existing code, while patch releases still never do.

## 11. Project structure

These rules keep a codebase navigable as it grows, especially when AI agents
make many small changes. Adapted from the Carreritas project.

### 11.1 Layers and dependency direction

- Source code is split into modules, one directory each under `src/`
  (for example `src/message/`, `src/server/`).
- Each project groups its modules into **layers** and documents them in its
  `README.md` (and `AGENTS.md`), from lowest to highest.
- Dependencies point **one way only**: a module may include headers from its
  own layer's modules or from lower layers, never from higher ones.
- `src/lowlevel/` (section 4) is always the lowest layer: it may not include
  any other project module.
- `main.cpp` is the top: it may include anything.
- Includes are written from the `src/` root (`#include "server/local_server.hpp"`),
  never with relative paths (`"../server/..."`), so the direction of every
  dependency is visible in the include line.

*Enforcement:* planned. The audit will read the layer list from CMake and
reject includes that point upward.

### 11.2 No catch-all utility modules

- No `utils`, `helpers`, `common` or `misc` modules. Shared code goes in a
  module named after what it does (`text_encoding`, `time_format`).
- A helper stays private to its file (anonymous namespace) by default.
- Extract a helper into a shared module only when **all** of these hold:
  - it has at least two real users in different modules;
  - its meaning is stable and independent of any one caller's domain;
  - the destination module has a single, focused responsibility.
- If extracting would create a broad, mixed-purpose API, keep the helper local,
  even at the cost of a small duplication.

*Enforcement:* review.

### 11.3 File size

| Threshold | Lines per `.cpp` / `.hpp` file | Meaning |
|---|---|---|
| Target | ≤ 250 | Normal size |
| Review | > 350 | Split by responsibility before adding more |

- When a new feature would push a file past the target, split the file by
  responsibility first, then add the feature.
- Functions are limited separately by clang-tidy: at most 80 lines, 6
  parameters and 4 levels of nesting (`readability-function-size`), and a
  cognitive complexity of 25 (`readability-function-cognitive-complexity`).

*Enforcement:* planned. The audit will report files over the review threshold.

### 11.4 Comment accuracy

- Comments describe the **current** behavior, never its history ("used to",
  "now also").
- When code changes, related comments change in the same commit.
- Prefer describing meaning over repeating values that live in constants
  ("at most `max_message_bytes`", not "at most 4096 bytes").
- Temporary behavior is marked with `TODO:` and enough context for someone
  else to resolve it.
- Don't comment what the code already says clearly; comment why.

*Enforcement:* review.

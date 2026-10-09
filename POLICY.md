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
| Microsoft toolset (Windows) | **MSVC 14.44** (Visual Studio 2022 17.14) or later: the standard library, runtime and libraries `clang-cl` builds with |
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
- **The standard library is part of the toolchain.** clang-tidy analyzes the
  library's code along with the project's, so the same code can get different
  findings with another version of it. ToneMatcher's first CI runs had five
  such findings, each seen on one library only. On Windows the library comes
  with the Microsoft toolset, not with LLVM, so CI pins it as well:
  - Self-hosted Windows runners have exactly the toolset `gate.yml` names
    (`MSVC_TOOLSET`, now 14.44), and only that one, since vcpkg's port builds
    pick a toolset on their own. The gate stops a job on a runner with another
    toolset. The pin changes only in a cpp-policy release, like
    `LLVM_VERSION` (section 10.1). 14.44 is the last Visual Studio 2022 release, which only
    gets servicing updates, so the pin needs no upkeep.
  - GitHub's Windows image updates its own, newer toolset every few weeks.
    cpp-policy's own CI keeps it, so findings from a newer library show up
    there before any project moves to it.
  - Every CI job prints its standard library's version (MSVC toolset,
    libstdc++ or libc++), so a difference between two runs can be traced.

  On Linux the library is the distribution's libstdc++; on macOS it is
  libc++, which comes with LLVM and so is pinned with it.

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

**Dependencies are built like the project.** vcpkg's own triplets build
each dependency with the system's compiler and none of the policy's settings.
Measured on macOS with a small C and C++ library: Apple Clang compiled it,
against Apple's libc++ 22 while the project used LLVM's libc++ 23 (two
versions of the standard library in one program), with basic stack
protection, and no AddressSanitizer. A program built with AddressSanitizer
that handed it a 16-byte buffer with a size of 17 ran to the end. On Windows
the compiler would be MSVC's `cl.exe`.

So vcpkg builds dependencies with cpp-policy's triplets, which `tools/vcpkg/`
holds:

| Triplet | Presets | Dependencies get |
|---|---|---|
| `cpp-policy-asan` | `dev`, `check`, `win-check` | AddressSanitizer, standard library hardening `debug` |
| `cpp-policy-tsan` | `tsan` | ThreadSanitizer, standard library hardening `debug` |
| `cpp-policy-nosan` | `release`, `debug`, `win-release`, `win-debug` | No sanitizer, standard library hardening `fast` |

All three compile with the same LLVM as the project (`llvm.cmake` looks where
the presets do and fails on any other major version), and add the policy's
security hardening: `-fstack-protector-strong`, `-fcf-protection` on x64 and
`_FORTIFY_SOURCE=3` in optimized builds on Linux and macOS, Control Flow
Guard in optimized builds on Windows. Dependencies often parse untrusted
input (zlib decompresses whatever a file contains), so they get the same
protection as the project's code.

- **Sanitizers match the preset** because each one fails with code it didn't
  instrument: AddressSanitizer misses an overread inside the dependency
  (above), libc++ reports false container overflows when uninstrumented code
  resizes a container, and ThreadSanitizer misses races and reports false
  ones.
- **UndefinedBehaviorSanitizer stays out of dependencies.** It would stop the
  program on a dependency's own undefined behavior, which the project can't
  fix. AddressSanitizer is what catches the project's mistakes at the
  boundary: a wrong size or a freed buffer handed to the library.
- **The triplets build for the machine they run on** (x64 or arm64, Linux,
  macOS or Windows); the policy doesn't cross-compile. On Windows the `asan`
  triplet builds only the release configuration, the one `win-check` uses.
  vcpkg's *host* triplet, for tools that run during a build (such as
  `vcpkg-cmake`), stays vcpkg's default with the system's compiler: nothing
  built with it goes into the program.
- **A build folder can change triplet** (other sanitizer options, or an
  upgrade from before v0.15.0). vcpkg then replaces the dependencies, and
  `setup.cmake` clears the cached paths that `find_path`, `find_library` and
  find modules such as `FindZLIB` kept into the old ones, so no `--fresh` is
  needed.
- **Upgrades rebuild them.** vcpkg keys its binary cache on the hashes of the
  triplet, `llvm.cmake` and the compiler, so a release that changes how
  dependencies are built, or a new LLVM, rebuilds them. For the same reason
  the files include nothing else: vcpkg wouldn't notice a change to an
  included file, so the three triplets repeat the same code and differ only
  in the line that names their sanitizer.

**Loading vcpkg:** vcpkg installs the dependencies in `project()`, before the
policy module is fetched, so projects keep `tools/vcpkg/` as an unchanged
copy (section 6) and load it in their `CMakeLists.txt`, before `project()`:

```cmake
include("${CMAKE_CURRENT_SOURCE_DIR}/tools/vcpkg/setup.cmake")
```

`setup.cmake` picks the triplet from the preset's sanitizer options, and
fails with a clear message when `VCPKG_ROOT` is missing (a new machine, CI, a
git app that doesn't load the shell profile), where CMake's own error only
shows a path starting with `/scripts/`. A `-DCMAKE_TOOLCHAIN_FILE` given on
the command line still wins; the triplet doesn't, since dependencies built
differently from the project are what this section prevents.

*Enforcement:* the audit fails when a project with a `vcpkg.json` lacks
`tools/vcpkg/` or has edited it. The self-test builds a small vcpkg project
in each of the check, tsan and release workflows, on each system, and checks
how its dependency was compiled and that AddressSanitizer catches the
overread above.

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

A non-owning raw pointer means "optional, may be null", with one exception: a
data member set from a reference in the constructor and commented
`// never null` (section 2.10). References can't be data members.

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

Tracked as W1 in section 12.

### 2.5 Initialization and declarations

- Always initialize variables. Uninitialized locals are an error.
- Prefer brace initialization `T x{...}`, except where it would select an
  `initializer_list` constructor unintentionally (for example, `std::vector<int> v(10)`).
- `auto` is allowed when the type is obvious from the right-hand side or
  irrelevant. It is not required everywhere.
- One declaration per line.
- `const` by default for locals that are not modified. Types whose
  const-ness differs between standard libraries are exempted from the check
  (`misc-const-correctness.AllowedTypes` in `.clang-tidy`), because the
  `const` one library asks for, the other rejects. The list:
  - `std::stop_source`: libstdc++ (GCC 16, `<stop_token>`) declares
    `request_stop()` `const`; libc++ and the standard don't.

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
- A condition variable needs `std::unique_lock`: it unlocks while waiting,
  which `std::scoped_lock` can't. That is the one place for it.
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
pools) is not covered yet (W3, section 12).

### 2.9 Formatting

Formatting is clang-format's job (`.clang-format`, checked by the gate): LLVM
style with 4-space indents and a limit of **100 columns**. The limit was
reviewed after the first real use: about 5% of lines go past 90 columns, and
only `NOLINT` comments (which clang-format doesn't wrap, section 5) and text
embedded in the code go past 100. 80 would rewrap about one line in nine;
120 is too wide for side-by-side diffs and phone screens.

`sh tools/hooks/tidy-files --format <file>...` formats the files named, and
`cmake --build --preset check --target policy-format-fix` every source. Both
only format: neither changes what the code says.

### 2.10 Idioms clang-tidy leads to

Some checks accept only one way of writing common code, and a first
clang-tidy run on code written without them reports hundreds of findings.
Check each C++ file right after editing it with `sh tools/hooks/tidy-files
<file>...` (section 8), not once the program works. The forms below pass; `tests/good/idioms.cpp` has each one, and
`tests/bad/` shows what the checks reject.

- **Initializing structs** (`modernize-use-designated-initializers`). A
  struct is built with designated initializers:
  `Options{.width = 4, .height = 2}`. A small type that is just a value (a
  color, a point, a size), written positionally in loops and tests, gets a
  `constexpr` constructor instead, so `Rgb{255, 0, 0}` stays short. A
  constructor makes the type a non-aggregate, which the check ignores.
  - **Fields may be left out.** A field that isn't named takes its default
    member initializer, or zero if it has none (an empty string, a null
    pointer, a nested struct of zeros). That is a rule of the language, so it
    holds at every optimization level: a `static_assert` on such a field
    passes, and at `-O0` to `-O3` the fields read 0 where a plain
    `Result r;` read garbage. The policy turns
    `-Wmissing-designated-field-initializers` off for this (7.1). What that
    gives up: when a field is added later, the places that build the struct
    without naming it aren't reported.
- **Members that refer to another object**
  (`cppcoreguidelines-avoid-const-or-ref-data-members`). Reference members
  are rejected: they break assignment. The constructor takes a reference and
  stores its address, and the member says it is never null:
  ```cpp
  explicit Grid(const Size& size) : size_{&size} {}
  const Size* size_; // never null: set from a reference
  ```
  `std::reference_wrapper` works too but needs `.get()` on every use.
- **Numbers from text with `std::from_chars`.** `data() + size()` is pointer
  arithmetic, and `data()` on a `std::string_view` trips
  `bugprone-suspicious-stringview-data-usage`. `std::to_address` gives both
  ends without either:
  ```cpp
  const char* const end = std::to_address(text.end());
  const auto [last, error] = std::from_chars(std::to_address(text.begin()), end, value);
  ```
- **Trailing commas aren't checked** (Waiting W4, section 12).
  `readability-trailing-comma` is off: it takes the comma after an empty
  braced value (`f(a, Options{}, b)`) for a trailing one, and its fix removes
  it. clang-format still decides the layout, and a trailing comma still
  keeps a list one element per line; write one where that reads better.
- **Flag enumerations of a C library** (`bugprone-signed-bitwise`).
  `FlagA | FlagB` on a plain C `enum` is refused, because its type is
  signed. The cast to unsigned belongs with the library, in the confined
  module that wraps it (section 4): one helper there, not a cast at each use.
- **Smaller ones:** `enum class E : std::uint8_t` for small enums
  (`performance-enum-size`); parentheses around a product added to something
  (`(y * width) + x`, `readability-math-missing-parentheses`); `reserve()`
  before a loop of `push_back`s (`performance-inefficient-vector-operation`);
  the same parameter names in a declaration and its definition.
- **Checks that don't follow the code:**
  `bugprone-unchecked-optional-access` doesn't see `emplace()` or a check made
  by the caller; check and dereference in the same function.
  `misc-const-correctness` asks for `const` on a local passed to a template
  parameter's call operator. Rewrite the code in both cases: suppressions
  outside confined areas aren't allowed (section 5).
- **Checks that depend on the standard library.** clang-tidy reads each
  platform's standard library, so the same code can pass on one system and
  fail on another (section 8). Seen so far, each costing a CI round:
  - **Environment variables:** the Windows C runtime deprecates `getenv`, a
    warning and so an error. Read them in a confined area: `getenv_s` into a
    `std::string` on Windows, `getenv` with a named suppression elsewhere
    (`concurrency-mt-unsafe`).
  - **The whole environment:** glibc declares `environ` in `<unistd.h>`, so
    declaring it yourself is `readability-redundant-declaration` on Linux,
    while macOS declares nothing. Use `*_NSGetEnviron()` (`<crt_externs.h>`)
    on macOS and `environ` from `<unistd.h>` elsewhere.
  - **Stream open modes:** the Microsoft library's `std::ios` flags are
    `int`s, so combining them (`std::ios::binary | std::ios::trunc`) is
    `bugprone-signed-bitwise` there. Pass one flag: an `std::ofstream`
    already truncates.
  - **Searching:** the Microsoft library routes `std::ranges::find` on a
    trivially comparable element of 3 bytes (or any size other than 1, 2,
    4 or 8) to a vectorized search that fails to compile. Use
    `std::ranges::any_of` with a comparison.
  - **Moving a `std::map`:** the Microsoft library allocates when node
    containers (`map`, `set`, `list`, the unordered ones) are moved, and
    reports allocation failure with `std::bad_array_new_length`. Like
    `std::bad_alloc`, the policy's `.clang-tidy` doesn't count it as an
    escaping exception (`bugprone-exception-escape`), so such members are
    fine everywhere.

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
  `std::variant` + `std::visit`. Where one is needed, give the reason on the
  same line: `dynamic_cast<Plugin*>(p); // rtti: plugins come from outside`
  (the audit checks it).
- Never ignore a returned `std::expected` (enforced by clang-tidy). Mark
  functions that return it `[[nodiscard]]` so the compiler warns too.
- `catch (...)` is only allowed at thread or program boundaries, and must log or
  rethrow. Every thread function has such a boundary (section 2.8). Name the
  boundary on the same line: `} catch (...) { // boundary: thread top` (the
  audit checks it; clang-tidy's `bugprone-empty-catch` rejects an empty
  handler).

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
- a formatting switch: `// clang-format off`;
- a sanitizer suppression: an entry in a sanitizer's suppression list.

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
5. Sanitizer suppressions exist only in cpp-policy
   (`cmake/sanitizers/lsan.supp`, applied by the `dev` and `check` test
   presets). Each entry is a proven false positive inside the operating
   system or the sanitizer runtime, never project or library code, and says
   how it was shown to be false; the self-test reproduces it. Projects can't
   add their own.
6. **A test doesn't set a sanitizer's options.** `ASAN_OPTIONS`,
   `LSAN_OPTIONS` and the like in a test's environment are rejected at
   configuration: `detect_leaks=0` there switched a check off where nothing
   showed it.
   - The one case with a way through: a test program that opens a window.
     On macOS, LeakSanitizer then reports what AppKit and CoreFoundation
     keep for the life of the process (Alfar: 949 reports, 3.5 MB, none from
     the project, GLFW or Dear ImGui). Suppressing those by library would
     also hide a leak of the project's own under a callback, so they aren't
     in `lsan.supp`.
   - Such a program is declared with
     `cpp_policy_add_tests(integration <module> … NO_LEAK_CHECK "<reason>")`.
     Every configure prints that LeakSanitizer is off for it, and why. Not
     for unit tests. AddressSanitizer and UndefinedBehaviorSanitizer stay
     on. What is lost: a leak in the code those tests run, so keep them to
     what needs the window.

**Third-party code.** clang-tidy ignores headers under `/_deps/`,
`/vcpkg_installed/`, `/third_party/` and `/external/`, except for one kind of
finding: the static analyzer follows calls into a header, and reports what it
finds there when the path starts in the project. A single-header C library
such as stb_image, compiled into the project, gets findings located in its
header but reported against the project's calling line. That call belongs in
a confined area anyway (it passes pointers and lengths), so it takes a
`NOLINT` there, naming the analyzer check, on the calling line
(`tests/good/lowlevel/c_library.cpp`). The library itself is never edited.

If code outside a confined area cannot satisfy a rule, either the code
moves into a confined area behind a safe interface, or the rule is
discussed and changed in `cpp-policy`. It is never silenced locally.

## 6. Policy files

The following files define enforcement and must not be weakened in a project:

- `.clang-tidy`, `.clang-format`
- `CMakePresets.json` and any CMake code that sets compile flags
- the git hooks in `tools/hooks/`, and any other `tools/` scripts
- with dependencies, `tools/vcpkg/` (how vcpkg builds them, section 1.1)
- `AGENTS.md`, agent settings (`.claude/settings.json`)
- CI workflows (`.github/workflows/`)

Rules can't be switched off from CMake either. At the end of configuration
the module checks that every target the project builds (fetched dependencies
and excluded directories aside) calls `cpp_policy_apply()` and keeps its
settings:
- no options that turn warnings off (`-Wno-…`, `/wd…`, `-w`) on targets,
  source files or `CMAKE_CXX_FLAGS`;
- no options or definitions that weaken a protection the policy turns on:
  `-fno-stack-protector` (or the weaker `-fstack-protector`),
  `-fcf-protection=none`, `_FORTIFY_SOURCE` below 3, a standard-library
  hardening macro turned off, `-fno-sanitize=…`, and `clang-cl`'s `/GS-`,
  `/guard:cf-` and `/sdl-`; `CPP_POLICY_HARDENING` has no "off" value (7.2);
- no `SKIP_LINTING`, and no changes to `CXX_CLANG_TIDY`.

Configuration fails otherwise.

Projects can't change the rules locally: their `.clang-tidy`,
`.clang-format`, `CMakePresets.json`, git hooks (`tools/hooks/`) and, with a
`vcpkg.json`, vcpkg files (`tools/vcpkg/`) must match the policy's (the audit
compares them byte for byte, and
`tools/upgrade.sh` copies them), and the build
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
| `release` | Shipping | Optimized, warnings as errors, standard library hardening (fast level), `_FORTIFY_SOURCE=3`, `-fstack-protector-strong`, `-fcf-protection` where supported; with `clang-cl`, Control Flow Guard (`/guard:cf`) on top of its default stack cookies (7.4) |
| `check` | The gate | Full build + full clang-tidy + format check + tests under sanitizers + suppression audit; like `dev`, but compiled at `-O1` so the tests run 15 to 21 times faster (14.1) |
| `unit` | Quick check while working | Like `check` without clang-tidy, the audit and the format check; runs only the unit tests |
| `debug` | Step-through debugging | Debug, no sanitizers, standard library hardening (debug level) |
| `tsan` | Data races | Debug, ThreadSanitizer, standard library hardening (debug level); macOS and Linux only |

Windows presets carry a `win-` prefix. On Windows, `win-dev` and `win-check`
are optimized (`RelWithDebInfo`, see 7.3), so `win-debug` is the one to step
through. The `release` workflow runs the tests on the optimized build, where
some bugs only appear; it is meant for CI rather than every push. So is the
`tsan` workflow: ThreadSanitizer can't be combined with AddressSanitizer, so
it needs a build of its own, and `clang-cl` doesn't provide it. `dev` and
`debug` stay at `-O0`, so that a debugger shows every variable.

Test presets:
- Every test has a 60-second timeout, so a hung test fails instead of holding
  up a push (CTest's own default is 25 minutes). A project may set a shorter
  `TIMEOUT` on its tests.
- The `dev` and `check` test presets turn on AddressSanitizer's leak
  detection (`ASAN_OPTIONS=detect_leaks=1`) and apply the policy's
  suppression list for false positives in the OS (section 5). Detection is on
  by default on Linux and off on macOS; `clang-cl` doesn't provide it.
- On macOS the same presets turn off the nano malloc zone
  (`MallocNanoZone=0`), as Xcode does whenever AddressSanitizer is on. With
  it on, libdispatch's cache of reusable work items (up to 112 per worker
  thread, on at most 64 threads) is reported as up to 7,168 leaks, because
  the pointers to it sit where LeakSanitizer doesn't look. Whether a
  terminal has the variable depends on the app that opened it; a
  self-hosted runner's service doesn't, so the presets set it
  (`tests/leak/nano_zone.cpp`). Seen on macOS 27; GitHub's macOS 15 runners
  don't report the cache either way.

ThreadSanitizer on Linux: threads that glibc creates internally, without
`pthread_create` (for example the helper threads of `getaddrinfo_a`), are
invisible to the runtime, and the first allocation on one of them crashes
the program. Check how your dependencies resolve names: cpp-httplib's
non-blocking `getaddrinfo` takes that path, so SimpleLocalServer removes that
option from its `tsan` build only.

### 7.1 Warnings

Always on, always errors: `-Wall -Wextra -Wpedantic -Wshadow -Wnon-virtual-dtor
-Wold-style-cast -Wcast-align -Wunused -Woverloaded-virtual -Wconversion
-Wsign-conversion -Wnull-dereference -Wdouble-promotion -Wformat=2
-Wimplicit-fallthrough -Wzero-as-null-pointer-constant -Wextra-semi -Werror`.
With `clang-cl`, `/W4` replaces `-Wall -Wextra` (in `clang-cl`, `-Wall` means
`-Weverything`).

One warning of `-Wextra` is off: `-Wmissing-designated-field-initializers`.
It rejected `Options{.width = 4}` whenever another member had no default
member initializer, and a class-type member (a `std::string`) may not have
`{}` as one, because clang-tidy calls that redundant. Every field then had
to be written out (section 2.10).

### 7.2 Standard library hardening

Each platform uses a different standard library, so the policy sets the
switch for all of them (each library ignores the others):

| Library | Where | Switch |
|---|---|---|
| libc++ | macOS | `_LIBCPP_HARDENING_MODE` |
| libstdc++ | Linux | `_GLIBCXX_ASSERTIONS` |
| Microsoft STL | Windows | `_MSVC_STL_HARDENING` |

`CPP_POLICY_HARDENING` picks the level: `fast` (the default, and what
`release` uses) or `debug`. It can't be turned off: the checks cost less than
can be measured (14.1), so configuration fails for any other value.

### 7.3 Sanitizers on Windows (`clang-cl`)

What to know:
- A thrown and caught exception works under AddressSanitizer (verified with
  LLVM 23.1.2: tests/clang_cl/slash_options.cpp throws and catches in the
  `win-check` tests). Older clang-cl releases crashed on any `throw`.
- The link needs the ASan runtime, which `cpp_policy_apply` adds, and the
  Visual Studio component "C++ AddressSanitizer" for `stl_asan.lib` (README).
- ASan does not work with the debug C runtime, so the Windows `dev` preset
  uses the release runtime (`/MD`) with debug info.
- UBSan is not enabled on Windows.

### 7.4 Hardening with `clang-cl`

Every configuration but Debug gets Control Flow Guard: `/guard:cf` when
compiling (indirect calls are checked against a table of valid targets) and
when linking (the table and the PE flag; lld-link doesn't add them on its
own). Stack cookies need no flag: `clang-cl` compiles with a strong stack
protector by default (`-stack-protector 2`, the equivalent of
`-fstack-protector-strong`). The audit rejects the options that turn either
off, in both spellings (`/GS-`, `-guard:cf-`, `/sdl-`, ...). The self-test
reads a program's PE header and requires `GUARD_CF` with a non-empty
function table, plus lld-link's ASLR and no-execute defaults
(`DYNAMIC_BASE`, `HIGH_ENTROPY_VA`, `NX_COMPAT`).

## 8. Enforcement layers

| Layer | When | What |
|---|---|---|
| Editor (clangd) | While typing | clang-tidy diagnostics, formatting |
| `tools/hooks/tidy-files` | After editing C++ files, run by whoever edited them (agent or person) | What the gate will say about those files, without the tests: the format, the audit's rules about one file (length, suppressions, `// boundary:`, test-case names) and clang-tidy, a few seconds each. A header is checked through a source that includes it, with that source's flags |
| Git pre-commit | On commit | Suppression audit, format check, and clang-tidy on the staged C++ files (`tidy-files`); warns when files have unstaged changes, since it checks the working folder |
| Git commit-msg | On commit | The message follows section 8.2 |
| Git pre-push | On push | The full gate (below); refuses to run with uncommitted changes, so it tests exactly what is pushed |
| CI (GitHub Actions) | On push | The same gate on Linux, Windows and macOS, through cpp-policy's reusable `gate.yml`, pinned to the same commit as the build (the audit checks it); on GitHub's machines or the owner's own (README) |

The git hooks come from cpp-policy (`tools/hooks/`); projects copy them
unchanged and enable them once per clone with `git config core.hooksPath
tools/hooks`. Configuration warns while a clone hasn't done so.

In CI, a run that a newer push to the same branch made obsolete is
cancelled (`gate.yml`): stopped on a branch; on the default branch the run
in progress finishes and only runs still waiting are dropped; never for a
tag. A cancelled run is neither a pass nor a failure, and no rule needs
every pushed commit to have a result: pre-push ran the gate before the
push, and a release is tagged on the commit whose run is green
(section 10).

**The launcher.** `sh tools/hooks/gate [workflow]` runs the workflow and
adds what a machine shared by several unattended agents needs:
- **One gate at a time on the machine;** a second waits for the first. Four
  agents in four folders ran four gates at once in Alfar: one that takes 5
  minutes alone took 25.
- **The machine stays awake** (macOS and Linux). A test that sleeps with the
  machine passes its time limit and is reported as failed: Alfar lost about
  2.5 hours to one such gate, and a merge was committed after it.
- **One last line,** `gate: passed` or `gate: FAILED`, and the workflow's own
  exit code. That merge was committed because the exit code read was
  another command's, later in the same line.

pre-push runs the gate through it.

Every layer works the same for any agent and for people: they are commands
and git hooks, and `AGENTS.md` says when to run them. An agent with a hook
system of its own may call `tidy-files` from it after each edit, but the
policy relies on nothing agent-specific.

The gate is `cmake --workflow --preset check` (`win-check` on Windows),
run through its launcher, `sh tools/hooks/gate`: configure, the audit and the format check (first: they take seconds, and a
fault in them shouldn't wait for the compiler), build with clang-tidy, and
tests under sanitizers. It is the only definition of "passes the policy". Every other
layer is a faster subset of it.

A passing gate proves the policy on the system that ran it, with that
system's standard library and headers: libc++ on macOS, libstdc++ on Linux,
the Microsoft library on Windows. clang-tidy reads each one, and they differ
(section 2.10), so a green `pre-push` on a Mac says nothing about the other
two. CI covers the systems a project lists; it is the authority for them.

The `check` build presets keep going after a file fails (`-k 0` to Ninja),
so one run reports every finding instead of the first.

### 8.2 Commit messages

Commits follow [Conventional Commits](https://www.conventionalcommits.org) and
say why:

```
fix(hooks): pick the win-check preset under Git for Windows

pre-commit always used the check preset, which is disabled on Windows, so
every commit there failed before any check ran.
```

- The subject is `type(scope): summary`, at most 72 characters. Types:
  `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `build`, `ci`, `chore`,
  `revert`. The scope is optional, lower case (`hooks`, `audit`, `server`). A
  `!` before the colon marks a breaking change.
- A blank line, then a body that says why the change was made. Trailers such
  as `Co-Authored-By:` don't count as the body.
- Release commits are `chore(release): <version>`.
- Messages git writes itself pass unchecked: merges, reverts, `fixup!`,
  `squash!` and `amend!`.

The `commit-msg` hook checks all of this. History from before the hook is
left as it is.

### 8.1 What is not checked by tools

These rules rely on review (and on agents following `AGENTS.md`):
- `const char*` used as a string type (section 2.2). A pattern can't tell a
  string from the legitimate uses (`argv` at the program boundary, pointers
  into a buffer for `std::from_chars`, C APIs in confined areas); that would
  take a custom clang-tidy check
- File names in `snake_case` (section 2.7)
- Pointer + length parameters (section 2.2): no check flags the signature,
  but indexing the pointer is caught as pointer arithmetic
- Whether a `catch (...)` really is at a boundary and whether an `// rtti:`
  reason holds (section 3): the audit requires them to be stated, review
  judges them. Tools do enforce that exceptions never escape `main` or
  `noexcept` functions, and that no handler is empty
- `[[nodiscard]]` on functions returning `std::expected` (section 3); ignoring
  the result is enforced, the attribute itself is not
- The "why" comment at the top of confined source files (section 4)
- Concurrency (section 2.8): `std::thread` and `detach()`, lock scope and
  order, and the catch at the top of every thread function; data races are
  found at run time by the `tsan` preset only where tests exercise them
- Project structure (section 11): layers and file size are checked; the
  helper extraction rule, comment accuracy and the roadmap's layout will
  always rely on review
- Budgets (section 13.5): sizes and memory growth are checked; whether every
  shipped program has a budget and every server a memory test is review
- Performance (section 14): measuring before optimizing, and giving before
  and after numbers, rely on review
- How tests are written (section 13.4): test names, labels and skipped
  tests are checked; `REQUIRE` versus `CHECK`, one behavior per test, fakes,
  no sleeps and testing through public headers rely on review

Every other rule in section 2, and the function size limits of section 11.3,
has a sample in `tests/bad/` proving clang-tidy rejects it (one of them in a
header, proving headers are checked). The rules enforced by the audit, such
as `#pragma once` and suppressions, have fixtures in `tests/audit/`.

## 9. AI agents

- Agent instructions live in `AGENTS.md`. Projects don't have a `CLAUDE.md`:
  Claude Code (v2.1.277 or later) reads `AGENTS.md` directly, but only when no
  `CLAUDE.md` exists, so adding one would hide `AGENTS.md` from it. Agent
  settings deny creating `CLAUDE.md`.
- **A new project is created with `tools/new-project.sh`** (README,
  "Starting a new project"), never by writing its build files by hand. The
  generator gives it the pinned release, the copied policy files, the git
  hooks, the layers, the tests, a size budget, `ROADMAP.md` and `AGENTS.md`;
  the audit compares several of those with the release's, so a hand-written
  setup fails it. That holds for a port too: generate the project, then
  bring the code in.
- **A rule that seems wrong or impossible for a project is reported, not
  worked around.** The agent stops and writes what the rule prevents, for
  the owner to take to cpp-policy. Three rules of 13.5 changed that way.
- Agents check each C++ file they edit with `sh tools/hooks/tidy-files
  <file>...`, and must run the gate (`cmake --workflow --preset check`,
  section 8) before declaring work complete.
- Agents must not add suppressions, edit policy files (section 6), or bypass
  git hooks (`--no-verify`).
- Where the agent supports permission rules, they back these rules up, but
  only partly: they block the agent's own file-editing tools and the
  `--no-verify` flag, not every shell command that could do the same (such as
  `sed -i` on a policy file, or `git -c core.hooksPath=…`). What an agent
  can't be stopped from doing is caught afterwards: the audit rejects edited
  copies of the policy files and hooks, configuration rejects weakened build
  settings, and CI runs the gate again on a clean machine. Agent settings are a
  guide, not a security boundary.

## 10. Versioning

- `cpp-policy` uses semantic versioning. Projects pin the **commit** of a
  release tag, with the tag name in a comment
  (`GIT_TAG <commit>   # v0.3.0`). A tag can be moved to other code later; a
  commit can't. That matters because cpp-policy's CMake code runs on every
  machine that configures a project.
- Projects upgrade with `tools/upgrade.sh <tag>` (README, "Upgrading"): it
  moves both pins and the copied policy files together and checks the result.
- The version is defined once, in `project(cpp_policy VERSION ...)` in
  `CMakeLists.txt`. A release commit sets it, adds the release to
  `CHANGELOG.md` (each change with its reason), updates the tag in the
  `README.md` example, and gets an annotated tag `v<version>`.
- A release's `CHANGELOG.md` entry starts its "Upgrading a project" steps
  with **"Work beyond `upgrade.sh`"**: "none", or what a project has to
  change. The owner can then batch the releases that need none.
- A release that changes what projects must write (a test recipe, a rule) is
  first run on each shape it applies to, on all three systems: at least a
  batch command and a server with a thread pool. Two recipes of 13.5 failed
  on SimpleLocalServer at first contact because they were developed on the
  other shape.
- **Major:** a new rule or tightened rule that can break existing code.
- **Minor:** new optional features, new presets, tooling improvements.
- **Patch:** fixes that never make passing code fail, for example removing a
  false positive.
- **Before 1.0**, the minor version takes the major's role: `0.x` to
  `0.(x+1)` may break existing code, while patch releases still never do.

### 10.1 Moving the toolchain pins

The toolchain is pinned in three places:

| Pin | Where | What depends on it |
|---|---|---|
| LLVM major | `CPP_POLICY_LLVM_MAJOR` (`CppPolicy.cmake`), `tools/vcpkg/llvm.cmake`, the presets' search paths, `LLVM_MAJOR` in `gate.yml` | Every machine: configuration fails with another major |
| Exact LLVM on Windows CI | `LLVM_VERSION` and its SHA-256 in `gate.yml` | GitHub's Windows jobs; self-hosted Windows runners install the same archive |
| Microsoft toolset | `MSVC_TOOLSET` in `gate.yml` | Self-hosted Windows runners (section 1) |

LLVM patch releases on macOS and Linux aren't pinned: machines take them
within the major in their normal updates. A self-test
(`toolchain/pins`) checks that every file names the same LLVM major.

**When.** The pins move in a *toolchain window*, twice a year. Each LLVM
major release opens one, about every six months.
- The target is the newest patch release of the new major when the window
  opens, never its `.1.0`, which tends to have regressions.
- The Microsoft toolset moves in the same window, to the newest one Visual
  Studio offers then.
- Both move in one release: the machines switch and the projects upgrade
  once per window.
- Outside a window, a pin moves only for a fix that is needed, following
  the same steps.

Homebrew's `llvm` moves to a new major within days of its release, which
would otherwise set the date for us. The major the policy pins then stays
available as `llvm@<major>`, which the presets, the vcpkg toolchain and the
gate look for first. On a Mac, `brew install llvm@23` keeps a project
building until its policy moves.

**Steps.**
1. **Open.** Choose the target versions from their release notes: new
   clang-tidy checks, standard library changes, removed options. Write the
   release's section in `ROADMAP.md`. Tell the administrators of the
   self-hosted runners and the projects that the window is open, with the
   targets.
2. **Trial the policy.** On a branch with the new pins:
   - cpp-policy's own CI and a local gate;
   - a decision on each new clang-tidy check (enabled unless it only
     produces noise);
   - the section 12 items reviewed.

   Nothing is released yet.
3. **Trial the projects, before anything moves.** Each project is built
   with the candidate toolchain against the policy branch, on every system
   (`-DFETCHCONTENT_SOURCE_DIR_CPP_POLICY=<branch checkout>`).
   - On a Windows runner machine: snapshot it, pause its runners (jobs
     wait in the queue), install the candidate, run the builds, and restore
     the snapshot.
   - On Linux, the new LLVM installs next to the old one.
   - Each project fixes its findings before the switch, in code that passes
     with both toolchains. When no such code exists, the fix goes into the
     upgrade commit instead.
4. **Release** the new pins as a minor release (section 10), and tag it.
   Tell the runner administrators the exact versions and checksums first.
5. **Switch, on one agreed day.** The runner machines change first:
   snapshot, install, and a trial build of cpp-policy at the new tag. Then
   every project that uses them upgrades right away (`tools/upgrade.sh`).
   - Until a project upgrades, its self-hosted Windows jobs stop at the
     toolset check, so this gap should be as short as possible.
   - A Windows runner machine holds one toolset at a time, so all projects
     switch together. Keeping old and new side by side would take runner
     labels per toolset and a second machine: the way out if too many
     projects share the runners to switch in one day.
6. **Roll back** if a project can't pass on the same day: the runner
   machines restore their snapshot, and the projects that upgraded revert
   their upgrade commit. The release stays; it is adopted in a later attempt.
7. **Close.** Each project's first run prints the new versions ("Show the
   toolchain"). The release commit already removed the window's section
   from `ROADMAP.md` (section 11.5). An old LLVM major is uninstalled once
   no project uses it.

## 11. Project structure

These rules keep a codebase navigable as it grows, especially when AI agents
make many small changes. Adapted from the Carreritas project.

A new project starts from `tools/new-project.sh` (README, "Starting a new
project"), which lays it out this way from the first commit.

### 11.1 Layers and dependency direction

- Source code is split into modules, one directory each under `src/`
  (for example `src/message/`, `src/server/`).
- Each project groups its modules into **layers** and documents them in its
  `README.md`, from lowest to highest. `AGENTS.md` points to
  `cpp_policy_layers()` and to the README; it has no table of its own,
  because only the owner edits that file and a table there goes stale
  (in Alfar it was wrong for 59 hours).
- Dependencies point **one way only**: a module may include headers from its
  own layer's modules or from lower layers, never from higher ones.
- `src/lowlevel/` (section 4) is always the lowest layer: it may not include
  any other project module.
- `main.cpp` is the top: it may include anything.
- Includes are written from the `src/` root (`#include "server/local_server.hpp"`),
  never with relative paths (`"../server/..."`), so the direction of every
  dependency is visible in the include line.

*Enforcement:* the project declares its layers in CMake, from the lowest up,
before `cpp_policy_add_checks()`:

```cmake
cpp_policy_layers(
    LAYER lowlevel
    LAYER message
    LAYER app server)
```

The audit then rejects, for every `#include "..."` under `src/`: an include
from a higher layer, a relative path, a header named without its module, and
any other module's header in a confined module. It also fails if a module is
in no layer, and if `src/` has two or more modules but no layers are
declared. Files directly in `src/` (`main.cpp`) are the top.

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
| Review, test sources (under `tests/`) | > 500 | The same |

- When a new feature would push a file past the target, split the file by
  responsibility first, then add the feature.
- A test source may be longer because it is mostly tables of cases and
  expected text; its length doesn't mean mixed responsibilities. In Alfar
  about a third of the splits the limit forced were of test files, and four
  full builds stopped on tests alone. The limits on functions are the same
  everywhere.
- `tidy-files` reports a file's length after an edit, and says so from 50
  lines before the limit, so the split comes before the next feature.
- Functions are limited separately by clang-tidy: at most 80 lines, 6
  parameters and 4 levels of nesting (`readability-function-size`), and a
  cognitive complexity of 25 (`readability-function-cognitive-complexity`).
  Code inside macros isn't counted. Each doctest `CHECK` added 3 at the top
  level and 5 in a loop, so a table test with six assertions measured 65;
  outside tests the policy allows almost no macros (2.4).

*Enforcement:* the audit fails on any source file over 350 lines (the review
threshold), outside excluded directories. The target of 250 is left to review.

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

### 11.5 Roadmap and changelog

Two files record a project's work, each with one job:

- **`ROADMAP.md`:** the open work: what comes next, and why.
- **`CHANGELOG.md`:** the finished work, per release, each change with its
  reason.

The commit that finishes a piece of work also records it in `CHANGELOG.md`
(under "Unreleased" until the release).

**cpp-policy upgrades are one line.** `CHANGELOG.md` is about the program.
Its introduction has a line `Policy: cpp-policy v<version>.`, updated in
place at each upgrade. An upgrade gets an entry only for what it changed in
the project's own code or tests, with the reason; why the policy changed is
in cpp-policy's `CHANGELOG.md`, and git history has every upgrade commit.
SimpleLocalServer's changelog had about 170 lines of "Upgraded to
cpp-policy vX" over nine upgrades that changed nothing in `src/`.

`ROADMAP.md` has up to three parts,
in this order:

```markdown
# Roadmap

## 0.4.0 (in progress)

**Goal:** the server can be used outside a trusted home network.

### Scope

- [x] The server prints a pairing code at startup.
- [ ] A device must send the code before it can post messages.

### Out of scope

- HTTPS: devices would need certificates they trust.

### Validation

- [ ] The gate passes in CI on every system.
- [ ] Pairing works from a phone and from another computer.

## Later

- [ ] A QR code for the address and the pairing code.

## Not planned

- Access from outside the local network: the server is for one home.
```

- **A version section** exists while that version is being worked on: a
  one-sentence goal and three lists.
  - **Scope** says what the version delivers, stated as behavior, and each
    item is ticked when it's done. It's a checklist, not a work log:
    "branch created" or "tests added" aren't scope items.
  - **Out of scope** lists what the version deliberately leaves out, each
    with its reason. Agents and contributors don't add these things
    without asking.
  - **Validation** says what shows that the version works: CI, and any
    manual checks, naming what is checked and where. An item is ticked
    with its evidence: a link to the CI run, or who checked it, on which
    machine.
- **On release,** the release commit deletes the version's section. The
  version's `CHANGELOG.md` entry now says what it delivered and why, and
  the section can still be read at the release tag. Out-of-scope items that
  still matter move to "Later" or "Not planned".
- **"Later"** holds the other open items, grouped as the project likes.
  An item is removed in the commit that resolves it.
- **"Not planned"** lists accepted limitations with their reasons, so that
  nobody proposes them again without new information.
- **Intent and status only.** No listings of files, modules or tests, no
  test or line counts, no "last updated" dates. The repository and git
  already record these, and hand-kept copies go stale. Carreritas'
  scope document grew to 500 lines that way: every version's scope stayed
  in the file, with a file tree that had to be edited on every refactor.

A project created with `tools/new-project.sh` starts with both files.
Its `AGENTS.md` tells agents to read `ROADMAP.md` before they start work.

*Enforcement:* review. The audit doesn't read prose.

### 11.6 Dependencies stay in their modules

A third-party library is used through one module (or a few), and the rest of
the program uses that module's own types. A frontend then can't come to
depend on the library by accident, and replacing the library touches only
that module.

- The project names each library's headers and the modules that may include
  them, before `cpp_policy_add_checks()`:

  ```cmake
  cpp_policy_confine_includes(httplib.h TO server)
  cpp_policy_confine_includes(nlohmann/ zlib.h TO backend SOURCES_ONLY)
  ```

  A name ending in `/` stands for every header under it, and one ending in
  `*` for every header whose name starts so: `imgui*` covers a library whose
  headers are in no folder of their own, and those a later version adds.
- Several lines may name one header, and they add up: `nlohmann/ TO
  settings` and `nlohmann/ TO inputs cache SOURCES_ONLY` allow it in
  `settings`'s headers and in the other two modules' source files only.
- **`SOURCES_ONLY`** allows the include only in those modules' source files,
  not in their headers. A header that includes the library passes it on to
  every file that includes that header, in any module. With `SOURCES_ONLY`
  no header can, so the library's types can't appear in the module's
  interface. Use it wherever the interface doesn't need them.
- Every dependency in `vcpkg.json` that the program's own code includes has
  such a line (doctest and nanobench are used only by tests).
- This is the rule behind a backend with several frontends (a command line,
  a window, later a phone): the frontends include the backend's interface,
  written with the project's own plain types (section 15.1), and nothing
  else of it.

*Enforcement:* the audit rejects, under `src/`, an include of a named header
(written with `<>` or `""`) from any other module or from `main.cpp`, and
with `SOURCES_ONLY` from any header. It also fails if a line names a module
that `src/` doesn't have. That every dependency has a line relies on review.

### 11.7 A library used by other projects

A project may offer a library, with or without programs of its own, and
another policy project may use it. Both keep their gates, and no code is
copied. ToneMatcher's library and Alfar are the first pair; before this,
Alfar carried 37 copied files that diverged from their source within two
days.

**In the project that offers it**

- **The library's code is in `lib/<name>/<module>/`,** and every include of
  it is written `"<name>/<module>/<header>.hpp"`, in the library's own code
  too. The program's modules stay in `src/`.
  - *Why a root of its own, and the name in every include:* a header of the
    library includes other headers of the library. Written as
    `"lowlevel/process.hpp"`, it would need the library's source root on the
    user's include path, where the user's own `lowlevel/` and `app/` are.
    And that root can't be `src/`, which also holds the program's modules.
- **`library.cmake`, at the repository's root, declares it** and nothing
  else: `find_package()` for what it links, and one call.

  ```cmake
  cpp_policy_library(tonematcher
      LAYER lowlevel
      LAYER image naming parse
      SOURCES lowlevel/process.cpp image/image.cpp naming/pieces.cpp parse/numbers.cpp
      DEPENDENCIES zlib
      LINK ZLIB::ZLIB)
  ```

  The project's `CMakeLists.txt` includes that file; so does a user. vcpkg,
  tests, checks and programs stay in `CMakeLists.txt`, which a user never
  runs.
- **The library has layers of its own** (`LAYER`, from the lowest up), and
  its `lowlevel` module is a confined area (section 4). The program's
  layers, in `cpp_policy_layers()`, are all above it.
- **The library doesn't include the program.** A dependency's headers are
  confined to its modules as `<name>/<module>` (11.6).
- A project offers one library. Its tests are the project's tests.
- **A release of the library is a tag on a commit whose CI was green on
  every system.** A user compiles the library's code for systems it may
  never build on itself, and the library's CI is the only place that code
  met a compiler. A change that alters a result on purpose says so first in
  `CHANGELOG.md`.

**In the project that uses it**

```cmake
cpp_policy_use_library(tonematcher
    GIT_REPOSITORY https://github.com/luiserh1/ToneMatcher.git
    GIT_TAG        <commit>)   # v0.4.0
target_link_libraries(app_core PRIVATE tonematcher::tonematcher)
cpp_policy_confine_includes(tonematcher/ TO textures)
```

- **A release, pinned by commit,** with the version in a comment, like
  cpp-policy's own pin (section 10).
- **The library is built in this project's build, as a dependency.** It gets
  this build's compiler, standard, hardening and sanitizers, which must be
  the same in everything linked together. It doesn't get this project's
  warnings as errors, clang-tidy, audit or format check: its own gate
  checked it, and this project can't edit it.
- **A floor.** Configuration fails if the library's project pins a
  cpp-policy older than the floor this release sets (v0.30.0, the first
  with libraries). The floor rises when a release makes a rule that older
  code can't be trusted to meet.
- **The library is below every layer of this project.** Which modules may
  include it is this project's choice, with the rule for any dependency
  (11.6).
- **Its packages don't travel:** vcpkg doesn't read a manifest through a
  fetch. This project's `vcpkg.json` lists each package the library needs,
  with its reason, and configuration fails if one is missing.
- **Its code counts in this project's budgets** (13.5): each program's size
  and memory. When a release of the library takes a program past a budget,
  the commit that moves the pin raises it, with the owner's approval and
  the library named as the reason.

**Not supported yet:** a project that is only a library; a library that
uses a library; marking some of a library's headers private; test helpers
offered by a library; a private repository fetched in CI, which needs a
credential.

*Enforcement:* the audit rejects, in the library's project, an include from
`lib/` of anything but `"<name>/<module>/…"`, an include of a higher layer
of the library, and a module of `lib/` in no layer. Configuration rejects,
in the user's project, a pin that isn't a commit, a library below the floor
and a missing package. That a release was green on every system relies on
review.

## 12. Waiting on the toolchain

Some decisions work around features the toolchain doesn't provide yet. Each
one is listed here with what would end it. The code that works around it
carries a `Waiting Wn` comment, so every place to change can be found when
the item resolves.

Items are reviewed at every toolchain upgrade (LLVM releases a major version
about every six months, section 10.1; CMake a minor one about every four). Where a compile
can tell, a probe in the self-test does it for us: it fails, on purpose, the
day the feature appears, or a tool's defect is fixed (`tests/probes/`).

| Item | Wanted | Workaround today | Resolves when | Checked by |
|---|---|---|---|---|
| W1 | C++ modules and `import std` | `#include` (section 2.4); module scanning off (`CXX_SCAN_FOR_MODULES OFF` in `CppPolicy.cmake`) | CMake makes `import std` stable, clang-tidy handles modules, and `clang-cl` with the Microsoft library catches up | Hand, at each CMake and LLVM upgrade |
| W2 | Time zones in libc++ on macOS (`std::chrono::zoned_time`, `current_zone`) | Local time through `localtime_r` / `localtime_s`, in a confined file | libc++ ships its time zone database on macOS. (libstdc++ already has it: verified with GCC 16 on Linux.) | Probe `waiting/w2_zoned_time` (macOS) |
| W3 | Parallel algorithms (`std::execution::par`) in libc++ without `-fexperimental-library` | Not used; parallel computation isn't covered by the policy yet | libc++ makes them stable. (libstdc++ has them with GCC 16 on Linux, but only by linking TBB, a compiled dependency that section 1.1 would have to admit.) | Probe `waiting/w3_parallel_algorithms` (macOS) |

| W4 | `readability-trailing-comma`, and `policy-format-fix` settling the commas with it | The check is off (`.clang-tidy`), and the fixer only formats (`format.cmake`) | clang-tidy stops reporting the comma after an empty braced value (`f(a, T{}, b)`, `= {}` as a default argument, `{T{}, T{}}`, `.member = {},`) whose type has default member initializers. Seen in LLVM 23.1.1 and 23.1.2; its fix removes a comma the syntax needs | Probe `waiting/w4_trailing_comma` (every system) |

When an item resolves: remove its workarounds (search for `Waiting Wn`),
delete its row and probe, and record the change in `CHANGELOG.md`.

## 13. Testing

Every project tests its code with doctest, through `cpp_policy_add_tests()`,
which turns the rules on names, labels and kinds into one line per test
program. (cpp-policy's own self-test is exempt: it tests CMake scripts and
tools, not a program's modules.)

### 13.1 Kinds of tests

| Kind | What it tests | Rules | Time limit |
|---|---|---|---|
| `unit` | One module, through its public header | No files, network, child processes, threads or clock; results don't depend on the machine; no state shared between test cases | 60 seconds for a module's unit tests together (in practice a fraction of a second) |
| `integration` | Modules together, or a module with the OS | Real sockets on ephemeral ports (port 0), temporary files and folders under the build folder, threads and processes; every wait has a timeout | 60 seconds, or less with `TIMEOUT` |
| `benchmark` | What a program costs: its size and its memory under load (13.5) | Built in every configuration, so clang-tidy checks it, but run only without sanitizers, which distort size, memory and time | 60 seconds, or less with `TIMEOUT` |

**Regression tests** aren't a kind of their own. When a bug is fixed, a test
that shows the bug comes with the fix. It is written first and seen failing,
then passes with the fix, and it goes in `TEST_SUITE("regression")`, which
labels it `regression` as well as its kind. It is kept, so the bug can't come
back unnoticed. Speed benchmarks are left for the performance section, still
on the roadmap.

### 13.2 Test programs and names

```cmake
cpp_policy_add_tests(unit message SOURCES test_sanitize.cpp LIBRARIES sls_core)
cpp_policy_add_tests(integration server SOURCES test_server.cpp LIBRARIES sls_core
                     TIMEOUT 30 ENVIRONMENT "HELPER=$<TARGET_FILE:helper>")
```

- **One program per kind and module,** `test_<kind>_<module>`, built with
  the policy like any target and linked with doctest's `main()` from
  cpp-policy.
- **Tests reach CTest named `<kind>/<module>/…` and labelled with their
  kind,** so `ctest -L unit` and `-R <regex>` select them.
  `cmake --workflow --preset unit` (`win-unit`) builds without clang-tidy
  and runs the unit tests only.
  - **A module's unit tests are one CTest test,** `unit/<module>/all test
    cases`: the program runs once, with every test case in one process. A
    failure names its test case, file and line, as doctest prints them. To
    run one case by hand: `<program> --test-case="<name>"`.
  - **Each integration or benchmark test case is its own CTest test,**
    `<kind>/<module>/<test case>`, in its own process: they use files, ports
    and the environment, and a crash fails only its own test.
  - *Why the difference:* under the sanitizers a process costs about 0.2 s,
    0.12 s of it LeakSanitizer's check when the process ends, whatever the
    test does. Measured on a project with 1,505 unit test cases in 10
    programs: 311 s with a process per case (77 s with ten at a time), 2 s
    with a process per program. Alfar's gate had grown from under a minute
    to eight for that reason alone. Unit tests may share no state (13.1), so
    separate processes protected nothing there.
  - When a unit test crashes (a sanitizer report), doctest names the test
    case and the cases after it in that program don't run until it is fixed.
  - Table rows are not separate tests. Rows run in a loop in their test
    case, and `CAPTURE` names the row that failed.
- **A test case is named after its behavior,** as a sentence ("an empty name
  is refused"). Names use letters, digits, spaces and `' . : ( ) + = - _`.
  doctest selects a test by a filter in which `,` `*` `?` and `\` are
  special, and two names that differ only in case would select each other.
- **Registration checks the tests after every build,** and the build fails
  on any of these:
  - a skipped test case;
  - a name outside those characters, or two names that differ only in case
    (the audit and `tidy-files` also read the names from the source text, so
    a bad one is reported before the program is compiled);
  - a doctest suite other than `regression`;
  - a program with no tests.
- **A test that isn't a doctest program** is added with `add_test()`, named
  and labelled the same way. Examples: running the finished program with
  arguments, or a script. Configuration fails for a test without a
  `<kind>/<module>/` name and its kind's label.

### 13.3 doctest

doctest was chosen over GoogleTest after both were tried on a real test file
and on the three systems (CHANGELOG 0.19.0):
- its `REQUIRE` stops the test even from inside a helper function;
- its failures print both values without extra code;
- clang-tidy sees all the test code, because table rows aren't written inside
  macros;
- it is header-only.

Projects add it to `vcpkg.json` like any dependency (section 1.1).

- **`main()` comes from cpp-policy** (`cmake/testing/doctest_main.cpp`), in
  a file of its own. Compiled in the same file as the tests, doctest's
  implementation lets the static analyzer follow its string class, and it
  reports memory leaks that LeakSanitizer shows don't exist (seen on macOS
  and Windows).
- **doctest uses the real standard headers.** `cpp_policy_add_tests()`
  defines `DOCTEST_CONFIG_USE_STD_HEADERS`. Without it, doctest includes
  `<ostream>` only with libc++, and with the other libraries declares what it
  needs in `namespace std` itself, which the standard doesn't allow. A test
  that printed a `std::string_view` (in `CAPTURE`, or a failed comparison)
  then compiled on macOS and Linux but not with Microsoft's library.
- **Printing a project's types in failures.** doctest prints a value with
  `operator<<` if one exists, and an enum as its number otherwise. The
  operator goes in the type's namespace, where doctest finds it, inside an
  inline anonymous namespace:

  ```cpp
  namespace app {
  inline namespace {
  std::ostream& operator<<(std::ostream& out, GreetingError error) {
      return out << describe(error);
  }
  } // namespace
  } // namespace app
  ```

  Why this shape: clang-tidy wants a function used in one file to have
  internal linkage (`misc-use-internal-linkage`), and rejects `static` for it
  (`misc-use-anonymous-namespace`). A plain anonymous namespace would hide the
  operator from doctest, because argument-dependent lookup ignores
  using-directives; an inline one doesn't.

### 13.4 How tests are written

- **`REQUIRE` only for what the rest of the test depends on;** `CHECK` for
  everything else, so one run reports every failure. For example,
  `REQUIRE(result.has_value())` comes before `*result`, and
  `REQUIRE_FALSE(result.has_value())` before `result.error()`: either call on
  the wrong alternative is undefined behavior.
- **Compare inside the check,** as in `CHECK(*text == "Hello, Ada!")`: doctest
  prints both sides only of a comparison.
- **One behavior per test case,** named after it.
- **Through the public interface:** a test includes the module's header from
  `src/` like any other code. A private helper worth testing on its own
  belongs in a module of its own.
- **Tables for cases of one behavior:** a `std::array` of rows with a `what`
  field, and a loop with `CAPTURE(row.what)`.
- **Fakes rather than mocks:** a small class that implements the interface
  with fixed behavior. No mocking framework.
- **No sleeps.** Wait for the event itself, with a timeout: a condition
  variable, `std::future::wait_for`, or polling with a deadline.
- **No state shared between test cases,** and no mutable globals (clang-tidy
  already rejects them).
- **No skipped tests.** Registration refuses them: fix the test, or delete
  it and record the missing test in `ROADMAP.md`.
- **`REQUIRE(value.has_value())` is the check before `*value`.** In test
  programs clang-tidy's `bugprone-unchecked-optional-access` is off: it
  can't see that `REQUIRE` stops the test, so it reported every dereference
  that followed one. A test that reads an empty optional without a `REQUIRE`
  still fails loudly, because library hardening stops the program (7.2). The
  check stays on everywhere else.
  - A library of test helpers is declared with
    `cpp_policy_test_support(<target>)`, after `cpp_policy_apply()`: its
    sources are then test code for the build and for `tidy-files` alike.
  - `tidy-files` checks a test header through a source that includes it. One
    that no source includes directly counts as test code when it is under
    the tests' top-level folder (`tests/`), so shared helpers live there,
    not under `src/`.
- **A bug fix comes with a regression test** that fails without it (13.1).
- **A port uses the original as its reference.** Its tests run the same
  inputs through the port and compare with what the original produced,
  saved with the tests and with a note of how it was made (the original's
  version and the command). Where the results may differ, the test states
  the tolerance and why. ToneMatcher's Gaussian blur is compared exactly
  with scipy's float32 output, which caught differences a "looks right"
  test would not.

*Enforcement:* the helper, registration and configuration check the names,
labels, suites, skipped tests and time limits. The rest of 13.4 relies on
review (section 8.1).

### 13.5 Budgets: size and memory

What a program costs is checked like what it does: a change that makes it
noticeably bigger, or makes its memory grow with its load, fails the build.
Both checks run in the `release` workflow, on every system CI runs.

**Size.** Every program a project ships has a size budget per system, next to
its target:

```cmake
cpp_policy_size_budget(my_tool MACOS 109568 LINUX 93184 WINDOWS 285696)
```

- The size is that of a copy stripped with `llvm-strip`: what would ship. The
  file the build leaves keeps its symbol table, which grows with names rather
  than code. In SimpleLocalServer's, it was 41% of the bytes.
- A budget is the stripped size plus **5%**, rounded up to whole KiB. The test
  `benchmark/size/<program>` prints the size, and the budget to set when there
  is none for this system or when the program has outgrown it. A fresh build
  gives the same size to the byte, and toolchain updates moved
  SimpleLocalServer's by 544 bytes over many releases. So 5% catches real
  growth (a new dependency, a large table) without failing on noise.
- **Raising a budget needs the owner's approval** and a line in `CHANGELOG.md`
  saying why. Agents ask. When the program shrank to well under its budget,
  the test says so, and the budget can come down.
- When a program is over budget, the test lists its sections (code,
  constants, exception tables, strings). For detail, link with a map
  (`-Wl,-map,<file>` on macOS, `-Wl,-Map=<file>` with `lld`, `/MAP` with
  `lld-link`): it gives every function's and string's size, and comparing two
  maps shows what grew.

**Memory under load.** A program that runs indefinitely (a server) has a
memory test, and so does every command that processes input of unbounded size
(a batch over many files): each its own, because a test of one command can't
see what another keeps. ToneMatcher's `diff` kept every full-size diff until
the end (528 MB on 92 images) while its `export` passed its test.
- It is a `benchmark` test that drives the program's work, reads how much
  memory that took, drives more work, and reads again. Benchmark tests get
  two measures:

  | Measure | What it reads | Use |
  |---|---|---|
  | `cpp_policy::live_heap_bytes()`, `peak_heap_bytes()` | An exact count of the C++ heap: every block from `operator new` until its `operator delete` | The memory test |
  | `cpp_policy::peak_memory_bytes()` | The operating system's peak for the process | A second test, only where the program's own memory is outside the C++ heap and can't be brought into it (below): a C library's `malloc`, mapped files. Sockets don't count: their buffers are the kernel's |

- **A C library that takes an allocator is given one that uses `operator
  new`.** zlib's `z_stream` has `zalloc` and `zfree`; set to two functions
  that call `operator new` and `operator delete`, in the confined file that
  wraps the library, every block zlib needs is C++ heap and the heap test
  counts it exactly. The command then needs no operating-system test.
  ToneMatcher's two such tests, kept for zlib, failed four times in two
  weeks without finding a leak; with the allocator they were removed, and
  the heap tests passed unchanged within the same budgets.
  - Only a stream takes an allocator. zlib's one-call functions, `compress`
    and `uncompress`, don't: replace them with a stream (`inflateInit`,
    `inflate`, `inflateEnd`).
  - Allocate with `new (std::nothrow)`: a failure then reaches the C library
    as a null block, and no exception crosses its code.
  - Test that the memory arrives: writing a 1 x 1 PNG raised ToneMatcher's
    heap by more than 200,000 bytes with the allocator and by 448 without.
- **The heap test** (`#include <cpp_policy/heap_bytes.hpp>`) differs for a
  batch command and a server. `live_heap_bytes()` gives the same number to
  the byte for the same work, on every run and every machine load. So does
  `peak_heap_bytes()` when the work runs on one thread; with several, the
  peak depends on how they overlap (SimpleLocalServer's moved by a few
  hundred bytes in 560,000). The numbers differ between systems, because
  each standard library stores a string or a path differently: a limit has
  to hold on the system where the count is largest.
- **A server keeps nothing per request.** Its test:
  1. Warm up in rounds of N requests until a round leaves
     `live_heap_bytes()` no higher than it found it, up to a maximum number
     of rounds. Fail if it never settles: that is a leak.
  2. Read `live_heap_bytes()`, serve 5N more requests, read it again. The
     second reading is less than 10% above the first.

  One unmeasured run is not a warm-up for a server. A thread pool settles
  only when every thread has served a request, and how long that takes
  depends on the machine. cpp-httplib allocates a table of about 700 bytes
  in each pool thread the first time it serves a connection. With rounds of
  1,000 messages SimpleLocalServer's live heap was flat from round 2 on
  macOS, round 5 on Windows and round 14 on Linux, and then identical to the
  byte for the rest of 30 rounds. The first version of this recipe (v0.24.0: N
  unmeasured, N, 5N) failed there with +45% on Linux and +20% on Windows,
  without a leak. cpp-policy's self-test `testing/heap_pool` now runs this
  recipe on a pool of that shape on every system.
- **A batch command** runs on its own each time, so its test is:
  1. Run the work once with N inputs, unmeasured, so that anything set up
     once is in place.
  2. `reset_peak_heap_bytes()`, run N inputs, read `peak_heap_bytes()`.
  3. `reset_peak_heap_bytes()`, run 5N inputs, read it again.

  The peak is an absolute figure. To measure what one operation adds, read
  `live_heap_bytes()` before it and subtract: the test program already holds
  about half a megabyte, so "the peak is over N" can pass for the wrong
  reason. It did, in the first version of ToneMatcher's allocator test.
  - **A batch command has a budget per input, 1 KiB by default:** enough
    for its name and a small fixed-size record. The second reading is at most
    the first plus 4N × the budget. A command that processes files in sorted
    order has to hold their names.
  - **A higher budget needs the owner's approval** and a line in
    `CHANGELOG.md` saying what the record is and why it is kept, like a size
    budget. It is a named constant in the command's test. Agents ask.
    ToneMatcher's `export`, `pipeline` and `match-tone` have 4 KiB per file:
    they keep each file's path and a record per layer, 621 bytes on macOS,
    1,032 on Windows and 2,200 on Linux for the same code. Passing 1 KiB
    would have needed a temporary file and a two-pass reader in the main
    command, to save 2 KB next to images of several megabytes each.
  - The budget is for records, not for content. Memory that grows with the
    size of the inputs (a decoded image, a whole output) is streamed, paged
    or capped, as below, whatever the budget.
- **Why not the operating system's peak:** it depends on what the allocator
  did with freed blocks, and that depends on timing. A program that
  allocates and frees six 1 MB buffers per round, with no leak, measured on
  macOS from 10 rounds to 50:

  | Condition | Growth of the peak, run by run |
  |---|---|
  | Idle machine | +80 to +82% in 6 of 6 runs |
  | 14 busy processes | +1%, +19%, +68%, +81%: mixed over 12 runs |
  | 14 busy processes, eight warm-up runs | 0.0% in 8 of 8 runs |

  The peak has two levels, depending on whether a freed block is reused or
  a new one is taken. ToneMatcher's `diff` test grew 4% in every idle run on
  a Mac and 30.6% in a CI run. Warm-up runs help but don't guarantee it:
  with eight, that test still failed 1 run in 10 on a loaded Mac.
  - **The noise is the measure's own; don't blame the machine.** The home
    server ran ToneMatcher's two operating-system tests 20 times per
    condition, with the eight-run warm-up:

    | System | Idle | Every processor busy |
    |---|---|---|
    | Linux | 0 to 1% | 0% in 20 of 20 (load average 84) |
    | Windows | up to 7.7%, in fixed steps of about 3, 4.4 and 8% | up to 8.8% |

    On Linux the reading didn't depend on load at all. On Windows it moves
    in steps on an idle machine with nothing else running, and load doesn't
    make it worse: a limit of 10% is then a thin margin. None of the 24
    failed CI runs the server examined was caused by lack of capacity.
  - Load does cost time: up to twice on the Windows machine with every
    processor busy. A test near its time limit is a finding for whoever runs
    the machines, with the run's link, like any suspected environment
    problem.
- **Where `peak_memory_bytes()` is used, the first reading comes after the
  warm-up, on every system.** A program's peak first rises while it settles:
  allocator pools, thread pools, caches, the operating system's buffers.
  That rise is not a leak. Measure the curve once on each system (the peak
  after each of many rounds). Then:
  - For a server, either run the work once, unmeasured, before the first
    reading, sized past the latest bend, or choose an N that is past it.
  - For a batch command, warm up with several runs of N inputs (ToneMatcher
    uses eight), never with one run larger than N. Peak memory never goes
    down. After a warm-up run as large as the measured one, a command that
    keeps memory per file and frees it at the end shows the same peak before
    and after.
  - ToneMatcher's export grew 7–12% from N to 5N without a warm-up run,
    depending on N, because its allocator settled over the first three
    runs. With one warm-up run it grew 1–6% at every N.
  - SimpleLocalServer chose a large N instead:

  | System | Warm-up | Peak growth from 15,000 to 50,000 messages |
  |---|---|---|
  | macOS | about 5,000 messages | 4% |
  | Windows | about 4,000 messages | 0.5% |
  | Linux | two steps of exactly 1 MiB, at about 6,000 and 11,000 messages | 0% |

  With N = 1,000, Windows failed (+11%) on warm-up alone. With N = 5,000,
  Linux failed (+39%), on its second step. With N = 15,000 every system
  passes, and a sink that keeps 64 bytes per message still fails
  (9.8 → 19.0 MB).
- **Run memory tests as CTest does.** doctest's `--success` keeps the text
  of every assertion, which multiplied ToneMatcher's peak by about 10.
- **An output that grows with the input counts too.** Memory may not grow
  with the number of inputs, and that includes building one output that
  covers all of them, such as a contact sheet of every image.
  - Write such an output as it is produced (streaming), so the file stays the
    same and memory stays flat.
  - Where the format can't be written in parts, split the output into pages
    of a fixed size. That changes what the user gets, so the owner decides.
  - Keep the whole output in memory only when its size has a documented cap
    (a maximum number of thumbnails, say), and test at that cap.
- **Keep it inside its time limit.** Where setting up the work is slow, reuse
  it: on the home server's Windows VM a new connection costs about 10 ms, so
  SimpleLocalServer's test sends its messages over kept-alive connections.
  A client that reuses a connection sets `TCP_NODELAY`. Otherwise, on Linux,
  Nagle's algorithm holds each request's body until its headers are
  acknowledged, and delayed acknowledgment makes that about 44 ms per
  request: 200 messages took 8.9 s instead of 7 ms. macOS and Windows don't
  show it.
- With `peak_memory_bytes()` the peak may grow by **less than 10%**. Peak
  memory never goes down, so growth means something is kept per unit of
  work. Such a test can fail without a leak, from the measure's own steps,
  which is why it is not the main test. Don't get used to rerunning it: a project whose
  test fails that way and has no memory outside the C++ heap drops it.
- Both measures come with benchmark tests, so projects need no OS code of
  their own. In builds with sanitizers, which have their own `operator new`,
  the heap count reads 0; benchmark tests don't run there.
- `peak_memory_bytes()` (`#include <cpp_policy/peak_memory.hpp>`):
  - On macOS and Linux it reports the peak resident memory (`ru_maxrss`).
  - On Windows it reports the peak private commit (`PeakPagefileUsage`): the
    memory the process allocated for itself. The peak working set also
    counts shared pages. Measured on SimpleLocalServer over 25 rounds of
    1,000 messages, private commit had the same warm-up and then stayed
    identical to the byte, while the working set moved by 8 KB in one run
    and by about 0.4 MB in steps in another. A sink keeping 64 bytes per
    message showed +48% in private commit, against +27% in the working set.
- SimpleLocalServer's peak was 7.01 MB after 1,000 messages, 7.01 MB after
  10,000 and 7.06 MB after 30,000.

*Enforcement:* the budget and memory tests fail the release workflow. Whether
every shipped program has a budget, and every server a memory test, relies on
review (section 8.1).

## 14. Performance

### 14.1 What the safety features cost

Measured on two workloads (SimpleLocalServer's `sanitize()`, which scans
text, and ToneMatcher's Gaussian blur, which indexes vectors in tight loops)
on an Apple Silicon Mac, best of five runs (the blur's unsanitized builds:
median of three reruns), 2026-10-01:

| Build | Cost against the release build |
|---|---|
| The release build's protections: standard-library hardening (`fast`), `-fstack-protector-strong`, `_FORTIFY_SOURCE=3` | Not measurable: within the machine's run-to-run noise (±15%). Builds with none of them were no faster |
| Standard-library hardening at the `debug` level | Also within noise |
| AddressSanitizer + UndefinedBehaviorSanitizer, at `-O3` | ×1.8 to ×2.4 |
| The same at `-O1` (the `check` and `unit` builds) | ×2 to ×6 |
| The same at `-O0` (the `dev` build, and `check` before v0.22.0) | ×43 to ×86 |
| ThreadSanitizer, at `-O3` | ×11 to ×14 |

- **Every protection stays on in release:** they cost less than the noise
  in which any speed difference would have to show.
- **What costs is optimization in the test builds.** That's why `check` and
  `unit` compile at `-O1`: their tests run 15 to 21 times faster than at
  `-O0`, with the same sanitizers, hardening and checks. `dev` and `debug`
  stay at `-O0` for the debugger.

### 14.2 Speed benchmarks

- **Measure first.** Speed work starts from a measurement that shows where
  the time goes (a profiler, or a benchmark of the suspected part), not from
  a guess. The change then shows the same measurement before and after.
- **Benchmarks are `benchmark` tests with nanobench.** A project lists
  `nanobench` in `vcpkg.json`, and `cpp_policy_add_tests(benchmark …)` links
  it and compiles its implementation once:

  ```cpp
  TEST_CASE("sanitize speed on a 4 KB message") {
      ankerl::nanobench::Bench bench;
      bench.title("sanitize").unit("message").minEpochIterations(200);
      bench.run("4 KB mixed text", [&] {
          auto result = sls::message::sanitize(text);
          ankerl::nanobench::doNotOptimizeAway(result);
      });
      CHECK_FALSE(bench.results().empty());
  }
  ```

  It prints the time per unit, the throughput and the error margin. Like
  every benchmark test, it runs only in the release build.
- **Only compare on one quiet machine, over several runs.** The same binary
  varied by up to 15% between runs on a quiet Mac, and a build running
  alongside slowed a measurement by 80%. CI machines are shared, so speed is
  never a CI check. A change that claims a speed-up, or might cost speed,
  gives nanobench's before and after (machine, median of several runs) in
  its `CHANGELOG.md` entry.
- **Instruction counts, a trial.** Time can't be compared in CI, but the
  number of instructions a benchmark executes can. Measured on the home
  server, 20 runs idle and 20 with every processor busy:

  | Program | Instructions, spread | Time, idle to busy |
  |---|---|---|
  | A fixed loop (4.9 billion instructions) | 0.000% | +33% |
  | ToneMatcher's `diff` heap test (79 billion) | 0.001% | +35% |

  - nanobench prints the count in a column `ins/<unit>` where the processor's
    counters are readable. That is only on the owner's Linux runner labelled
    `benchmark`: the counters are closed by default, and opening them is a
    security setting of the machine.
  - A project calls `benchmark.yml` next to the gate, pinned to the same
    commit. It runs the benchmark tests there and keeps their output in the
    job's summary and as an artifact. **It checks nothing yet:** the trial is
    to see how the counts move over real commits before any budget is
    written.
  - What a count doesn't see: time in the kernel (disk, starting a process),
    and waiting. It includes child processes. It is valid for one processor
    family and one toolchain build, so a toolchain window (10.1) changes it.
  - Linux only: Windows and macOS don't give a program these counters
    without elevated rights.
  - First results, on ToneMatcher: the same code on two runs differed by 1
    to 3,011 instructions in 1.4 to 5.2 billion. The first change expected
    to matter (zlib's memory through `operator new`, and a new
    decompression loop) moved the one benchmark that reads and writes PNGs
    by 0.08% and the other three by under 0.0001%. Its time went from 344
    to 371 ms, which alone would have said nothing.

### 14.3 Writing fast code without weakening it

- **Defaults that cost nothing:** contiguous containers (`std::vector`,
  `std::array`, `std::string`); `reserve()` when the size is known; pass
  large objects by `const&` and move what is handed over; no copies to
  satisfy an interface that could take a `std::span` or `std::string_view`.
- **A proven hot spot is made fast within the rules.** Remove work rather
  than checks: hoist a size check out of the loop and iterate with ranges or
  iterators, avoid allocation in the loop, choose a better algorithm or data
  layout. Never turn hardening or a sanitizer off for speed: configuration
  rejects it (section 6), and 14.1 shows the gain wouldn't be there.
- **Parallel computation:** section 15.5.

*Enforcement:* the build settings are presets and configuration checks;
"measure first" and before/after numbers rely on review.

## 15. Design

How a program is shaped, where sections 2 and 11 say how its parts are
written and arranged. It describes what both projects already do:
SimpleLocalServer and ToneMatcher have 71 `struct`s and 25 `class`es between
them, and no derived class or virtual function. Most of it is judgement, so
it relies on review; no rule here needs a tool the gate doesn't already run.

### 15.1 Data first

- **Plain data is a `struct`:** public members, no invariant between them.
  Behaviour is free functions that take it, in the module that owns the
  type. Such a function can be tested with a value built in the test, and
  read without knowing a class.
- **A `class` needs a reason.** It protects an invariant (its members must
  agree with each other, so only its functions may change them) or it owns a
  resource (a file, a handle, a temporary directory). Its data is private.
  Section 2.6 says how to write one; this says when.
- A type is one or the other: all data public, or all private. clang-tidy
  enforces that
  (`cppcoreguidelines-non-private-member-variables-in-classes`).
- No getters and setters around data that has no invariant: that is a
  `struct` with more code.

### 15.2 Closed sets and polymorphism

- **A closed set of kinds is an `enum class`** (the kinds differ in a value)
  **or a `std::variant`** (they differ in what they hold). A set is closed
  when the module that defines it knows every member. A `switch` over it
  has no `default`, so the compiler reports a kind that was added and not
  handled.
- **Behaviour passed in is a function parameter:** a template parameter or
  `std::function`, not an interface with one virtual function.
- **Inheritance is only for open runtime polymorphism:** code outside the
  module adds new kinds, chosen at run time. Neither project has needed it.
  When one does, section 2.6 applies, and the base class has no data.
- No inheritance to share code. Share it with a function or a member.

### 15.3 Containers and layout

- `std::vector` (or `std::array`, `std::string`) by default (14.3).
  `std::map` and `std::set` are right where ordered iteration or lookup by
  key is the point; ToneMatcher uses them fifteen times.
- **Layout for the cache is a technique for measured hot spots, not the
  default style.** Splitting an array of objects into arrays of fields can
  speed up a loop that reads one field of many objects. It makes the code
  harder to read, so it comes with a benchmark showing the gain (14.2).

### 15.4 Tests first where the behaviour is known

- **A bug fix:** the failing test is written first (13.4).
- **A function whose inputs and outputs are clear before it is written**
  (a parser, a conversion, a calculation): its tests come first, or in the
  same commit.
- **Not for code whose shape is still being found.** Write it, then test
  what it turned out to do before the commit that finishes it. Every
  behaviour still ends with a test (section 13); this is only about order.

### 15.5 Parallel computation

Single-threaded by default. Threads for work that must be concurrent (a
server's connections) follow section 2.8. Threads for speed need a
measurement first (14.2), and wait for libc++'s parallel algorithms where
those would do (W3 in section 12). This section will grow when they arrive.

### 15.6 The interface between a backend and its frontends

A program with more than one frontend (a command line and a window, or
later a phone) has three parts, each one or more layers (11.1): the backend,
which does the work and holds the dependencies (11.6); the interface, which
is what a user can do; and the frontends, which only present it.

- **Plain data in and out:** the interface's functions take and return
  `struct`s of section 15.1, standard-library types, and nothing from a
  third-party library. With `SOURCES_ONLY` (11.6) the audit enforces the
  last part.
- **Errors are values** (`std::expected`, section 3). No exception crosses
  the interface: the backend catches what its dependencies throw and returns
  it as an error.
- **It offers what a user can do, not what the backend contains.** One
  function per task ("match these tones"), not one per backend function. An
  interface that passes everything through hides nothing.
- **No second copy of the types.** The backend uses the interface's
  `struct`s directly wherever it can. A parallel set of types with
  conversions doubles every change.
- **Frontends hold no logic.** Validation, defaults and formatting that two
  frontends would both need live behind the interface. Behaviour is tested
  once, at the interface, without any frontend.
- An interface written this way can also be called from another language,
  which is what a phone frontend needs. Building for iOS and Android is not
  covered by this policy yet.

*Enforcement:* the `struct`/`class` split by clang-tidy; the rest relies on
review (section 8.1).

# C++ Project Policy

> **Version:** the `project()` version in `CMakeLists.txt`; changes are listed in
> `CHANGELOG.md`. Enforced by the `cpp-policy` module, clang-tidy config and self-tests.

This document defines the restricted, modern subset of C++ used by the
owner's projects, the ones that consume `cpp-policy`. **The owner** is the
person who decides for a project: what it does, the exceptions to these
rules it may have, and what joins its main line; the rules say "the owner"
for that role. Most rules are enforced mechanically (compiler warnings,
clang-tidy, the configure checks and the audit, section 8). This document is
the human-readable reference and the source of truth when a tool and this
text disagree.

---

## 1. Toolchain

| Item | Requirement |
|---|---|
| Language standard | **C++23**, compiler extensions **off** (`CMAKE_CXX_EXTENSIONS OFF`) |
| Compiler | **LLVM Clang** on all platforms: `clang++` on macOS/Linux, `clang-cl` on Windows |
| LLVM version | **23.x** (clang, clang-tidy and clang-format from the same release) |
| macOS | Every build is for **macOS 26.0** (`CMAKE_OSX_DEPLOYMENT_TARGET`, set by the presets), on a Mac with 26 or later |
| Microsoft toolset (Windows) | **MSVC 14.44** (Visual Studio 2022 17.14) or later: the standard library, runtime and libraries `clang-cl` builds with |
| Build system | CMake ≥ 3.29 (the oldest with every command the policy's scripts use), driven only through `CMakePresets.json` |
| Generator | Ninja |
| Dependencies | vcpkg in manifest mode (`vcpkg.json`); every project has one, since the test framework comes from it (sections 1.1, 13) |

Notes:
- Extensions are off so that the code is standard C++, which another
  compiler or a later Clang reads the same way (since 0.1.0).
- One compiler on every system, one release of it: one set of warnings and
  of clang-tidy findings, so a check passes or fails the same way everywhere
  (since 0.1.0). GCC and MSVC's own compiler (`cl.exe`) are not supported.
  They may be added later as extra build jobs without changing these rules.
- One generator, Ninja, on every system: the same build files and the same
  parallel build, from the same presets (since 0.1.0).
- On macOS use Homebrew LLVM, not Apple Clang. Apple Clang has a different
  version scheme and doesn't ship clang-tidy.
- clang-tidy and clang-format are located next to the compiler, so all three
  always come from the same LLVM release.
- **The standard library is part of the toolchain.** clang-tidy analyzes the
  library's code along with the project's, so the same code can get different
  findings with another version of it (since 0.17.0). On Windows the library
  comes with the Microsoft toolset, not with LLVM, so CI pins it as well:
  - Self-hosted Windows runners have exactly the toolset `gate.yml` names
    (`MSVC_TOOLSET`, now 14.44), and only that one, since vcpkg's port builds
    pick a toolset on their own. The CI gate stops a job on a runner with another
    toolset. The pin changes only in a cpp-policy release, like
    `LLVM_VERSION` (section 10.1).
  - GitHub's Windows image updates its own, newer toolset every few weeks.
    cpp-policy's own CI keeps it, so findings from a newer library show up
    there before any project moves to it.
  - Every CI job prints its standard library's version (MSVC toolset,
    libstdc++ or libc++), so a difference between two runs can be traced.

  On Linux the library is the distribution's libstdc++. On macOS it is
  libc++: its headers come with LLVM and are pinned with it, but the library
  a program runs with is the system's, and the headers refuse what the
  system the build is for doesn't have.
- **On macOS every build is for the same system, 26.0,** whatever the Mac it
  runs on. The presets set it, configuration fails without it, and the
  dependencies are built for it too.
  - *Why:* a build with no target is for the machine's own system, and
    code that compiles there can fail on an older one (since 0.34.0).
  - *Why 26:* the projects are the owner's own tools, and an older floor
    means writing by hand what the library has. The programs don't run on
    macOS 15 or older.
  - What a newer libc++ adds after 26.0 fails to compile everywhere, with
    the system that has it in the message (`introduced in macOS ...`).
  - The floor moves only in a cpp-policy release, like the LLVM pin (10.1).

### 1.1 Dependencies

Prefer the standard library. Add a library only when it saves real work the
project would otherwise have to write and maintain. When one is needed:

- **License:** permissive open source only: MIT, BSD-2-Clause, BSD-3-Clause,
  Apache-2.0, BSL-1.0, Zlib, ISC, 0BSD, Unlicense, CC0-1.0, IJG, libpng-2.0.
  No GPL: projects link statically, so the GPL would cover the whole program
  (since 0.3.0).
  LGPL or any other license needs a review and a change to this list, made
  in cpp-policy.
  - **A license written `A AND B` needs both on the list;** `A OR B` needs
    one. `libjpeg-turbo` is `BSD-3-Clause AND IJG`.
  - **A package's own dependencies are checked too,** so a package the
    project never named can be the one refused. The message says so.
  - **A package that is built and not linked** (libspng, which vcpkg's
    libjpeg-turbo port needs for a part a program may not use) still has to be
    on the list: the check is of what is installed. What a license asks of
    a distributed program applies to what is in the program. Confine its
    headers `TO NONE`, check once that the program has none of its symbols
    (`nm` on the unstripped release program), and say so in the reason of
    the package that brings it.
  - **IJG** (libjpeg-turbo) asks one thing of a program distributed without
    its source: its documentation says "this software is based in part on
    the work of the Independent JPEG Group". A project that uses it puts
    that sentence in its `README.md`.
  - The owner's approval of a dependency is about the need for it. It
    doesn't replace this list: a license outside it stops the build until
    cpp-policy's list changes.
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
each dependency with the system's compiler and none of the policy's settings:
another standard library in the same program, weaker hardening, and no
sanitizer to catch the project's mistakes at the boundary (since 0.15.0).

So vcpkg builds dependencies with cpp-policy's triplets, which `tools/vcpkg/`
holds:

| Triplet | Presets | Dependencies get |
|---|---|---|
| `cpp-policy-asan` | `dev`, `unit`, `check`, `win-dev`, `win-check` | AddressSanitizer, standard library hardening `debug` |
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
- **A build folder can change triplet** (other sanitizer options). vcpkg
  then replaces the dependencies, and
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
on another. `int` is 32 bits on every supported platform (since 0.2.0).

### 2.4 Preprocessor

| Banned | Use instead |
|---|---|
| Macros for constants | `constexpr` variables |
| Function-like macros | `constexpr` / `consteval` functions, templates |
| Include guards | `#pragma once` (the audit requires it in every header) |

Macros are still allowed for platform detection, build configuration and
include directives.

`#pragma once` departs from the Core Guidelines, whose SF.8 asks for include
guards because the pragma isn't standard. With one compiler on every system
it works everywhere, it has no name to invent or to keep in step when a header
is copied or renamed, and its one weak spot, two copies of the same header
included together, stops the compile with a redefinition error (since
0.1.0).

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

The styles are the ones the first projects already used (since 0.2.0).
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
  functions) while holding a lock; that is how deadlocks start (since
  0.3.0). When two locks
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

Formatting is clang-format's job (`.clang-format`, checked by the local and
CI gates): LLVM style with 4-space indents and a limit of **100 columns**.
80 would rewrap ordinary code, and 120 is too wide for side-by-side diffs
and phone screens; past 100 there are only `NOLINT` comments, which
clang-format doesn't wrap (section 5), and text embedded in the code (since
0.7.0).

`sh tools/hooks/tidy-files --format <file>...` formats the files named, and
`cmake --build --preset check --target policy-format-fix` every source. Both
only format: neither changes what the code says.

### 2.10 Idioms clang-tidy leads to

Some checks accept only one way of writing common code, and a first
clang-tidy run on code written without them reports hundreds of findings.
Check each C++ file right after editing it with `sh tools/hooks/tidy-files
<file>...` (section 8), not once the program works. The forms below pass;
`tests/good/idioms.cpp` shows several of them, and `tests/bad/` some of what
the checks reject.

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
  - **A command's output and error streams are two parameters,**
    `std::ostream& out, std::ostream& err`. When a function runs out of
    parameters (the limit is six), they travel as one: a struct of two
    pointers, built from references, by the rule above.
    ```cpp
    struct Streams {
        Streams(std::ostream& out_stream, std::ostream& err_stream)
            : out{&out_stream}, err{&err_stream} {}
        std::ostream* out; // never null: set from a reference
        std::ostream* err; // never null: set from a reference
    };
    ```
    A struct of two `std::ostream&` is what the check refuses.
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
- **A C library whose only error path is `longjmp`** (libjpeg). The wrapper
  in the confined module needs `setjmp` and `longjmp`, and two checks
  refuse each: `modernize-avoid-setjmp-longjmp`, and
  `cppcoreguidelines-pro-bounds-array-to-pointer-decay` for `jmp_buf`. One
  named suppression of both on each of the two lines, with the reason.
  (`cert-err52-cpp` says the same and isn't among the policy's checks; it
  needn't be named.) No object with a destructor may live between the
  `setjmp` and the call that can jump.
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
  fail on another (section 8). The cases met so far:
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
  - **An optional's value put back in an optional** (`return *number;`
    from a function that returns `std::optional`) is
    `bugprone-optional-value-conversion` with libstdc++ only. Return the
    optional itself, or build the new one from the value you mean.
  - **A `std::array`'s iterator kept in a variable:** it is a pointer in
    libc++ and libstdc++ and a class in the Microsoft library, so `const
    auto*` didn't compile on Windows, and `readability-qualified-auto`
    refused `const auto` on macOS. The policy's `.clang-tidy` now stops that
    check at a type alias (`IgnoreAliasing: false`): write
    `const auto found = std::ranges::find(table, value);`, which passes on
    every system. A plain pointer declared with `auto` is still reported.

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

- Such code lives only in the confined directories: `src/lowlevel/`, and in
  a library, `lib/<name>/lowlevel/`. Only cpp-policy sets them (section 6),
  so what the audit allows is the same in every project (since 0.42.0).
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
- a pragma or attribute that silences checks for the code around it:
  `#pragma clang system_header` (every warning in the rest of the file), and
  the attributes that turn a sanitizer or a protection off in a function,
  in any of their spellings (`[[clang::...]]`, `__attribute__((...))`,
  `__declspec(...)`): `no_sanitize` and its variants,
  `no_address_safety_analysis`, `disable_sanitizer_instrumentation`,
  `no_stack_protector`, `stack_protector_ignore`, `nocf_check`, `safebuffers`
  and `guard(nocf)`. The
  audit knows these names; one it doesn't know is still a suppression, and
  review's to find;
- a sanitizer suppression: an entry in a sanitizer's suppression list.

Rules, enforced by the suppression audit (the `policy-audit` target,
`cmake/scripts/audit_suppressions.cmake`):

1. A `NOLINT` **must name the specific check**. A bare `// NOLINT` is rejected.
2. Every suppression **must give a reason**, so that review can judge it
   where it is (since 0.2.0):
   - `// NOLINT(cppcoreguidelines-pro-bounds-pointer-arithmetic): parsing packed header in-place`
     (`NOLINTEND` is exempt: its `NOLINTBEGIN` gives the reason);
   - `#pragma clang diagnostic ignored "-Wold-style-cast" // SIG_ERR is a C cast`;
   - `// clang-format off: columns aligned by hand`;
   - `#pragma clang system_header // the system API below warns, not ours`,
     and the same trailing comment after an attribute that turns a check off.
3. `NOLINT`, diagnostic pragmas, `system_header` and the attributes that turn
   a check off are **only allowed inside confined areas** (section 4).
   `clang-format off` is allowed anywhere, since it only affects layout.
4. Wildcard suppressions (`NOLINT(*)`, `NOLINT(cppcoreguidelines-*)`) are rejected.
5. Sanitizer suppressions exist only in cpp-policy
   (`cmake/sanitizers/lsan.supp`, applied by the `dev` and `check` test
   presets). Each entry is a proven false positive inside the operating
   system or the sanitizer runtime, never project or library code, and says
   how it was shown to be false; the self-test reproduces it. Projects can't
   add their own.
6. **A test doesn't set a sanitizer's options.** `ASAN_OPTIONS`,
   `LSAN_OPTIONS` and the like in a test's environment are rejected at
   configuration, in `ENVIRONMENT` and, since 0.43.0, in
   `ENVIRONMENT_MODIFICATION`: `detect_leaks=0` there switched a check off
   where nothing showed it.
   - The one case with a way through: a test program that opens a window.
     On macOS, LeakSanitizer then reports what AppKit and CoreFoundation
     keep for the life of the process. Suppressing those by library would
     also hide a leak of the project's own under a callback, so they aren't
     in `lsan.supp` (since 0.28.0).
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
- `CMakePresets.json` and any CMake code that sets compile flags or link
  options (`target_link_options()`, `-Wl,...`). Naming a library or a
  system framework to link (`target_link_libraries(... "-framework
  AudioToolbox")`) is not a flag but a dependency: an agent asks the owner
  before adding one, as for any dependency (1.1), and then writes it.
- the git hooks in `tools/hooks/`, and any other `tools/` scripts
- with dependencies, `tools/vcpkg/` (how vcpkg builds them, section 1.1)
- the policy's part of `AGENTS.md` (above `## This project`), agent settings
  (`.claude/settings.json`)
- CI workflows (`.github/workflows/`)

Rules can't be switched off from CMake either. At the end of configuration
the module checks that every target the project builds (fetched dependencies
and excluded directories aside) calls `cpp_policy_apply()` and keeps its
settings:
- no options that turn warnings off (`-Wno-…`, `/wd…`, `-w`) on targets,
  source files or `CMAKE_CXX_FLAGS`;
- no options or definitions that weaken a protection the policy turns on:
  `-fno-stack-protector` (or the weaker `-fstack-protector`),
  `-fcf-protection=none`, `_FORTIFY_SOURCE` below 3 or undefined at all (the
  policy defines it at 3 itself; its own `-U` before that is the only one
  allowed), a standard-library hardening macro turned off, `-fno-sanitize=…`,
  and `clang-cl`'s `/GS-`, `/guard:cf-` and `/sdl-`; `CPP_POLICY_HARDENING`
  has no "off" value (7.2);
- no sanitizer option of the project's own: the sanitizers' options are
  the policy's, so any option that starts with `-fsanitize`, `-fno-sanitize`
  or `/fsanitize` is refused unless it is word for word one the policy
  passes itself (since 0.44.0). A list of the options that weaken a check
  would never be complete: clang 23 alone has several, and each LLVM
  release can add more. Among them: an ignore list (`-fsanitize-ignorelist=`), which
  silences a sanitizer by function or file for the whole build, and
  `-fsanitize-recover=`, which lets a test pass with a finding printed;
- no `-mllvm` or `-Xclang`, which pass any setting to the compiler's
  internals, the sanitizers' instrumentation among them (since 0.44.0);
- each of these also inside a generator expression, `SHELL:` or `-Wp,`
  (`$<$<CONFIG:Release>:-fno-stack-protector>`), and with the macro as a word
  of its own (`-U _FORTIFY_SOURCE`), since 0.42.0;
- no `SKIP_LINTING`, and no changes to `CXX_CLANG_TIDY`;
- no change to the excluded directories (`build`, `out`, `.git`,
  `third_party`, `external`, `vcpkg_installed`), which every check skips, or
  to the confined ones (section 4). An excluded directory added with one line
  had skipped every check with nothing printed (since 0.42.0).

Configuration fails otherwise.

Fortify is also checked where it takes effect: outside Debug, the policy
forces a small header (`cmake/fortify/fortify_check.hpp`) into every compile
of the project's own targets, and it stops the compile unless the macro is 3.
The compiler applies every definition from the command line before it,
whatever the spelling (a flag variable, a response file, `-Wp,`), so a route
the configure checks don't read still fails the build (since 0.42.0).

Projects can't change the rules locally:
- their `.clang-tidy`, `.clang-format`, `CMakePresets.json`, git hooks
  (`tools/hooks/`) and, with a `vcpkg.json`, vcpkg files (`tools/vcpkg/`) must
  match the policy's: the audit compares them byte for byte, and
  `tools/upgrade.sh` copies them;
- the policy's part of `AGENTS.md`, everything above `## This project`, must
  be the release's `template/AGENTS.md.in` down to that heading: the audit
  compares it and names the first line that differs (since 0.43.0);
- `.claude/settings.json` is copied by `tools/upgrade.sh`, but not compared;
- a CI workflow must call cpp-policy's `gate.yml`, pinned to the commit the
  build uses (the audit checks both, section 8);
- the build always uses the policy's copies of the configuration files (on
  Windows with one check off, W5 in section 12).

A project may only tighten what the module's options allow (for example
`CPP_POLICY_EXCEPTIONS OFF`). Any other change, stricter or looser, is made in
`cpp-policy` itself.

### 6.1 Repository files

- **`.gitignore` and `.gitattributes`:** cpp-policy's copies are the required
  minimum. A project's files must contain every line of them and may add their
  own (the audit checks it). They ignore build output, personal and editor
  state, and OS clutter, and force LF line endings on every platform:
  ignore files written by hand missed editor folders, and Git's line-ending
  conversion on Windows breaks the audit's byte comparison of copied files
  (since 0.2.0).
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
| `check` | The local gate | Full build + full clang-tidy + format check + tests under sanitizers + suppression audit; like `dev`, but compiled at `-O1` so the tests run 15 to 21 times faster (14.1) |
| `unit` | Quick check while working | Like `check` without clang-tidy, the audit and the format check; runs only the unit tests |
| `debug` | Step-through debugging | Debug, no sanitizers, standard library hardening (debug level) |
| `tsan` | Data races | Debug, ThreadSanitizer, standard library hardening (debug level), compiled at `-O1` like `check`; macOS and Linux only |

Windows presets carry a `win-` prefix. On Windows, `win-dev` and `win-check`
are optimized (`RelWithDebInfo`, see 7.3), so `win-debug` is the one to step
through. The `release` workflow runs the tests on the optimized build, where
some bugs only appear; it is meant for CI rather than every push. So is the
`tsan` workflow: ThreadSanitizer can't be combined with AddressSanitizer, so
it needs a build of its own, and `clang-cl` doesn't provide it (since 0.3.0).
`dev` and `debug` stay at `-O0`, so that a debugger shows every variable.

Test presets:
- Every test has a 60-second timeout, so a hung test fails instead of holding
  up a push (CTest's own default is 25 minutes). A unit program's 60 seconds
  are fixed; an integration or benchmark test may set a shorter `TIMEOUT`,
  or one up to 600 seconds with `SLOW` and a reason (13.2).
- **A test that times out gets one more run,** in every test preset
  (CTest's `after-timeout`), and the local gate's last lines and CI name each
  test that needed it: "timed out and passed on a second run".
  - *Why:* a test near its limit on a quiet machine passes it when other
    work shares the machine. Such a failure says nothing about the code, and
    costs an unattended agent 20 minutes or more each time (since 0.37.0).
  - *What it costs:* a deadlock that happens only sometimes is also a
    timeout, and passes on its second run. So **the local gate remembers,
    on the machine and across working copies, each test that needed a
    second run, and fails the second time one does**: a finding to take to
    the owner (since 0.42.0). The record is a file in the user's cache
    (`<cache>/cpp-policy/retried/<project>.txt`, one line per test), and a
    test's line is removed once its cause is fixed. CI starts fresh each
    time, so it only names the test.
  - **A test that holds a scratch folder** (13.4) gets its second run only
    if the killed run's lock is free at once: the lock names the process
    that holds it, which is gone.
  - Only a timeout is run again. A test that fails any other way fails.
    CTest can do this for every test or none, not for chosen programs.
  - A hung test takes twice its limit to fail.
- **In the `tsan` build every test's limit is three times what it is
  elsewhere** (60 seconds become 180), and the build is optimized at `-O1`.
  A project writes nothing for it.
  - *Why:* ThreadSanitizer costs several times what the check build's
    sanitizers do. The limit that catches a hung test in `check` was, under
    `tsan`, the real limit of every test, and nothing said so (since 0.35.0).
  - *Why `-O1` and not `-O2`:* it is what `check` runs at, and a higher
    level lets the compiler remove more of the memory accesses
    ThreadSanitizer watches.
  - A project doesn't choose which test programs run under `tsan`: a
    program left out would be watched by nobody.
- CTest gets eight jobs. Every test still runs alone unless the project calls
  `cpp_policy_parallel_tests()` (13.2).
  - *Why eight:* on a 10-core Mac, eight jobs took about 30% less time than
    four, and ten gained little more while bringing the slowest tests nearer
    their limits (since 0.41.0). On the home server (2026-11-10) the Windows
    virtual machine was fastest at eight, slower at thirty-two; Linux would
    gain about 75 s a run at sixteen, but shares its presets with macOS.
  - The number isn't taken from the machine's cores. The Windows virtual
    machine reports 32 processors and was slower at 32 jobs than at eight,
    and on the Mac ten gained 7% over eight. (A preset could say "as many
    as the machine has cores" only from presets version 11, which needs
    CMake 4.3; the policy's minimum is 3.29.) A runner with fewer than
    eight cores runs eight anyway, each test more slowly.
- The `dev` and `check` test presets turn on AddressSanitizer's leak
  detection (`ASAN_OPTIONS=detect_leaks=1`) and apply the policy's
  suppression list for false positives in the OS (section 5). Detection is on
  by default on Linux and off on macOS; `clang-cl` doesn't provide it.
- On macOS the same presets turn off the nano malloc zone
  (`MallocNanoZone=0`), as Xcode does whenever AddressSanitizer is on. With
  it on, libdispatch's cache of reusable work items is reported as
  thousands of leaks, because the pointers to it sit where LeakSanitizer
  doesn't look. Whether a terminal has the variable depends on the app that
  opened it; a self-hosted runner's service doesn't, so the presets set it
  (`tests/leak/nano_zone.cpp`, since 0.12.2).

ThreadSanitizer on Linux: threads that glibc creates internally, without
`pthread_create` (for example the helper threads of `getaddrinfo_a`), are
invisible to the runtime, and the first allocation on one of them crashes
the program. Check how your dependencies resolve names: cpp-httplib's
non-blocking `getaddrinfo` takes that path, so a project that uses it removes
that option from its `tsan` build only.

### 7.1 Warnings

On for every target of the project's own, and always errors (a library the
project uses is compiled as a dependency, section 11.7): `-Wall -Wextra -Wpedantic -Wshadow -Wnon-virtual-dtor
-Wold-style-cast -Wcast-align -Wunused -Woverloaded-virtual -Wconversion
-Wsign-conversion -Wnull-dereference -Wdouble-promotion -Wformat=2
-Wimplicit-fallthrough -Wzero-as-null-pointer-constant -Wextra-semi -Werror`.
With `clang-cl`, `/W4` replaces `-Wall -Wextra` (in `clang-cl`, `-Wall` means
`-Weverything`). Each warning on the list points at a bug, or at code the
subset bans (conversions that lose data, shadowing, old-style casts, null
pointers), and rarely fires on correct code; as errors, none is left for later
(since 0.1.0).

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
- UBSan runs with ASan, as on the other systems: its checks come from the
  ASan runtime the policy links, so it needs nothing more at the link. It
  was left out from 0.1.0 without being tried, and found to work in 0.43.0;
  the self-test `ub/detected` checks on every system that a signed overflow
  is reported and stops the program.
- ThreadSanitizer isn't available with `clang-cl`, so Windows has no `tsan`
  workflow.

### 7.4 Hardening with `clang-cl`

Every configuration but Debug gets Control Flow Guard: `/guard:cf` when
compiling (indirect calls are checked against a table of valid targets) and
when linking (the table and the PE flag; lld-link doesn't add them on its
own). Stack cookies need no flag: `clang-cl` compiles with a strong stack
protector by default (`-stack-protector 2`, the equivalent of
`-fstack-protector-strong`). The configure checks reject the options that turn
either off, in both spellings (`/GS-`, `-guard:cf-`, `/sdl-`, ...). The
self-test reads a program's PE header and requires `GUARD_CF` with a non-empty
function table, plus lld-link's ASLR and no-execute defaults (`DYNAMIC_BASE`,
`HIGH_ENTROPY_VA`, `NX_COMPAT`).

## 8. Enforcement layers

| Layer | When | What |
|---|---|---|
| Editor (clangd) | While typing | clang-tidy diagnostics, formatting |
| `tools/hooks/tidy-files` | After editing C++ files, run by whoever edited them (agent or person) | What the local gate will say about those files, without the tests: the format, the audit's rules about one file (length, suppressions, `// boundary:`, test-case names) and clang-tidy, a few seconds each. A header is checked through a source that includes it, with that source's flags |
| Git pre-commit | On commit | `tidy-files` on the staged files only (the format, the audit's rules about one file, clang-tidy); nothing at all for a commit without a C++ file; warns when a staged file has unstaged changes, since it checks the working folder |
| Git commit-msg | On commit | The message follows section 8.2 |
| Git pre-push | On push | The local gate (below); refuses to run with uncommitted changes, so it tests exactly what is pushed |
| CI (GitHub Actions) | On push, to any branch | The same gate on Linux, Windows and macOS, through cpp-policy's reusable `gate.yml`, pinned to the same commit as the build (the audit checks it); on GitHub's machines or the owner's own (README) |

The git hooks come from cpp-policy (`tools/hooks/`); projects copy them
unchanged and enable them once per clone with `git config core.hooksPath
tools/hooks`. Configuration warns while a clone hasn't done so. Hooks each
project wrote for itself were compared by nothing, and a clone without the
setting skipped every check silently (since 0.3.0).

- **The commit hook checks what is committed, and the local gate the whole
  tree.** A half-written file that isn't part of a commit doesn't stop it,
  and a commit of documents alone configures and builds nothing (since
  0.41.0).
- **`tidy-files` says how many files it has, then names each one** as
  clang-tidy starts on it, so a long run isn't silent. When a
  `CMakeLists.txt` changed since the last configure, it configures again
  first, as the build would (since 0.41.0).
- **The local gate's audit and format check skip drafts:** files git doesn't
  track that no target compiles. They are named, as not checked. A new
  source that the build compiles is checked, tracked or not (since 0.41.0).

**Two gates.** The *local gate* is `cmake --workflow --preset check`
(`win-check` on Windows), run through its launcher, `sh tools/hooks/gate`:
configure, the audit and the format check (first: they take seconds, and a
fault in them shouldn't wait for the compiler), build with clang-tidy, and
tests under sanitizers. It is the only definition of "passes the policy";
every other local layer is a faster subset of it. The *CI gate* is
cpp-policy's `gate.yml`, which runs the check, release and tsan workflows on
each system a project lists. *The audit* is the script
`cmake/scripts/audit_suppressions.cmake` (suppressions, layers, includes,
file sizes, test names, copies of the policy files, CI pins); the checks
that run while CMake configures (section 6) are *the configure checks*.

**A stage reaches `main` through CI.** A stage ends on a branch of its own,
which is pushed; the CI gate runs on it, and the stage joins `main` once it
is green on every system and the owner has said so. A private repository's
branches are not published by this. *Why:* a stage pushed to `main` after
a local gate alone is checked on one system, and the faults the others find
land on `main` (since 0.41.0).

In CI, a run that a newer push to the same branch made obsolete is
cancelled (`gate.yml`): stopped on a branch; on the default branch the run
in progress finishes and only runs still waiting are dropped. A cancelled
run is neither a pass nor a failure, and no rule needs every pushed commit
to have a result: pre-push ran the local gate before the push, and a
release is tagged on the commit whose run is green (section 10).

**A tag push starts no run.** The CI file runs on branches only
(`branches: ['**']` under `push:`, from the template; `upgrade.sh` adds it
to a bare `push:`): the tag goes on a commit whose run was green, so a run
for it would test the same files again, and could only fail by chance
(since 0.43.0).

**The launcher.** `sh tools/hooks/gate [workflow]` runs the workflow and
adds what a machine shared by several unattended agents needs (since
0.29.0):
- **One gate at a time on the machine;** a second waits for the first, since
  gates that run together share the processors and each takes several times
  as long. The lock is a folder, one per user and machine, for every project
  and checkout on it; `CPP_POLICY_GATE_LOCK` names another folder. A lock
  whose process is gone, or that names none after a minute, is taken over;
  a lock path that can't be a folder fails at once. CI's jobs don't take
  it, so on a machine that is also a runner, a CI job and a local gate can
  run together.
- **The machine stays awake** (macOS and Linux): a test that sleeps with the
  machine passes its time limit and is reported as failed.
- **One last line,** `gate: passed` or `gate: FAILED`, and the workflow's own
  exit code, so that a command chained after it can't hide the result.
- **Before that line, the passing tests close to their time limit** (13.2),
  and the tests that needed a second run (section 7).
- **A workflow that failed is remembered until it passes in that folder
  again,** and pre-push refuses meanwhile, naming it. The push's own gate is
  the check workflow, so a failed `release` or `tsan` run would otherwise
  travel with the push (since 0.36.0). A commit can't be refused for this:
  the commit after a failed gate is usually its fix.
- **A workflow that passed on a commit is remembered too,** when nothing
  was uncommitted before or after it, and pre-push doesn't run the local
  gate again on that commit in that folder: the end of a stage runs it and
  the push follows (since 0.37.0). Any new commit, or a gate that fails,
  forgets it.
  - The hook stays for a project whose CI runs on the same
    machine: the hook keeps a red commit from being pushed, and CI is the
    layer that doesn't depend on the agent. CI's own run on the same Mac
    stays too: it starts from a clean checkout in a clean folder, so it
    finds a file never committed or a leftover in a stale build folder,
    which a local gate can't.

pre-push runs the local gate through it.

**When the local gate runs.** Work is done in stages: a stage is what ends in a
push or in a merge into the main line.

- **The local gate runs at the end of each stage, and always before
  anything joins the main line.** Not before every commit: between commits
  the commit hook and `tidy-files` say what the local gate would say about the
  files changed. *Why:* a gate before every commit took most of an
  unattended agent's time, and over fifteen stages caught nothing a gate
  per stage missed (since 0.31.0).
- **A stage that adds or changes tests also runs the release workflow
  once** (`sh tools/hooks/gate release`) before it ends. The local gate is
  the check build; a test can pass there and fail in the release build, where
  the code is optimized and timing differs.
- **A stage that touches code that runs on more than one thread, or its
  tests, also runs the tsan workflow once** (`sh tools/hooks/gate tsan`,
  on macOS and Linux) before it ends: data races are found there and
  nowhere else (since 0.35.0).
- Which tests to run between commits is the agent's judgment (those of the
  modules it touched); no tool checks it, so it is advice in `AGENTS.md`
  and not a rule here.

Every layer works the same for any agent and for people: they are commands
and git hooks, and `AGENTS.md` says when to run them. An agent with a hook
system of its own may call `tidy-files` from it after each edit, but the
policy relies on nothing agent-specific.

**The tidy cache.** clang-tidy is about two thirds of a check build, and a
developer's gate and a CI runner on the same machine checked the same commit
twice (since 0.41.0). The build runs clang-tidy through
`cmake/scripts/tidy_cache.cmake`, which remembers each file that passed,
under a fingerprint of everything clang-tidy reads for it: the program
(its path, size and date), its options, the policy's configuration, the
compile command, and the path and contents of every file the compile
includes, listed by the compiler on each run. A file whose fingerprint has
passed before isn't checked again; a file with a finding is checked every
time. The source and build folders are replaced by placeholders, so two
checkouts of one commit share their entries, except when either folder's
path matches the configuration's `ExcludeHeaderFilterRegex` (a project
under an `external/` folder), where clang-tidy would see the headers
differently.
- The cache is one per user and machine: `~/Library/Caches/cpp-policy/tidy`
  on macOS, `~/.cache/cpp-policy/tidy` on Linux,
  `%LOCALAPPDATA%\cpp-policy\tidy` on Windows. `CPP_POLICY_TIDY_CACHE`
  names another folder, or `off`. Entries are empty files; those unused for
  30 days are removed by a configure, at most once a day.
- GitHub's own machines start empty each time and gain nothing from it.
- The self-test `tidy/cache` changes each input in turn and checks that
  only the files it concerns are checked again, and that a finding fails
  the build whatever the cache holds.

A passing gate proves the policy on the system that ran it, with that
system's standard library and headers: libc++ on macOS, libstdc++ on Linux,
the Microsoft library on Windows. clang-tidy reads each one, and they differ
(section 2.10), so a green `pre-push` on a Mac says nothing about the other
two. The CI gate covers the systems a project lists; it is the authority for
them.

The `check` build presets keep going after a file fails (`-k 0` to Ninja),
so one run reports every finding instead of the first.

### 8.1 What no tool checks

Review covers these, and agents following `AGENTS.md`. `AGENTS.md` sends an
agent here at the end of each stage.
- 1.1: a dependency is lightweight and alive; the ports' changes read before
  `builtin-baseline` moves; no vcpkg binary cache the project doesn't
  control.
- 5: an attribute that turns a sanitizer or a protection off under a name
  the audit doesn't know.
- 2.1: a reference, not a pointer, for an argument that must be present.
- 2.2: `const char*` as a string type (a pattern can't tell it from `argv`
  or a pointer into a buffer); pointer and length parameters (indexing the
  pointer is caught as pointer arithmetic).
- 2.7: file names in `snake_case`.
- 2.8: atomics beyond flags and counters outside confined areas; manual
  `lock()` and `unlock()`; lock scope and order; the catch at the top of
  every thread function; a class safe from several threads says so. Data
  races are found by the `tsan` workflow only where tests exercise them.
- 3: a `catch (...)` really at a boundary, and an `// rtti:` reason that
  holds (the audit requires both to be stated); `[[nodiscard]]` on functions
  that return `std::expected` (ignoring the result is caught).
- 4: the comment on why a confined source file is confined.
- 9: how agents work for the owner, as `AGENTS.md` states it.
- 10.1: the text that names the toolchain pins (README, `AGENTS.md`).
- 11: extracting a helper (11.2), the target of 250 lines a file (11.3),
  comment and document accuracy (11.4), the changelog's rejected options
  and the roadmap's layout (11.5), a confine line for every dependency
  (11.6), a library release green on every system (11.7).
- 13.4: `REQUIRE` versus `CHECK`, one behavior per test, fakes, no sleeps,
  tests through public headers, real data used by hand.
- 13.5: a size budget on every system for each shipped program, and a
  memory test for every server.
- 14: measuring before optimizing, with numbers before and after.
- 15: the design rules.

clang-tidy's rules of section 2 have samples in `tests/bad/` that it must
reject (one in a header, proving headers are checked), and so do the
function size limits of section 11.3. The audit's rules, such as `#pragma
once` and suppressions, have fixtures in `tests/audit/`.

### 8.2 Commit messages

Commits follow [Conventional Commits](https://www.conventionalcommits.org) and
say why: subjects that say what kind of change each commit is can be scanned
and turned into release notes, and the body keeps the reason (since 0.8.0).

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
  as `Co-Authored-By:` don't count as the body. The body holds the reasons
  about the change itself; a reason that someone changing the code later
  will need goes in the code (11.4).
- Release commits are `chore(release): <version>`.
- Messages git writes itself pass unchecked: merges, reverts, `fixup!`,
  `squash!` and `amend!`.

The `commit-msg` hook checks all of this. History from before the hook is
left as it is.

## 9. AI agents

"The owner" is the person who decides for a project (the introduction);
`AGENTS.md` uses the word the same way.

- Agent instructions live in `AGENTS.md`. Projects don't have a `CLAUDE.md`:
  Claude Code (v2.1.277 or later) reads `AGENTS.md` directly, but only when no
  `CLAUDE.md` exists, so adding one would hide `AGENTS.md` from it. Agent
  settings deny creating `CLAUDE.md`.
- **A new project is created with `tools/new-project.sh`** (README,
  "Starting a new project"), never by writing its build files by hand. The
  generator gives it the pinned release, the copied policy files, the git
  hooks, the layers, the tests, `ROADMAP.md` and `AGENTS.md`;
  the audit compares several of those with the release's, so a hand-written
  setup fails it. That holds for a port too: generate the project, then
  bring the code in.
- **A rule that seems wrong or impossible for a project is reported, not
  worked around.** The agent stops and writes what the rule prevents, for
  the owner to take to cpp-policy, where the rule is changed if it is wrong.
- Agents check each C++ file they edit with `sh tools/hooks/tidy-files
  <file>...`, and run the local gate at the end of each stage, when section
  8 says.
- Agents must not add suppressions, edit policy files (section 6), or bypass
  git hooks (`--no-verify`).
- Where the agent supports permission rules, they back these rules up, but
  only partly: they block the agent's own file-editing tools and the
  `--no-verify` flag, not every shell command that could do the same (such as
  `sed -i` on a policy file, or `git -c core.hooksPath=…`). Most of what an
  agent can't be stopped from doing is caught afterwards: the audit rejects
  edited copies of `.clang-tidy`, `.clang-format`, `CMakePresets.json`, the
  hooks, the vcpkg files and the policy's part of `AGENTS.md`, and a CI
  that doesn't call the CI gate; the configure checks reject weakened build
  settings; and the CI gate runs again on a clean machine. An edit to the
  agent settings isn't caught: `upgrade.sh` puts them back at the next
  upgrade. Agent settings are a guide, not a security boundary. An edit to
  `AGENTS.md` is asked, not refused: below its heading it is the project's,
  and changes with the owner's word.
- **An upgrade is the owner's, or an agent's with the owner's word for that
  upgrade.** `upgrade.sh` writes files no agent edits otherwise (`tools/`,
  `.claude/`, `AGENTS.md`), and a release may ask for `AGENTS.md` to be
  pruned by hand; with the rule naming no one, an agent couldn't do either.
  What is under `## This project` is the project's own instructions: an
  agent changes them with the owner's word (since 0.43.0).

**How agents work for the owner** is the section of that name in
`AGENTS.md`, part of the policy's text that `upgrade.sh` refreshes. Its
rules came from a review of every complaint the owner had made more than
once in three weeks of work with agents (since 0.41.0). A project file
can't override an agent's own safety rules, and doesn't try: the rules are
about how to work.

## 10. Versioning

- `cpp-policy` uses semantic versioning. Projects pin the **commit** of a
  release tag, with the tag name in a comment
  (`GIT_TAG <commit>   # v0.3.0`). A tag can be moved to other code later; a
  commit can't. That matters because cpp-policy's CMake code runs on every
  machine that configures a project.
- Projects upgrade with `tools/upgrade.sh <tag>` (README, "Upgrading"): it
  moves both pins and the copied policy files together and checks the result.
  In the CI file it also adds `branches: ['**']` under a bare `push:`, and
  names any other push trigger (section 8).
  It also brings the release's text into `AGENTS.md`: everything above the
  heading `## This project` is the policy's and becomes the release's, and
  what follows that heading is the project's own, left as it is (since
  0.42.0). It updates the changelog's `Policy:` line too (11.5).
- The version is defined once, in `project(cpp_policy VERSION ...)` in
  `CMakeLists.txt`. A release commit sets it, adds the release to
  `CHANGELOG.md` (each change with its reason), updates the tag in the
  `README.md` example, and gets an annotated tag `v<version>`.
- A release's `CHANGELOG.md` entry starts its "Upgrading a project" steps
  with **"Work beyond `upgrade.sh`"**: "none", or what a project has to
  change. The owner can then batch the releases that need none.
- A release that changes what projects must write (a test recipe, a rule) is
  first run on each shape it applies to, on all three systems: at least a
  batch command and a server with a thread pool. A recipe developed on one
  shape can fail on the other at first contact (since 0.24.2).
- **Major:** a new rule or tightened rule that can break existing code.
- **Minor:** new optional features, new presets, tooling improvements.
- **Patch:** fixes that never make passing code fail, for example removing a
  false positive.
- **Before 1.0**, the minor version takes the major's role: `0.x` to
  `0.(x+1)` may break existing code, while patch releases still never do.

### 10.1 Moving the toolchain pins

The toolchain is pinned in four places, which move only in a cpp-policy
release:

| Pin | Where | What depends on it |
|---|---|---|
| LLVM major | `CPP_POLICY_LLVM_MAJOR` (`CppPolicy.cmake`), `tools/vcpkg/llvm.cmake`, the presets' search paths, `LLVM_MAJOR` in `gate.yml` | Every machine: configuration fails with another major |
| Exact LLVM on Windows CI | `LLVM_VERSION` and its SHA-256 in `gate.yml` | GitHub's Windows jobs; self-hosted Windows runners install the same archive |
| Microsoft toolset | `MSVC_TOOLSET` in `gate.yml` | Self-hosted Windows runners (section 1) |
| macOS floor | `CPP_POLICY_MACOS_TARGET` (`CppPolicy.cmake`), the presets, the triplets | Every Mac build (section 1) |

LLVM patch releases on macOS and Linux aren't pinned: machines take them
within the major in their normal updates. The self-tests `toolchain/pins`
and `vcpkg/triplet_files` check that the files name the same LLVM major and
macOS floor; text that names them, such as the README's, is checked by
review.

**When.** The pins move in a *toolchain window*, twice a year. Each LLVM
major release opens one, about every six months. The target is the newest
patch release of the new major when the window opens, never its `.1.0`,
which tends to have regressions; the Microsoft toolset moves in the same
window. Outside a window, a pin moves only for a fix that is needed.
*Why:* the owner wants newer toolsets now and then, and a pinned toolset
can only move with the runner machines and the projects in a known order;
the owner chose two windows a year, one release each (since 0.18.0).

Homebrew's `llvm` moves to a new major within days of its release. The
major the policy pins then stays available as `llvm@<major>`, which the
presets, the vcpkg toolchain and the CI gate look for first. On a Mac,
`brew install llvm@23` keeps a project building until its policy moves.

**What a project does in a window.**
- Before the switch, it builds with the candidate toolchain against the
  policy's branch, on every system
  (`-DFETCHCONTENT_SOURCE_DIR_CPP_POLICY=<branch checkout>`), and fixes its
  findings in code that passes with both toolchains. When no such code
  exists, the fix goes into the upgrade commit instead.
- On the agreed day, once the runner machines have switched, it upgrades
  right away (`tools/upgrade.sh`): until then its self-hosted Windows jobs
  stop at the toolset check.
- If a project can't pass on that day, the projects that upgraded revert
  their upgrade commit, and the release is adopted in a later attempt.
- Its first run after the switch prints the new versions ("Show the
  toolchain").

cpp-policy's own steps for a window (trials, runner machines, snapshots,
roll-back) are in `MAINTAINING.md`.

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
  (since 0.28.0).
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
| Limit | 350 | Split by responsibility before adding more |
| Limit, test sources (under `tests/`) | 500 | The same |

A file of one responsibility rarely needs more than 250 lines, and one past
350 usually holds two; the limit makes the split happen when it is cheap.
An agent reads a file whole, and 250 lines fit in one careful read (since
0.2.0, enforced since 0.6.0).

- When a new feature would push a file past the target, split the file by
  responsibility first, then add the feature.
- A test source may be longer because it is mostly tables of cases and
  expected text; its length doesn't mean mixed responsibilities (since
  0.28.0). The limits on functions are the same everywhere.
- `tidy-files` reports a file's length after an edit, and says so from 50
  lines before the limit, so the split comes before the next feature.
- Functions are limited separately by clang-tidy: at most 80 lines, 6
  parameters and 4 levels of nesting (`readability-function-size`), and a
  cognitive complexity of 25 (`readability-function-cognitive-complexity`).
  Code inside macros isn't counted, so doctest's assertions don't fill a
  test's budget (since 0.26.3); outside tests the policy allows almost no
  macros (2.4).

*Enforcement:* the audit fails on a source file over 350 lines, or 500 under
`tests/`, outside excluded directories. The target of 250 is left to review.

### 11.4 Comment and document accuracy

- Comments describe the **current** behavior, never its history ("used to",
  "now also"): their reader needs what the code does, and the history is in
  the commits (since 0.2.0).
- When code changes, related comments change in the same commit, **and so
  does every document and every text the program shows its users** (its
  help, its messages). A change of wording isn't finished until a search
  for the old wording finds nothing (since 0.41.0).
- **A reason goes where its reader will look:** in the code when someone
  changing that code later needs it; in the commit message when it is about
  the change itself (8.2).
- Prefer describing meaning over repeating values that live in constants
  ("at most `max_message_bytes`", not "at most 4096 bytes"): a value written
  twice goes stale when the constant changes (since 0.2.0).
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

- **A decision is recorded with the options it rejected.** When a change
  chose between options, its changelog entry names the ones not taken and
  why; a later entry that reverses it names the entry it replaces. The
  changelog is dated and only added to, so it is the project's record of
  decisions: no separate decision log, which would be a third place for
  reasons beside the changelog and the commits, and go stale. A glossary of
  the project's own terms is welcome where it has some; it is not required.
- **Documents written by hand that describe the current state go stale;**
  the others don't (the changelog is added to, a list a script checks fails
  loudly). So they are kept few and short, and reread when a stage closes.
- **No code for old formats nobody depends on.** Until someone outside the
  project depends on a format (a file, a configuration, a library's
  interface), there is no code to read its old versions: data in an old
  format is converted once, with the owner's word, and the old reader is
  not kept: code nobody needs is debt. The test is who depends on it, not
  the version number (since 0.41.0).

**The version is written once,** in `project(<Name> VERSION ...)` in
`CMakeLists.txt`. A program that prints its version gets it from there, as
a compile definition for the file that prints it
(`target_compile_definitions(... PRIVATE APP_VERSION="${PROJECT_VERSION}")`,
which the policy's check of definitions accepts), not from a second constant
kept by hand. The definition goes on the target that holds the code that
prints it. **A library gets its release with `VERSION_IN <file>` in
`cpp_policy_library()`** (section 11.7): in a project that uses it,
`PROJECT_VERSION` is the user's. It is build configuration, which section
2.4 allows as a macro, and the code gives it a name and a type at once:
`constexpr std::string_view version = APP_VERSION;`. A version kept in two
places is changed in one at release (since 0.33.1).

**cpp-policy upgrades are one line.** `CHANGELOG.md` is about the program.
Its introduction has a line `Policy: cpp-policy v<version>.`, updated in
place at each upgrade. An upgrade gets an entry only for what it changed in
the project's own code or tests, with the reason; why the policy changed is
in cpp-policy's `CHANGELOG.md`, and git history has every upgrade commit.
An entry per upgrade fills the changelog with releases that changed nothing
in the program (since 0.24.2).

`ROADMAP.md` has up to four parts,
in this order:

```markdown
# Roadmap

## Now

Pairing code: the server prints it; checking it on the device is half done
(`src/pairing/`), its tests are written. Open: is a code valid for one
device or for all? Next: the check, then the phone test.

## 0.4.0 (in progress)

**Goal:** the server can be used outside a trusted home network.

### Scope

- [x] The server prints a pairing code at startup.
- [ ] A device must send the code before it can post messages.

### Out of scope

- HTTPS: devices would need certificates they trust.

### Validation

- [ ] The CI gate passes on every system.
- [ ] Pairing works from a phone and from another computer.

## Later

- [ ] A QR code for the address and the pairing code.

## Not planned

- Access from outside the local network: the server is for one home.
```

- **"Now"** is the state of the work, rewritten at the end of each stage or
  session: done, half done, open questions, the next step. A fresh session
  with only the files must be able to carry on from it (section 9).
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
  already record these, and hand-kept copies go stale (since 0.16.0).

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
  - An include is allowed when any one line allows it. A narrower line
    therefore restricts nothing beside a wider one: with `lib/ TO a b c` in
    place, `lib/parse/ TO a` leaves `lib/parse/` open to `b` and `c` too.
- **`TO NONE`** keeps a header from every module:

  ```cmake
  cpp_policy_confine_includes(tonematcher/ TO NONE)
  cpp_policy_confine_includes(tonematcher/parse/ TO project app)
  cpp_policy_confine_includes(zlib.h TO NONE)
  ```

  Since lines add up, the first two open one folder of a library to two
  modules and leave the rest of it to nobody: the way to say which parts of
  a library a project uses. The third is for a package that only a library
  needs (11.7) and none of the project's own code includes. `NONE` stands
  alone after `TO`; the same name on a `NONE` line and on a line with
  modules is refused.
- **`SOURCES_ONLY`** allows the include only in those modules' source files,
  not in their headers. A header that includes the library passes it on to
  every file that includes that header, in any module. With `SOURCES_ONLY`
  no header can, so the library's types can't appear in the module's
  interface. Use it wherever the interface doesn't need them.
- Every dependency in `vcpkg.json` has such a line (doctest and nanobench
  are used only by tests): the modules that include it, or `NONE` when only
  a library the project uses does.
- The lines are about what a file includes itself. A module that gets a
  dependency's types through another header (a library's, or another
  module's) needs no line of its own for them: that header's interface is
  what passes them on, and `SOURCES_ONLY` is what stops a module's headers
  from doing so.
- This is the rule behind a backend with several frontends (a command line,
  a window, later a phone): the frontends include the backend's interface,
  written with the project's own plain types (section 15.1), and nothing
  else of it.

A module named on a line that includes none of the line's headers gets a
note from the audit, not an error: the line says more than the code does.

*Enforcement:* the audit rejects, under `src/`, an include of a named header
(written with `<>` or `""`) from any other module or from `main.cpp`, and
with `SOURCES_ONLY` from any header, and with `NONE` from anywhere. It also
fails if a line names a module that `src/` doesn't have. That every
dependency has a line relies on review.

### 11.7 A library used by other projects

A project may offer a library, with or without programs of its own, and
another policy project may use it. Both keep their gates, and no code is
copied: copies diverge from their source within days (since 0.30.0).

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
  runs. `CMakeLists.txt` doesn't repeat the `find_package()` calls.
- **The library's target is `<name>_library`, linked by its alias
  `<name>::<name>`.** The plain name `<name>` is left for the program,
  which is usually called like its library (`tonematcher`).
- **The library has layers of its own** (`LAYER`, from the lowest up), and
  its `lowlevel` module is a confined area (section 4). The program's
  layers, in `cpp_policy_layers()`, are all above it.
- **The library doesn't include the program.** A dependency's headers are
  confined to its modules as `<name>/<module>` (11.6).
- **A library that relies on what a release gives the build says so:**
  `NEEDS_POLICY 0.38.0` in `cpp_policy_library()`, the oldest cpp-policy a
  project that uses it may be on. Configuration then fails in an older
  user, with the release to upgrade to, where a README could only say so
  (since 0.38.0). v0.38.0 is the first release that knows the word, and an
  older one fails on the word itself: so a library that uses it needs
  v0.38.0 at least.
- **A library that says its release gets it from the policy:**
  `VERSION_IN <file>` names the one of its `SOURCES` that is compiled with
  `<NAME>_VERSION="1.2.0"` (the library's name in capitals), read from
  `project(... VERSION ...)` in the `CMakeLists.txt` beside `library.cmake`.
  The version stays written once (11.5), and is the library's in a user's
  build too, where `PROJECT_VERSION` is the user's (since 0.40.0).
  Configuration fails when that line has no number. v0.40.0 is the first
  release that knows the word: a library that uses it says `NEEDS_POLICY
  0.40.0`, so that an older user is told what to do.
- A project offers one library. Its tests are the project's tests, and its
  version, tag and changelog are the project's, so they describe it whole
  (since 0.30.0).
- **A header in `lib/<name>/<module>/internal/` is that module's own.** No
  other module of the library includes it, and no user does: both audits
  refuse it. Every other header of the library can be included by a user.
  A comment saying "internal" stopped nobody (since 0.31.0).
- **A C library's type stays out of a header behind a class with a hidden
  state,** which keeps the library's header in one source file; a forward
  declaration of the C type is refused for its name (since 0.31.0).
- **What only tests use is offered apart,** as `<name>::test_support`:
  `TEST_SUPPORT <files>` in `cpp_policy_library()`, with `TEST_LINK` for what
  they link. They are files of the library's modules that aren't in
  `SOURCES` (a folder for scratch files, sample inputs), checked as test
  code. The library's tests link it, and so do a user's. They go in a module
  of their own (`testing`), which is in a `LAYER` like any other: the top
  one, since a helper may use anything in the library and nothing in the
  library may use it. Headers alone are enough; no source file is needed.
- **A release of the library is a tag on a commit whose CI was green on
  every system.** That commit is the release commit: it names the release in
  `CHANGELOG.md` and sets the version, it is pushed, and the tag goes on it
  once its run is green. One run, and the tagged tree's changelog says which
  release it is. (Tagging first and naming the release in a later commit
  leaves the tagged tree calling its own changes "Unreleased".) A user
  compiles the library's code for systems it may never build on itself, and
  the library's CI is the only place that code met a compiler. A change
  that alters a result on purpose says so first in `CHANGELOG.md`.

**In the project that uses it**

```cmake
cpp_policy_use_library(tonematcher
    GIT_REPOSITORY https://github.com/luiserh1/ToneMatcher.git
    GIT_TAG        <commit>)   # v0.4.0
target_link_libraries(app_core PRIVATE tonematcher::tonematcher)
cpp_policy_confine_includes(tonematcher/ TO NONE)
cpp_policy_confine_includes(tonematcher/image/ TO textures)
cpp_policy_confine_includes(tonematcher/parse/ TO textures settings)
cpp_policy_confine_includes(zlib.h TO NONE)   # only the library includes it
```

- **A release, pinned by commit,** with the version in a comment, like
  cpp-policy's own pin (section 10).
  `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh --library <name>
  <tag>` moves it and runs the local gate: the script is in the build folder's
  copy of the policy, as for a policy upgrade (section 10); a project has no
  `tools/upgrade.sh` of its own.
  Moving it by hand is the same change: the commit and the version in its
  comment, one line, and then the local gate. The script exists to get the commit
  of a tag right.
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
  (11.6): `TO NONE` for the library as a whole, and a line for each of its
  modules that the project uses. Lines add up, so one line that gives the
  whole library to many modules would undo the narrower ones.
- **Its packages don't travel:** vcpkg doesn't read a manifest through a
  fetch. This project's `vcpkg.json` lists each package the library needs,
  with its reason ("ToneMatcher's library reads PNG with it" is one), and
  configuration fails if one is missing.
  - The library's `library.cmake` calls `find_package()` for them; this
    project calls it only for what its own targets link.
  - A package none of this project's code includes is confined `TO NONE`.
- **The first build after a library replaces copied code is a whole one:**
  every file that includes it is compiled and checked again, and the
  commit's hook checks every file staged. It happens once (since 0.33.0).
- **Its code counts in this project's budgets** (13.5): each program's size
  and memory. When a release of the library takes a program past a budget,
  the commit that moves the pin raises it, with the owner's approval and
  the library named as the reason.

**A library in a private repository.** On a developer's machine git fetches
it with the developer's own access. The CI gate needs a token that can
read that repository: the owner creates it, stores it as a secret of the
user's repository, and passes it to the CI gate as `library_token` (README,
"Continuous integration"). The CI gate gives it to git for that job only, as a
header sent to the libraries' addresses and to no other. Agents never see
or handle it.

**Not supported yet:** a project that is only a library; a library that
uses a library.

*Enforcement:* the audit rejects, in the library's project, an include from
`lib/` of anything but `"<name>/<module>/…"`, an include of a higher layer
of the library, a module of `lib/` in no layer, and another module's
`internal/` header. In the user's project the audit rejects an include of a
library's `internal/` header, and configuration rejects a pin that isn't a
commit, a library below the floor and a missing package. That a release
was green on every system relies on review.

## 12. Waiting on the toolchain

Some decisions work around features the toolchain doesn't provide yet. Each
one is listed here with what would end it. The code that works around it
carries a `Waiting Wn` comment, so every place to change can be found when
the item resolves.

Items are reviewed at every toolchain upgrade (LLVM releases a major version
about every six months, section 10.1; CMake a minor one about every four).
Where a compile can tell, a probe in the self-test does it for us: it fails,
on purpose, the day the feature appears, or a tool's defect is fixed
(`tests/probes/`).

| Item | Wanted | Workaround today | Resolves when | Checked by |
|---|---|---|---|---|
| W1 | C++ modules and `import std` | `#include` (section 2.4); module scanning off (`CXX_SCAN_FOR_MODULES OFF` in `CppPolicy.cmake`) | CMake makes `import std` stable, clang-tidy handles modules, and `clang-cl` with the Microsoft library catches up | Hand, at each CMake and LLVM upgrade |
| W2 | Time zones in libc++ on macOS (`std::chrono::zoned_time`, `current_zone`) | Local time through `localtime_r` / `localtime_s`, in a confined file | libc++ ships its time zone database on macOS. (libstdc++ already has it: verified with GCC 16 on Linux.) | Probe `waiting/w2_zoned_time` (macOS) |
| W3 | Parallel algorithms (`std::execution::par`) in libc++ without `-fexperimental-library` | Not used; parallel computation isn't covered by the policy yet | libc++ makes them stable. (libstdc++ has them with GCC 16 on Linux, but only by linking TBB, a compiled dependency that section 1.1 would have to admit.) | Probe `waiting/w3_parallel_algorithms` (macOS) |
| W4 | `readability-trailing-comma`, and `policy-format-fix` settling the commas with it | The check is off (`.clang-tidy`), and the fixer only formats (`format.cmake`) | clang-tidy stops reporting the comma after an empty braced value (`f(a, T{}, b)`, `= {}` as a default argument, `{T{}, T{}}`, `.member = {},`) whose type has default member initializers. Seen in LLVM 23.1.1 and 23.1.2; its fix removes a comma the syntax needs | Probe `waiting/w4_trailing_comma` (every system) |
| W5 | `clang-analyzer-optin.core.EnumCastOutOfRange` on Windows | The check is off in the Windows build's copy of `.clang-tidy` (`_cpp_policy_tidy_config()` in `CppPolicy.cmake`); macOS and Linux keep it | clang-tidy stops reporting Microsoft's own `<filesystem>` header (`xfilesystem_abi.h`, a cast to `__std_fs_stats_flags`) for `std::filesystem::is_empty()`, `file_size()` and `last_write_time()` (since 0.33.1) | Probe `waiting/w5_filesystem_enum` (Windows) |

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
| `unit` | One module, through its public header | No files, network, child processes, threads or clock; results don't depend on the machine | 60 seconds for a module's unit tests together (in practice a fraction of a second) |
| `integration` | Modules together, or a module with the OS | Real sockets on ephemeral ports (port 0), temporary files and folders under the build folder, threads and processes; every wait has a timeout | 60 seconds, or less with `TIMEOUT`; more with `SLOW` and a reason (13.2) |
| `benchmark` | What a program costs: its size and its memory under load (13.5), and its speed (14.2) | Built in every configuration, so clang-tidy checks it, but run only without sanitizers, which distort size, memory and time | 60 seconds, or less with `TIMEOUT`; more with `SLOW` and a reason |

**Regression tests** aren't a kind of their own. When a bug is fixed, a test
that shows the bug comes with the fix. It is written first and seen failing,
then passes with the fix, and it goes in `TEST_SUITE("regression")`, which
labels it `regression` as well as its kind. It is kept, so the bug can't come
back unnoticed.

### 13.2 Test programs and names

```cmake
cpp_policy_add_tests(unit message SOURCES test_sanitize.cpp LIBRARIES sls_core)
cpp_policy_add_tests(integration server SOURCES test_server.cpp LIBRARIES sls_core
                     TIMEOUT 30 ENVIRONMENT "HELPER=$<TARGET_FILE:helper>")
cpp_policy_add_tests(integration window SOURCES test_walk.cpp LIBRARIES gui
                     TIMEOUT 180 SLOW "the walk through every task is one hand's session")
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
  - *Why the difference:* under the sanitizers a process costs about 0.2 s
    whatever the test does, so a process per unit test case made the local gate
    minutes longer; unit tests share no state (13.4), so separate processes
    protected nothing there (since 0.29.0).
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
- **A test has 60 seconds,** a unit program 60 for all its cases, and
  `TIMEOUT` sets less for an integration or benchmark program's tests. A test that passes its limit
  fails. (In the `tsan` build each limit is three times as long, section 7.)
  - **More than 60, up to 600, needs `SLOW "<reason>"`:** a sentence that
    says why a test of that program can't be shorter or split. It is printed
    at every configure, like every exception. Not for unit tests: a slow
    test is an integration test.
  - **A passing test that used two thirds of its limit is named** by the
    gate's launcher before its last line, and in CI's log: `gate: close to
    its time limit: "<test>" took 46 s of 60`. It is the next test to fail
    on a busy machine (since 0.33.0).
- **Tests run one at a time,** unless the project asks otherwise with one
  line before its first `cpp_policy_add_tests()`:

  ```cmake
  cpp_policy_parallel_tests()
  ```

  - Unit and integration tests then run eight at a time (the presets' number
    of jobs, section 7), which shortens the tests' part of a gate several
    times (since 0.33.0).
  - **Still alone:** benchmarks, whose measures another test would disturb;
    the tests of a `SLOW` program; any test added with `add_test()`; and the
    tests of a program declared `ALONE`, for tests that share something two
    of them can't hold at once (a fixed port, a folder with a fixed name).
  - Before turning it on, make each test use a folder and a port of its own,
    or mark its program `ALONE`. Tests that run together also share the
    processors: one that was near its limit alone will pass it.
- **In the release workflow, a unit program's test cases run in a random
  order.** They run one after another in one process, so a case that leaves
  state behind (a `static` inside the code under test) can make a later one
  fail, or pass, depending on order; "no state shared between test cases"
  (13.4) can't see state inside the code (since 0.41.0). The order comes
  from a seed kept in the build
  folder, chosen at its first configure and printed at every configure:
  `cpp-policy: unit test cases run in a random order, seed 1234567890`.
  Configuring with `-DCPP_POLICY_TEST_SEED=<seed>` repeats that order. CI
  starts from a new folder, so each run has a new seed. The check workflow,
  which agents run most, keeps the order of the source, so its failures stay
  easy to read. Integration and benchmark tests run one case per process,
  where order doesn't matter.
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

- **Test data is under `tests/data/`,** tracked, binary files included. The
  audit and the format check don't read it (since 0.33.1).
  - **What made it is beside it:** the script or the command, so that a
    sample can be made again or a new one added. That script may be in any
    language. It runs once, by hand; the build, the tests and the gates never
    run it, so the project needs nothing installed for it.
  - A test finds its data through `ENVIRONMENT "<NAME>=<folder>"` in
    `cpp_policy_add_tests()`, never through a path relative to where the
    test happens to run.
  - No personal or private data, and nothing a licence forbids
    redistributing: the repository may become public, and a library's
    users fetch all of it.
  - **Where size matters, the data is generated at real size** by the test
    (as the memory tests of 13.5 do), not kept small for convenience.
- **Real data is used by hand, never by the gates.** A claim about speed or
  quality is checked once on real data at real size, by whoever makes it:
  the figures, and where the data was, go in the commit or the changelog,
  never the data. Such a run finds its data through an environment
  variable, and is not a test the gates run: CI doesn't have the data.
- **Tests that run several at a time (13.2) share nothing by name.** Each
  test case that writes files uses a folder named after itself or with a
  random name, under the build folder. Two test cases with the same folder
  name pass alone and fail together now and then; a helper that makes these
  folders should refuse one that is already in use.
  - **Its lock names the process that holds it,** and a lock whose process
    is gone is free at once: a test killed at its time limit leaves its lock
    behind, and a lock judged by age would make the second run after a
    timeout (section 7) fail on it (since 0.41.0). The launcher's own lock works
    this way.
- **`REQUIRE` only for what the rest of the test depends on;** `CHECK` for
  everything else, so one run reports every failure. For example,
  `REQUIRE(result.has_value())` comes before `*result`, and
  `REQUIRE_FALSE(result.has_value())` before `result.error()`: either call on
  the wrong alternative is undefined behavior.
- **Compare inside the check,** as in `CHECK(*text == "Hello, Ada!")`: doctest
  prints both sides only of a comparison.
- **One behavior per test case,** named after it, so that a failure names
  the behavior that broke.
- **Through the public interface:** a test includes the module's header from
  `src/` like any other code. A private helper worth testing on its own
  belongs in a module of its own.
- **Tables for cases of one behavior:** a `std::array` of rows with a `what`
  field, and a loop with `CAPTURE(row.what)`.
- **Fakes rather than mocks:** a small class that implements the interface
  with fixed behavior. No mocking framework: a fake is plain code a reader
  can follow, where a mock's expectations hide the behavior in a framework.
- **No sleeps.** Wait for the event itself, with a timeout: a condition
  variable, `std::future::wait_for`, or polling with a deadline. A sleep is
  too short on a busy machine and wasted on a quiet one.
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
  the tolerance and why. An exact comparison with the original catches
  differences a "looks right" test would not (since 0.26.1).

*Enforcement:* the helper, registration and configuration check the names,
labels, suites, skipped tests and time limits. The rest of 13.4 relies on
review (section 8.1).

### 13.5 Budgets: size and memory

What a program costs is checked like what it does: a change that makes it
noticeably bigger, or makes its memory grow with its load, fails the build.
Both checks run in the `release` workflow, on every system CI runs (since
0.20.0).

**Size.** Every program a project ships has a size budget per system, next to
its target:

```cmake
cpp_policy_size_budget(my_tool MACOS 109568 LINUX 93184 WINDOWS 285696)
```

- **A system with no budget yet passes, and says the number to set,** since
  a size can only be measured on its own system (since 0.34.0). A new
  project starts with none (`cpp_policy_size_budget(my_tool)`). Every
  configure names the systems still without a budget; the release build
  prints "`my_tool` is N bytes stripped; it has no LINUX budget (with 5%
  headroom: M)" after the link, in CI's log as well. The owner approves the
  first numbers like any later one. A program that ships has all three.
- **A development program has no budget, and says so:**
  `cpp_policy_tool(frame_recorder "records what the window draws in every
  frame, for its tests")`, after `cpp_policy_apply()`. It is built and
  checked like the rest and never shipped, and every configure prints its
  reason. Without a place in the build, such a program was linked outside
  it, where nothing checked it (since 0.41.0). A program with both a budget
  and this marker fails at configure.
- **A program that isn't built on a system says `NOT_BUILT` in its place:**
  `cpp_policy_size_budget(my_window MACOS 5308416 LINUX NOT_BUILT WINDOWS
  NOT_BUILT)`. A notice nobody can act on teaches its readers to pass over
  notices (since 0.39.0). A build on a system that says `NOT_BUILT` fails: a
  program has a budget wherever it is built.
- The size is that of a copy stripped with `llvm-strip`: what would ship.
  The file the build leaves keeps its symbol table, which grows with names
  rather than code (since 0.20.0).
- A budget is the stripped size plus **5%**, rounded up to whole KiB. A
  fresh build gives the same size to the byte and toolchain updates move it
  little, so 5% catches real growth (a new dependency, a large table)
  without failing on noise (since 0.20.0). The test
  `benchmark/size/<program>` prints the size, and the budget to set when the
  program has outgrown it. A release build also says the size, and what is
  left of the budget, after each link, since CTest shows a passing test's
  output to nobody (since 0.31.0).
- **Beside the stripped size, the test and the line after each link give
  what the sections add up to** ("sections: N", `llvm-size`'s total). The
  file grows a page at a time, 16 KiB on macOS, so a change can fit in the
  padding there, show no growth, and take another system over its budget.
  The sections' total moves with every byte, on the developer's machine
  (since 0.38.1). The budget stays a budget of the file, which is what ships.
- **Setting or raising a budget needs the owner's approval** and a line in
  `CHANGELOG.md` saying why. Agents ask. When the program shrank to well
  under its budget, the test says so, and the budget can come down.
- **A program over its budget sends its author back to the code first,** to
  look for what the change doesn't need: a heavier facility than the job
  asks for, a table kept twice, a dependency for one function. That is the
  budget's use, and it often finds something. **But never at the cost of
  clarity:** when the only way under the budget makes the code harder to
  read, the agent asks the owner to raise it, and says what it tried. The
  owner would rather raise a budget than have code made worse to fit (since
  0.38.1).
- **The approval is of the growth and its reason, given once,** with the
  size on the system at hand; the other systems' numbers follow from
  measurement (since 0.36.0):
  1. The commit that grows the program sets the approved budget for the
     system it was measured on and removes the others' numbers. Their CI
     jobs pass and print the sizes (a system with no budget, above).
  2. The next commit sets each to its measured size plus 5%, with no
     second approval.
  3. A release commit has all three numbers.
- When a program is over budget, the test lists its sections (code,
  constants, exception tables, strings). For detail, link with a map
  (`-Wl,-map,<file>` on macOS, `-Wl,-Map=<file>` with `lld`, `/MAP` with
  `lld-link`): it gives every function's and string's size, and comparing two
  maps shows what grew.

**Memory under load.** A program that runs indefinitely (a server) has a
memory test, and so does every command that processes input of unbounded size
(a batch over many files): each its own, because a test of one command can't
see what another keeps (since 0.21.0).
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
  counts it exactly. The command then needs no operating-system test, whose
  readings are noisy (below; since 0.31.0).
  - Only a stream takes an allocator. zlib's one-call functions, `compress`
    and `uncompress`, don't: replace them with a stream (`inflateInit`,
    `inflate`, `inflateEnd`).
  - Allocate with `new (std::nothrow)`: a failure then reaches the C library
    as a null block, and no exception crosses its code.
  - Test that the memory arrives: the heap must rise when the library works.
- **The heap test** (`#include <cpp_policy/heap_bytes.hpp>`) differs for a
  batch command and a server. `live_heap_bytes()` gives the same number to
  the byte for the same work, on every run and every machine load. So does
  `peak_heap_bytes()` when the work runs on one thread; with several, the
  peak depends on how they overlap, by a few hundred bytes. The numbers
  differ between systems, because each standard library stores a string or
  a path differently: a limit has to hold on the system where the count is
  largest.
- **A server keeps nothing per request.** Its test:
  1. Warm up in rounds of N requests until a round leaves
     `live_heap_bytes()` no higher than it found it, up to a maximum number
     of rounds. Fail if it never settles: that is a leak.
  2. Read `live_heap_bytes()`, serve 5N more requests, read it again. The
     second reading is less than 10% above the first.

  One unmeasured run is not a warm-up for a server: a thread pool settles
  only when every thread has served a request, and how long that takes
  depends on the machine (since 0.24.2). cpp-policy's self-test
  `testing/heap_pool` runs this recipe on such a pool on every system.
- **A batch command** runs on its own each time, so its test is:
  1. Run the work once with N inputs, unmeasured, so that anything set up
     once is in place.
  2. `reset_peak_heap_bytes()`, run N inputs, read `peak_heap_bytes()`.
  3. `reset_peak_heap_bytes()`, run 5N inputs, read it again.

  The peak is an absolute figure. To measure what one operation adds, read
  `live_heap_bytes()` before it and subtract: the test program already holds
  about half a megabyte, so "the peak is over N" can pass for the wrong
  reason.
  - **A batch command has a budget per input, 1 KiB by default:** enough
    for its name and a small fixed-size record. The second reading is at most
    the first plus 4N × the budget. A command that processes files in sorted
    order has to hold their names (since 0.24.1).
  - **A higher budget needs the owner's approval** and a line in
    `CHANGELOG.md` saying what the record is and why it is kept, like a size
    budget. It is a named constant in the command's test. Agents ask.
  - The budget is for records, not for content. Memory that grows with the
    size of the inputs (a decoded image, a whole output) is streamed, paged
    or capped, as below, whatever the budget.
- **A command with one input of any size that must hold all of it** (a
  mesh, a whole document) has a budget per unit of that input instead: a
  triangle, a pixel, a line. Its test runs the command on S units, then on
  5S, and the second reading is at most the first plus 4S × the budget.
  The unit and its budget are named constants in the test. There is no
  default, since a byte per pixel and a kilobyte per triangle are both
  reasonable: each budget is approved by the owner, with a line in
  `CHANGELOG.md`, like the ones above (since 0.41.0).
- **Trying a memory test while writing it:** `peak_heap_bytes()` measures
  nothing in the check build, whose sanitizers replace the allocator. Build
  and run the one test in the release build: `cmake --preset release`,
  `cmake --build --preset release`, `ctest --preset release -R "<test>"`.
- **Why not the operating system's peak:** it depends on what the allocator
  did with freed blocks, and that depends on timing. The same program, with
  no leak, grew by nothing in one run and by over 80% in another; warm-up
  runs help but don't guarantee it (since 0.24.0).
  - **The noise is the measure's own; don't blame the machine.** On Linux
    the reading doesn't depend on load; on Windows it moves in steps even on
    an idle machine (since 0.26.5).
  - Load does cost time. A test near its time limit is a finding for whoever
    runs the machines, with the run's link, like any suspected environment
    problem.
- **Where `peak_memory_bytes()` is used, the first reading comes after the
  warm-up, on every system.** A program's peak first rises while it settles:
  allocator pools, thread pools, caches, the operating system's buffers.
  That rise is not a leak. Measure the curve once on each system (the peak
  after each of many rounds). Then (since 0.20.1):
  - For a server, either run the work once, unmeasured, before the first
    reading, sized past the latest bend, or choose an N that is past it.
  - For a batch command, warm up with several runs of N inputs, never with
    one run larger than N. Peak memory never goes down. After a warm-up run
    as large as the measured one, a command that keeps memory per file and
    frees it at the end shows the same peak before and after.
- **Run memory tests as CTest does.** doctest's `--success` keeps the text
  of every assertion, which multiplies the peak (since 0.21.0).
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
  it: a server's test sends its messages over kept-alive connections. A
  client that reuses a connection sets `TCP_NODELAY`: otherwise, on Linux,
  Nagle's algorithm holds each request's body until its headers are
  acknowledged, and delayed acknowledgment makes each request wait tens of
  milliseconds (since 0.20.2).
- **A `peak_memory_bytes()` test sees nothing below the program's starting
  peak:** with small inputs, a leak of a decoder's whole state per input can
  pass. The test first shows that its work rises above the starting peak:
  the reading after the work is larger than the one before it, or the test
  fails as proving nothing (since 0.33.3). Small leaks per input in a C
  library are LeakSanitizer's to find, in the ordinary tests.
- With `peak_memory_bytes()` the peak may grow by **less than 10%**. Peak
  memory never goes down, so growth means something is kept per unit of
  work. Such a test can fail without a leak, from the measure's own steps,
  which is why it is not the main test. Don't get used to rerunning it: a
  project whose test fails that way and has no memory outside the C++ heap
  drops it.
- Both measures come with benchmark tests, so projects need no OS code of
  their own. In builds with sanitizers, which have their own `operator new`,
  the heap count reads 0; benchmark tests don't run there.
- `peak_memory_bytes()` (`#include <cpp_policy/peak_memory.hpp>`):
  - On macOS and Linux it reports the peak resident memory (`ru_maxrss`).
  - On Windows it reports the peak private commit (`PeakPagefileUsage`): the
    memory the process allocated for itself. The peak working set also
    counts shared pages, and moved where private commit stayed steady
    (since 0.21.0).

*Enforcement:* the budget and memory tests fail the release workflow. Whether
every shipped program has a budget, and every server a memory test, relies on
review (section 8.1).

## 14. Performance

### 14.1 What the safety features cost

- **Every protection stays on in release:** standard-library hardening
  (`fast`), `-fstack-protector-strong` and `_FORTIFY_SOURCE=3` cost less
  than the run-to-run noise in which any speed difference would have to
  show (since 0.22.0).
- **What costs is the sanitizers, and optimization offsets it.** That's why
  `check`, `unit` and `tsan` compile at `-O1`: with the same sanitizers,
  hardening and checks, their tests run many times faster than at `-O0`
  (since 0.22.0, and 0.35.0 for `tsan`). `dev` and `debug` stay at `-O0`
  for the debugger.

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
- **Only compare on one quiet machine, over several runs.** Time on one
  machine varies between runs, and much more beside other work, so speed is
  never a CI check (since 0.22.0). A change that claims a speed-up, or might
  cost speed, gives nanobench's before and after (machine, median of several
  runs) in its `CHANGELOG.md` entry.
- **Instruction counts are a trial** (`benchmark.yml`, since 0.27.0): CI
  records them and checks nothing. How a project takes part is in
  cpp-policy's `ROADMAP.md`.

### 14.3 Writing fast code without weakening it

- **Defaults that cost nothing:** contiguous containers (`std::vector`,
  `std::array`, `std::string`); `reserve()` when the size is known; pass
  large objects by `const&` and move what is handed over; no copies to
  satisfy an interface that could take a `std::span` or `std::string_view`.
- **A proven hot spot is made fast within the rules.** Remove work rather
  than checks: hoist a size check out of the loop and iterate with ranges or
  iterators, avoid allocation in the loop, choose a better algorithm or data
  layout. Never turn hardening or a sanitizer off for speed: configuration
  rejects it (section 6), and 14.1 says the gain wouldn't be there.
- **Parallel computation:** section 15.5.

*Enforcement:* the build settings are presets and configuration checks;
"measure first" and before/after numbers rely on review.

## 15. Design

How a program is shaped, where sections 2 and 11 say how its parts are
written and arranged. It describes how the owner's projects were already
written when it was added: plain data, free functions, and no derived class
(since 0.25.0). Most of it is judgement, so it relies on review; no rule
here needs a tool the gates don't already run.

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
  module adds new kinds, chosen at run time. A hierarchy spreads one
  behaviour over several classes, so a reader has to find every override to
  know what a call does, and no compiler warns of a kind left unhandled
  (since 0.25.0). Where it is needed, section 2.6 applies, and the base
  class has no data.
- No inheritance to share code. Share it with a function or a member.

### 15.3 Containers and layout

- `std::vector` (or `std::array`, `std::string`) by default (14.3).
  `std::map` and `std::set` are right where ordered iteration or lookup by
  key is the point.
- **Layout for the cache is a technique for measured hot spots, not the
  default style.** Splitting an array of objects into arrays of fields can
  speed up a loop that reads one field of many objects. It makes the code
  harder to read, so it comes with a benchmark showing the gain (14.2).

### 15.4 Tests first where the behaviour is known

- **A bug fix:** the failing test is written first (13.4).
- **A function whose inputs and outputs are clear before it is written**
  (a parser, a conversion, a calculation): its tests come first, or in the
  same commit. A test written first states what the function must do before
  the code can bend it to what it happens to do (since 0.25.0).
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
is what a user can do; and the frontends, which only present it. The
dependencies then stay in the backend, and a new frontend adds presentation
and nothing else (since 0.26.1).

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
- **Reading and writing files are separate functions from the work.** The
  entry takes and returns data in memory. A helper that loads that data
  from a path (a configuration, a saved map) may live beside it, in the
  backend or the library, when more than one frontend needs it; it is its
  own function, so a frontend that already has the data never touches a
  file (since 0.31.0).
- An interface written this way can also be called from another language,
  which is what a phone frontend needs. Building for iOS and Android is not
  covered by this policy yet.

*Enforcement:* the `struct`/`class` split by clang-tidy; the rest relies on
review (section 8.1).

### 15.7 Decisions in code

Four rules, each about code that works where it was written and fails
later, with other data or on another machine (since 0.41.0):

- **What something is comes from measuring it, or from data that says
  so,** never from its name, its number or its position. Code doesn't
  decide that a photo shows an object because the file is called
  `object-13`: logic tied to names works in the project it was written for
  and silently gives wrong results in the next. A configuration that says
  "this file is the sky" is data, and code may act on it. Names are what
  the user sees.
- **A figure shown to users that depends on the machine** (a time, a speed,
  an estimate) **is measured at run time, or not shown.** Constants inside
  the code, such as the test limits of section 7, are not concerned.
- **One way per problem:** before adding a second mechanism for something,
  reuse the first, or replace it in the same piece of work. Section 11.2 is
  the same rule for helpers.
- **A fix that works only for the data at hand says so,** in a `TODO:` with
  enough context (11.4) and in `ROADMAP.md`, so that a general solution is
  owed rather than assumed.

*Enforcement:* review (section 8.1).

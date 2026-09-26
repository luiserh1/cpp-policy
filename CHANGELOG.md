# Changelog

Each entry says what changed and why. Projects read this before moving their
`GIT_TAG` to a new release. Versioning rules: POLICY.md section 10.

## 0.3.3 (2026-09-26)

Findings from the first Linux run (CachyOS, LLVM 23.1.2, GCC 16's libstdc++,
glibc 2.44). One check is relaxed for a single type, so no passing code
starts failing (POLICY.md 10).

### Upgrading a project

1. Pin the commit of `v0.3.3` and copy `.clang-tidy`.
2. If the project runs the `tsan` workflow on Linux, read the ThreadSanitizer
   note in POLICY.md 7 and check how its dependencies resolve names.

### Fixes

- `misc-const-correctness` no longer analyzes `std::stop_source`
  (`AllowedTypes: '^std::stop_source$'`). *Why:* libstdc++ (GCC 16,
  `<stop_token>`) declares `request_stop()` `const`, while libc++ and the
  standard declare it non-const. So on Linux the check demanded a `const`
  that the macOS build rejects, and no portable code satisfied both
  (SimpleLocalServer's `check` failed on `tests/test_lowlevel.cpp`). POLICY.md
  2.5 keeps the list of such types.

### Documentation

- POLICY.md 7: under ThreadSanitizer on Linux, threads that glibc creates
  internally (for example `getaddrinfo_a`'s helpers) crash the runtime on
  their first allocation. *Why:* SimpleLocalServer's `tsan` test crashed in
  cpp-httplib's non-blocking `getaddrinfo`; a program that only calls
  `getaddrinfo_a` reproduces it, and plain `getaddrinfo` does not.
- README: how to install LLVM 23 on Linux distributions without apt.llvm.org
  packages (the official release tarball in `/usr/lib/llvm-23`). *Why:* the
  first Linux run was on CachyOS (Arch), where no package provides LLVM 23;
  with the tarball the presets work unchanged and `check`, `tsan` and
  `release` all pass.
- POLICY.md 12: W2 and W3 note that libstdc++ (GCC 16) already provides time
  zones and, with TBB, parallel algorithms. *Why:* found on the same run. The
  items still wait on libc++ on macOS, and using the parallel algorithms on
  Linux would first need TBB admitted as a dependency (section 1.1).

### Self-test

- The good sample uses a `std::stop_source` the standard way. *Why:* with
  libstdc++ it fails clang-tidy as soon as the exemption above is removed.

## 0.3.2 (2026-09-26)

Fixes for Windows (`clang-cl`), found the first time the policy ran there:
`win-check` failed in every project, first in clang-tidy and then at link
time. Nothing had passed on Windows before, so no passing code starts
failing (POLICY.md 10). The changes only apply with `clang-cl`.

### Upgrading a project

1. Pin the commit of `v0.3.2`.
2. Windows: install the Visual Studio component "C++ AddressSanitizer"
   (README: Setup per platform).

### Fixes

- clang-tidy sees the slash-form options of `clang-cl`. `cpp_policy_apply`
  adds `--driver-mode=cl` to the compile options. *Why:* CMake passes
  clang-tidy `--extra-arg-before=--driver-mode=cl`, but clang-tidy drops the
  arguments after `--` that look like input files before it applies that, and
  in GCC mode every slash-form option looks like a path. So every slash-form
  flag was invisible to clang-tidy: `/EHsc` (it reported "cannot use 'try'
  with exceptions disabled"), `/W4`, `/DNDEBUG`, and CMake's `/DWIN32
  /D_WINDOWS`. Dash-form `-D` definitions from `target_compile_definitions`
  did get through. A copy of the flag among the compile options is read in
  time (verified with LLVM 23.1.2).
- Sanitized programs link with `clang-cl`. `cpp_policy_apply` links the ASan
  runtime (`clang_rt.asan_dynamic-<arch>.lib`, the runtime thunk as a whole
  archive, `/include:__asan_seh_interceptor`), with paths asked from the
  compiler; configuration fails if they are missing. *Why:* the `clang-cl`
  driver adds these when it links, but CMake calls `lld-link` directly, so
  every program failed with undefined `__asan_*` symbols.
- The ASan runtime DLL is copied next to each sanitized program. *Why:* the
  tests, a debugger and running the program by hand find it without any
  change to `PATH` or to a project's presets.

### Documentation

- README: the Windows setup needs the Visual Studio component "C++
  AddressSanitizer" (`Microsoft.VisualStudio.Component.VC.ASAN`), which
  provides `stl_asan.lib`; without it the link fails.
- POLICY.md 7.3: a caught exception works under ASan with LLVM 23.1.2. *Why:*
  the old text ("crashes on any `throw`") was never verified; the new
  self-test throws and catches under ASan in `win-check`.

### Self-test

- `tests/clang_cl/slash_options.cpp` (only with `clang-cl`) fails to build
  if clang-tidy loses a `/D` option or `/EHsc`, and throws and catches at run
  time. Removing either fix above makes `win-check` fail again.

## 0.3.1 (2026-09-25)

A fix for 0.3.0: its new leak detection on macOS reported a false positive
inside the operating system, so projects that make network lookups (for
example an HTTP client) failed their tests without leaking anything.

### Upgrading a project

1. Pin the commit of `v0.3.1`.
2. Copy the `LSAN_OPTIONS` setting of the `dev` and `check` test presets
   from `CMakePresets.json`.

### Fixes

- Leak detection applies a suppression list owned by cpp-policy
  (`cmake/sanitizers/lsan.supp`), copied into every build folder and used by
  the `dev` and `check` test presets. Its one entry covers thread-local
  storage that dyld allocates for the sanitizer runtime's own `qsort` on
  system worker threads, which stay alive at the leak check. *Why:*
  SimpleLocalServer's HTTP test failed on 0.3.0 with this "leak", reached
  through `getaddrinfo`. A program that allocates nothing reproduces it
  (tests/leak/os_false_positive.cpp), and the same `qsort` on an ordinary
  thread reports nothing, so it is not a leak in any project's code.
- POLICY.md 5 adds sanitizer suppressions to the kinds of suppression: only
  in cpp-policy, only proven false positives in the OS or the sanitizer
  runtime, each reproduced by the self-test. *Why:* a suppression list is as
  easy to misuse as `NOLINT`, so it gets the same kind of rules.
- POLICY.md 10: a patch release may remove false positives; it still never
  makes passing code fail. *Why:* the old wording ("doesn't change what
  passes or fails") would have made this fix a minor release, though it can
  only turn wrong failures into passes.

## 0.3.0 (2026-09-25)

Changes from the walkthrough of SimpleLocalServer, the project that pilots
this policy. Item numbers continue the list started for 0.2.0. Before 1.0 a
minor release may break existing code: the dependency check and the hook
copy check below can reject projects that passed 0.2.0. `.clang-tidy` and
`.clang-format` are unchanged.

### Upgrading a project

1. Pin the commit of `v0.3.0` instead of a tag, with the tag in a comment,
   and drop `GIT_SHALLOW` (README: "Use in a project" shows how to find it).
2. Copy `tools/hooks/` from this repository over the project's own hooks, and
   run `git config core.hooksPath tools/hooks` in every clone.
3. If the project uses vcpkg: make each dependency an object with
   `"default-features": false`, the `"features"` it uses, and a `"$reason"`;
   put the `VCPKG_ROOT` lines from POLICY.md 1.1 before `project()`.
4. Copy the `tsan` presets and the test presets' `timeout` and
   `ASAN_OPTIONS` settings from `CMakePresets.json`.
5. Make sure every thread function catches exceptions at its top
   (POLICY.md 2.8; review only).
6. Run the gate: leak detection is now on for macOS, so it may report leaks
   that went unnoticed before.

### Git hooks

- cpp-policy now ships the git hooks (tools/hooks/pre-commit and pre-push).
  Projects copy them unchanged, the audit rejects edited or missing copies,
  and configuration warns while a clone hasn't run `git config core.hooksPath
  tools/hooks`. *Why:* every project carried its own hand-made hooks that
  nothing compared, and a clone without the setting silently skipped every
  check; both undermined the gate the hooks exist to run. (#43)
- pre-push refuses to run while the working folder has uncommitted changes,
  and pre-commit warns when files have unstaged changes. *Why:* both hooks
  check the files on disk, but git commits the staged version and pushes
  commits; an uncommitted fix could make the gate pass while broken commits
  were pushed. pre-commit only warns so partial staging (`git add -p`) keeps
  working. (#66)

### Documentation

- POLICY.md 9 says agent permission rules enforce the agent rules only partly,
  names what they miss (shell edits, `git -c core.hooksPath=…`) and what
  catches it afterwards. *Why:* the text said the rules were "enforced
  technically", which overstated what a deny list can do. (#43)
- POLICY.md 1.1 gives the lines a vcpkg project puts before `project()` so a
  missing VCPKG_ROOT is reported by name. *Why:* without it, CMake only
  reports a toolchain path starting with `/scripts/` plus an unrelated Ninja
  error, and the policy module can't check it because it loads after
  `project()`. (#46)
- New POLICY.md 12, Waiting on the toolchain: a register of decisions that
  work around missing toolchain features (W1 modules and `import std`, W2
  libc++ time zones, W3 libc++ parallel algorithms), each with its workaround,
  what would end it and how it is checked. Workarounds in code carry a
  `Waiting Wn` comment. *Why:* such decisions were scattered: some recorded in
  POLICY.md, others only in a code comment, with nothing prompting anyone to
  look again. (#61)
- Projects pin the commit a release tag points to, with the tag in a comment,
  instead of the tag (POLICY.md 10, README). *Why:* a tag can be moved to
  other code later, for example by someone who takes over the repository's
  account, and cpp-policy's CMake code runs on every machine that configures a
  project. A commit can't be moved. (#55)

### Rules

- New POLICY.md 2.8, Concurrency: std::jthread instead of std::thread and
  detach(), no unsynchronized shared data, std::scoped_lock, no functions that
  aren't thread-safe, subtle atomics only in confined areas, short critical
  sections, and a catch at the top of every thread function. clang-tidy
  already enforced two of these (concurrency-mt-unsafe,
  modernize-use-scoped-lock); they now have samples in tests/bad/, and the
  rest is listed as review-only in 8.1. *Why:* the policy said nothing about
  threads beyond allowing `catch (...)` at thread boundaries, so an exception
  escaping a thread (which ends the program without reaching main's handlers)
  broke no written rule. (#48, #47)
- New POLICY.md 1.1, Dependencies: the standard library first; permissive
  licenses only (no GPL, since projects link statically); few transitive
  dependencies; optional features off; maintained; each dependency's reason
  recorded in a `$reason` field; baseline moves only after reading what
  changed; no untrusted binary caches. Configuration now fails when a
  vcpkg.json dependency is a plain name or lacks `"default-features": false`
  or a `$reason`, or when any installed package declares a license outside the
  list (read from vcpkg's SPDX files). *Why:* the policy only said to use
  vcpkg. SimpleLocalServer showed the cost: cpp-httplib's default features
  compiled and linked a compression library (brotli) that the program never
  uses. (#54, #53)

### Presets

- New `tsan` configure, build, test and workflow presets (macOS and Linux) and
  the CPP_POLICY_THREAD_SANITIZER option. The self-test proves the preset
  reports a deliberate race (tests/tsan/race.cpp), and the good sample gained
  a thread-safe Tally that must pass under it. *Why:* AddressSanitizer does
  not detect data races, and ThreadSanitizer can't share its build, so races
  went unchecked. Like `release`, it is meant for CI. (#48)
- The `dev` and `check` test presets turn on leak detection
  (`ASAN_OPTIONS=detect_leaks=1`), and the self-test proves it with a
  deliberate leak (tests/leak/leak.cpp). *Why:* AddressSanitizer finds leaks
  on macOS with LLVM 23 but keeps that off by default there, so leaks were
  only caught on Linux. We had assumed macOS couldn't detect them at all;
  checking it during the walkthrough showed otherwise.
- Every test preset sets a 60-second timeout per test. *Why:* CTest's default
  is 1500 seconds, so a hung test (a server waiting on a firewall prompt, say)
  held the pre-push hook for up to 25 minutes before failing. (#62)

### Self-test

- Probes for W2 and W3 (tests/probes/, macOS only): each uses the missing
  feature and must fail to compile; the day it compiles, the test fails and
  says to revisit the item. *Why:* toolchain upgrades are when these items
  resolve, and a failing test is harder to overlook than a note. (#61)

## 0.2.0 (2026-09-25)

Changes from the first full walkthrough of the repository. Item numbers refer
to that review's issue list. Before 1.0 a minor release may break existing
code: new rules below can reject code that passed 0.1.1.

### Upgrading a project

1. Set `GIT_TAG v0.2.0`.
2. Copy `.clang-tidy` and `.clang-format` again (both changed).
3. Add the missing lines of this repository's `.gitignore` to the project's,
   and copy `.gitattributes`.
4. Delete `CLAUDE.md`; keep a deny rule for creating it in the agent settings.
5. Optionally copy the new `debug` and `release` presets from
   `CMakePresets.json`.
6. Run the gate and fix what the new rules report.

### Documentation

- The version now has a single source (the `project()` version) and a release
  procedure; POLICY.md explains what `0.x` versions mean. *Why:* the version
  was written in three places and two were stale (the README still said
  v0.1.0, `project()` said 0.1.0 after v0.1.1 was tagged). (#14)
- POLICY.md 2.1: the pointer-parameter row said "may be null *and* are
  required", which contradicts itself; it now says required arguments use
  references. *Why:* the rule could not be followed as written. (#3)
- POLICY.md 2.3 no longer recommends `std::start_lifetime_as`. *Why:* libc++
  23 does not provide it, so the recommendation could not compile. (#4)
- POLICY.md sections 5, 8 and 9 name the real tools: the `policy-audit` target
  and the `check` workflow instead of a `tools/` folder that never existed;
  the pre-commit hook is described as it is (audit and format check, no
  clang-tidy); the agent hook and CI are marked as planned. *Why:* the text
  still described the first draft, and agents follow it literally. (#7, #10)
- POLICY.md sections 6 and 9 drop `CLAUDE.md`. *Why:* Claude Code reads
  `AGENTS.md` directly since v2.1.277, and only when there is no `CLAUDE.md`,
  so the import file is no longer needed and a stray one would hide the
  instructions. (#17)
- POLICY.md section 6 no longer says projects may add checks locally; they may
  only tighten through the module's options. *Why:* there was no way to do it,
  since project configs must match the policy's and the build uses the
  policy's copies. May be revisited in a later version. (#8)
- POLICY.md 8.1 lists two more review-only rules: `[[nodiscard]]` on functions
  returning `std::expected`, and the "why" comment in confined files, which
  now explicitly applies to `.cpp` files only. *Why:* both read as enforced
  but nothing checks them. (#9)
- POLICY.md 2.4 states that modules and `import std` are not used yet, with
  the reasons (experimental in CMake, immature clang-tidy support, Windows
  lag). *Why:* their absence looked like an oversight; now it is a recorded
  decision to revisit. (#6)
- README pins the current release in its usage example. (#1)
- README explains why projects copy `.clang-tidy` and `.clang-format`: editors
  read them, the build never does, and the audit keeps them identical. *Why:*
  the copies looked redundant; the reason was only hinted at. (#2)
- Corrected two comments that described the wrong behavior (the `CMakeFiles/`
  filter and the `.clang-format` include groups). *Why:* POLICY.md 11.4,
  comment accuracy. (#21, #24)

### Tooling

- The Apple Clang error now gives the same fix as the README (put LLVM first
  in PATH) instead of also suggesting `CMakeUserPresets.json`. *Why:* two
  different fixes for one problem; PATH is what the presets rely on and keeps
  clang-tidy and clang-format from the same folder. (#22)
- `cmake/scripts/common.cmake` is renamed `source_files.cmake`. *Why:*
  POLICY.md 11.2 bans catch-all names like `common`; the policy repo follows
  its own rule. (#25)
- The format fix target reports a clang-format failure as such, instead of
  telling you to run the fix target you just ran. (#31)
- The audit's `CHECK_SYNC` switch is renamed `CHECK_PROJECT_FILES`, since it
  now covers the ignore and attributes files too. Only affects someone calling
  the script by hand.
- `cpp_policy_apply()` turns off CMake's module scanning
  (`CXX_SCAN_FOR_MODULES OFF`). *Why:* with C++23, CMake scanned every file
  and added a `@….modmap` argument that only exists after a build, so clangd
  and clang-tidy on unbuilt files got a broken compile command. Modules aren't
  used (POLICY.md 2.4), and builds skip a step. (#40)
- New `debug` / `win-debug` presets (Debug, no sanitizers) and a README
  "Debugging" section. *Why:* no preset could be stepped through on Windows
  (`win-dev` must be optimized for ASan), there was no sanitizer-free Debug
  build anywhere, and debugging wasn't documented. Raised by the owner. (#33)
- New `release` / `win-release` test presets and workflows run the tests on
  the optimized build. *Why:* tests only ran in Debug, so bugs that appear
  only with optimization, and release-only settings, went untested. Meant for
  CI, not the pre-push hook (owner's choice). (#34)

### Self-tests

- Audit fixtures now pin line numbers (`file:line:`) and cover the config copy
  check, `NOLINTBEGIN`/`END`, excluded folders, and lines containing
  characters CMake lists treat specially. A fixture may override its config
  with an `options.cmake`. *Why:* the copy check, line counting and exclusions
  were untested; breaking them on purpose now fails the self-test. (#37)
- Nine new bad samples: `malloc`, union type punning, functional casts,
  function-like macros, several declarations per line, missing `const`,
  implicit conversion operators, a non-virtual base destructor, and a
  violation inside a header. Pointer + length parameters move to the
  review-only list (no check flags the signature). *Why:* POLICY.md claimed
  every section-2 rule had a sample; about ten did not, so a clang-tidy
  upgrade could drop those rules unnoticed. (#11)
- The good sample (`tests/good/`) now teaches the right lessons: its NOLINT
  covers a `reinterpret_cast` that is truly needed (viewing bytes as text)
  instead of pointer arithmetic that plain indexing avoids; the polymorphic
  `Shape` base has protected copy and move, so it can't be sliced; `buffer.*`
  is split into `numbers.*` and `shapes.*`. *Why:* people and agents copy
  examples, and the old one showed suppressing a rule instead of fixing the
  code. (#39)

### Rules

- The audit detects diagnostic pragmas written as operators (`_Pragma`,
  `__pragma`), and every diagnostic pragma must give a reason in a trailing
  comment. *Why:* the operator form, usable inside macros, passed the audit
  anywhere; and pragmas are suppressions like NOLINT, so they follow the same
  reason rule. (#28)
- `// clang-format off` must give a reason (`// clang-format off: reason`); it
  stays allowed anywhere. *Why:* it is a formatting suppression that no rule
  covered; it only affects layout, so confining it would add friction without
  benefit. (#32)
- The audit requires `#pragma once` in every header (`.h .hpp .hh .hxx`) and
  rejects include guards. *Why:* POLICY.md 2.4 banned include guards but
  nothing enforced it; clang-tidy has no check for this (its only related
  check enforces the opposite). (#5)
- New POLICY.md 6.1, repository files: a project's `.gitignore` and
  `.gitattributes` must contain every line of cpp-policy's copies (checked by
  the audit); nothing editor-specific is committed. cpp-policy's `.gitignore`
  gains the Visual Studio, CLion, VS Code and Windows entries, and a
  `.gitattributes` forces LF line endings. *Why:* ignore files were
  hand-written per repo and neither ignored `.vs/`; Git for Windows'
  line-ending conversion would break the audit's byte comparison of the
  `.clang-*` copies. (#36, #30)
- Configuration fails if a project target doesn't call `cpp_policy_apply()`,
  or if warnings or clang-tidy are switched off from CMake
  (`-Wno-…`/`/wd…`/`-w` on targets, sources or `CMAKE_CXX_FLAGS`;
  `SKIP_LINTING`; a changed `CXX_CLANG_TIDY`). *Why:* the suppression audit
  only looked at source code, so the whole policy could be switched off in
  `CMakeLists.txt`, which agents must be allowed to edit. (#29)
- `short`, `long` and `long long` are banned (clang-tidy
  `google-runtime-int`); use `<cstdint>` fixed-width types, `std::size_t`, or
  plain `int`. *Why:* `long` is 64 bits on macOS/Linux and 32 on Windows, so
  the same code can silently truncate on one platform. Raised by the owner.
  (#12)
- Naming convention (POLICY.md 2.7), enforced by
  `readability-identifier-naming`: PascalCase types, snake_case everything
  else, trailing `_` on private members, UPPER_CASE macros. *Why:* the check
  was enabled without options, so it checked nothing, and no convention was
  written down; the chosen one is what the code already used. (#18)
- Functions are limited to 80 lines, 6 parameters and 4 levels of nesting
  (`readability-function-size`), plus the existing cognitive complexity limit
  of 25. *Why:* POLICY.md 11.3 claimed a function size limit, but the check
  had no thresholds set (only 800 statements), so it never fired. (#15)

### Formatting

- `<winsock2.h>` always sorts first among the non-standard headers. *Why:*
  alphabetical sorting put `<iphlpapi.h>` and `<windows.h>` before it; on
  Windows that pulls in the old `<winsock.h>` and breaks the build with
  redefinition errors (SimpleLocalServer's `network_interfaces.cpp` was
  affected, never compiled on Windows yet). (#20)

## 0.1.1

- `.clang-format` no longer re-wraps `NOLINT` comments. *Why:* a wrapped
  `NOLINTNEXTLINE` points at the wrong line (found in SimpleLocalServer).

## 0.1.0

- First release: policy document, CMake module, clang-tidy and clang-format
  configurations, suppression audit, presets and self-tests.

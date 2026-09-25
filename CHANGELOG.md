# Changelog

Each entry says what changed and why. Projects read this before moving their
`GIT_TAG` to a new release. Versioning rules: POLICY.md section 10.

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

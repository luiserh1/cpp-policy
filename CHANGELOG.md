# Changelog

Each entry says what changed and why. Projects read this before moving their
`GIT_TAG` to a new release. Versioning rules: POLICY.md section 10.

## 0.15.0 (2026-09-28)

vcpkg builds dependencies like the project: same LLVM, same sanitizer,
the policy's hardening. The audit fails for a project with a `vcpkg.json`
until it has `tools/vcpkg/`, so a minor release (POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.15.0`. In a
   project with a `vcpkg.json` it also copies `tools/vcpkg/` and replaces
   the eight lines that loaded vcpkg before `project()` with
   `include("${CMAKE_CURRENT_SOURCE_DIR}/tools/vcpkg/setup.cmake")`. If
   `CMakeLists.txt` loads vcpkg some other way, it stops before changing
   anything and prints the line to use instead.
2. The first configuration of each preset builds the dependencies again,
   now with LLVM: once per triplet (`asan`, `tsan`, `nosan`), then from
   vcpkg's cache. Header-only dependencies are unaffected.

### Dependencies (POLICY.md 1.1)

- vcpkg builds dependencies with cpp-policy's triplets in `tools/vcpkg/`
  instead of its own. `setup.cmake` picks one from the preset's sanitizer
  options: `cpp-policy-asan` (dev, check, win-check), `cpp-policy-tsan`
  (tsan) or `cpp-policy-nosan` (the rest). All three compile with the
  same LLVM as the project, found where the presets look and required to
  be the same major version, and add `-fstack-protector-strong`,
  `-fcf-protection` on x64, `_FORTIFY_SOURCE=3` in optimized builds, or
  Control Flow Guard on Windows, and standard library hardening. *Why:*
  vcpkg's default triplets use the system's compiler with none of the
  policy's settings. Measured on macOS: Apple Clang compiled the
  dependency against Apple's libc++ 22 while the project used LLVM's
  libc++ 23, with basic stack protection and no AddressSanitizer, and a
  sanitized program that passed it a 16-byte buffer with a size of 17
  ran to the end. ToneMatcher's zlib was built that way, and its PNG
  codec hands zlib buffers and sizes.
- *Why sanitizers match the preset:* each one fails with code it didn't
  instrument. AddressSanitizer misses errors inside it, libc++ reports
  false container overflows when it resizes a container, and
  ThreadSanitizer misses races and reports false ones there.
- *Why not UndefinedBehaviorSanitizer:* it would stop the program on a
  dependency's own undefined behavior, which the project can't fix.
  AddressSanitizer catches what the project controls: the sizes and
  buffers it hands the library.
- *Why the security hardening too:* dependencies often parse untrusted
  input (zlib decompresses whatever a file holds), so they get the same
  protection as the project's code. The owner chose this on 2026-09-28.
- The files include nothing: vcpkg keys its binary cache on the hashes of
  the triplet, `llvm.cmake` and the compiler, so a change to either file
  or a new LLVM rebuilds the dependencies, but a change to an included
  file would go unnoticed. The three triplets therefore repeat the same
  code and differ only in the line naming their sanitizer.
- Projects load vcpkg with one `include` of `tools/vcpkg/setup.cmake`
  before `project()`, which also keeps the `VCPKG_ROOT` check. Future
  changes to how vcpkg is loaded then reach projects through upgrades
  alone.

### Audit

- A project with a `vcpkg.json` must have the five `tools/vcpkg/` files,
  unchanged. *Why:* an edited triplet would build the dependencies
  differently from the project without anyone noticing.

### Tools

- `upgrade.sh` copies `tools/vcpkg/` and replaces the old vcpkg lines
  (above). `new-project.sh --vcpkg` gives new projects both.

### CI

- `gate.yml`'s `vcpkg` input works without a `vcpkg.json`: the runner's
  vcpkg stays at its commit. cpp-policy's own CI now sets it, so the
  self-test's vcpkg tests, and the template's `--vcpkg` variant, run on
  every system.

### Self-test

- `vcpkg/dependencies_built_like_project` configures a small project with
  the build's own compiler and options; vcpkg builds its dependency, a
  local port that reports how it was compiled. The C and C++ files must
  report LLVM's major version, the preset's sanitizer, strong stack
  protection and, in Release, `_FORTIFY_SOURCE=3` (Linux and macOS), the
  C++ file the project's standard library and the expected hardening mode.
  With AddressSanitizer, a one-byte overread inside the dependency must
  stop the program. It runs in the check, tsan and release workflows, so
  each triplet is tested on each system. With vcpkg's default triplet it
  fails (Apple Clang, libc++ 22, no sanitizer); with the asan triplet's
  sanitizer removed, too.
- `vcpkg/triplet_files`: the triplets differ only in their sanitizer line,
  and `llvm.cmake` asks for the LLVM version `CppPolicy.cmake` requires.
- `audit/vcpkg_missing`, `audit/vcpkg_differs`; `upgrade/behavior` covers
  the vcpkg lines being replaced, and refused when they're unknown.

## 0.14.0 (2026-09-28)

New projects are generated from the policy. A new feature that changes
nothing for existing projects, so a minor release (POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.14.0`. Nothing
   else to do.

### Tools

- `tools/new-project.sh <folder> <Name> [--vcpkg]` creates a project from
  the release it's run from (a clone checked out at a release tag). The
  project is pinned to that release in `CMakeLists.txt` and its CI
  workflow, has the release's `.clang-tidy`, `.clang-format`,
  `CMakePresets.json`, `.gitignore`, `.gitattributes` and `tools/hooks/`,
  an agent-neutral `AGENTS.md`, agent settings, a README and a CHANGELOG,
  and a small program that shows each layer: `main.cpp`, an `app` module
  returning `std::expected`, a confined `lowlevel` module (reading an
  environment variable with POLICY.md 2.10's idiom) and a test. It becomes
  a git repository with the hooks enabled. `--vcpkg` adds `vcpkg.json` with
  the baseline `VCPKG_ROOT` is checked out at, the `VCPKG_ROOT` check and
  `vcpkg: true` in CI. It refuses a checkout that isn't at a release tag or
  has uncommitted changes, since the project would pin files nobody
  published. *Why:* SimpleLocalServer and ToneMatcher were each set up by
  hand, copying files and pins from the README; the generator gives a new
  project everything at once, passing the gate from the first commit.
- *Why a generator in cpp-policy and not a GitHub template repository:* a
  template repository is a second copy of the policy files and pins that
  would need an upgrade after every release, or new projects would start
  behind. The generator produces each project from the release it's run
  from, so there's nothing to keep in sync, and the self-test runs a
  generated project's gate on every push, so a release can't ship a
  template that fails its own policy. The owner chose this on 2026-09-28.
- The template lives in `template/`, excluded from cpp-policy's own checks:
  it's checked as a generated project instead, with its own layers and
  confined area.

### Self-test

- `template/new_project` generates a project (and, with `VCPKG_ROOT` set,
  the `--vcpkg` variant) pinned to the current commit, with FetchContent
  pointed at this checkout. It must configure, build with clang-tidy, pass
  the audit and the format check, pass its tests, print its greeting, and
  make its first commit through its own hooks. A C-style cast added to the
  template makes it fail. It runs in the builds with AddressSanitizer only
  (dev, check).

## 0.13.0 (2026-09-28)

clang-tidy on single files: a command for right after an edit, and in
pre-commit for the staged files. pre-commit can now fail where it passed, so
a minor release (POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.13.0`: it copies
   the new `tools/hooks/tidy-files` and `pre-commit`.
2. Add to the project's `AGENTS.md` (the owner, since agents can't edit it)
   that C++ files are checked right after editing them:
   `sh tools/hooks/tidy-files <file>...`.

### Tools

- `tools/hooks/tidy-files <file>...` runs clang-tidy, with the policy's
  configuration, on just those files: a few seconds each instead of the
  whole gate. It skips files that aren't C++, are in excluded directories
  or are third-party code (what `.clang-tidy`'s `ExcludeHeaderFilterRegex`
  matches, at any depth), and sources this build doesn't compile (another
  platform's, which CI checks). Headers are checked on their own. *Why:* porting
  ToneMatcher, the first clang-tidy run came after the code worked and
  reported 492 findings. Checking each file as it's edited finds them one
  file at a time.
- `pre-commit` runs it on the staged files, after the audit and format
  check. Every agent and person commits through git, so findings turn up at
  each commit even when nobody ran the command.
- POLICY.md 8 and 9: the planned "agent hook (Claude Code)" is replaced by
  this command. *Why:* a hook for one agent would have made the others
  second-class; the policy relies only on commands and git hooks, which
  work the same for any agent and for people, and `AGENTS.md` says when to
  run them. An agent's own hook system may call `tidy-files`, as an extra.
- The audit requires `tools/hooks/tidy-files` to be an unchanged copy, like
  the git hooks.

### Self-test

- `hooks/tidy_files`: a throwaway project copying the policy's files and
  configured through its presets. `tidy-files` configures it, passes clean
  files and skips a text file; fails on a C-style cast in a header and
  names it; skips the same header under a nested `third_party/`, and a
  source the build doesn't compile. `pre-commit` fails
  while the header is staged and passes once it isn't; without its
  `tidy-files` step, the test fails.

## 0.12.2 (2026-09-28)

A false positive on macOS, found by SimpleLocalServer's first CI run on the
owner's Mac. Nothing that passes can fail, so a patch release (POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.12.2`: it copies
   the new `CMakePresets.json`.

### Presets

- The `dev` and `check` test presets set `MallocNanoZone=0`. *Why:*
  SimpleLocalServer's `macos check` failed on the self-hosted runner with 26
  leaks inside libdispatch, from cpp-httplib's address lookup, while the
  same binary passed from a terminal. The difference was the environment:
  the Claude app's terminals set `MallocNanoZone=0`, the runner's launchd
  service doesn't, and with the nano malloc zone on, libdispatch's cache of
  reusable work items is invisible to LeakSanitizer. It isn't a leak: the
  count stops growing at 7,168 (112 cached items on each of at most 64
  worker threads) however much work is queued, shown with up to 300,000
  items. Xcode sets the same variable whenever AddressSanitizer is on. A
  plain Terminal window without it would have failed the gate too.

### Self-test

- `leak/nano_zone_off` queues 1,000 empty work items and must pass with the
  presets' setting; without it, it failed on the owner's Mac (macOS 27).
  GitHub's macos-15 runners don't report the cache even with the nano zone
  on, so a test requiring the reports couldn't be kept: on those runners
  the test proves nothing, only that the setting does no harm.

## 0.12.1 (2026-09-28)

From ToneMatcher's first CI runs: six runs and 76 minutes to its first green
build on Linux and Windows, one finding per run. Nothing that passes can
fail, so a patch release (POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.12.1`: it copies
   the new `.clang-tidy` and `CMakePresets.json`. The first build afterwards
   re-checks every file (below).

### Build

- A changed `.clang-tidy` re-checks every file, not only the ones that
  changed. *Why:* the build didn't know objects depend on the file clang-tidy
  reads, so after an upgrade to a release with other rules, files already
  built kept their old results and the local gate could pass where CI, which
  builds from scratch, would fail. clang-tidy now reads a copy in the build
  folder named after a hash of its contents: CMake re-runs when the policy's
  file changes, the new name changes every clang-tidy command, and Ninja
  rebuilds whatever command changed.

### Presets

- The `check` and `win-check` build presets pass `-k 0` to Ninja: a failing
  file no longer stops the build. *Why:* each of ToneMatcher's failing CI
  runs showed one problem, because Ninja stopped at the first file; the
  next only appeared after another push and a CI wait of up to 16 minutes.
  One run now lists everything, in CI and in the local gate.

### Rules

- `bugprone-exception-escape` ignores `bad_array_new_length`, as it already
  ignores `std::bad_alloc`. *Why:* the Microsoft library allocates when it
  moves a `std::map` (and the other node containers) and reports allocation
  failure with that type, so on Windows only, every class holding a
  `std::map` failed the check; ToneMatcher replaced `std::map` with a map
  of its own to pass. The name must be unqualified (the check doesn't match
  `std::bad_array_new_length`), which ToneMatcher's agent found and tested.
- POLICY.md 2.10 lists the findings that depend on the standard library,
  each with the form that passes on every system: environment variables,
  `environ`, stream open modes and `std::ranges::find`.
- POLICY.md 8: a passing gate proves only the system that ran it; CI is the
  authority for the others.

### Self-test

- `tidy/rebuild_on_config_change`: a throwaway project builds clean, its
  copy of the policy's `.clang-tidy` loses an option, and the next build,
  with no source changed, must report the finding. It failed before the
  fix.
- `presets/keep_going`: a throwaway project with three broken files, built
  with the check presets' options one file at a time, must report all
  three. With Ninja's default it fails.
- `tests/good/allocation.cpp` lets `std::bad_array_new_length` escape a
  `noexcept` function; without the option the good build fails. The new bad
  sample `exception_escape` shows other exceptions are still reported.

## 0.12.0 (2026-09-28)

CI can run a system's jobs on the owner's own machine. A new optional
feature, so a minor release (POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.12.0`.
2. Optional: to run a system on your own machine, set up a runner (README,
   "Your own machine as a runner"), then add that system to both `systems`
   and `self_hosted` in `.github/workflows/ci.yml`, e.g.
   `self_hosted: '["macos"]'`.

### CI

- `gate.yml` takes `self_hosted`, a list of systems whose jobs go to a
  repository runner of the owner's (labels `self-hosted` and `macOS`,
  `Linux` or `Windows`) instead of GitHub's. *Why:* on a private repository
  a macOS minute costs about ten Linux ones, so SimpleLocalServer left macOS
  out of CI, which is a gap once the owner works from Linux or Windows
  machines too. The owner's Mac runs them for free; while it is off the jobs
  wait (up to GitHub's 24 hours).
- On such a machine the gate installs and resets nothing: it uses the
  machine's LLVM, CMake and Ninja, and a vcpkg clone of its own in the
  runner's tool folder, never the owner's `VCPKG_ROOT`. The toolchain step
  now shows the LLVM found through the presets' `PATH`, which on a
  self-hosted Linux machine may be the system's.

## 0.11.0 (2026-09-27)

`policy-format-fix` also fixes trailing commas. A tooling improvement that
makes no passing code fail, so a minor release (POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.11.0`. Nothing
   else to do.

### Tools

- `policy-format-fix` formats, runs clang-tidy with only
  `readability-trailing-comma` and its fixes on the files the build compiles,
  and formats again. *Why:* that check wants a comma after the last element
  exactly when clang-format puts a list on several lines, so fixing one
  undid the other: ToneMatcher needed three rounds of clang-tidy and
  clang-format by hand. One run now leaves both right. It takes a few
  seconds per ten files (about 30 s on ToneMatcher's 107).
- Files the build doesn't compile (another platform's) are left alone: they
  can't be parsed here, and this platform's gate doesn't check them either.

### Self-test

- `format/fix_trailing_commas`: a throwaway project with lists that need a
  comma, one of them only after clang-format splits it; after one fix, the
  format check and the comma check must both pass. Without the clang-tidy
  step it fails.

## 0.10.2 (2026-09-27)

Documentation and self-tests only; nothing that passes or fails changes, so a
patch release (POLICY.md 10). They come from porting ToneMatcher (about
10,800 lines) under the policy, where the first clang-tidy run reported 492
findings and an in-tree C library looked impossible to use.

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.10.2`. Nothing
   else to do.

### Rules

- POLICY.md 2.10, "Idioms clang-tidy leads to": the accepted forms for
  building structs (designated initializers, or a constructor on small value
  types), for members that refer to another object, for `std::from_chars`
  and for trailing commas, plus the smaller checks new code meets first.
  *Why:* each project was finding these by trial and error, and ToneMatcher
  and SimpleLocalServer ended up with different `from_chars` code.
- POLICY.md 2.1: a pointer member set from a reference in the constructor
  and commented `// never null` is the one non-owning pointer that isn't
  "may be null". *Why:* reference members are rejected by clang-tidy, so
  the pointer is the replacement, and 2.1 contradicted it.
- POLICY.md 5, "Third-party code": the static analyzer reports findings
  inside an excluded header against the project line that calls into it,
  and a `NOLINT` there, in a confined area, removes them. *Why:* ToneMatcher
  concluded stb_image couldn't be used and wrote its own PNG codec; the
  suppression was allowed all along.

### Self-test

- `tests/good/idioms.cpp` uses each idiom of 2.10;
  `tests/good/lowlevel/c_library.cpp` calls a stand-in C library
  (`tests/good/third_party/sample_c.h`) whose leak the analyzer finds, with
  the `NOLINT` on the calling line. Without it the build fails.
- New bad samples: `reference_member`, `positional_init`, and
  `third_party_call` (the analyzer finding reaches the project through an
  excluded header).

## 0.10.1 (2026-09-27)

A fix to `tools/upgrade.sh`; nothing about the rules or the build changes,
so a patch release (POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.10.1`. If the
   project is on v0.10.0 or older, its copy doesn't hand over yet (below), so
   run this one release's copy instead:
   `sh <a cpp-policy clone at v0.10.1>/tools/upgrade.sh v0.10.1`.

### Tools

- `upgrade.sh` hands over to the target release's own `upgrade.sh` once it
  has fetched it, when the two differ. *Why:* upgrading SimpleLocalServer to
  v0.10.0 with its fetched v0.9.0 copy left `CMakePresets.json` unchanged,
  because v0.9.0 didn't know the presets had become a policy file. A release
  now always decides what upgrading to it involves. The release is fetched
  once and passed on.

### Self-test

- The upgrade test's fake v2.0.0 carries its own `upgrade.sh`, which must be
  the one that runs; without the handover the test fails.

## 0.10.0 (2026-09-27)

Projects' `CMakePresets.json` becomes an unchanged copy, checked by the
audit, so a project that passed before can fail: a minor release
(POLICY.md 10).

### Upgrading a project

1. If the project uses vcpkg, first add the toolchain line after the
   `VCPKG_ROOT` check, before `project()` (POLICY.md 1.1):
   `set(CMAKE_TOOLCHAIN_FILE "$ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake" CACHE FILEPATH "...")`.
   Without it, the new presets load no vcpkg and `find_package` fails.
2. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.10.0`: it
   replaces `CMakePresets.json` with the policy's copy.
3. Presets a project added of its own go into `CMakeUserPresets.json`
   (personal, not committed), or are proposed to cpp-policy.

### Rules

- `CMakePresets.json` joins `.clang-tidy`, `.clang-format` and the hooks: the
  audit fails unless it is byte-identical to the policy's, and `upgrade.sh`
  copies it. *Why:* each project carried the policy's presets plus one line
  (vcpkg's `toolchainFile`), and nothing checked the rest, so presets could
  drift between releases unnoticed. With the toolchain in `CMakeLists.txt`,
  there's nothing left to differ.
- POLICY.md 1.1's `VCPKG_ROOT` snippet sets `CMAKE_TOOLCHAIN_FILE` too, as a
  cache default, so a toolchain given on the command line still wins.

### Self-test

- `tests/audit/presets_differs`; the upgrade test's fake releases carry
  presets. Taking the presets out of the audit's list, or out of
  `upgrade.sh`'s copy, fails a test.

## 0.9.0 (2026-09-27)

The layer check, so code that passed before can fail: a minor release
(POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.9.0`.
2. If `src/` has two or more modules, declare the layers before
   `cpp_policy_add_checks()`, from the lowest up:
   `cpp_policy_layers(LAYER lowlevel LAYER model LAYER ui)` (POLICY.md 11.1).
3. Write every `#include "..."` under `src/` from the `src/` root
   (`"model/item.hpp"`), and fix any that point to a higher layer.

### Rules

- The audit checks the dependency direction of POLICY.md 11.1 on every
  `#include "..."` under `src/`: no include from a higher layer, no relative
  path, no header named without its module, and nothing but its own headers
  in a confined module. A module in no layer fails, and so does `src/` with
  two or more modules and no layers. *Why:* 11.1 promised this check; until
  now the direction was kept by review only.
- New CMake function `cpp_policy_layers(LAYER <modules>... ...)`. It fails on
  an empty layer, a name that isn't a directory name, a module in two layers,
  or a call after `cpp_policy_add_checks()`.

### Fixes

- The include-guard rule (0.2.0) never fired: in
  `if(first MATCHES "^ifndef (.+)$" AND second STREQUAL "define ${CMAKE_MATCH_1}")`
  the `${CMAKE_MATCH_1}` is expanded before the `MATCHES` runs. The two
  conditions are now separate. A header with a guard also lacks
  `#pragma once`, which was always reported, so no passing code fails now.
- The self-test hid that: a pass regex is a list, and a `;` in an
  `expect.txt` split it into alternatives that pass on their own. The
  include-guard fixture passed on "use #pragma once", part of the other
  error. The harness now turns `;` into `.`; four fixtures that had one are
  strict again (`hooks_missing`, `include_guard`, `repo_files_missing`,
  `sync_missing`). Found because a break in the new layer check wasn't caught.

### Self-test

- Audit fixtures `layers_ok`, `layers_upward`, `layers_relative`,
  `layers_confined`, `layers_missing`, `layers_unassigned`; bypass fixtures
  `layers_late` and `layers_duplicate`. Breaking each rule (the direction
  check, same-layer includes rejected, relative paths, confinement, missing
  and unassigned layers) fails the matching fixture.

## 0.8.1 (2026-09-27)

A fix to `tools/upgrade.sh`'s report; nothing about the rules or the build
changes, so a patch release (POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.8.1`.

### Tools

- `upgrade.sh` lists changed and new files with `git status --short`.
  *Why:* upgrading SimpleLocalServer to v0.8.0 copied the new `commit-msg`
  hook correctly, but the list of changes left it out: `git diff --stat` only
  shows tracked files, and a hook the release adds is untracked until it's
  committed. The self-test's fake release now adds a hook, and fails with the
  old listing.

## 0.8.0 (2026-09-27)

A new hook that can refuse commits that went through before, so a minor
release (POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.8.0`. It copies
   the new `tools/hooks/commit-msg`; the audit requires it.
2. From then on, commit messages follow POLICY.md 8.2. Existing history
   stays as it is.

### Rules

- Commit messages follow Conventional Commits: a subject
  `type(scope): summary` of at most 72 characters (types `feat`, `fix`,
  `perf`, `refactor`, `test`, `docs`, `build`, `ci`, `chore`, `revert`), a
  blank line, and a body that says why. Release commits are
  `chore(release): <version>`. *Why:* a history whose subjects say what kind
  of change each commit is can be scanned and turned into release notes, and
  the body keeps the reason every commit here has carried so far. Trailers
  don't count as the body; merges, reverts and fixup/squash/amend commits
  pass unchecked.

### Hooks

- `tools/hooks/commit-msg` checks the message. It drops comment lines and
  everything below git's scissors line first, as git does. On a
  rejection it says where git kept the message, to reuse it.

### Self-test

- `hooks/behavior` runs the hook on 17 messages, one or two per rule,
  including the 72/73-character boundary and trailer-only bodies. Breaking
  the hook (no length limit, no body check, trailers counted as a body, merges
  not exempt, comments kept) fails the test each time.

## 0.7.0 (2026-09-27)

Two review-only rules become audit checks, so code that passed before can
fail: a minor release, which before 1.0 may break code (POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.7.0`.
2. On every `catch (...)` line, name the boundary: `// boundary: program`,
   `// boundary: thread top`, and so on.
3. On every `dynamic_cast` or `typeid` line, give the reason: `// rtti: ...`.

### Rules

- The audit fails on a `catch (...)` without `// boundary: which` on the same
  line, and on `dynamic_cast` or `typeid` without `// rtti: reason`. Only the
  code before any `//` is searched, so comments may mention them. *Why:*
  POLICY.md 3 allowed catch-all handlers only at boundaries and discouraged
  RTTI, but nothing checked either; stating the reason where the code is makes
  review judge it, as NOLINT reasons do. The other half of the catch-all rule
  (log or rethrow) was already partly enforced: clang-tidy's
  `bugprone-empty-catch` rejects an empty handler.
- `const char*` as a string type stays a review rule, and POLICY.md 8.1 now
  says why: a pattern can't tell it from `argv`, pointers for
  `std::from_chars` or C APIs.

### Self-test

- `tests/audit/catch_all_reason`, `catch_all_no_reason`, `rtti_reason`,
  `rtti_no_reason`, including comments that mention the constructs and an
  identifier containing `dynamic_cast`. Breaking the checks (either one off,
  searching whole lines, accepting any comment as a reason) fails at least
  one of them.
- The samples' three `catch (...)` handlers name their boundaries.

### Documentation

- POLICY.md 2.9: formatting, and why the limit stays at 100 columns. *Why:*
  the limit was accepted provisionally and reviewed after real use (1,785
  lines across cpp-policy and SimpleLocalServer): 80 would rewrap about 11% of
  them, and nothing past 100 is code clang-format could wrap.

## 0.6.1 (2026-09-27)

A new tool; nothing about the rules or the build changes, so a patch release
(POLICY.md 10).

### Upgrading a project

1. Pin the commit of `v0.6.1` in `GIT_TAG` and in `.github/workflows/ci.yml`,
   for example with the new script:
   `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.6.1`.

### Tools

- `tools/upgrade.sh <tag>`: upgrades a project to a release. It moves the
  `GIT_TAG` pin and every CI gate pin to the release's commit, copies
  `.clang-tidy`, `.clang-format` and the hooks, fails unless each change is
  really there, shows the diff and the release's CHANGELOG entry, and runs
  the gate. It refuses a working folder with uncommitted changes and commits
  nothing. *Why:* every upgrade so far needed a script written by hand, and
  one of them passed the gate without changing anything. Checked by replaying
  two real SimpleLocalServer upgrades (v0.3.3 to v0.4.0, with a hook change,
  and v0.5.1 to v0.6.0, with CI): the results match the commits made by hand
  byte for byte.

### Self-test

- `upgrade/behavior` (not on Windows, like the hooks test): a fake cpp-policy
  with two releases and a project on the first. The upgrade must move both
  pins, copy the files (hooks executable), show only the new CHANGELOG entry,
  and refuse a dirty folder or an unknown tag without changing anything.
  Breaking the script (no dirty check, CI pins skipped, tag comment left,
  hooks not executable, whole CHANGELOG shown) fails the test each time.

## 0.6.0 (2026-09-27)

A new audit rule, so a minor release (POLICY.md 10): code that passed before
can fail.

### Upgrading a project

1. Pin the commit of `v0.6.0` in `GIT_TAG` and in `.github/workflows/ci.yml`.
2. Split any source file over 350 lines by responsibility (POLICY.md 11.3),
   or move generated or third-party code to an excluded directory.

### Rules

- The audit fails on a source file over 350 lines, reporting it at line 351.
  *Why:* POLICY.md 11.3 set the threshold ("split by responsibility before
  adding more") without a check, and a rule nothing checks tends to be skipped,
  by agents especially. The 250-line target stays a review matter. A final
  newline doesn't count as a line.

### Self-test

- `tests/audit/file_at_limit` (350 lines, passes) and `file_too_long` (351,
  fails). Checked by breaking the rule: an off-by-one limit, counting the final
  newline and disabling the rule each fail at least one of them.

## 0.5.1 (2026-09-27)

A CI fix found by the first project to use the gate with vcpkg. It only makes
failing CI jobs work, so a patch release (POLICY.md 10).

### Upgrading a project

1. Pin the commit of `v0.5.1` in `GIT_TAG` and in `.github/workflows/ci.yml`
   (the audit requires both to match).

### CI

- With `vcpkg: true`, the gate now checks out the runner's vcpkg at the
  manifest's `builtin-baseline` and rebuilds the tool. *Why:*
  SimpleLocalServer's first CI run failed on every job with "no version
  database entry for cpp-httplib at 0.58.0": the runner image's vcpkg is a
  checkout from when the image was built, and vcpkg reads port versions from
  the checked-out files, so fetching the newer history wasn't enough. The
  checkout uses `--force` because the Ubuntu image has modified files in its
  copy. The step was tried first on both runners with SimpleLocalServer's
  manifest (a temporary probe workflow, now removed).

## 0.5.0 (2026-09-27)

CI in GitHub Actions. It adds an audit rule, so it goes out as a minor
release (POLICY.md 10).

### Upgrading a project

1. Pin the commit of `v0.5.0` in `GIT_TAG`.
2. Optional, recommended: add `.github/workflows/ci.yml` calling this
   repository's `gate.yml` at the same commit (README, "Continuous
   integration"), and add `.github/` to the files agents must not edit
   (`AGENTS.md` and `.claude/settings.json`, POLICY.md 6).

### Rules

- CI workflows are policy files (POLICY.md 6): projects protect them like the
  presets and the hooks. *Why:* CI is the check an agent can't skip locally;
  an edited workflow would weaken it unnoticed.
- The audit fails if a workflow calls `cpp-policy/.github/workflows/gate.yml`
  at any ref other than the commit the build uses (a tag fails too).
  *Why:* two pins that can drift apart would let CI run a different policy
  than the local gate.

### CI

- `.github/workflows/gate.yml`: a reusable workflow that runs `check`, `tsan`
  and `release` on Linux (Ubuntu 24.04, LLVM from apt.llvm.org), Windows
  (Server 2025, the official LLVM archive) and macOS (15, Homebrew LLVM),
  with no `tsan` on Windows. Inputs: `systems` and `vcpkg`. *Why:* the first
  test on all three systems took a week of sessions relayed by hand; every
  system now runs on every push. Every download is pinned (actions by commit,
  the apt key by fingerprint, the Windows archive by SHA-256), and jobs only
  get read access.
- `.github/workflows/ci.yml` runs it for this repository on every push.

### Fixes

- The audit's check that skips the project-file comparisons in cpp-policy's
  own tree never matched: `POLICY_ROOT` ends in a slash and `SOURCE_DIR`
  doesn't. It was harmless for the copy checks (the policy's files equal
  themselves) but not for the new CI pin check; both paths are now resolved
  with `file(REAL_PATH)`.

### Self-test

- `tests/audit/ci_pin_matches`, `ci_pin_differs`, `ci_pin_tag`.

## 0.4.1 (2026-09-27)

A self-test fix from the Linux verification of 0.4.0. No rule, flag or check
changes, so a patch release (POLICY.md 10).

### Upgrading a project

1. Pin the commit of `v0.4.1`. Nothing else.

### Self-test

- `leak/detected` leaks eight objects instead of one. *Why:* the test was
  flaky on Linux (about 4 passes in 10): LeakSanitizer scans the stack
  conservatively, and the single leaked pointer lingered in a dead stack
  slot, so on runs where ASLR's stack offset put that slot inside the scanned
  range the block counted as reachable. Disabling the stack scan gave 20/20
  reports and disabling ASLR 0/20, which located the cause. With eight
  leaks at most one pointer can linger; 40/40 with ASLR on and 10/10 with it
  off. Not an LLVM 23 or 0.4.0 regression: the 0.3.3 program behaves the
  same on the same machine.

### Documentation

- README: debugging with Visual Studio on Windows (Open Folder, the
  `win-debug` configuration, program arguments, Ctrl+C under the debugger).
  *Why:* checked by hand on the first Windows run (SimpleLocalServer #33);
  cmake-gui, the obvious entry point, fails without the presets.

## 0.4.0 (2026-09-26)

Release hardening for Windows (`clang-cl`), the last build-flag gap found
in the first Windows run. It adds flags and an audit rule, so it is a minor
release (POLICY.md 10); the flags apply to every configuration but Debug.

### Upgrading a project

1. Pin the commit of `v0.4.0`.
2. Nothing else: the flags come from `cpp_policy_apply`.

### Rules

- With `clang-cl`, every configuration but Debug is built and linked with
  Control Flow Guard (`/guard:cf`). *Why:* `clang-cl` got none of the
  release hardening the other platforms get (`_FORTIFY_SOURCE`,
  `-fstack-protector-strong`, `-fcf-protection`), and the module's comment
  claimed it wasn't available. CFG is the Windows counterpart of
  `-fcf-protection`. Stack cookies need no flag: `clang-cl -###` shows
  `-stack-protector 2` (strong) with no options at all, so they were already
  on. `_FORTIFY_SOURCE` has no `clang-cl` equivalent; the MSVC STL hardening
  macro (7.2) covers the standard library.
- The audit rejects the options that turn hardening off, in both spellings
  `clang-cl` accepts: `/GS-`, `-GS-`, `/guard:cf-`, `-guard:cf-`, `/sdl-`,
  `-sdl-`. *Why:* the same rule already protects warnings (`-Wno-*`, `/wd`).
- POLICY.md 7 lists the Windows flags in the `release` row and 7.4 explains
  them.

### Self-test

- `tests/hardening/pe_flags.cmake` (only with `clang-cl`, configurations
  other than Debug, so `win-dev`, `win-check` and `win-release`) reads
  `policy_good_test.exe` with `llvm-readobj` and requires `GUARD_CF` with a
  non-empty function table, plus lld-link's `DYNAMIC_BASE`,
  `HIGH_ENTROPY_VA` and `NX_COMPAT`. *Why:* the load config's
  `CF_INSTRUMENTED` flag is set by the MSVC runtime in every program, guarded
  or not, so it can't be the criterion; the function table can.
- `tests/bypass/hardening_option`: a target that passes `/GS- -guard:cf-`
  (one of each spelling) must be rejected at configure time.
- `hooks/behavior` clears the `GIT_*` variables git exports to hooks, and
  always runs with `GIT_DIR` pointing at a decoy. *Why:* pushing from a
  linked worktree runs the gate with `GIT_DIR` set to an absolute path into
  the real repository, so the test's throwaway-repository commands acted on
  the real one: `git init` set `core.bare = true` there and the push failed.
  From an ordinary clone `GIT_DIR` is `.git`, relative, which is why it had
  not shown up. Found while pushing this release's fixture fix from a
  worktree.

## 0.3.4 (2026-09-26)

A fix for Windows, found when the git hooks first ran under Git for Windows.
It only makes a broken hook work, so no passing code starts failing
(POLICY.md 10).

### Upgrading a project

1. Pin the commit of `v0.3.4` and copy `tools/hooks/pre-commit` (the audit's
   hook-copy check requires the two together).

### Fixes

- `pre-commit` selects its preset from `uname`, like `pre-push` already did:
  `win-check` under Git for Windows (MINGW, MSYS, Cygwin), `check` elsewhere,
  and it looks for the configure cache under `build/<preset>/`. *Why:* it
  always ran `cmake --preset check`, and that preset is disabled on Windows,
  so every commit there failed with "Cannot use disabled configure preset"
  before any check ran.

### Self-test

- `tests/hooks/run.cmake` runs both hooks a second time with a stub `uname`
  that reports `MINGW64_NT-…`, and requires the `win-check` preset. *Why:*
  the test runs on macOS and Linux only (it drives the hooks through `sh`),
  and this covers the Windows branch there. The real Git for Windows shell
  was exercised by hand (a misformatted commit rejected, a clean commit with
  an unstaged file warned and passed).

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

# Changelog

Each entry says what changed and why. Projects read this before moving their
`GIT_TAG` to a new release. Versioning rules: POLICY.md section 10.

## Unreleased

- **`clang-analyzer-optin.core.EnumCastOutOfRange` is off on Windows**
  (Waiting W5, POLICY.md 12), in the build and in `tidy-files`, which now
  reads the build's own copy of `.clang-tidy`. A probe on Windows says when
  the defect is gone.
  *Why:* with Microsoft's library the analyzer reports the library's own
  header for `std::filesystem::is_empty()`, `file_size()` and
  `last_write_time()`. ToneMatcher met it three times, each as a failed
  Windows job after a green local gate, and could only stop calling the
  function.
- POLICY.md 11.5: a project's version is written once, in `project()`, and
  a program that prints it gets it from there.
  *Why:* ToneMatcher's v0.4.1 printed 0.4.0; its version was in two places
  and the release commit changed one.
- POLICY.md 13.4: test data lives under `tests/data/`, binary files
  included, with the script that made it beside it, in any language and
  never run by the build or the gate; and tests that run several at a time
  share no folder by name.
  *Why:* asked by ToneMatcher, which tracks 36 PNG samples and their Python
  generator, and found by hand that no two of its tests share a scratch
  folder before turning parallel tests on.

## 0.33.0 (2026-10-10)

From the first real use of a library: Alfar replaced its copy of
ToneMatcher's code (39 files) with ToneMatcher's library at the first try,
and reported what the user's side made awkward, with two proposals from
its owner about tests' time. Everything here is optional: a minor release.

### Upgrading a project

**Work beyond `upgrade.sh`:** none.

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.33.0`.
2. Optional: `cpp_policy_parallel_tests()` before the first
   `cpp_policy_add_tests()`, once each integration test uses a folder and a
   port of its own (POLICY.md 13.2). Mark a program whose tests can't run
   beside others `ALONE`.
3. Optional, in a project that uses a library: `TO NONE` for the library
   as a whole and a line per module used (POLICY.md 11.7).
4. Optional, for the owner: `AGENTS.md`'s first paragraph in new projects
   says to configure before reading the fetched `POLICY.md` after a pin
   move. Agents may not edit `AGENTS.md`.

### Added

- **`cpp_policy_confine_includes(<header>... TO NONE)`:** no module may
  include it. Lines add up, so `lib/ TO NONE` with `lib/parse/ TO a b` opens
  one folder of a library and leaves the rest to nobody.
  *Why:* Alfar uses five of the library's eleven modules and had no way to
  say that nobody includes the other six; it gave them to one module, which
  wasn't true. The same line holds a package that only the library needs
  (zlib there), which had no confinement line to be on.
- **`SLOW "<reason>"` in `cpp_policy_add_tests()`:** a `TIMEOUT` above 60
  seconds, up to 600, for one test program, printed at every configure.
  *Why:* the limit had no exception, and a test that honestly takes longer
  could only be cut to fit. The owner's proposal: keep 60 as the rule, and
  make the exception say why, as `NO_LEAK_CHECK` does.
- **The gate names the passing tests that used two thirds of their limit,**
  before the launcher's last line and in CI's log
  (`cmake/scripts/test_times.cmake`).
  *Why:* two of Alfar's tests took 41 and 46 seconds of 60 for days and
  nothing said so; then four gate runs failed on them alone while other
  agents were building.
- **`cpp_policy_parallel_tests()`:** a project's unit and integration tests
  run four at a time. Benchmarks, `SLOW` programs, `add_test()` tests and
  programs declared `ALONE` still run alone. The presets give CTest four
  jobs; without the call every test is marked to run alone, so nothing
  changes for a project that doesn't ask.
  *Why:* after 0.29.0, integration tests are 381 of the 389 seconds of
  Alfar's tests, one at a time. Opt-in, because tests that share a port or
  a folder would fail together.
- **`tidy-files` configures again when the build folder holds another
  release of the policy than `CMakeLists.txt` pins.**
  *Why:* a pin moved by a merge left v0.31.0 in Alfar's build folder, and
  the first POLICY.md 11.7 its agent read was the old one.

### Changed

- POLICY.md 11.6 and 11.7 say what "lines add up" means for a narrower line
  beside a wider one, that a module which gets a dependency's types through
  another header needs no line, that `library.cmake` is where
  `find_package()` is called, and what the first build after a library
  replaces copied code costs. 11.7's example for a user is `TO NONE` and a
  line per module.
  *Why:* each was a question Alfar had to answer by trying.
- POLICY.md 11.7: a library's test support goes in a module of its own in
  the top layer, and may be headers only; the release commit (changelog and
  version) comes before the tag, which goes on it once its CI is green.
  *Why:* asked by ToneMatcher on releasing v0.4.1, whose tagged tree lists
  the release's changes under "Unreleased".

### Measured, by Alfar

- The switch to the library: both programs about 200 bytes larger, 2,942
  built files byte for byte the same, 120 s before and 124 s after.
- The gate's tests on the same code: about 580 s with v0.26.5 (1,634 CTest
  tests), 389 s with v0.31.0 (642). Unit tests went from about 180 s to 8.

## 0.32.0 (2026-10-09)

Release B of the library plan (POLICY.md 11.7): what the first real use,
ToneMatcher's library for Alfar, showed was missing. All of it optional: a
minor release.

### Upgrading a project

**Work beyond `upgrade.sh`:** none.

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.32.0`.
2. A project that uses a library in a private repository: the owner creates
   a token and passes it to the gate (README, "Continuous integration").
3. Optional, in a project that offers a library: move headers that are a
   module's own into `<module>/internal/`; offer test helpers with
   `TEST_SUPPORT`.

### Added

- **`library_token`, a secret of `gate.yml` and `benchmark.yml`:** a token
  that can read the private repositories of the libraries a project uses.
  The gate reads their addresses from the `cpp_policy_use_library()` calls
  and gives git the token for the job only, as a header sent to those
  addresses and to no other. *Why:* ToneMatcher's and Alfar's repositories
  are private, and CI's own token reads only its own repository. Tried
  here with a dummy value: the header went to the library's address and not
  to another repository on the same host.
- **`upgrade.sh --library <name> <tag>`** moves a library's pin to that
  release's commit, with the tag in a comment, and runs the gate.
- **`TEST_SUPPORT` and `TEST_LINK` in `cpp_policy_library()`:** files of the
  library that only tests use, offered as `<name>::test_support`. *Why:*
  Alfar keeps a copy of ToneMatcher's `scratch_folder.hpp` for its tests.
- **`internal/`:** a header in `lib/<name>/<module>/internal/` is that
  module's own. The library's audit refuses it from another module, and a
  user's audit refuses it altogether (fixtures `library_internal`,
  `library_internal_user`). *Why:* ToneMatcher's `png_format.hpp` and
  `zlib_stream.hpp` were internal by a comment only, and Alfar could
  include them.
- The self-test's library offers test support and has an internal header;
  its user links the first and is refused the second.

### Not tried yet

**The token in a real CI run.** cpp-policy's repository is public and uses
no library, so its CI runs that step only as far as "This project uses no
library". The first real run will be Alfar's, once the owner has created
the token. If it fails to fetch, the job's log says which address.

## 0.31.0 (2026-10-09)

From ToneMatcher, which released its library on v0.30.0 the same day: a
defect in the audit, and what the two library functions made awkward. The
library's target is renamed, so a project that declares one changes a few
lines: a minor release.

### Upgrading a project

**Work beyond `upgrade.sh`:** only for a project that offers a library
(ToneMatcher): see step 2.

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.31.0`.
2. The library's target is now `<name>_library`. Link it by its alias,
   `<name>::<name>`, everywhere; the program can take the name `<name>` back
   (and its size budget with it).
3. `cpp_policy_confine_includes()` lines that were left out because of the
   defect below can go in.

### Fixed

- **With any `cpp_policy_confine_includes()` line, the audit rejected every
  suppression below a file's first `#include`** as "outside a confined
  area", in confined folders too. The change of 0.29.0 that made two lines
  for one header add up reused the variable that says whether the file is
  confined. Found by ToneMatcher, with the line numbers; no fixture had a
  confinement line and a suppression together, and `includes_in_confined`
  now does. Projects on 0.29.0 or 0.30.0 with such lines and a `NOLINT` in
  `src/lowlevel/` fail their audit until they upgrade.

### Changed

- **A library's target is `<name>_library`,** with the alias
  `<name>::<name>` and the file `lib<name>.a` (POLICY.md 11.7). *Why:* in
  0.30.0 it was `<name>`, which is what a project's program is usually
  called; ToneMatcher had to rename its program's target to
  `tonematcher_program`. The self-test's library project now has a program
  with the library's name.
- **A release build says each program's size after it links,** and what is
  left of its budget (13.5). *Why:* CTest hides a passing test's output, so
  the size could be read only from a failing job. ToneMatcher's program had
  been 160 bytes under its macOS budget without anyone knowing, and its
  Windows size couldn't be read at all.

### Documentation

- 11.7: `CMakeLists.txt` doesn't repeat `library.cmake`'s `find_package()`
  calls; every header of a library can be included by its user, and how to
  keep something inside meanwhile (a class with a hidden state, which is
  also how a C library's type stays out of a header).
- 15.6: reading and writing files are functions apart from the entry, and
  may live beside it.
- 13.5 and `heap_bytes.hpp`: how to measure what one operation adds to the
  heap (the peak is absolute; subtract the live bytes read before it), and
  three notes on giving a C library an allocator (only a stream takes one,
  so `compress`/`uncompress` are replaced; allocate with `std::nothrow`;
  test that the memory arrives). ToneMatcher did it as 13.5 said and
  reported what the text had left out, including a test that passed for
  the wrong reason.
- 14.2: the instruction-count trial's first results. A real change showed
  as 0.08% on the one benchmark it touched; moving 46 files between folders
  and targets changed the others by at most 99 instructions.

## 0.30.0 (2026-10-09)

One policy project used as a library by another (POLICY.md 11.7, new):
release A of the plan the owner approved. New and optional: a minor release.

### Upgrading a project

**Work beyond `upgrade.sh`:** none, unless the project is to offer a library
or use one.

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.30.0`.
2. To offer a library: move its modules to `lib/<name>/<module>/`, write
   their includes as `"<name>/<module>/<header>.hpp"`, declare it in
   `library.cmake` with `cpp_policy_library()`, and include that file from
   `CMakeLists.txt` before `cpp_policy_add_checks()`.
3. To use one: `cpp_policy_use_library(<name> GIT_REPOSITORY … GIT_TAG
   <commit>)`, link `<name>::<name>`, list its packages in `vcpkg.json`, and
   say which modules may include it with
   `cpp_policy_confine_includes(<name>/ TO …)`.

### Added

- **`cpp_policy_library()`:** a library in `lib/<name>/<module>/`, with
  layers of its own, declared in `library.cmake`. The audit holds its
  layers and refuses an include from it into `src/` (fixtures `library_ok`,
  `library_rules`).
- **`cpp_policy_use_library()`:** fetches a library's repository at a
  pinned commit, includes only its `library.cmake`, and builds it in this
  build as a dependency: this build's compiler, standard, hardening and
  sanitizers; not its warnings as errors, clang-tidy, audit or format.
  Configuration fails for a library checked with a cpp-policy below the
  floor (v0.30.0) and for a package the library needs that `vcpkg.json`
  doesn't list.
- **`cpp_policy_confine_includes()` takes `<library>/<module>`** as a
  module, for the library's own dependencies.
- **Self-test `library/used_by_another_project`:** a library project with a
  program, and a user whose modules have the library's names (`lowlevel`,
  `app`). Each passes its build with clang-tidy, its audit and its format
  check; the user's test calls the library. The user's gate must fail for
  a module that isn't allowed to include the library, a missing package and
  a library below the floor; the library's, for an include of the program.

*Why:* asked by Alfar (2026-10-09). The owner decided that ToneMatcher's
work will be available inside Alfar with no code copied and no third
repository, so ToneMatcher builds a library and its program over it. Alfar
carried 37 copied files, edited within two days. The layout was the one
decision without an alternative: a library header that included
`"lowlevel/process.hpp"` would need the library's root on the user's
include path, beside the user's own `lowlevel/`. The owner approved the
layout, and the library as a dependency with a floor in its user's build.

### Not in this release (release B)

Shaped by the first real use, ToneMatcher's library in Alfar: `upgrade.sh`
for a library's pin, test helpers offered by a library, and the credential
a private repository needs to be fetched in CI. Until then a user moves the
pin by hand, and a project whose CI can't fetch the library's repository
runs that part of its gate where it can.

### Not tried on a real project yet

The self-test's library has two modules and no real dependency. Fetching
was tried through `FETCHCONTENT_SOURCE_DIR`, not from a remote repository.

## 0.29.0 (2026-10-09)

The gate costs less time for the same checks: the second release from
Alfar's report. How unit tests reach CTest changes, so scripts that select a
unit test case by its CTest name need changing: a minor release.

### Upgrading a project

**Work beyond `upgrade.sh`:** none for the code. The upgrade copies the new
hooks, including `tools/hooks/gate`.

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.29.0`.
2. Run the gate with `sh tools/hooks/gate` from now on. A project's own
   launcher (Alfar's `out/gate`) can go.
3. A module's unit tests are now one CTest test, `unit/<module>/all test
   cases`. `ctest -R "unit/<module>/<case>"` no longer finds a case; run the
   program with `--test-case="<name>"`. Integration and benchmark tests are
   unchanged.
4. Optional: a second `cpp_policy_confine_includes()` line for a header
   another line names; zlib's allocator (POLICY.md 13.5).

### Changed

- **A module's unit tests run in one process** (POLICY.md 13.2), as one
  CTest test. *Why:* Alfar's gate grew from under a minute to eight as its
  tests grew to 1,500, and the time was processes, not tests. Measured here
  on 1,505 unit test cases in 10 programs, under the sanitizers:

  | How they run | Time |
  |---|---|
  | A process per test case, one at a time (until now) | 311 s |
  | A process per test case, ten at a time | 77 s |
  | A process per program | 2 s |

  A process costs about 0.2 s there, 0.12 s of it LeakSanitizer's check at
  exit. Unit tests may share no state, so separate processes protected
  nothing. A failure still names its test case, file and line; after a
  crash the later cases of that program don't run until it is fixed.
  Integration and benchmark tests keep a process per case. The owner chose
  it over running cases in parallel, which changes the decision of 0.19.0
  (one CTest test per test case) for unit tests (2026-10-09).
- **A module's unit tests have 60 seconds together,** where each case had
  10. The owner chose it: 10 for a whole program could fail on a busy
  machine. That a unit test takes well under a second stays a rule for
  review.

### Added

- **`tools/hooks/gate`, the gate's launcher** (POLICY.md 8): one gate at a
  time on the machine, the machine kept awake (macOS and Linux), one last
  line `gate: passed` or `gate: FAILED`, and the workflow's own exit code.
  pre-push runs the gate through it. *Why:* each is from Alfar. Four agents
  ran four gates at once, 25 minutes each where one takes 5. A Mac that
  slept made tests time out: about 2.5 hours lost, and a merge committed
  after a failing gate because the exit code read was another command's.
  Alfar had written its own launcher; three projects on one machine would
  each have written one.

### Fixed

- **Two `cpp_policy_confine_includes()` lines for one header rejected each
  other** (found by Alfar; a defect since 0.26.0). They now add up, each
  with its own `SOURCES_ONLY` (audit fixture `includes_two_lines`).

### Documentation

- POLICY.md 13.5: a C library that takes an allocator (zlib's `zalloc`) is
  given one that uses `operator new`, so the heap test counts its memory
  and the operating-system test isn't needed. Suggested to ToneMatcher,
  whose two such tests failed four times without finding a leak.
- `ROADMAP.md`: this release, and what comes after it (libraries).

### Not tried on a real project yet

The times above are from a generated project with trivial tests. Alfar's
own gate, before and after, is this release's validation and is asked of
Alfar.

## 0.28.0 (2026-10-08)

From Alfar's report: a project built in four days by unattended agents on
v0.26.5, with measurements of what the policy cost. This release fixes the
defects it found and makes the quick check say what the gate will. One
change can make a passing project fail (sanitizer options in a test's
environment), so it is a minor release.

### Upgrading a project

**Work beyond `upgrade.sh`:** only for a project that sets a sanitizer's
options in a test's environment (Alfar does): see step 2.

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.28.0`. It copies
   the new `.clang-tidy`, `CMakePresets.json` and hooks.
2. `ENVIRONMENT "ASAN_OPTIONS=detect_leaks=0"` on a test program is now
   refused. Replace it with `NO_LEAK_CHECK "<reason>"` (POLICY.md 5).
3. Optional: `cpp_policy_test_support(<target>)` for a library of test
   helpers; `imgui*` in `cpp_policy_confine_includes()` in place of a list
   of header names.
4. Optional, for the owner: replace the layer table in `AGENTS.md` with the
   template's "Layers" section, which points to `cpp_policy_layers()`.
5. Code written round the old rules still passes: named values in place of
   `Type{}`, test files split at 350 lines.

### Fixed

- **`policy-format-fix` broke code.** It let clang-tidy apply
  `readability-trailing-comma`'s fixes, and that check takes the comma after
  an empty braced value for a trailing one: `f(1, Options{}, 2)` became
  `f(1, Options{} 2)`, and the same in a default argument and in an array.
  Alfar lost at least a dozen builds to it. 0.26.3 recorded the defect (W4)
  too narrowly, as `.member = {}` only, and left the fixer applying the fix.
  The check is now off and the fixer only formats (see "Changed").
- **The pre-commit check refused code the gate accepted.**
  - A header was checked on its own with the flags of a "similar" source,
    which could lack an include path. It is now checked through a source of
    the build that includes it, with that source's flags and checks, and
    only the header's findings shown.
  - A library of test helpers was test code for the hook and program code
    for the build. `cpp_policy_test_support(<target>)` declares it, for
    both.
- **In a git worktree, the audit's CI pin check failed inside pre-commit.**
  Git exports `GIT_DIR` to hooks, and the policy's own commit was then read
  from the project's repository.
- **LeakSanitizer could be switched off unseen,** through a test's
  `ENVIRONMENT`. Sanitizer options there are now rejected at configuration
  (bypass fixtures `test_sanitizer_options`, `test_plain_sanitizer_options`).

### Changed

- **`readability-trailing-comma` is off until LLVM fixes it** (W4; the probe
  now uses the call-argument shape). `policy-format-fix` is clang-format
  only: seconds where it took 6 minutes at Alfar's 640 files. The owner
  chose this over keeping the check without its fixer (2026-10-08).
- **`tidy-files` reports what the gate will say about the files named,
  without the tests:** the format, the audit's rules about one file (length,
  suppressions, `// boundary:`, test-case names) and clang-tidy.
  `tidy-files --format <file>...` formats them. *Why:* in Alfar 8 of 38 gate
  runs were lost to faults that have nothing to do with behaviour and were
  reported only at the end of a build of several minutes.
- **The gate runs the audit and the format check before compiling**
  (`check-first`, a step of the `check` workflow). Nothing is removed.
- **Test sources, under `tests/`, may have 500 lines** (POLICY.md 11.3);
  product code keeps 350. `tidy-files` says so from 50 lines before either
  limit. The owner chose it: about a third of Alfar's forced splits were
  test files.
- **Test-case names are read from the source text** by the audit and
  `tidy-files`, with the allowed characters in the message. They were found
  only when the test program registered its tests, after compiling and
  linking: 11 times in Alfar, each a rebuild.
- **`AGENTS.md` has no layer table** (template; POLICY.md 11.1). It points to
  `cpp_policy_layers()`, which the audit enforces, and to `README.md`, which
  agents may edit. In Alfar the table was wrong for 59 hours, and an agent
  avoided creating a module because it needed a line there. The owner chose
  it.

### Added

- **`NO_LEAK_CHECK "<reason>"` in `cpp_policy_add_tests()`** (POLICY.md 5),
  for a test program that opens a window: LeakSanitizer reports what the
  operating system keeps for the life of the process. Every configure
  prints that it is off, and why; it is refused for unit tests. *Why:* this
  was the one rule Alfar could not meet. Entries in `lsan.supp` by library
  would also hide a project's own leak under a callback, so the honest
  option is a switch that shows.
- **A prefix in `cpp_policy_confine_includes()`** (`imgui*`), for a library
  whose headers are in no folder of their own.
- POLICY.md 2.8: a condition variable needs `std::unique_lock`. 2.10: flag
  enumerations of a C library under `bugprone-signed-bitwise`.

### Not in this release

The rest of Alfar's report needs measurements or the owner's decisions, and
comes next: the cost of the tests under the sanitizers (one process per
test case, run one at a time), a launcher for the gate that keeps the
machine awake and takes a lock, budgets in unattended runs, sharing code
between projects, and MPL-2.0, which the owner left open until a project
needs it.

## 0.27.0 (2026-10-07)

A trial: instruction counts of the benchmark tests, recorded in CI
(POLICY.md 14.2). Optional, and it checks nothing: a minor release. CI also
cancels runs that a newer push made obsolete.

### Upgrading a project

**Work beyond `upgrade.sh`:** none, unless the project joins the trial.

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.27.0`.
2. To join the trial (ToneMatcher first; it needs the `benchmark` runner on
   the repository), the owner adds to the CI workflow:

   ```yaml
     benchmark:
       uses: luiserh1/cpp-policy/.github/workflows/benchmark.yml@<commit> # v0.27.0
   ```

   and the project has at least one nanobench benchmark (14.2).

### Added

- **`.github/workflows/benchmark.yml`,** a reusable workflow: on the runner
  labelled `benchmark` it builds the release preset, runs the benchmark
  tests, and keeps their output in the job's summary and as an artifact for
  90 days. A failing test doesn't fail it (the gate decides), and where the
  counters aren't readable it says so and passes. *Why:* the owner asked
  whether CI is consistent enough to check performance. It isn't for time:
  a job gets whatever processors are free. The server administrator
  measured that instruction counts repeat to 0.001% between an idle and a
  fully loaded machine, while time moved by a third. The owner chose to
  open the counters on one labelled runner and to run a trial on one
  project before any budget rule (2026-10-02).
- **The audit and `upgrade.sh` treat every cpp-policy workflow a project
  calls like the gate:** pinned to the commit the build uses, and moved on
  upgrade (audit fixture `ci_pin_benchmark`). *Why:* a benchmark job at an
  older commit than the build would measure with another release's rules.

### Changed

- **CI cancels runs that a newer push made obsolete** (`gate.yml`;
  POLICY.md 8). On a branch the older run is stopped. On the default branch
  the run in progress finishes, and runs still waiting behind it are
  replaced by the newest. A tag's run is never cancelled. `benchmark.yml`
  does the same on branches and measures every commit of the default
  branch. Projects get it with this upgrade, with no change to their own
  workflow. *Why:* asked by the owner through the server administrator. The
  home server is now off part of the time; pushes queue up, and when it
  came back the runners worked through every queued commit in order, old
  ones included. The rule lives in `gate.yml`, where a group is evaluated
  for the calling workflow, so each cpp-policy workflow has a group name of
  its own. Tried on cpp-policy's CI with two quick pushes to a branch
  (runs 37605998535 and 37606149110): the first was cancelled and the
  second ran. The owner chose both the place and the behaviour
  (2026-10-07).

### Not tried yet

The benchmark workflow can't run in cpp-policy's own CI: this repository is public and
has no self-hosted runner. Its shell logic was tried here on real benchmark
output with and without the counters' column; its first real run will be
ToneMatcher's. POLICY.md 10 asks for a trial before a release, and here the
release is what makes the trial possible, because the audit requires the
call to be pinned to the build's commit.

## 0.26.5 (2026-10-02)

### Upgrading a project

**Work beyond `upgrade.sh`:** none. Text only.

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.26.5`.

### Changed (POLICY.md 13.5)

- **The operating system's peak is noisy by itself, not because a machine is
  busy.** 13.5 said such a test "can fail on a busy machine" and called a CI
  machine "busy" without evidence. It now carries the home server's
  measurements (20 runs per condition of ToneMatcher's two tests): on Linux
  the growth was 0% with every processor busy; on Windows the reading moves
  in fixed steps, up to 7.7%, on an idle machine, and load doesn't make it
  worse. *Why:* the server administrator measured it after the owner asked
  whether CI fails because the server is busy, and found that none of 24
  failed runs was caused by capacity. The wording here had helped spread
  that explanation. The macOS reproduction in 13.5 stands: there, load did
  change which of two levels a run landed on.
- Load costs time (up to twice on Windows); a test near its time limit, or
  any suspected environment problem, goes to whoever runs the machines with
  the run's link.

## 0.26.4 (2026-10-02)

### Upgrading a project

**Work beyond `upgrade.sh`:** none.

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.26.4`.

### Fixed

- **`tidy-files` (and so `pre-commit`) reported an optional read after
  `REQUIRE` in a test header that isn't in a test source's folder,** while
  the gate accepted it. 0.26.3 gave the test setting only to headers in the
  same folder as a test source; `tests/support/x.hpp`, shared by sources in
  `tests/integration/` and `tests/benchmark/`, was checked as program code.
  A header is now test code anywhere under the top-level folder the test
  sources are in, unless that folder is `src/`. The generated-project test
  has such a header. *Why:* found by GalleryOrganizer on adopting 0.26.3;
  the gate and the hook must agree, or a commit fails on code the gate
  passes.

## 0.26.3 (2026-10-02)

From the first session of a new project, GalleryOrganizer, created from
v0.26.1: two defects and four points of friction, all reproduced. Rules are
only loosened, so nothing that passed fails: a patch release.

### Upgrading a project

**Work beyond `upgrade.sh`:** none. The upgrade copies the new `.clang-tidy`
and hooks.

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.26.3`.

### Fixed

- **`pre-commit` split staged file names on spaces.** A staged test asset
  named `quoted make.jpg` reached `tidy-files` as two names. It now splits on
  newlines only, and asks git for unquoted names.
- **`tidy-files` skipped files added since the build was configured,** said
  "not built on this system", and ended `OK`. It now configures the build
  again, once, before deciding. A file that still isn't compiled is reported
  as "NOT CHECKED" and counted in the summary.

### Changed

- **A designated initializer may leave fields out** (POLICY.md 2.10, 7.1):
  `-Wmissing-designated-field-initializers` is off. *Why:* three rules made
  some structs impossible to initialize. A class-type member may not have
  `{}` as its default (clang-tidy calls it redundant); leaving it out was
  then an error; and writing `.member = {}` for a nested struct hits the
  clang-tidy defect below. Omitted fields are initialized by the language at
  every optimization level, which the owner asked about and which was
  checked with a `static_assert` and at `-O0` to `-O3`. The owner chose it
  (2026-10-02), knowing that a field added later is no longer reported where
  the struct is built.
- **Cognitive complexity doesn't count code inside macros** (11.3;
  `IgnoreMacros` in `.clang-tidy`). *Why:* each doctest `CHECK` added 3 to 5,
  so a table loop with two `REQUIRE`s and six `CHECK`s measured 65 against a
  limit of 25, and the form 13.4 asks for needed a helper per row. Measured
  here: the same test passes with the option. The owner chose it.
- **In test programs, `bugprone-unchecked-optional-access` is off** (13.4).
  `cpp_policy_add_tests()` adds the option, and `tidy-files` gives test
  sources the same. *Why:* `REQUIRE(value.has_value())` followed by `*value`
  was still reported, since clang-tidy can't see that `REQUIRE` stops the
  test. Library hardening stops a test that reads an empty optional. The
  owner chose it over documenting a workaround.

### Waiting on the toolchain

- **W4 (POLICY.md 12), new:** clang-tidy's `readability-trailing-comma`
  reports the comma after an empty braced aggregate (`.inner = {},`) whose
  members have default member initializers as a trailing comma. In the
  middle of a list its fix removes a comma the syntax needs; at the end,
  `policy-format-fix` never settles. Workaround: leave the field out. Probe
  `waiting/w4_trailing_comma`, on every system.

### Also

- `new-project.sh`'s closing text says that the size budget and the layer
  table in `AGENTS.md` are the sample's and need the owner.

## 0.26.2 (2026-10-02)

The shell scripts are now tested on Windows. Tests only: a patch release.

### Upgrading a project

**Work beyond `upgrade.sh`:** none. Nothing a project uses changed.

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.26.2`.

### Tests

- **`hooks/behavior` and `upgrade/behavior` run on Windows,** under the `sh`
  that Git for Windows ships (found next to `git`), which is the shell git
  runs hooks with there. They were skipped on Windows before.
- **New `template/new_project_script`,** on every system: it runs
  `tools/new-project.sh` itself on a throwaway copy of the policy tagged as
  a release, and checks the pins, the vcpkg baseline, the enabled hooks, LF
  line endings in the copied hooks, and both refusals (no release tag,
  uncommitted changes). Only the CMake script behind it was tested before.

*Why:* the owner asked whether the scripts work on every supported system.
On Windows the hooks, `upgrade.sh` and `new-project.sh` rested on manual
runs, and the last two had, as far as known, only ever been run on macOS.
All three passed on Windows at the first CI run (36946376225), so no script
needed a fix. They need Git for Windows' `sh`; none runs from PowerShell or
`cmd` directly.

## 0.26.1 (2026-10-02)

Three general points that were in the brief for a new project, moved into
the policy. Text only: a patch release.

### Upgrading a project

**Work beyond `upgrade.sh`:** none.

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.26.1`.

### Added

- **15.6, the interface between a backend and its frontends:** plain data in
  and out, errors as values and no exception crossing it, one function per
  thing a user can do, no second copy of the types, no logic in frontends.
- **13.4, a port uses the original as its reference:** tests compare with
  the original's saved output on the same inputs.
- **9, a new project is created with `tools/new-project.sh`,** never by
  hand; and a rule that seems wrong for a project is reported to the owner
  for cpp-policy, not worked around.

*Why:* the owner is starting a port with a backend and several frontends in
a new conversation, and asked whether what the brief had to spell out should
be in the policy. These are true of any project, so a conversation that
reads the policy now gets them without being told. What is specific to that
project (which frontends, in what order, the first milestone) stays in its
brief. Building for iOS and Android stays out until it has been tried.

## 0.26.0 (2026-10-02)

A dependency's headers can be kept in the modules that use it
(POLICY.md 11.6, new). Optional until a project declares one: a minor
release.

### Upgrading a project

**Work beyond `upgrade.sh`:** none required.

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.26.0`.
2. When convenient, add a `cpp_policy_confine_includes()` line for each
   dependency the program's code includes, before `cpp_policy_add_checks()`.
   Both projects already keep theirs in one module, so the lines record what
   is true: `httplib.h TO server` in SimpleLocalServer; `nlohmann/ TO config`
   and `zlib.h TO lowlevel SOURCES_ONLY` in ToneMatcher.

### Added

- **`cpp_policy_confine_includes(<header or directory/>... TO <module>...
  [SOURCES_ONLY])`**, checked by the audit: the named headers may be
  included only from those modules, and with `SOURCES_ONLY` only from their
  source files. Audit fixtures `includes_outside`, `includes_header`,
  `includes_ok`, `includes_unknown_module`; bypass fixture `includes_late`.
  *Why:* the owner plans a project with a backend, an interface and several
  frontends (a command line, a window, later iOS and Android), so that the
  backend's many dependencies don't reach the frontends. Layers
  (11.1) only order the project's own modules; nothing stopped a frontend
  from including a third-party header directly. `SOURCES_ONLY` exists
  because a header that includes a library passes it on to every file that
  includes that header, which is how a dependency reaches a frontend without
  anyone writing its name there.
- The template's `AGENTS.md` mentions the rule.

## 0.25.0 (2026-10-02)

Design (POLICY.md 15, new): the last item of the roadmap's "how we test,
measure and design".

### Upgrading a project

**Work beyond `upgrade.sh`:** none.

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.25.0`.
2. Optional: add the "Design" line of the template's `AGENTS.md` to the
   project's own (the owner edits that file).

### Added

- **POLICY.md 15, Design:** plain data in `struct`s with free functions; a
  `class` only to protect an invariant or own a resource; `enum class` or
  `std::variant` for closed sets, inheritance only for open runtime
  polymorphism; `std::vector` by default, with cache layout as a technique
  for measured hot spots; tests first where the behaviour is known up
  front; single-threaded by default. *Why:* issue #27. It is written as
  guidance checked in review, because it is judgement and both projects
  already work this way (71 `struct`s, 25 `class`es, no derived class or
  virtual function between them). The one mechanical part, a type's data
  being all public or all private, was already a clang-tidy check.
  SimpleLocalServer's review (0.24.2) said no rule about the code had got
  in its way; this section is meant to keep that true. The owner agreed the
  approach, and that "data-oriented" in the strict sense (layout for the
  cache) belongs to measured hot spots (2026-10-02).
- The template's `AGENTS.md` has a "Design" line.

### Roadmap

- "Design approach (#27)" is done, and with it the group "how we test,
  measure and design". Only the modules experiment remains, waiting on
  CMake.

## 0.24.2 (2026-10-02)

Corrections from SimpleLocalServer's review of what the policy has cost it.
Nothing that passed fails: a patch release.

### Upgrading a project

**Work beyond `upgrade.sh`:** none required.

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.24.2`.
2. When convenient: replace the "Upgraded to cpp-policy" entries in
   `CHANGELOG.md` with the one line `Policy: cpp-policy v0.24.2.`
   (POLICY.md 11.5).
3. A server whose heap test follows v0.24.0's recipe (N unmeasured, N, 5N)
   moves to the one below. SimpleLocalServer's already does.

### Changed

- **13.5, the server's heap test:** warm up in rounds until a round leaves
  `live_heap_bytes()` no higher, up to a maximum; then 5N more requests may
  raise it by less than 10%. A leak never settles and fails in the warm-up.
  *Why:* v0.24.0's recipe was developed on ToneMatcher's batch commands and
  not tried on a server. On SimpleLocalServer it failed with +45% on Linux
  and +20% on Windows, without a leak: cpp-httplib allocates a table in each
  pool thread on first use, and Linux needed 13,000 messages to reach them
  all. The notice for v0.24.0 said N could be much smaller and no warm-up
  curve was needed; that was wrong. The new recipe is SimpleLocalServer's
  own fix.
- **13.5, what is exact:** `live_heap_bytes()` always; `peak_heap_bytes()`
  only for work on one thread. *Why:* SimpleLocalServer measured peaks
  between 562,240 and 563,072 bytes over identical rounds.
- **13.5, the operating system's peak test:** not required for sockets
  (kernel memory), and "rerun it" is gone: a project whose test fails
  without a cause and has no memory outside the C++ heap drops it. *Why:*
  SimpleLocalServer's failed once on Windows (+21%) and passed on the next
  run with the same code; a test that fails now and then teaches people to
  rerun. That one failure is unexplained.
- **11.5, cpp-policy upgrades are one line in a project's `CHANGELOG.md`**
  (`Policy: cpp-policy v<version>.`), plus entries only for what an upgrade
  changed in the project itself. The template has the line and `upgrade.sh`
  reminds of it. *Why:* SimpleLocalServer's changelog had about 170 lines of
  upgrade entries, which buried what changed in the program. The owner chose
  this (2026-10-02).
- **10, releases:** every "Upgrading a project" section starts with "Work
  beyond `upgrade.sh`", and a release that changes what projects must write
  is first run on each shape it applies to, on all three systems. *Why:*
  nine upgrades in one stretch, three needing real work, and two 13.5
  recipes that failed at first contact with the server.

### Added

- Self-test `testing/heap_pool`: the server recipe on a pool of 32 threads
  that each allocate a table on first use, and a handler that keeps 64 bytes
  per request, which must never settle. It gives cpp-policy a server-shaped
  case of its own on every system.

## 0.24.1 (2026-10-02)

The memory a batch command may keep per input is a budget, not a fixed
figure (POLICY.md 13.5). Nothing that passed fails: a patch release.

### Changed (POLICY.md 13.5)

- **1 KiB per input is the default budget. A command may have a higher
  one,** with the owner's approval and a `CHANGELOG.md` line saying what the
  record is and why it is kept, like a size budget. The budget is for
  records; memory that grows with the inputs' content is still streamed,
  paged or capped. *Why:* proposed by ToneMatcher after moving its twelve
  memory tests to the heap counter. The fixed 1 KiB of 0.24.0 was set from
  estimates made before anyone had measured with the counter, and was wrong
  in two ways:
  - The count differs between systems. The same code kept 621, 1,032 and
    2,200 bytes per file on macOS, Windows and Linux, because each standard
    library stores a path and a string differently. A fixed limit judged the
    library as much as the design.
  - It was far below what matters. Each input there is an image of several
    megabytes; the record is about 2 KB. Passing would have cost a temporary
    file and a two-pass reader in the main command, and gave the user
    nothing.

  The owner chose budgets, and approved 4 KiB per file for ToneMatcher's
  `export`, `pipeline` and `match-tone` (2026-10-02).
- 13.5 now says that the heap count is exact per system and differs between
  systems, so a limit must hold on the largest.

## 0.24.0 (2026-10-01)

Memory tests that don't depend on the machine's load (POLICY.md 13.5). The
rule for batch commands changes, so a test that passed may need rewriting: a
minor release (POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.24.0`.
2. Rewrite each memory test with `cpp_policy::peak_heap_bytes()`
   (POLICY.md 13.5, "The heap test"). Keep a `peak_memory_bytes()` test only
   where the memory is outside the C++ heap.
3. A batch command that keeps more than 1 KiB per input needs to write its
   output as it is produced; that is a change for the project and its owner.

### Added

- **`cpp_policy::live_heap_bytes()`, `peak_heap_bytes()` and
  `reset_peak_heap_bytes()`** (`#include <cpp_policy/heap_bytes.hpp>`), for
  benchmark tests: an exact count of the C++ heap, made by replacing
  `operator new` and `operator delete` in the test program. Self-test
  `testing/heap_bytes`; the generated-project test uses it on every system.
  *Why:* ToneMatcher reported that its `diff` memory test grew 4% on an idle
  machine and 30.6% on a busy CI machine, with the same code. Reproduced
  here with a program that only allocates and frees 1 MB buffers: the
  operating system's peak grew +80% idle and anywhere from +1% to +81% under
  load, because it depends on whether the allocator reuses a freed block.
  macOS's peak physical footprint moved the same way. A count of live bytes
  can't vary. The owner chose it (2026-10-01).
  - It doesn't see memory a C library takes with `malloc()`, or mapped
    files; `peak_memory_bytes()` stays for those.
  - In builds with sanitizers nothing is replaced and it reads 0. The `check`
    build therefore compiles and lints only that branch of `heap_bytes.cpp`;
    the counting branch was linted by hand with the same configuration, on
    macOS.

### Changed (POLICY.md 13.5)

- **A batch command may keep up to 1 KiB per input** (its name and a small
  fixed-size record); the test allows 4N × 1,024 bytes between its two
  readings. A server still keeps nothing per request (less than 10%).
  *Why:* asked by ToneMatcher. A command that processes files in sorted
  order must hold their names, and "less than 10%" of a 1 MB baseline failed
  at a few hundred names. Its commands keep 0.45, 0.9 and 3.1 KB per file;
  the last builds a whole plan in memory, which 13.5 already said to stream.
  The owner chose the figure (2026-10-01).
- **Warm-up for a batch command, where `peak_memory_bytes()` is still
  used:** several runs of N inputs, never one run larger than N. *Why:*
  found by ToneMatcher. Peak memory never goes down, so after a warm-up run
  as large as the measured one, a command that keeps memory per file and
  frees it at the end looks flat.

## 0.23.0 (2026-10-01)

Standard-library hardening can no longer be turned off. A project that set
`CPP_POLICY_HARDENING=none` now fails to configure: a minor release
(POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.23.0`.
2. Nothing else, unless the project sets `CPP_POLICY_HARDENING=none` itself
   (the presets never did): remove that setting.

### Changed

- **`CPP_POLICY_HARDENING` accepts only `fast` and `debug`.** Any other
  value, `none` included, stops configuration (POLICY.md 6, 7.2; bypass
  fixture `hardening_none`). *Why:* 0.22.0 rejected the options and
  definitions that weaken one protection, but this switch still removed the
  standard library's checks in one line. The measurements in POLICY.md 14.1
  found no speed to gain from that: builds without the protections were no
  faster. The owner decided to remove the value (2026-10-01).

## 0.22.0 (2026-10-01)

Performance (POLICY.md 14, new), from measurements. The `check` build is
optimized, and configuration rejects options that weaken the release
protections, so code that passed can fail: a minor release (POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.22.0`. It copies
   the new `CMakePresets.json`.
2. If configuration now reports "turns hardening off", remove that option or
   definition (POLICY.md 6).
3. Optional: speed benchmarks with nanobench (POLICY.md 14.2).

### Performance (POLICY.md 14, new)

- **14.1, what the safety features cost**, measured on SimpleLocalServer's
  `sanitize()` and ToneMatcher's Gaussian blur:
  - The release build's protections (hardening, stack protector,
    fortify 3) cost less than the machine's run-to-run noise (±15%), so
    they all stay.
  - ASan + UBSan cost ×1.8–2.4 at `-O3`, ×2–6 at `-O1`, and ×43–86 at `-O0`.
  - ThreadSanitizer costs ×11–14.
- **14.2, speed benchmarks:** measure first. Benchmarks are `benchmark`
  tests with nanobench. Speed is compared only on one quiet machine, over
  several runs, and is never a CI check; a change that claims or risks speed
  gives its before and after in `CHANGELOG.md`.
  - *Why nanobench:* it's header-only, MIT, and in vcpkg, and runs inside a
    doctest test case. It built with no clang-tidy findings, implementation
    included, and agreed with a hand-written timing loop within 5%. Google
    Benchmark has its own `main()` and registration macros, which don't fit
    doctest.
  - *Why no CI check:* the same binary varied by up to 15% between runs on a
    quiet Mac, and a build running alongside slowed one measurement by 80%.
    The owner chose before/after numbers in the commit (2026-10-01).
- **14.3, writing fast code within the rules:** cheap defaults (contiguous
  containers, `reserve()`, `std::span` and `std::string_view`), and removing
  work rather than checks in a proven hot spot.

### Presets

- `check` compiles at `-O1` (`cfg-optimized-tests`): its tests run 15–21
  times faster than at `-O0` (`sanitize()`: 76.6 s → 3.6 s; the blur:
  8.6 s → 0.57 s), with the same sanitizers, hardening and clang-tidy. The
  owner chose it for `check`, with `dev` and `debug` staying at `-O0` for the
  debugger (2026-10-01).
- `unit` has its own configuration, `dev` at `-O1` without clang-tidy, so
  the quick workflow is quick too. `win-check` and `win-unit` were already
  optimized (`RelWithDebInfo`, POLICY.md 7.3).

### Bypass checks (POLICY.md 6)

- Configuration rejects the following on targets, source files and
  `CMAKE_CXX_FLAGS`, as it rejects `-Wno-…`:
  - `-fno-stack-protector` and the weaker `-fstack-protector`;
  - `-fcf-protection` other than `full`;
  - `_FORTIFY_SOURCE` below 3;
  - `-U` or a disabling value of the standard-library hardening macros;
  - `-fno-sanitize=…`.

  Compile definitions are now checked too. *Why:* found while measuring.
  These were the release protections that a project could still turn off
  from CMake without configuration noticing; only warnings and `clang-cl`'s
  `/GS-`, `/guard:cf-` and `/sdl-` were checked. The owner chose to close it
  in this release (2026-10-01).
- `CPP_POLICY_HARDENING=none` is still accepted when a project sets it
  itself. Whether to forbid it is left for the owner. (Removed in 0.23.0.)

### Benchmark tests

- With nanobench in the project's `vcpkg.json`, `cpp_policy_add_tests(benchmark …)`
  links it and compiles its implementation once
  (`cmake/testing/nanobench_impl.cpp`).

### Self-test

- `bypass/protection_options` and `bypass/hardening_definitions`: each
  weakened protection fails configuration. `bypass/clean` proves the
  policy's own options aren't flagged.
- `template/new_project` adds nanobench and a speed test to the generated
  project. It must be built under clang-tidy in the check build and run in
  the release build.

## 0.21.0 (2026-10-01)

Memory tests per command, and outputs that grow with the input (POLICY.md
13.5), from ToneMatcher's v0.20.0 report. A tightened rule, though checked by
review, so a minor release (POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.21.0`.
2. Every command that processes input of unbounded size gets its own memory
   test. An output that grows with the number of inputs is streamed, paged,
   or kept whole only up to a documented cap.

### Budgets (POLICY.md 13.5)

- **A memory test per command,** not per program. *Why:* ToneMatcher's
  `export` had one and passed, while its `diff` kept every full-size diff
  until the end: 528 MB on its 92 images. Only a test of `diff` sees that.
  The owner chose per command (2026-10-01).
- **An output that grows with the input counts as memory kept per input.**
  Stream it if the format allows; otherwise use pages of fixed size, which
  is the owner's call because it changes the output; or keep it whole only
  up to a documented cap, and test at the cap. *Why:* ToneMatcher's single
  contact sheet grows by about 0.5 MB per image, so `diff` can't pass a 10%
  test even once its bug is fixed. ToneMatcher asked which the policy
  prefers. The owner chose streaming first (2026-10-01).
- **The first reading comes after the warm-up:** an unmeasured run before it,
  or an N past the bend. *Why:* without a warm-up run, ToneMatcher's export
  grew 7–12% from N to 5N, depending on N, as its allocator settled over the
  first three runs; with one, 1–6% at every N. A test without either can
  fail at random near the 10% limit.
- **Memory tests run as CTest runs them.** doctest's `--success` keeps every
  assertion's text: about 10 times the peak in ToneMatcher's test.
- **On Windows, `peak_memory_bytes()` reports the peak private commit**
  (`PeakPagefileUsage`) instead of the peak working set. A test near its
  limit can fail where it passed, since the same leak is a larger share of a
  smaller number. *Why:* SimpleLocalServer measured both on the home
  server's Windows VM, 25 rounds of 1,000 messages each (run 36850710397).
  - After the same warm-up (about 4,000 messages), private commit stayed at
    4,968,448 bytes to the byte up to 25,000. The working set moved by 8 KB
    in that run, and by about 0.4 MB in steps in an earlier one.
  - A sink keeping 64 bytes per message grew private commit by 48% (6.07 →
    8.96 MB), against 27% for the working set: twice the margin over the
    10% limit.
  - macOS and Linux keep `ru_maxrss`, for which there is no such
    measurement yet.

## 0.20.2 (2026-10-01)

A correction to POLICY.md 13.5 (documentation only), so that projects don't
copy a number that fails. A patch release (POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.20.2`. Nothing
   else.

### Budgets (POLICY.md 13.5)

- The warm-up example now covers all three systems, and says to choose N past
  the latest bend. *Why:* v0.20.1 cited N = 5,000 as passing, which held on
  macOS and Windows only. Once the home server's Linux runner had
  `llvm-strip`, SimpleLocalServer's test failed there at N = 5,000 (+39%).
  The Linux peak rises in two steps of exactly 1 MiB, at about 6,000 and
  11,000 messages, then stays flat to 50,000 (run 36842331640). With
  N = 15,000, growth up to 50,000 is 0% on Linux, 0.5% on Windows and 4% on
  macOS. All 8 jobs pass (run 36842841438), and a sink that keeps 64 bytes
  per message still fails. (SimpleLocalServer's report of 2026-10-01.)
- A client that reuses connections sets `TCP_NODELAY`. *Why:* on Linux,
  Nagle's algorithm with delayed acknowledgment cost about 44 ms per request
  over a kept-alive connection: 200 messages took 8,881 ms, against 7 ms
  with `TCP_NODELAY` (run 36841795360). Reusing connections, which 13.5
  recommends, is what exposes it.

## 0.20.1 (2026-10-01)

Fixes from SimpleLocalServer's adoption of v0.20.0 (its report of
2026-10-01). Nothing that passed can fail, so a patch release (POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.20.1`. A
   self-hosted Linux runner needs the `llvm-23` package (README, "Setup per
   platform"). The home server's already has it.

### Requirements

- `llvm-strip` and `llvm-size` are now listed with the other LLVM tools,
  and the gate installs `llvm-23` on GitHub's Linux machines. *Why:*
  `cpp_policy_size_budget()` needs them, but nothing named them.
  - On GitHub's Ubuntu, apt also installs `clang-23`'s recommended packages,
    `llvm-23-dev` and with it `llvm-23`, so they were there.
  - The home server builds its Linux image from the gate's list without
    recommended packages, so SimpleLocalServer's release job failed at
    configure there (run 36838148786).
  - The server conversation found the cause, installed `llvm-23` and
    suggested naming it in the gate (2026-10-01).
  - Homebrew's LLVM and the official Windows archive include both tools.

### Budgets (POLICY.md 13.5)

- Memory tests must choose N past the program's warm-up. Measure the peak
  after each of many rounds once on each system, and start past the bend.
  *Why:* with N = 1,000, SimpleLocalServer's test failed on Windows (+11%) on
  warm-up alone. Its 25-round curve rose 0.95 MB over the first 4,000
  messages on Windows (230 KB over 5,000 on macOS), then stayed flat
  (+0.6%). With N = 5,000 it passes, and a sink that keeps 64 bytes per
  message still fails it.
- Memory tests stay inside their time limit by reusing slow setup: a new
  connection costs about 10 ms on the home server's Windows VM.
- `peak_memory_bytes()` is documented per system: `ru_maxrss` on macOS and
  Linux, the peak working set on Windows, which counts shared pages too.
  The report suggests the peak private commit (`PeakPagefileUsage`) as a
  steadier signal on Windows. It isn't switched here: SimpleLocalServer was
  asked to measure both first.

## 0.20.0 (2026-10-01)

Budgets: each program's size, and its memory under load, checked in the
release workflow. Nothing that passes fails until a project adds budgets
and memory tests, so a minor release (POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.20.0`.
2. Add `cpp_policy_size_budget(<program>)` for each program you ship, and run
   `cmake --workflow --preset release` (`win-release`) on each system, or let
   CI do it. Each system's test prints the budget to set. The owner approves
   the numbers.
3. A server, or a program that processes input of unbounded size, gets a
   memory test (POLICY.md 13.5): `cpp_policy_add_tests(benchmark <module>
   ...)`.
4. Have the owner add the budget line of cpp-policy's
   `template/AGENTS.md.in` ("Tests" section) to `AGENTS.md`.

### Budgets (POLICY.md 13.5, new)

- **`cpp_policy_size_budget(<program> MACOS … LINUX … WINDOWS …)`** adds the
  test `benchmark/size/<program>` to Release builds without sanitizers. It
  strips a copy with `llvm-strip` and fails if it is larger than this
  system's budget, or if the system has none, printing the size, a budget
  with 5% headroom, and the copy's sections. Raising a budget needs the
  owner's approval and a CHANGELOG line.
  - *Why the stripped size:* SimpleLocalServer's release file is 840,640
    bytes on macOS, but 41% of that is its symbol table, which grows with
    names. Stripped, it is 538,176, the same to the byte on a fresh build.
  - *Why 5%:* toolchain updates moved SimpleLocalServer's size by 544 bytes
    over many releases. 5% is about 27 KB: enough for noise, small enough to
    catch a new dependency or a large table.
  - *Why LLVM's tools and not bloaty:* `llvm-strip` and `llvm-size` come with
    the LLVM every machine already has. bloaty's Homebrew version is from 2020
    and it isn't in vcpkg. For detail, a link map gives every function's size
    on all three systems (POLICY.md 13.5 says how).
  - The owner chose budgets in `CMakeLists.txt` with owner approval, 5%
    headroom, and memory tests for servers and unbounded input (2026-10-01).
- **The `benchmark` test kind:** `cpp_policy_add_tests(benchmark …)` programs
  are built in every configuration, so clang-tidy checks them, and run only
  without sanitizers. They link **`cpp_policy::peak_memory_bytes()`**
  (`#include <cpp_policy/peak_memory.hpp>`), the process's peak resident
  memory from `getrusage()` or `GetProcessMemoryInfo()`.
- **Memory tests** drive a program's work N times, read the peak, drive it
  4N more, and require less than 10% growth. SimpleLocalServer's peak was
  7.01 MB after 1,000 messages, 7.01 MB after 10,000 and 7.06 MB after
  30,000 (measured from outside, 2026-10-01).
- `cmake/testing/` is a confined folder in cpp-policy's own audit: it holds
  `peak_memory.cpp`'s operating-system code. Its one `NOLINT` is for glibc,
  which declares `ru_maxrss` in a union.

### Template

- The program has a size budget: 109,568 bytes on macOS, 93,184 on Linux and
  285,696 on Windows, measured in CI with 5% headroom. `AGENTS.md` tells
  agents not to raise budgets.

### Self-test

- `testing/peak_memory`: the peak rises by at least half of 64 MiB touched,
  and doesn't fall when it is freed, in every build on every system.
- `template/new_project` adds a memory test to the generated project. It
  checks that the test is built but not registered in the check build, then
  runs the release build, where the memory test and the size budget must
  both run and pass.

## 0.19.2 (2026-10-01)

A fix to v0.19.1's fix for random link failures on Windows. Nothing that passed
can fail, so a patch release (POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.19.2`. It copies the
   new `tools/vcpkg/setup.cmake`. A workaround that orders links so that the
   AddressSanitizer runtime is copied first can go.

### Dependencies (POLICY.md 1.1)

- `tools/vcpkg/setup.cmake` turns `VCPKG_APPLOCAL_DEPS` off. *Why:*
  ToneMatcher's Windows check job still failed at random on v0.19.1, with
  `open_for_read("…\clang_rt.asan_dynamic-x86_64.dll"): permission denied`
  (its report of 2026-10-01, runs 36751433308 and 36820701579). That is
  vcpkg's error, not CMake's. After every link vcpkg runs `z-applocal`,
  which copies the program's DLLs next to it and reads the ones already
  there. It read the AddressSanitizer runtime while another program's
  post-build step was writing it, and v0.19.1's lock doesn't cover vcpkg.
  - The policy's triplets link every dependency statically, so vcpkg had no
    DLL to copy: turning the step off loses nothing, and saves a step per
    link.
  - ToneMatcher's analysis was right; v0.19.1's notes blamed only two copies
    colliding. That race was real too (cpp-policy's own CI saw CMake's
    "Error copying file"), and the lock stays.
  - Chosen over the report's other option, copying the runtime once per
    folder before anything there links: that would also work, but needs
    more machinery once the reader is gone.

### Self-test

- `vcpkg/dependencies_built_like_project` fails if `build.ninja` still has
  vcpkg's applocal step. With the check alone, both Windows jobs failed
  (run 36821930703). With the fix, they pass.

## 0.19.1 (2026-09-30)

A fix to v0.19.0: a test that prints a `std::string_view` compiles on
Windows. Nothing that passed can fail, so a patch release (POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.19.1`, from v0.19.0
   or, together with its steps, from an older release. A test that added
   `#include <ostream>` only for this can drop it.

### Testing (POLICY.md 13.3)

- `cpp_policy_add_tests()` defines `DOCTEST_CONFIG_USE_STD_HEADERS` for
  doctest's `main()` and every test program, so doctest includes the
  standard headers (`<ostream>` among them) on every system. *Why:*
  SimpleLocalServer's port to doctest (its report of 2026-09-30) failed to
  compile on both Windows jobs. A test `CAPTURE`d a `std::string_view` without
  including `<ostream>`, and Microsoft's library defines `string_view`'s
  `operator<<` only with it.
  - doctest includes the standard headers only with libc++. With libstdc++
    and Microsoft's library it declares what it needs in `namespace std`
    itself, which the standard doesn't allow (the header silences
    clang-tidy's check for that).
  - Chosen over the report's suggestion, a rule to include `<ostream>`:
    nothing would check that rule, since `misc-include-cleaner` is off, and
    the option removes the cause on every system.
- The template's own test missed it because its file includes `<ostream>` for
  a printer.

### Windows (POLICY.md 7.3)

- The AddressSanitizer runtime is copied next to each program under a lock on
  the folder (`cmake/scripts/copy_runtime.cmake`). *Why:* this release's
  first CI run on `main` failed once on Windows with "Error copying file
  (if different) … Permission denied", and passed when rerun. Programs in
  one folder link in parallel and each copies the same DLL there. One copy
  could read the file while another was writing it, find it different, and
  fail to overwrite it. The race is older than this release, but the
  test-registration step runs each test program right after the copy, so a
  folder of test programs meets it more often. ToneMatcher's tests folder
  will have eleven.

### Self-test

- The template's lowlevel test prints a `std::string_view` (in `CAPTURE`)
  without including `<ostream>`. Without the fix, CI's Windows check job
  failed with the report's error; with it, all jobs pass.

## 0.19.0 (2026-09-30)

A testing section and the tools that go with it: doctest for every project,
one CTest test per test case, named and labelled by kind. Projects whose
tests are added with `add_test()` under other names fail to configure until
they move, so a minor release (POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.19.0 --no-gate`.
   The gate would fail until the next steps are done.
2. Add doctest to `vcpkg.json`:
   `{"name": "doctest", "default-features": false, "$reason": "..."}`.
3. Move each test program to `cpp_policy_add_tests(<kind> <module> SOURCES
   ... LIBRARIES ...)`, and its checks to doctest `TEST_CASE`s written as
   POLICY.md 13.4 says. Tests that aren't doctest programs keep `add_test()`
   with a `<kind>/<module>/<case>` name and their kind as label. Delete
   `tests/check.hpp`.
4. Have the owner update `AGENTS.md` with the "Tests" section of cpp-policy's
   `template/AGENTS.md.in`.
5. `cmake --workflow --preset check`, then commit.

### Testing (POLICY.md 13, new)

- **Kinds.**
  - `unit`: one module; no files, network, processes, threads or clock;
    10 s per test case.
  - `integration`: modules together or with the OS; ephemeral ports, a
    timeout on every wait; 60 s, or less with `TIMEOUT`.
  - Regression tests are in doctest's `regression` suite and get that label
    as well. They are written first, with the bug fix.
- **`cpp_policy_add_tests()`** builds `test_<kind>_<module>` with the policy
  and doctest's `main()` from cpp-policy. After each build, it registers
  every `TEST_CASE` as the CTest test `<kind>/<module>/<test case>`,
  labelled with its kind. The build fails on:
  - a skipped test case;
  - a name doctest can't select exactly (`,` `*` `?` `\`), or two names
    that differ only in case;
  - a suite other than `regression`;
  - a program with no tests.
- **Configuration** fails for a test added with `add_test()` without a
  `<kind>/<module>/` name and its kind's label (cpp-policy's own self-test
  is exempt).
- **How tests are written (13.4):**
  - `REQUIRE` only for preconditions of the rest of the test (the
    `.error()` on a success in SimpleLocalServer's test was undefined
    behavior);
  - comparisons inside `CHECK`, one behavior per test, tables with
    `CAPTURE`;
  - fakes rather than mocks, no sleeps, no shared state, no skipped tests;
  - a regression test with every bug fix.
- *Why doctest:* a spike ported SimpleLocalServer's `test_sanitize` to
  doctest and to GoogleTest. It ran them under the policy on macOS, then a
  template project with both on Linux and Windows in CI. Both passed
  everywhere; the differences:
  - doctest's `REQUIRE` stops a test even from a helper function, while
    GoogleTest's `ASSERT_*` only leaves the helper;
  - doctest's failures print both values without extra code, while
    GoogleTest prints table rows as raw bytes, even in CTest's test names,
    until a printer is written for each type;
  - clang-tidy checks all of doctest's test code, while code inside
    GoogleTest's macros escapes some checks;
  - doctest is header-only (smaller programs, nothing compiled per triplet).

  GoogleTest was cleaner under clang-tidy with no setup, and the owner
  knows it. The owner chose doctest (2026-09-30).
- *Why doctest's `main()` is in its own file:* in the same file as the
  tests, the static analyzer reports two memory leaks inside doctest's
  string class on macOS and Windows. LeakSanitizer found none in 16 failing
  checks over three runs, while the policy's leak test, run as a control,
  reported its leaks.
- *Why the printer idiom:* `operator<<` for a project enum must be found by
  doctest (in the enum's namespace), have internal linkage
  (`misc-use-internal-linkage`) and not be `static`
  (`misc-use-anonymous-namespace`). Only an inline anonymous namespace does
  all three; GoogleTest's `PrintTo` hook would also break the naming rule.
- *Why one CTest test per test case, not per table row:* each CTest test is
  a process, and AddressSanitizer takes about 0.15 s to start one. 33
  row-level tests took 5.6 s where the programs took 0.04 s.

### Presets

- `unit` and `win-unit` workflows: build the `dev` configuration (no
  clang-tidy) and run the tests labelled `unit`.

### Template (`tools/new-project.sh`)

- Every project uses vcpkg, at least for doctest: `VCPKG_ROOT` is required,
  and `--vcpkg` is accepted but no longer needed. The owner chose doctest
  for every project over a hand-written checker for small ones.
- Tests for both modules with doctest through `cpp_policy_add_tests()`, and
  `tests/check.hpp` is gone. `AGENTS.md` has a "Tests" section.

### Self-test

- `template/new_project` checks the generated project's tests as CTest sees
  them (5 unit tests, by name) and that a skipped test case fails the
  build. It now needs `VCPKG_ROOT`, like the vcpkg test.
- `testing/*`: the registration script on saved doctest listings: an
  accepted one, plus a skipped case, a bad name, two names that differ only
  in case, another suite, and no tests.
- `bypass/test_unnamed`, `bypass/test_unlabelled`: `add_test()` without the
  name or the label fails configuration. `bypass/clean` has a correctly
  named and labelled one.

## 0.18.0 (2026-09-30)

How and when the toolchain pins move, and a guard so that Homebrew can't
move LLVM before the policy does. Nothing that passes can fail, and projects
get a new copy of `CMakePresets.json` and `tools/vcpkg/llvm.cmake`: a minor
release (POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.18.0`. It copies
   the new presets and `llvm.cmake`. Nothing else to do.

### Versioning (POLICY.md 10.1)

- New section "Moving the toolchain pins": the LLVM major, the exact LLVM on
  Windows CI, and `MSVC_TOOLSET`.
  - They move in a *toolchain window* twice a year, opened by each LLVM
    major release. The target is the new major's newest patch release,
    never `.1.0`, and the newest Microsoft toolset.
  - Both move in one release.
  - The steps: open; trial the policy on a branch; trial the projects
    before anything moves (Windows runner machines in a snapshot); release;
    switch the runner machines and the projects on one agreed day; roll
    back if needed; close.

  *Why:* the owner wants to move to newer toolsets now and then
  (2026-09-30). Since v0.17.0 pinned the toolset, a move needs the runner
  machines and the projects to change in a known order. Self-hosted Windows
  runners hold one toolset at a time, so all projects switch together, and
  the project trial beforehand keeps that switch uneventful. The owner
  chose two windows a year and one release per window (2026-09-30).

### Toolchain

- The presets, the vcpkg toolchain (`llvm.cmake`) and the gate look for
  Homebrew's `llvm@23` before its `llvm`, and the gate installs `llvm@23`
  on GitHub's macOS machines when Homebrew's `llvm` is another major.
  *Why:* the presets used Homebrew's unversioned `llvm`, which Homebrew
  moves to each new major within days of its release. With LLVM 24 (due
  around March 2027), cpp-policy's own macOS CI and any Mac that ran `brew
  upgrade` would have failed the compiler check before the policy chose to
  move. Homebrew keeps the previous major as `llvm@<major>`, so the policy
  now sets the date.
- README, "Setup per platform": the macOS rows and a note on `llvm@23`.

### Self-test

- `toolchain/pins`: every file that names the LLVM major (the presets'
  search paths, `LLVM_MAJOR` and `LLVM_VERSION` in `gate.yml`) names
  `CPP_POLICY_LLVM_MAJOR`, so a major move can't forget one. Tried with 24:
  it names each file left at 23.

### cpp-policy

- The roadmap item "Moving the toolchain pins" is resolved by this release.

## 0.17.0 (2026-09-30)

CI pins the Microsoft toolset of self-hosted Windows runners. A job on a
runner with another toolset now stops, so code that passed can fail: a
minor release (POLICY.md 10).

### Upgrading a project

1. Self-hosted Windows runners must have MSVC 14.44 (Visual Studio 2022
   17.14 or its Build Tools) and no other toolset. The owner's server
   already has it. Projects without self-hosted Windows runners need
   nothing.
2. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.17.0`.

### Toolchain (POLICY.md 1)

- The Microsoft toolset is now part of the toolchain table: MSVC 14.44 or
  later on developer machines, exactly `MSVC_TOOLSET` (14.44) on
  self-hosted CI. *Why:* the server conversation asked (2026-09-30) which
  toolset its Windows runners should have. The gate pinned LLVM but not the
  toolset, whose standard library clang-tidy analyzes. Its runners had
  14.44 and GitHub's image 14.51, and ToneMatcher found that five of its
  first seven clang-tidy findings depended on the library.
- Why a pin, and not GitHub's image or no rule:
  - GitHub's image updates Visual Studio every few weeks, so following it
    means a target that keeps moving;
  - with no rule, a finding could come and go with a machine's updates;
  - a pin changes only in a release, like `LLVM_VERSION`.

  14.44 is the last Visual Studio 2022 release and only gets servicing
  updates, so it holds without upkeep. cpp-policy's own CI keeps GitHub's
  newer toolset, which gives an early warning before the pin moves. The
  owner chose the pin (2026-09-30); a protocol for moving it is on the
  roadmap.

### CI (`gate.yml`)

- `MSVC_TOOLSET: '14.44'` next to `LLVM_VERSION`. On a self-hosted Windows
  runner, "Show the toolchain" reads the toolset `clang-cl` finds (from the
  include paths of `clang-cl -###`) and stops the job if its major.minor
  differs.
- Every job prints its standard library's version: the MSVC toolset on
  Windows, `_GLIBCXX_RELEASE` on Linux, `_LIBCPP_VERSION` on macOS.

## 0.16.0 (2026-09-28)

How a project records its open and finished work. New guidance and a new
template file that change nothing for existing projects, so a minor release
(POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.16.0`. Nothing
   else is required.
2. Optional, to adopt the layout: rewrite the project's open-work file as
   `ROADMAP.md` in the layout of POLICY.md 11.5 (`template/ROADMAP.md.in`
   is a starting point), and have the owner add the "Planned work" section
   of `template/AGENTS.md.in` to `AGENTS.md`.

### Project structure (POLICY.md 11.5)

- New section "Roadmap and changelog". `ROADMAP.md` holds the open work,
  and `CHANGELOG.md` the finished work with its reasons. The roadmap has up
  to three parts:
  - a section for the version in progress: a one-sentence goal, the scope
    as behavior (ticked when done), what is out of scope and why, and how
    the version is validated;
  - "Later", for the other open items;
  - "Not planned", for accepted limitations with their reasons.

  The release commit deletes the version's section, since the CHANGELOG
  entry now says what the version delivered, and the tag keeps the section.
  No listings of files or tests, no counts, no dates. *Why:* the roadmap
  item taken from Carreritas' `docs/scope.md`. Its per-version goal, scope,
  out-of-scope list and validation status were useful, especially the
  out-of-scope list, which stops agents from adding what was deliberately
  left out. But the file grew to about 500 lines: every released version
  stayed in it, next to a file tree and progress logs that were edited by
  hand and went stale. Each part of it now lives where it doesn't
  duplicate anything:
  - the open work in the roadmap;
  - what was done, with its reasons, in the CHANGELOG;
  - the released scope at its tag;
  - the file listings nowhere, since git has them.

  The owner chose the name (`ROADMAP.md`, as in cpp-policy), deletion on
  release, and template-plus-guidance with no audit check (2026-09-28).
- Review only (POLICY.md 8.1): the audit doesn't read prose.

### Tools

- `tools/new-project.sh` creates `ROADMAP.md` with the first version's
  section (0.1.0, matching `project()`) to fill in. The generated
  `AGENTS.md` has a "Planned work" section: read the roadmap before
  starting, ask before doing anything it lists under "Out of scope" or "Not
  planned", and record finished work in the CHANGELOG in the same commit.

### cpp-policy

- `ROADMAP.md` follows the layout: no version is in progress, so its items
  are under "Later". The scope-document item is resolved by this release.

## 0.15.1 (2026-09-28)

A fix to v0.15.0: build folders that change triplet configure again without
`--fresh`. Nothing can fail that passed, so a patch release (POLICY.md 10).

### Upgrading a project

1. `sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.15.1`, from
   v0.15.0 or from an older release. Build folders configured before the
   upgrade need nothing more.

### Dependencies (POLICY.md 1.1)

- `tools/vcpkg/setup.cmake` clears cached paths into the old triplet's
  folder when a build folder's triplet changes, so they are found again
  under the new one. *Why:* ToneMatcher's upgrade to v0.15.0 (its report
  of 2026-09-28) found that every build folder configured before the
  upgrade failed to generate: `FindZLIB` had cached zlib's paths under
  `vcpkg_installed/arm64-osx/`, which vcpkg removed when it installed the
  `cpp-policy-asan` triplet. The same happened without an upgrade when a
  folder was reconfigured with other sanitizer options, the case the
  `FORCE` on `VCPKG_TARGET_TRIPLET` was meant to handle. The self-test and
  the trial upgrade only configured empty folders, so they didn't see it.
  Of the report's two fixes, clearing the entries was chosen over
  stopping with "configure with --fresh": it covers both cases with
  nothing to remember, and only clears paths inside the old triplet's
  folder, which vcpkg has just removed. Configuration names what it
  cleared.
- POLICY.md 1.1 now says that vcpkg's host triplet (tools that run during
  the build, such as `vcpkg-cmake`) keeps the system's compiler: nothing
  built with it goes into the program. Also from ToneMatcher's report.

### Self-test

- `vcpkg/dependencies_built_like_project` reconfigures its folder with the
  other sanitizer setting, builds again and checks that the dependency
  switched. Without the fix it fails: the build still wants the old
  triplet's `libpolicy_probe.a`.

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

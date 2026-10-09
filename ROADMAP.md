# Roadmap

Open work on cpp-policy itself: what comes next, and why. What's done is in
`CHANGELOG.md`, with the reasons; items are removed from here in the commit
that resolves them. The layout is the one POLICY.md 11.5 gives projects.

Until 2026-09-28 these lived in SimpleLocalServer's `PENDING.md`, the
project that piloted the policy. Numbers like #38 refer to the issues found
in the walkthroughs of that time.

## 0.29.0 (in progress)

**Goal:** the gate costs an agent less time for the same checks.

From Alfar's report (2026-10-08): its gate grew from under 1 minute to about
8 as its tests grew from 57 to 1,500, and most of that is the tests under
the sanitizers. The owner chose this before libraries (2026-10-09).

### Scope

- [ ] Measured first, on a project with about 1,500 test cases: what one
      test case costs under the sanitizers, and what running tests in
      parallel and running a program's unit tests in one process each save.
- [ ] The test step is faster by what the measurements justify, with every
      test still run under the sanitizers.
- [ ] One command runs the gate, keeps the machine awake, lets only one gate
      run at a time on the machine, returns the gate's own exit code and
      ends with one line that says whether it passed.
- [ ] Two `cpp_policy_confine_includes()` lines for one header add up,
      each with its own `SOURCES_ONLY` (found by Alfar: today the second
      rejects what the first allows).
- [ ] POLICY.md 13.5 says how a C library's memory is brought into the heap
      count through its allocator (zlib's `zalloc`).

### Out of scope

- Moving tests out of the local gate into CI (Alfar's option C): the gate
  stays the one definition of "passes the policy".
- Skipping the hook's clang-tidy after a gate that passed on the same tree:
  worth doing, but it needs a record of what the gate checked; later.

### Validation

- [ ] The gate passes in CI on every system.
- [ ] Alfar's gate time before and after, for the same tests.
- [ ] The launcher tried on macOS, Linux and Windows.

## Later

### Libraries: one policy project used by another

Asked by Alfar (2026-10-09), with ToneMatcher as the library and Alfar as
its user. The owner approved the plan the same day: a library's code in
`lib/<name>/<module>/` with its name in every include; `library.cmake` with
`cpp_policy_library()`; `cpp_policy_use_library()` for the user; the library
built in the user's build as a dependency, with a floor on its policy
version.

- [ ] **Release A:** the layout, the two functions, the audit's rules for
      `lib/`, and a library and a user of it in cpp-policy's own tests, on
      every system. ToneMatcher can start after it.
- [ ] **Release B,** shaped by that first real use: `upgrade.sh` for a
      library's pin, test helpers offered by a library, the credential a
      private repository needs in CI.

### From Alfar's report, not yet designed

- [ ] **Budgets and "ask the owner" in unattended runs:** a way for the
      owner to grant a standing rule (the size budget at a release commit),
      and a first CI run that has no number for a system yet.
- [ ] **A file the policy names for rules that could not be met,** listed by
      the audit.
- [ ] **Smaller:** the padding check's threshold; the message when a build
      runs without its preset; a shipped local-time function (W2); the
      hook's clang-tidy after a gate that passed on the same tree.

### Trials running

- **Instruction counts** (ToneMatcher, since 2026-10-08): whether a budget
  rule is worth writing, once the counts have been seen over real commits.

### Open, the owner's

- **MPL-2.0** (Eigen, Ceres): left open until a project needs it
  (2026-10-08).

### Waiting

- [ ] **Modules experiment:** once CMake makes `import std` stable, convert
      one module of a project (e.g. SimpleLocalServer's `message/sanitize`)
      and check that clang-tidy and the gate still pass (POLICY.md 2.4 says
      why modules aren't used yet; W1 in POLICY.md 12).

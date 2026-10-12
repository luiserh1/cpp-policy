# Roadmap

Open work on cpp-policy itself: what comes next, and why. What's done is in
`CHANGELOG.md`, with the reasons; items are removed from here in the commit
that resolves them. The layout is the one POLICY.md 11.5 gives projects; no
version is in progress.

Until 2026-09-28 these lived in SimpleLocalServer's `PENDING.md`, the
project that piloted the policy. Numbers like #38 refer to the issues found
in the walkthroughs of that time.

## Later

### Libraries, after their first use

Releases A and B (0.30.0, 0.32.0) are out. Open:

- [ ] The token in a real CI run: Alfar's, once the owner has created it.
- [x] `cpp_policy_parallel_tests()` in real projects (0.33.0): ToneMatcher
      41 s to 14 s; Alfar 756 s to 217 s, no program `ALONE`.
- [ ] Windows and Linux have not built Alfar yet: it has no remote, so no
      CI. The library, libjpeg-turbo and parallel tests are proven there on
      macOS only.
- [ ] A project that is only a library, and a library that uses a library:
      when a project needs one. cli-cpparser (v0.1.0, public) is a library
      with a small example program in `src/`, and nothing in 11.7 got in
      its way.
- [ ] Two libraries in one project: untried. Alfar will be the first, with
      ToneMatcher's and cli-cpparser.

### From Alfar's report, not yet designed

- [ ] **Budgets and "ask the owner" in unattended runs:** a way for the
      owner to grant a standing rule (the size budget at a release commit).
      (A first CI run with no number for a system: done in 0.34.0.)
- [ ] **A file the policy names for rules that could not be met,** listed by
      the audit.
- [ ] **Smaller:** the padding check's threshold; the message when a build
      runs without its preset; a shipped local-time function (W2); the
      hook's clang-tidy after a gate that passed on the same tree.
- [ ] **From its report of 2026-10-10:** a build after a `CMakeLists.txt`
      changes runs clang-tidy on the whole tree again (13 to 30 minutes);
      the size budget is tested only in the release workflow, and on macOS
      moves 16 KiB at a time; `tidy-files` says "OK (0 files)" for a path
      that doesn't exist; its trial of one full gate per stage, with the
      hook and the touched modules' tests between commits.

### Trials running

- **Instruction counts** (ToneMatcher, since 2026-10-08): whether a budget
  rule is worth writing, once the counts have been seen over real commits.
  - Seen so far: the same code repeats to about 3,000 instructions in
    billions; a rewrite of the PNG row filters showed as -43% on one
    benchmark; untouched benchmarks moved by 3, 413 and 788 instructions
    when a function they call gained an argument.
  - So a budget needs a small tolerance, not zero; and a count says nothing
    of the output, which a benchmark could check with a checksum in the
    same run.

### Open, the owner's

- **MPL-2.0** (Eigen, Ceres): left open until a project needs it
  (2026-10-08).
- **An owner's exception for one named package's license,** with a reason
  printed at every configure (asked by Alfar, 2026-10-11): when a license
  comes up that the owner would accept for one project but not for all.

### Waiting

- [ ] **Modules experiment:** once CMake makes `import std` stable, convert
      one module of a project (e.g. SimpleLocalServer's `message/sanitize`)
      and check that clang-tidy and the gate still pass (POLICY.md 2.4 says
      why modules aren't used yet; W1 in POLICY.md 12).
